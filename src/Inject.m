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
static BOOL DSARoundActive = NO;    // 本轮是否已填过（只认本次运行内填的，避免重启后残留状态误发）

// —— 最早允许填充的时间戳（点完新建对话要等新会话打开）——
static NSTimeInterval DSAFillNotBefore = 0;
void DSASetFillDelay(NSTimeInterval sec) {
    DSAFillNotBefore = [[NSDate date] timeIntervalSince1970] + sec;
}

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

/// 已知「不是发送」的控件（真机 diag 里出现过的），避免误点
static BOOL DSAIsNotSend(NSString *cls, NSString *low) {
    NSArray *bad = @[ @"uploadbutton", @"searchoperation", @"reasoningoperation",
                      @"ttsbutton", @"sessiontts", @"open_sidebar", @"newchat",
                      @"regenerate", @"textfield" ];
    for (NSString *b in bad) if ([low containsString:b]) return YES;
    (void)cls;
    return NO;
}

static UIView *DSAFindSendControl(void) {
    UIWindow *w = DSAKeyWindow();
    if (!w) return nil;
    __block UIView *hit = nil;

    // ① 名字/标签里带 send / 发送
    DSAWalk(w, ^(UIView *v) {
        if (hit || !v.window || !v.isUserInteractionEnabled) return;
        if (![v isKindOfClass:[UIControl class]]) return;
        NSString *cls = NSStringFromClass([v class]);
        NSString *label = v.accessibilityLabel ?: @"";
        NSString *aid = v.accessibilityIdentifier ?: @"";
        NSString *low = [NSString stringWithFormat:@"%@ %@ %@", cls, label, aid].lowercaseString;
        if (DSAIsNotSend(cls, low)) return;
        if ([low containsString:@"send"] || [label containsString:@"发送"])
            hit = v;
    });
    if (hit) return hit;

    // ② 兜底：发送按钮就在输入框附近（同一输入区容器内），取右下角那个小控件
    UITextView *tv = DSAFindPromptTextView();
    if (!tv) return nil;
    UIView *scope = tv;
    for (int i = 0; i < 3 && scope.superview; i++) scope = scope.superview;   // 上溯 3 层
    __block UIView *best = nil;
    __block CGFloat bestScore = -1;
    DSAWalk(scope, ^(UIView *v) {
        if (![v isKindOfClass:[UIControl class]] || !v.window || !v.isUserInteractionEnabled) return;
        NSString *cls = NSStringFromClass([v class]);
        NSString *label = v.accessibilityLabel ?: @"";
        NSString *low = [NSString stringWithFormat:@"%@ %@", cls, label].lowercaseString;
        if (DSAIsNotSend(cls, low)) return;
        if (v.frame.size.width > 80 || v.frame.size.height > 80) return;      // 只要小控件
        if (v.frame.size.width < 24 || v.frame.size.height < 24) return;
        // 越靠右下分越高
        CGFloat score = v.frame.origin.x + v.frame.origin.y;
        if (score > bestScore) { bestScore = score; best = v; }
    });
    DSADiagLog([NSString stringWithFormat:@"[SEND] fallback pick=%@ score=%.0f",
                 best ? NSStringFromClass([best class]) : @"nil", bestScore]);
    return best;
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

// 状态：
//   pending 非空        → 需要填（阶段 A）
//   pending 空 + 已填   → 需要发（阶段 B，最多 kDSAMaxTries 次）
//   DSASendTries = -1   → 本轮完成，永不再动
void DSAInjectTick(void) {
    @try {
        if (DSASendTries < 0) return;                       // 本轮已完成

        DSAStore *store = [DSAStore shared];
        [store loadIfNeeded];

        // —— 阶段 A：有待发提示词 → 填一次 ——
        NSString *pending = [store pendingAgentId];
        if (pending.length) {
            // 等新会话打开，避免填进旧会话
            if ([[NSDate date] timeIntervalSince1970] < DSAFillNotBefore) return;
            DSAAgent *agent = [store agentWithId:pending];
            if (!agent || !agent.systemPrompt.length) {
                [store setPendingAgentId:nil];              // 智能体被删了
                return;
            }
            if (!DSAFillPrompt(agent.systemPrompt)) return; // 还没输入框，下秒再试
            [store markSessionInjected:@"_filled"];
            [store setPendingAgentId:nil];                  // 填完立刻清，杜绝重复填
            DSASendTries = 0;                               // 进入发送阶段
            DSARoundActive = YES;
            DSADiagLog(@"[STATE] filled once, pending cleared, will try send");
            return;
        }

        // —— 阶段 B：已填过 → 尝试发送（最多 3 次，成功即停）——
        if (DSASendTries < 0) return;
        if (!DSARoundActive) return;                        // 本轮没填过，无事可做

        // 先判断是否已经发出去了：输入框被清空 = 发送成功
        UITextView *tv = DSAFindPromptTextView();
        if (tv) {
            NSString *cur = tv.text ?: @"";
            if (cur.length == 0) {
                DSASendTries = -1;
                DSADiagLog(@"[STATE] input cleared → message sent OK");
                return;
            }
        }
        if (DSASendTries >= kDSAMaxTries) {
            DSASendTries = -1;
            DSADiagLog(@"[STATE] send attempts exhausted, stop (text still in box)");
            return;
        }
        DSASendTries++;
        DSATrySendOnce();
    } @catch (__unused NSException *e) {
        DSADiagLog([NSString stringWithFormat:@"[POLL] exception %@", e.reason]);
    }
}

/// 用户手动点了新建对话 / 重新选择智能体时，重置状态
void DSAResetInjection(void) {
    DSASendTries = 0;
    DSARoundActive = NO;
    DSAFillNotBefore = 0;
    [[DSAStore shared] uninjectMark:@"_filled"];
}
