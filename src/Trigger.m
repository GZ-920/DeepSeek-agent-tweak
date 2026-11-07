//
//  Trigger.m — 「用某智能体新建对话」
//
//  两段式：
//    1. 记录 pendingAgentId（会话页出现时 Inject.m 会接管发提示词）
//    2. 尽量真的新建一个对话：
//       a) 找到输入框所在页面，模拟点「新建对话 / 侧栏 +」按钮
//       b) 找不到就跳回聊天首页（pop 到根），让用户点 +；此时 pendingAgentId 依然有效
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"
#import "AgentStore.h"
#import "AgentListController.h"

extern UIViewController *DSATopMost(UIViewController *base);
extern UIWindow *DSAKeyWindow(void);
extern void DSAToast(NSString *text);

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

/// 找「新建对话」按钮：优先 accessibilityLabel，其次 systemItem 类名
static UIButton *DSAFindNewChatButton(void) {
    UIWindow *w = DSAKeyWindow();
    __block UIButton *hit = nil;
    DSAWalk(w, ^(UIView *v) {
        if (hit || ![v isKindOfClass:[UIButton class]] || !v.window) return;
        NSString *label = [(UIButton *)v accessibilityLabel] ?: @"";
        NSString *cls = NSStringFromClass([v class]);
        if ([label containsString:@"新建"] || [label.lowercaseString containsString:@"new chat"] ||
            [label.lowercaseString containsString:@"new conversation"] ||
            [cls containsString:@"NewChat"] || [cls containsString:@"Compose"])
            hit = (UIButton *)v;
    });
    return hit;
}

/// 尝试把界面退回聊天首页（可弹出侧栏的地方）
static void DSABackToChatHome(void) {
    UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
    if (!top) return;
    UINavigationController *nav = nil;
    UIViewController *p = top;
    while (p) {
        if ([p isKindOfClass:[UINavigationController class]]) { nav = (UINavigationController *)p; break; }
        p = p.parentViewController;
    }
    if (!nav) return;
    if (nav.viewControllers.count > 1) [nav popToRootViewControllerAnimated:YES];
}

void DSAOpenNewChatWithAgent(DSAAgent *agent) {
    if (!agent) return;
    [[DSAStore shared] setPendingAgentId:agent.agentId];

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = DSAKeyWindow();
        UIViewController *root = w.rootViewController;
        // 先把我们自己弹出的智能体页收掉，露出聊天界面
        UIViewController *top = DSATopMost(root);
        if ([top isKindOfClass:[DSAAgentListController class]] ||
            ([top isKindOfClass:[UINavigationController class]] &&
             [[(UINavigationController *)top topViewController] isKindOfClass:[DSAAgentListController class]])) {
            [top dismissViewControllerAnimated:YES completion:^{
                DSABackToChatHome();
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    UIButton *btn = DSAFindNewChatButton();
                    if (btn) [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
                    else DSAToast([NSString stringWithFormat:@"已选好「%@」\n点一下「新建对话」，会自动发送设定提示词", agent.name]);
                });
            }];
        } else {
            DSABackToChatHome();
            DSAToast([NSString stringWithFormat:@"已选好「%@」\n点「新建对话」后会自动发送设定提示词", agent.name]);
        }
    });
}
