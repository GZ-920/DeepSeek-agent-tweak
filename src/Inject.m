//
//  Inject.m — 智能体首条设定提示词注入
//
//  关键教训：这个环境下 hook（viewDidAppear:）不触发，只有 %ctor 的定时任务可靠。
//  所以注入不依赖 hook，改为：启动后每秒轮询一次，条件满足就填输入框 + 发送。
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"
#import "AgentStore.h"

void DSADiagLog(NSString *line);

// sessionId -> 待发送提示词
static NSMutableDictionary<NSString *, NSString *> *DSAPending(void) {
    static NSMutableDictionary *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSMutableDictionary dictionary]; });
    return d;
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
        if (!v.isUserInteractionEnabled) return;
        if (!v.window) return;
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
        BOOL isSend = [cls.lowercaseString containsString:@"send"] ||
                      [label containsString:@"发送"] ||
                      [label.lowercaseString containsString:@"send"] ||
                      [aid.lowercaseString containsString:@"send"];
        if (isSend) hit = v;
    });
    return hit;
}

#pragma mark - 填入 + 发送

BOOL DSASendPrompt(NSString *prompt) {
    if (!prompt.length) return NO;
    UITextView *tv = DSAFindPromptTextView();
    if (!tv) { DSADiagLog(@"[INJ] no textview"); return NO; }

    @try {
        [tv becomeFirstResponder];
        [tv setText:prompt];
        [tv setSelectedRange:NSMakeRange(prompt.length, 0)];
        [tv.delegate textViewDidChange:tv];
        [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:tv];
    } @catch (__unused NSException *e) {
        DSADiagLog([NSString stringWithFormat:@"[INJ] set text failed %@", e.reason]);
        return NO;
    }
    DSADiagLog([NSString stringWithFormat:@"[INJ] text set len=%lu", (unsigned long)prompt.length]);

    UIView *send = DSAFindSendControl();
    if (!send) {
        DSADiagLog(@"[INJ] no send control (text is in box, user can tap send)");
        return NO;
    }
    DSADiagLog([NSString stringWithFormat:@"[INJ] send control %@", NSStringFromClass([send class])]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if ([send isKindOfClass:[UIControl class]])
            [(UIControl *)send sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
    return YES;
}

#pragma mark - 轮询（不依赖 hook）

void DSAStartInjectionPolling(void) {
    // 轮询在 Tweak.xm 的 %ctor 里启动（DSAInjectTick 由定时任务调用）
}

// 每 1 秒轮询一次：有待发提示词 → 填输入框
void DSAInjectTick(void) {
    @try {
        DSAStore *store = [DSAStore shared];
        [store loadIfNeeded];
        NSString *pending = [store pendingAgentId];
        if (pending.length) {
            DSAAgent *agent = [store agentWithId:pending];
            if (agent && agent.systemPrompt.length) {
                DSADiagLog(@"[POLL] pending agent found, trying to inject");
                if (DSASendPrompt(agent.systemPrompt)) {
                    [store setPendingAgentId:nil];
                    DSADiagLog(@"[POLL] injected OK, pending cleared");
                }
            }
        }
        // 还有排队中的（曾填过但没发出去）
        NSString *queued = DSAPending()[@"_q"];
        if (queued.length) {
            if (DSASendPrompt(queued)) {
                [DSAPending() removeObjectForKey:@"_q"];
            }
        }
    } @catch (__unused NSException *e) {
        DSADiagLog([NSString stringWithFormat:@"[POLL] exception %@", e.reason]);
    }
}
