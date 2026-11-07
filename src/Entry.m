//
//  Entry.m — 「智能体」入口
//
//  插入策略（按优先级，安全第一）：
//    1. 如果列表本身是 UITableView/UICollectionView 且没有 header → 直接当 headerView（永远在列表内部，不会跑到状态栏）
//    2. 否则插到列表的父视图，并要求「条 + 列表」一起在一个安全区域内（父视图高度 > 列表高度）
//    3. 都不满足就放弃（宁可不显示，也不要挡住状态栏）
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"
#import "AgentListController.h"

static char kDSAEntryTag;
static char kDSAEntryBarTag;

@interface DSAEntryProxy : NSObject
+ (void)tapped;
@end

@implementation DSAEntryProxy
+ (void)tapped {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
        while ([top isKindOfClass:[UIAlertController class]] && top.presentedViewController)
            top = top.presentedViewController;
        if (!top) return;
        if ([top isKindOfClass:[DSAAgentListController class]]) return;
        if ([top isKindOfClass:[UINavigationController class]] &&
            [[(UINavigationController *)top topViewController] isKindOfClass:[DSAAgentListController class]]) return;
        [top presentViewController:[DSAAgentListController presentedRoot] animated:YES completion:nil];
    });
}
@end

/// 造一个 44pt 高的入口条
static UIView *DSAMakeEntryBar(void) {
    UIView *bar = [UIView new];
    bar.backgroundColor = UIColor.clearColor;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    btn.contentEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 16);
    btn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [btn setTitle:@"🤖  智能体" forState:UIControlStateNormal];
    [btn addTarget:[DSAEntryProxy class] action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    btn.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [bar addSubview:btn];

    UIView *line = [UIView new];
    line.backgroundColor = [UIColor separatorColor];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [btn.topAnchor constraintEqualToAnchor:bar.topAnchor],
        [btn.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [btn.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [btn.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [line.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:16],
        [line.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-16],
        [line.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [line.heightAnchor constraintEqualToConstant:0.5],
    ]];
    return bar;
}

void DSAEnsureEntry(UIView *view) {
    if (!view || !view.window) return;
    if (objc_getAssociatedObject(view, &kDSAEntryTag)) return;

    // —— 方案 1：作为表格的 headerView ——
    if ([view isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)view;
        if (!tv.tableHeaderView) {
            UIView *bar = DSAMakeEntryBar();
            bar.frame = CGRectMake(0, 0, tv.bounds.size.width, 44);
            tv.tableHeaderView = bar;
            objc_setAssociatedObject(view, &kDSAEntryTag, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
    }
    if ([view isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)view;
        if (!cv.backgroundView) {
            UIView *bar = DSAMakeEntryBar();
            // 集合视图没有 headerView 的通用位置，退化为方案 2
            (void)bar;
        }
    }

    // —— 方案 2：插到父视图，且父视图必须明显更高（说明列表上面有空间）——
    UIView *host = view.superview;
    if (!host) return;
    if (objc_getAssociatedObject(host, &kDSAEntryBarTag)) return;
    if (![view isKindOfClass:[UIScrollView class]]) return;

    UIWindow *w = view.window;
    CGRect listInHost = [view convertRect:view.bounds toView:host];
    BOOL roomAbove = listInHost.origin.y >= 44;      // 列表上方至少有 44pt
    if (!roomAbove) return;
    if (host.bounds.size.height < w.bounds.size.height * 0.5) return;  // 父视图太小，说明是某个小卡片

    UIView *bar = DSAMakeEntryBar();
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:view.topAnchor],
        [bar.heightAnchor constraintEqualToConstant:44],
    ]];
    objc_setAssociatedObject(host, &kDSAEntryBarTag, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kDSAEntryTag, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
