//
//  Tweak.xm — 智能体功能注入入口
//
#import <UIKit/UIKit.h>
#import "AgentStore.h"

extern void DSAEnsureEntry(UIView *view);
extern void DSAOnSessionShown(NSString *sessionId);

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
        [[DSAStore shared] loadIfNeeded];
        NSLog(@"[DSAgent] loaded");
    }
}
