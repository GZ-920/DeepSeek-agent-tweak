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
static BOOL DSATryDirectSend(void);   // 前置声明

// —— 发送尝试状态：0=未开始, >0=已尝试次数, -1=已完成（不再动）——
static int DSASendTries = 0;
static const int kDSAMaxTries = 3;
static NSString *DSALastAgentId = nil;   // 本轮使用的智能体（发送成功后据此绑定会话）
static BOOL DSARoundActive = NO;        // 本轮是否已填过（只认本次运行内填的，避免重启残留误发）

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
    // ① 先试「底层直发」：直接调 App 自己的发送方法（存在才调）
    if (DSATryDirectSend()) { DSADiagLog(@"[INJ] direct send (app method)"); return YES; }

    // ② 退路：找发送控件点一下
    UIView *send = DSAFindSendControl();
    if (!send) { DSADiagLog(@"[INJ] no send control"); return NO; }
    if ([send isKindOfClass:[UIControl class]]) {
        [(UIControl *)send sendActionsForControlEvents:UIControlEventTouchUpInside];
        DSADiagLog([NSString stringWithFormat:@"[INJ] send tapped (%d/%d)", DSASendTries, kDSAMaxTries]);
        return YES;
    }
    return NO;
}

#pragma mark - 会话名 / 隐藏提示词

/// 发送成功后：读出当前 sessionId → 绑定智能体 + 抓会话标题
static void DSABindCurrentSession(void) {
    @try {
        DSAStore *store = [DSAStore shared];
        NSString *agentId = DSALastAgentId;
        if (!agentId.length) return;

        UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
        NSString *sid = nil;
        // 逐个候选属性读 sessionId（Swift 存储属性经 KVC 可读）
        for (NSString *k in @[ @"sessionId", @"sessionID", @"chatSessionId", @"currentSessionId",
                               @"session_id", @"conversationId" ]) {
            @try {
                id v = [top valueForKey:k];
                if ([v isKindOfClass:[NSString class]] && [v length]) { sid = v; break; }
            } @catch (__unused NSException *e) {}
        }
        // 读不到就再挖一层 viewModel
        if (!sid) {
            for (NSString *k in @[ @"viewModel", @"vm", @"session", @"currentSession" ]) {
                @try {
                    id vm = [top valueForKey:k];
                    for (NSString *k2 in @[ @"sessionId", @"sessionID", @"id" ]) {
                        id v = [vm valueForKey:k2];
                        if ([v isKindOfClass:[NSString class]] && [v length]) { sid = v; break; }
                    }
                    if (sid) break;
                } @catch (__unused NSException *e) {}
            }
        }

        if (!sid) {
            DSADiagLog(@"[BIND] sessionId not readable from top VC");
            return;
        }
        [store bindSession:sid toAgent:agentId];

        // 抓会话标题
        NSString *title = top.navigationItem.title ?: top.title;
        if (!title.length) {
            UINavigationBar *bar = top.navigationController.navigationBar;
            for (UIView *v in bar.subviews) {
                if (![v isKindOfClass:[UILabel class]]) continue;
                NSString *t = ((UILabel *)v).text;
                if (t.length) { title = t; break; }
            }
        }
        if (title.length) [store setConversationName:title forSession:sid];
        DSADiagLog([NSString stringWithFormat:@"[BIND] sid=%@ agent=%@ title=%@",
                     sid, agentId, title ?: @"(none)"]);
        DSALastAgentId = nil;
        DSARefreshNativeSidebar();      // ★ 立即刷新，智能体对话才会出现
    } @catch (__unused NSException *e) {
        DSADiagLog([NSString stringWithFormat:@"[BIND] exception %@", e.reason]);
    }
}

/// 隐藏提示词消息（扫描可见 cell，文字等于任一智能体提示词就隐藏）
static void DSAHidePromptMessages(void) {
    @try {
        DSAStore *store = [DSAStore shared];
        [store loadIfNeeded];
        NSMutableArray *prompts = [NSMutableArray array];
        for (DSAAgent *ag in store.agents)
            if (ag.systemPrompt.length) [prompts addObject:ag.systemPrompt];
        if (!prompts.count) return;

        UIWindow *w = DSAKeyWindow();
        NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
        int guard = 0;
        while (stack.count && guard++ < 5000) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            for (UIView *s2 in v.subviews) [stack addObject:s2];
            if (!v.window) continue;
            BOOL isCell = [v isKindOfClass:[UICollectionViewCell class]] || [v isKindOfClass:[UITableViewCell class]];
            if (!isCell) continue;
            // 取 cell 里所有 label 的拼接文本
            NSMutableString *txt = [NSMutableString string];
            NSMutableArray *st2 = [NSMutableArray arrayWithObject:v];
            while (st2.count) {
                UIView *c = st2.lastObject; [st2 removeLastObject];
                for (UIView *s3 in c.subviews) [st2 addObject:s3];
                if ([c isKindOfClass:[UILabel class]]) [txt appendString:((UILabel *)c).text ?: @""];
                if ([c isKindOfClass:[UITextView class]]) [txt appendString:((UITextView *)c).text ?: @""];
            }
            for (NSString *p in prompts) {
                if (p.length >= 6 && [txt containsString:[p substringToIndex:MIN((NSUInteger)30, p.length)]]) {
                    if (!v.hidden) {
                        v.hidden = YES;
                        v.alpha = 0;
                        v.userInteractionEnabled = NO;
                        DSADiagLog([NSString stringWithFormat:@"[HIDE] prompt cell %@ hidden",
                                     NSStringFromClass([v class])]);
                    }
                    break;
                }
            }
        }
    } @catch (__unused NSException *e) {
        DSADiagLog([NSString stringWithFormat:@"[HIDE] exception %@", e.reason]);
    }
}

#pragma mark - 底层直发

/// 在输入区容器 / 页面控制器上找 App 自己的发送方法并调用
static BOOL DSATryDirectSend(void) {
    @try {
        UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
        if (!top) return NO;

        // 收集候选对象：top VC、nav、以及类名含 InputArea 的视图
        NSMutableArray *targets = [NSMutableArray arrayWithObject:top];
        if (top.navigationController) [targets addObject:top.navigationController];
        UIWindow *w = DSAKeyWindow();
        NSMutableArray *stack = [NSMutableArray arrayWithObject:(UIView *)w];
        int g = 0;
        while (stack.count && g++ < 3000) {
            UIView *v = stack.lastObject; [stack removeLastObject];
            for (UIView *s2 in v.subviews) [stack addObject:s2];
            if (!v.window) continue;
            if ([NSStringFromClass([v class]) containsString:@"InputArea"]) [targets addObject:v];
        }

        NSArray *sels = @[ @"sendPrompt", @"sendMessage", @"submit", @"send", @"doSend" ];
        for (id t in targets) {
            for (NSString *sn in sels) {
                SEL sel = NSSelectorFromString(sn);
                if ([t respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [t performSelector:sel];
#pragma clang diagnostic pop
                    DSADiagLog([NSString stringWithFormat:@"[INJ] called -[%@ %@]",
                                 NSStringFromClass([t class]), sn]);
                    return YES;
                }
            }
        }
    } @catch (__unused NSException *e) {
        DSADiagLog([NSString stringWithFormat:@"[INJ] direct send exception %@", e.reason]);
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
            DSALastAgentId = [pending copy];                // 记住是哪个智能体
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
                DSABindCurrentSession();
                DSAHidePromptMessages();
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
