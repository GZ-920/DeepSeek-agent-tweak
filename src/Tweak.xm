//
//  Tweak.xm — 智能体功能注入入口
//
//  调试顺序（重要）：
//    1. DSA_SELFTEST：dylib 一加载就在右上角贴红色 “DSAgent ✓” 角标
//       —— 看不到角标 = dylib 根本没被注入（和 hook 写得好不好无关）
//    2. 角标出现后，再看侧栏列表顶部有没有「🤖 智能体」
//       —— 角标有、入口没有 = sessionListTable 这个属性名不对
//
#import <UIKit/UIKit.h>
#import "AgentStore.h"
#import "DSAShared.h"


%hook UIViewController

- (void)viewDidLayoutSubviews {
    %orig;
    @try {
        id v = [self valueForKey:@"sessionListTable"];
        if ([v isKindOfClass:[UIView class]] && [(UIView *)v window]) DSAEnsureEntry((UIView *)v);
    } @catch (__unused NSException *e) {}
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *cls = NSStringFromClass([self class]);
    if ([cls containsString:@"MessageViewController"] ||
        [cls containsString:@"MessageListViewController"]) {
        for (NSString *k in @[ @"sessionId", @"sessionID", @"chatSessionId", @"currentSessionId" ]) {
            @try {
                id sid = [self valueForKey:k];
                if ([sid isKindOfClass:[NSString class]] && [sid length]) {
                    DSAOnSessionShown((NSString *)sid);
                    break;
                }
            } @catch (__unused NSException *e) {}
        }
    }
}

%end

%ctor {
    @autoreleasepool {
        NSLog(@"[DSAgent] constructor running");
        [[DSAStore shared] loadIfNeeded];
#ifdef DSA_SELFTEST
        DSAInstallSelfTest();
#endif
        NSLog(@"[DSAgent] loaded");
    }
}
