//
//  Inject.m — 智能体首条设定提示词注入
//
//  教训（v0.1.16）：轮询里 pending 只在「发送成功」时清除 → 用户删掉后 1 秒又被填回；
//  发送成功后 pending 仍在 → 每秒重发一次 → 服务器繁忙。
//
//  正确做法：严格的一次性状态机
//    pending 存在 → ① 文字还没填就填一次（填完立刻清 pending，绝不重复填）
//                   ② 填完后最多尝试发送 3 次，每次间隔 1.5 秒，发过就停
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"
#import "AgentStore.h"

void DSADiagLog(NSString *line);

// —— 发送尝试状态：0=未开始, >0=已尝试次数, -1=已完成（不再动）——
static int DSASendTries = 0;
static const int kDSAMaxTries = 3;

static void DSAWalk(UIView *root, void (^block)(UIView *)) {
    if (!root) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    int guard = 0;
    while (stack.count && guard++ < 5000) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if (v.hidden || v.alpha < 0.05) continue;
        block(v);
        for (UIView *s in v.subviews) [stack addObject:s];
    }
}

#pragma mark - 找输入框 / 发送按钮

static UITextView *DSAFindPromptTextView(void) {
    UIWindow *w = DSAKeyWindow();
    if (!w) return nil;
    __block UITextView *best = nil;
    __block CGFloat bestArea = 0;
    DSAWalk(w, ^(UIView *v) {
        if (![v isKindOfClass:[UITextView class]]) return;
        if (!v.isUserInteractionEnabled || !v.window) return;
        CGFloat area = v.frame.size.width * v.frame.size.height;
        if (area > bestArea) { best = (UITextView *)v; bestArea = area; }
    });
    return best;
}

static UIView *DSAFindSendControl(void) {
    UIWindow *w = DSAKeyWindow();
    if (!w) return nil;
    __block UIView *hit = nil;
    DSAWalk(w, ^(UIView *v) {
        if (hit || !v.window || !v.isUserInteractionEnabled) return;
        if (![v isKindOfClass:[UIControl class]]) return;
        NSString *cls = NSStringFromClass([v class]);
        NSString *label = v.accessibilityLabel ?: @"";
        NSString *aid = v.accessibilityIdentifier ?: @"";
        if ([cls.lowercaseString containsString:@"send"] ||
            [label containsString:@"发送"] ||
            [label.lowercaseString containsString:@"send"] ||
            [aid.lowercaseString containsString:@"send"])
            hit = v;
    });
    return hit;
}

#pragma mark - 填入（只填一次）

/// 把提示词写进输入框。返回 YES = 已写入（无论是否发送）
static BOOL DSAFillPrompt(NSString *prompt) {
    if (!prompt.length) return NO;
    UITextView *tv = DSAFindPromptTextView();
    if (!tv) { DSADiagLog(@"[INJ] no textview"); return NO; }

    // 已经是这段文字 → 不重复写（避免打断用户）
    NSString *cur = tv.text ?: @"";
    if ([cur isEqualToString:prompt]) {
        DSADiagLog(@"[INJ] already filled");
        return YES;
    }
    @try {
        [tv becomeFirstResponder];
        [tv setText:prompt];
        [tv setSelectedRange:NSMakeRange(prompt.length, 0)];
        [tv.delegate textViewDidChange:tv];
        [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:tv];
    } @catch (__unused NSException *e) {
        DSADiagLog([NSString stringWithFormat:@"[INJ] fill failed %@", e.reason]);
        return NO;
    }
    DSADiagLog([NSString stringWithFormat:@"[INJ] filled len=%lu", (unsigned long)prompt.length]);
    return YES;
}

#pragma mark - 发送（最多 3 次）

static BOOL DSATrySendOnce(void) {
    UIView *send = DSAFindSendControl();
    if (!send) { DSADiagLog(@"[INJ] no send control"); return NO; }
    if ([send isKindOfClass:[UIControl class]]) {
        [(UIControl *)send sendActionsForControlEvents:UIControlEventTouchUpInside];
        DSADiagLog([NSString stringWithFormat:@"[INJ] send tapped (%d/%d)", DSASendTries, kDSAMaxTries]);
        return YES;
    }
    return NO;
}

#pragma mark - 轮询

void DSAInjectTick(void) {
    @try {
        if (DSASendTries < 0) return;                 // 已完成，永不再动
        if (DSASendTries >= kDSAMaxTries) {           // 尝试用尽 → 停手，交给用户
            return;
        }
        DSAStore *store = [DSAStore shared];
        [store loadIfNeeded];
        NSString *pending = [store pendingAgentId];
        if (!pending.length) return;

        DSAAgent *agent = [store agentWithId:pending];
        if (!agent || !agent.systemPrompt.length) {
            [store setPendingAgentId:nil];            // 智能体被删了 → 清掉
            return;
        }

        // ① 填一次，填完立刻清 pending（杜绝重复填）
        if (![store sessionInjected:@"_filled"]) {
            if (!DSAFillPrompt(agent.systemPrompt)) return;   // 还没输入框，下秒再试
            [store markSessionInjected:@"_filled"];
            [store setPendingAgentId:nil];
            DSASendTries = 1;                          // 开始尝试发送
            DSADiagLog(@"[STATE] filled once, pending cleared, will try send");
            return;
        }

        // ② 已填过 → 尝试发送，最多 3 次
        DSASendTries++;
        DSATrySendOnce();
        if (DSASendTries >= kDSAMaxTries) {
            DSADiagLog(@"[STATE] send attempts exhausted, stop");
            DSASendTries = -1;                         // 永久停止
        }
    } @catch (__unused NSException *e) {
        DSADiagLog([NSString stringWithFormat:@"[POLL] exception %@", e.reason]);
    }
}

/// 用户手动点了新建对话 / 重新选择智能体时，重置状态
void DSAResetInjection(void) {
    DSASendTries = 0;
    [[DSAStore shared] uninjectMark:@"_filled"];
}
