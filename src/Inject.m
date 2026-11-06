//
//  Inject.m — 智能体首条设定提示词注入
//
#import <UIKit/UIKit.h>
#import "AgentStore.h"

extern void DSAToast(NSString *text);
extern UIWindow *DSAKeyWindow(void);
extern UIViewController *DSATopMost(UIViewController *base);

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
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if (v.hidden || v.alpha < 0.05) continue;
        block(v);
        for (UIView *s in v.subviews) [stack addObject:s];
    }
}

static UITextView *DSAFindPromptTextView(void) {
    UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
    __block UITextView *best = nil;
    __block CGFloat bestArea = 0;
    DSAWalk(top.view, ^(UIView *v) {
        if (![v isKindOfClass:[UITextView class]] || !v.isUserInteractionEnabled) return;
        CGFloat area = v.frame.size.width * v.frame.size.height;
        if (area > bestArea && v.window) { best = (UITextView *)v; bestArea = area; }
    });
    return best;
}

static UIButton *DSAFindSendButton(void) {
    UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
    __block UIButton *send = nil;
    DSAWalk(top.view, ^(UIView *v) {
        if (send || ![v isKindOfClass:[UIButton class]] || !v.window) return;
        NSString *cls = NSStringFromClass([v class]);
        NSString *label = v.accessibilityLabel ?: @"";
        if ([cls containsString:@"Send"] || [label containsString:@"发送"] ||
            [label.lowercaseString containsString:@"send"])
            send = (UIButton *)v;
    });
    return send;
}

/// 把提示词写进输入框并提交；返回 YES 表示已成功触发发送
BOOL DSASendPrompt(NSString *prompt) {
    if (!prompt.length) return NO;
    UITextView *tv = DSAFindPromptTextView();
    if (!tv) return NO;
    [tv becomeFirstResponder];
    [tv setText:prompt];
    [tv setSelectedRange:NSMakeRange(prompt.length, 0)];
    [tv.delegate textViewDidChange:tv];
    [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:tv];
    UIButton *send = DSAFindSendButton();
    if (!send || !send.enabled) return NO;      // 输入框已填好，等用户按发送
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [send sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
    return YES;
}

static void DSARetryPending(NSString *sessionId, int attempt) {
    if (attempt > 8) {
        DSAToast(@"设定提示词已填进输入框，请点发送");
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DSAStore *store = [DSAStore shared];
        NSString *p = DSAPending()[sessionId];
        if (!p || [store sessionInjected:sessionId]) return;
        if (DSASendPrompt(p)) {
            [DSAPending() removeObjectForKey:sessionId];
            [store markSessionInjected:sessionId];
        } else {
            DSARetryPending(sessionId, attempt + 1);
        }
    });
}

/// 会话页出现时调用
void DSAOnSessionShown(NSString *sessionId) {
    if (!sessionId.length) return;
    DSAStore *store = [DSAStore shared];
    [store loadIfNeeded];
    NSString *pending = [store pendingAgentId];

    if (pending.length) {
        DSAAgent *agent = [store agentWithId:pending];
        [store setPendingAgentId:nil];
        if (!agent) return;
        [store bindSession:sessionId toAgent:agent.agentId];
        if ([store sessionInjected:sessionId]) return;
        DSAPending()[sessionId] = agent.systemPrompt;
        DSARetryPending(sessionId, 0);
        return;
    }
    if (DSAPending()[sessionId] && ![store sessionInjected:sessionId])
        DSARetryPending(sessionId, 0);
}
