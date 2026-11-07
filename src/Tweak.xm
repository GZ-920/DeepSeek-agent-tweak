//
//  Tweak.xm — 智能体功能注入入口
//
//  入口插入采用「多属性名候选 + 视图树兜底」：
//    1. 先试 App 里出现过的属性名（sessionListTable / sessionList / sessionCols...）
//    2. 都不中时，扫描屏幕上的 UITableView / UICollectionView，
//       取「高度最大且不是消息流」的那个当作会话列表
//
#import <UIKit/UIKit.h>
#import "AgentStore.h"
#import "DSAShared.h"

// 候选属性名（App 升级改名时往这里加）
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

/// 从某个 VC 上按候选属性名找列表视图
static UIView *DSAFindListByKey(id vc) {
    for (NSString *k in DSASessionListKeys()) {
        @try {
            id v = [vc valueForKey:k];
            if ([v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]]) return v;
        } @catch (__unused NSException *e) {}
    }
    return nil;
}

/// 视图树兜底：找屏幕上最像「会话列表」的滚动视图
static UIView *DSAFindListByTree(void) {
    UIWindow *w = DSAKeyWindow();
    if (!w) return nil;
    __block UIView *best = nil;
    __block CGFloat bestH = 0;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        for (UIView *s in v.subviews) [stack addObject:s];
        if (!v.window) continue;
        BOOL isList = [v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]];
        if (!isList) continue;
        // 排除消息流（通常占满整屏宽度且高度大于屏高 0.7，且 cell 是聊天气泡）；
        // 这里用「宽度 < 屏宽 0.94」来识别侧栏列表
        CGFloat h = v.frame.size.height;
        BOOL narrower = v.frame.size.width < w.bounds.size.width * 0.94;
        if (narrower && h > bestH) { best = v; bestH = h; }
    }
    return best;
}

%hook UIViewController

- (void)viewDidLayoutSubviews {
    %orig;
    UIView *list = DSAFindListByKey(self);
    if (!list) return;
#ifdef DSA_SELFTEST
    DSAScanControls(self);
#endif
    DSAEnsureEntry(list);
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

// 侧栏展开/主页出现时再兜底一次（属性名全不对时的最后一招）
- (void)viewWillAppear:(BOOL)animated {
    %orig;
#ifdef DSA_SELFTEST
    DSAScanControls(self);
#endif
    NSString *cls = NSStringFromClass([self class]);
    if ([cls containsString:@"Sidebar"] || [cls containsString:@"SessionList"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIView *list = DSAFindListByKey(self);
            if (!list) list = DSAFindListByTree();
            if (list) DSAEnsureEntry(list);
        });
    }
}

%end

// 兜底：任何滚动视图完成布局时，若页面里有 Sidebar 类 VC，再尝试一次
%hook UITableView
- (void)layoutSubviews {
    %orig;
    NSString *cls = NSStringFromClass([self class]);
    if ([cls containsString:@"Session"] || [cls containsString:@"Sidebar"] || [cls containsString:@"History"]) {
        DSAEnsureEntry(self);
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
