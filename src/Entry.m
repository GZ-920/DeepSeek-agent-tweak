//
//  Entry.m — 「智能体」入口
//
//  教训：之前两次都失败——钉父视图顶部 → 顶到状态栏；加"位置不对就不显示"的保护 → 直接不显示。
//  现在改成最稳的两种落地方式：
//    A. 表格有空位 → 设为 tableHeaderView（永远在列表内部第一行）
//    B. 其他情况  → 直接挂到 UIWindow 上的悬浮胶囊，绝对坐标 + 自动避让状态栏/底部输入框
//  B 不依赖任何 App 内部视图结构，也不会挡住状态栏。
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"
#import "AgentListController.h"

static char kDSAEntryTag;
static char kDSAFloatingTag;

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

#pragma mark - A. 作为表格 header

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
    [bar addSubview:btn];

    UIView *line = [UIView new];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = [UIColor separatorColor];
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

#pragma mark - B. 悬浮胶囊

/// 悬浮胶囊：挂在 window 上，位置避开状态栏（顶部、右侧下方一点）
static void DSAInstallFloatingEntry(void) {
    UIWindow *w = DSAKeyWindow();
    if (!w) return;
    if (objc_getAssociatedObject(w, &kDSAFloatingTag)) return;

    UIButton *pill = [UIButton buttonWithType:UIButtonTypeSystem];
    [pill setTitle:@"🤖 智能体" forState:UIControlStateNormal];
    pill.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [pill setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    pill.backgroundColor = [UIColor colorWithRed:0.29 green:0.48 blue:1.0 alpha:0.92];
    pill.layer.cornerRadius = 17;
    pill.layer.shadowColor = UIColor.blackColor.CGColor;
    pill.layer.shadowOpacity = 0.18;
    pill.layer.shadowRadius = 6;
    pill.layer.shadowOffset = CGSizeMake(0, 2);
    [pill addTarget:[DSAEntryProxy class] action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];

    CGFloat h = 34, wdt = 92;
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) safeTop = w.safeAreaInsets.top;
    if (safeTop <= 0) safeTop = 44;                       // 状态栏兜底
    pill.frame = CGRectMake(w.bounds.size.width - wdt - 10, safeTop + 6, wdt, h);
    pill.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [w addSubview:pill];
    objc_setAssociatedObject(w, &kDSAFloatingTag, pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSLog(@"[DSAgent] floating entry at %@", NSStringFromCGRect(pill.frame));
}

#pragma mark - 对外

void DSAEnsureEntry(UIView *view) {
    if (!view || !view.window) return;

    // A：表格 header
    if ([view isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)view;
        // 只挑"像会话列表"的表：宽度不超过屏幕 96%
        if (tv.bounds.size.width > 0 && tv.bounds.size.width < tv.window.bounds.size.width * 0.96) {
            if (!tv.tableHeaderView) {
                UIView *bar = DSAMakeEntryBar();
                bar.frame = CGRectMake(0, 0, tv.bounds.size.width, 44);
                tv.tableHeaderView = bar;
                objc_setAssociatedObject(view, &kDSAEntryTag, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                NSLog(@"[DSAgent] entry installed as tableHeaderView on %@", NSStringFromClass([tv class]));
                return;
            }
        }
    }
    // 没有合适空位 → 保证悬浮入口在
    DSAInstallFloatingEntry();
}

/// 启动/切换页面时调用：保证悬浮入口存在（幂等）
void DSAEnsureFloatingEntry(void) {
    DSAInstallFloatingEntry();
}
