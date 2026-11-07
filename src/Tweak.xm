//
//  Tweak.xm — 智能体功能注入入口
//
//  所有调试开关都是「可独立关闭」的，方便闪退时二分定位：
//    DSA_SELFTEST   —— 红色角标 + 写沙盒标记
//    DSA_SCAN       —— 扫描页面属性名，写入 Documents/DSAgent_scan.txt
//    DSA_UI_FORCE   —— 注入 4 秒后强制弹出智能体页
//    DSA_TREE_FALLBACK / DSA_TABLE_HOOK —— 视图树兜底 / UITableView layout 兜底
//
#import <UIKit/UIKit.h>
#import "AgentStore.h"
#import "DSAShared.h"

static NSArray *DSASessionListKeys(void) {
    static NSArray *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[ @"sessionListTable", @"sessionTableView", @"sessionList",
                  @"sessionListView", @"sidebarTableView", @"historyTableView",
                  @"sessionCollectionView", @"conversationListView" ];
    });
    return keys;
}

static UIView *DSAFindListByKey(id vc) {
    for (NSString *k in DSASessionListKeys()) {
        @try {
            id v = [vc valueForKey:k];
            if ([v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]]) return v;
        } @catch (__unused NSException *e) {}
    }
    return nil;
}

#ifdef DSA_TREE_FALLBACK
static UIView *DSAFindListByTree(void) {
    @try {
        UIWindow *w = DSAKeyWindow();
        if (!w) return nil;
        UIView *best = nil;
        CGFloat bestH = 0;
        NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
        int guard = 0;
        while (stack.count && guard++ < 4000) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            for (UIView *s in v.subviews) [stack addObject:s];
            if (!v.window) continue;
            BOOL isList = [v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]];
            if (!isList) continue;
            CGFloat h = v.frame.size.height;
            if (v.frame.size.width < w.bounds.size.width * 0.94 && h > bestH) { best = v; bestH = h; }
        }
        return best;
    } @catch (__unused NSException *e) { return nil; }
}
#endif

%hook UIViewController

- (void)viewDidLayoutSubviews {
    %orig;
    // 诊断阶段：先不插表格 header，专注确认悬浮胶囊能否显示
    (void)self;
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

- (void)viewWillAppear:(BOOL)animated {
    %orig;
#ifdef DSA_SCAN
    DSAScanControls(self);
#endif
    NSString *cls = NSStringFromClass([self class]);
    if ([cls containsString:@"Sidebar"] || [cls containsString:@"SessionList"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIView *list = DSAFindListByKey(self);
#ifdef DSA_TREE_FALLBACK
            if (!list) list = DSAFindListByTree();
#endif
            if (list) DSAEnsureEntry(list);
        });
    }
}

%end

#ifdef DSA_TABLE_HOOK
%hook UITableView
- (void)layoutSubviews {
    %orig;
    NSString *cls = NSStringFromClass([self class]);
    if ([cls containsString:@"Session"] || [cls containsString:@"Sidebar"] || [cls containsString:@"History"]) {
        DSAEnsureEntry(self);
    }
}
%end
#endif

%ctor {
    @autoreleasepool {
        NSLog(@"[DSAgent] constructor running");
        [[DSAStore shared] loadIfNeeded];
#ifdef DSA_SELFTEST
        DSAInstallSelfTest();
#endif
        // 悬浮入口：不依赖任何 hook，启动后分几次重试挂上（幂等）
        for (double d = 1.5; d <= 9.0; d += 2.5) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                NSLog(@"[DSAgent] floating attempt @%.1fs", d);
                DSAProbeWindows();
                DSAProbeVariants();
            });
        }
        // 注入轮询：不依赖 hook，每秒一次
        dispatch_async(dispatch_get_main_queue(), ^{
            DSAInjectTick();
            __block void (^loop)(void) = ^{
                DSAInjectTick();
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ loop(); });
            };
            loop();
        });
        NSLog(@"[DSAgent] loaded");
    }
}
