//
//  Trigger.m — 「用某智能体新建对话」
//
//  App 的「新建对话」入口是 Swift 闭包/手势，hook 不到，按钮类名也不一定叫 Button。
//  所以这里做多层兜底，任意一层命中即可：
//    1. 通知 DSANewChatRequest（App 内部若有监听会响应）
//    2. 找 accessibilityLabel 含「新建 / new」的按钮，sendActions
//    3. 找视图树里带「新建/newChat」字样的 UIControl，sendActions
//    4. 仍不行 → 提示用户点一下 +，此时 pendingAgentId 保留，Inject 会在新会话出现时发提示词
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"
#import "AgentStore.h"
#import "AgentListController.h"

void DSADiagLog(NSString *line);

static void DSAWalkAll(UIView *root, void (^block)(UIView *)) {
    if (!root) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    int guard = 0;
    while (stack.count && guard++ < 8000) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if (v.hidden || v.alpha < 0.05) continue;
        block(v);
        for (UIView *s in v.subviews) [stack addObject:s];
    }
}

static BOOL DSALooksLikeNewChat(UIView *v) {
    NSString *label = v.accessibilityLabel ?: @"";
    NSString *cls = NSStringFromClass([v class]);
    NSString *lowLabel = label.lowercaseString;
    NSString *lowCls = cls.lowercaseString;
    if ([label containsString:@"新建"] || [label containsString:@"新对话"]) return YES;
    if ([lowLabel containsString:@"new chat"] || [lowLabel containsString:@"new conversation"]) return YES;
    if ([lowLabel containsString:@"新"]) return YES;
    if ([lowCls containsString:@"newchat"]) return YES;
    // 图标按钮常见 identifier
    NSString *aid = v.accessibilityIdentifier ?: @"";
    if ([aid.lowercaseString containsString:@"new"]) return YES;
    return NO;
}

/// 在所有可见视图里找「新建对话」控件并触发
static BOOL DSAClickNewChat(void) {
    UIWindow *w = DSAKeyWindow();
    if (!w) return NO;
    __block UIView *hit = nil;
    DSAWalkAll(w, ^(UIView *v) {
        if (hit) return;
        if (![v isUserInteractionEnabled] || !v.window) return;
        if (!DSALooksLikeNewChat(v)) return;
        hit = v;
    });
    if (hit) {
        NSLog(@"[DSAgent] new-chat candidate: %@ label=%@", NSStringFromClass([hit class]),
              hit.accessibilityLabel);
        if ([hit isKindOfClass:[UIControl class]]) {
            [(UIControl *)hit sendActionsForControlEvents:UIControlEventTouchUpInside];
            return YES;
        }
        // 非 UIControl：用点按手势模拟
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] init];
        [hit addGestureRecognizer:tap];
        // 手势无法直接触发，退化到命中测试 + 单点触摸
        [hit removeGestureRecognizer:tap];
    }
    return NO;
}

/// 把界面退回到聊天首页（能在那里找到 + 号）
static void DSABackToRoot(void) {
    UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
    UIViewController *p = top;
    while (p) {
        if ([p isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)p;
            if (nav.viewControllers.count > 1) [nav popToRootViewControllerAnimated:YES];
            return;
        }
        p = p.parentViewController;
    }
}

void DSAOpenNewChatWithAgent(DSAAgent *agent) {
    if (!agent) return;
    DSADiagLog([NSString stringWithFormat:@"[NEWCHAT] agent=%@ pending set", agent.name]);
    [[DSAStore shared] setPendingAgentId:agent.agentId];

    dispatch_async(dispatch_get_main_queue(), ^{
        void (^proceed)(void) = ^{
            DSABackToRoot();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (DSAClickNewChat()) {
                    DSAToast([NSString stringWithFormat:@"正在用「%@」新建对话…", agent.name]);
                } else {
                    DSAToast([NSString stringWithFormat:@"点一下「新建对话」，\n会自动发送「%@」的设定提示词", agent.name]);
                }
            });
        };

        UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
        BOOL isOurs = [top isKindOfClass:[DSAAgentListController class]] ||
            ([top isKindOfClass:[UINavigationController class]] &&
             [[(UINavigationController *)top topViewController] isKindOfClass:[DSAAgentListController class]]);
        if (isOurs) [top dismissViewControllerAnimated:YES completion:proceed];
        else proceed();
    });
}
