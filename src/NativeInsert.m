//
//  NativeInsert.m — 把「智能体」入口插进原生会话列表（搜索框下面）
//
//  识别方法（不再猜视图层级）：
//    遍历窗口里所有 UITableView / UICollectionView，看它**可见 cell 的类名**——
//    会话列表的 cell 类名含 "SessionList"（真机类名 DeepSeek_Chat.SessionListCollectionView.Cell）。
//    消息流的 cell 是气泡类，不含 SessionList，所以不会误判。
//
//  插入方法：
//    entry.bottom = list.topAnchor（紧跟在搜索框下面，不会跑到状态栏）
//    entry.height = 44，leading/trailing 跟随列表
//
//  识别成功后会移除悬浮胶囊（原生入口优先）。
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"

static char kDSANativeTag;          // 已插入的列表
static char kDSANativeBarTag;       // 条本身

@interface DSAEntryProxy : NSObject
+ (void)tapped;
@end

void DSADiagLog(NSString *line);
void DSARemoveFloatingPill(void);   // Entry.m 提供

static UIView *DSAMakeNativeBar(void) {
    UIView *bar = [[UIView alloc] initWithFrame:CGRectZero];
    bar.backgroundColor = [UIColor clearColor];

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

    UIView *line = [[UIView alloc] initWithFrame:CGRectZero];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = [UIColor separatorColor];
    [bar addSubview:line];

    [NSLayoutConstraint activateConstraints:@[
        [btn.topAnchor constraintEqualToAnchor:bar.topAnchor],
        [btn.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [btn.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [btn.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [lab.leadingAnchor constraintEqualToAnchor:btn.leadingAnchor constant:16],
        [lab.centerYAnchor constraintEqualToAnchor:btn.centerYAnchor],
        [line.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:16],
        [line.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-16],
        [line.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [line.heightAnchor constraintEqualToConstant:0.5],
    ]];
    return bar;
}

/// 该列表是不是「会话列表」：看可见 cell 的类名
static BOOL DSAIsSessionList(UIView *v) {
    NSString *own = NSStringFromClass([v class]);
    if ([own containsString:@"SessionList"]) return YES;

    NSArray *cells = nil;
    if ([v isKindOfClass:[UICollectionView class]])
        cells = [(UICollectionView *)v visibleCells];
    else if ([v isKindOfClass:[UITableView class]])
        cells = [(UITableView *)v visibleCells];
    if (!cells.count) return NO;
    for (id c in cells) {
        NSString *cc = NSStringFromClass([c class]);
        if ([cc containsString:@"SessionList"] || [cc containsString:@"SessionCell"] ||
            [cc containsString:@"ConversationCell"])
            return YES;
    }
    return NO;
}

/// 找到会话列表并插入；返回 YES = 已插入
BOOL DSAInsertIntoNativeList(void) {
    UIWindow *w = DSAKeyWindow();
    if (!w) return NO;

    __block UIView *target = nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
    int guard = 0;
    while (stack.count && guard++ < 5000) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        for (UIView *s in v.subviews) [stack addObject:s];
        if (!v.window) continue;
        BOOL isList = [v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]];
        if (!isList) continue;
        if (objc_getAssociatedObject(v, &kDSANativeTag)) return NO;   // 已经插过了
        if (DSAIsSessionList(v)) { target = v; break; }
    }
    if (!target) return NO;

    UIView *host = target.superview;
    if (!host) return NO;
    if (objc_getAssociatedObject(host, &kDSANativeBarTag)) return NO;

    UIView *bar = DSAMakeNativeBar();
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:bar];

    // 关键：条的底边贴着列表顶边 → 正好在搜索框下面，绝不会跑到状态栏
    NSLayoutConstraint *bottom = [bar.bottomAnchor constraintEqualToAnchor:target.topAnchor];
    NSLayoutConstraint *h = [bar.heightAnchor constraintEqualToConstant:44];
    NSLayoutConstraint *lead = [bar.leadingAnchor constraintEqualToAnchor:target.leadingAnchor];
    NSLayoutConstraint *trail = [bar.trailingAnchor constraintEqualToAnchor:target.trailingAnchor];
    // 顶边不低于容器顶（防止列表 y=0 时条跑到屏幕外）
    NSLayoutConstraint *topGuard = [bar.topAnchor constraintGreaterThanOrEqualToAnchor:host.topAnchor];
    topGuard.priority = UILayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[bottom, h, lead, trail, topGuard]];
    [host bringSubviewToFront:bar];

    objc_setAssociatedObject(target, &kDSANativeTag, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host, &kDSANativeBarTag, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DSADiagLog([NSString stringWithFormat:@"[NATIVE] inserted on %@ (host %@)",
                 NSStringFromClass([target class]), NSStringFromClass([host class])]);

    // 原生入口已就位 → 收掉悬浮胶囊
    DSARemoveFloatingPill();
    return YES;
}

/// 由定时任务调用：找到就插，插过就不再管
void DSAEnsureNativeEntry(void) {
    @try { DSAInsertIntoNativeList(); }
    @catch (__unused NSException *e) {
        DSADiagLog([NSString stringWithFormat:@"[NATIVE] exception %@", e.reason]);
    }
}
