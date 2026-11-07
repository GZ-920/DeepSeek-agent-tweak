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
static BOOL dispatching = NO;
static BOOL DSAFloatingDisabled(void) {
    static BOOL v; static dispatch_once_t once;
    dispatch_once(&once, ^{ v = [[NSUserDefaults standardUserDefaults] boolForKey:@"DSAFloatingDisabled"]; });
    return v;
}

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

    UIControl *btn = [[UIControl alloc] initWithFrame:CGRectZero];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn addTarget:[DSAEntryProxy class] action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:btn];

    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectZero];
    lab.translatesAutoresizingMaskIntoConstraints = NO;
    lab.text = @"🤖  智能体";
    lab.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    lab.textColor = [UIColor colorWithRed:0.29 green:0.48 blue:1.0 alpha:1.0];
    lab.userInteractionEnabled = NO;
    [btn addSubview:lab];
    [NSLayoutConstraint activateConstraints:@[
        [lab.leadingAnchor constraintEqualToAnchor:btn.leadingAnchor constant:16],
        [lab.centerYAnchor constraintEqualToAnchor:btn.centerYAnchor],
    ]];

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

/// 悬浮胶囊：先复刻「探针已验证可见」的画法（蓝底圆角 + 白字 UILabel），再放最上层
static void DSAInstallFloatingEntry(void) {
    if (DSAFloatingDisabled()) return;
    UIWindow *w = DSAKeyWindow();
    if (!w) { NSLog(@"[DSAgent] floating: no key window"); return; }
    if (objc_getAssociatedObject(w, &kDSAFloatingTag)) return;
    if (dispatching) return;

    // 和探针完全一致：UIControl(76x34) + 背景 + 圆角 + UILabel 子视图
    CGRect f = CGRectMake(w.bounds.size.width - 84, 200, 76, 34);
    UIControl *pill = [[UIControl alloc] initWithFrame:f];
    pill.backgroundColor = [UIColor colorWithRed:0.29 green:0.48 blue:1.0 alpha:1.0];
    pill.layer.cornerRadius = 17;
    pill.clipsToBounds = YES;
    [pill addTarget:[DSAEntryProxy class] action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];

    UILabel *lab = [[UILabel alloc] initWithFrame:pill.bounds];
    lab.text = @"智能体";
    lab.font = [UIFont boldSystemFontOfSize:13];
    lab.textColor = UIColor.whiteColor;
    lab.textAlignment = NSTextAlignmentCenter;
    lab.backgroundColor = [UIColor clearColor];
    lab.userInteractionEnabled = NO;
    [pill addSubview:lab];

    [w addSubview:pill];
    [w bringSubviewToFront:pill];
    objc_setAssociatedObject(w, &kDSAFloatingTag, pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSLog(@"[DSAgent] floating entry at %@ window=%@", NSStringFromCGRect(pill.frame),
          NSStringFromClass([w class]));
    @try {
        NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [[NSString stringWithFormat:@"floating ok %@ %@ %@\n", [NSDate date],
          NSStringFromCGRect(pill.frame), NSStringFromClass([w class])]
            writeToFile:[dir stringByAppendingPathComponent:@"DSAgent_float.txt"] atomically:YES
               encoding:NSUTF8StringEncoding error:nil];
    } @catch (__unused NSException *e) {}
}

#pragma mark - 对外
static void DSAEnsureEntryUnsafe(UIView *view);

void DSAEnsureEntry(UIView *view) {
    if (!view || !view.window) return;
    @try { DSAEnsureEntryUnsafe(view); }
    @catch (__unused NSException *e) { NSLog(@"[DSAgent] entry failed: %@", e.reason); }
}

static void DSAEnsureEntryUnsafe(UIView *view) {

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
    // 没有合适空位 → 交给「页面出现」时机去挂悬浮入口（不在布局回调里做）
}

/// 启动/切换页面时调用：保证悬浮入口存在（幂等、整块包 @try）
void DSAEnsureFloatingEntry(void) {
    if (dispatching) return;
    dispatching = YES;
    @try { DSAInstallFloatingEntry(); }
    @catch (__unused NSException *e) { NSLog(@"[DSAgent] floating failed: %@", e.reason); }
    @finally { dispatching = NO; }
}
