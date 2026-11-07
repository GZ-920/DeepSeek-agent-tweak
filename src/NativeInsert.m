//
//  NativeInsert.m — 把「智能体」入口插进原生会话列表
//
//  识别：可见 cell 类名含 SessionList
//  插入：优先用「列表上方空隙」；空隙不足时，找到钉住列表 top 的约束并把它下移 44pt 腾出空间
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"

static char kDSANativeTag;
static char kDSANativeBarTag;

@interface DSAEntryProxy : NSObject
+ (void)tapped;
@end

void DSADiagLog(NSString *line);
void DSARemoveFloatingPill(void);
void DSARemoveProbePill(void);

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

static BOOL DSAIsSessionList(UIView *v) {
    NSString *own = NSStringFromClass([v class]);
    if ([own containsString:@"SessionList"]) return YES;
    NSArray *cells = nil;
    if ([v isKindOfClass:[UICollectionView class]]) cells = [(UICollectionView *)v visibleCells];
    else if ([v isKindOfClass:[UITableView class]]) cells = [(UITableView *)v visibleCells];
    if (!cells.count) return NO;
    for (id c in cells) {
        NSString *cc = NSStringFromClass([c class]);
        if ([cc containsString:@"SessionList"] || [cc containsString:@"SessionCell"] ||
            [cc containsString:@"ConversationCell"])
            return YES;
    }
    return NO;
}

/// 打印 target 及祖先链在 window 里的坐标（诊断用）
static void DSADumpGeom(UIView *target) {
    UIWindow *w = target.window;
    NSMutableString *out = [NSMutableString string];
    UIView *v = target;
    for (int i = 0; i < 5 && v; i++, v = v.superview) {
        CGRect r = [v convertRect:v.bounds toView:nil];
        [out appendFormat:@"\n  L%d %@ frame(win)=%.0f,%.0f %.0fx%.0f",
         i, NSStringFromClass([v class]), r.origin.x, r.origin.y, r.size.width, r.size.height];
    }
    // 找搜索框
    NSMutableArray *stack = [NSMutableArray arrayWithObject:w ?: target];
    int guard = 0;
    while (stack.count && guard++ < 4000) {
        UIView *x = stack.lastObject;
        [stack removeLastObject];
        for (UIView *s in x.subviews) [stack addObject:s];
        NSString *c = NSStringFromClass([x class]);
        if ([c containsString:@"Search"] && x.window) {
            CGRect r = [x convertRect:x.bounds toView:nil];
            [out appendFormat:@"\n  [SEARCH] %@ %.0f,%.0f %.0fx%.0f", c, r.origin.x, r.origin.y, r.size.width, r.size.height];
        }
    }
    DSADiagLog([NSString stringWithFormat:@"[NATIVE] geom%@", out]);
}

/// 尝试把钉住 target.top 的约束常量加大 44pt，腾出空间
static BOOL DSAMakeRoom(UIView *target, UIView *host) {
    for (NSLayoutConstraint *c in host.constraints) {
        if (c.firstItem == target && c.firstAttribute == NSLayoutAttributeTop &&
            c.relation == NSLayoutRelationEqual) {
            c.constant += 44;
            DSADiagLog([NSString stringWithFormat:@"[NATIVE] pushed list down via host constraint (constant=%.0f)", c.constant]);
            return YES;
        }
    }
    for (NSLayoutConstraint *c in target.constraints) {
        if (c.firstItem == host && c.firstAttribute == NSLayoutAttributeTop &&
            c.relation == NSLayoutRelationEqual) {
            c.constant += 44;
            DSADiagLog([NSString stringWithFormat:@"[NATIVE] pushed list down via target constraint (constant=%.0f)", c.constant]);
            return YES;
        }
    }
    return NO;
}

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
        if (objc_getAssociatedObject(v, &kDSANativeTag)) return NO;
        if (DSAIsSessionList(v)) { target = v; break; }
    }
    if (!target) return NO;

    UIView *host = target.superview;
    if (!host) return NO;
    if (objc_getAssociatedObject(host, &kDSANativeBarTag)) return NO;

    DSADumpGeom(target);

    // 列表在 host 里的顶部位置
    CGRect tf = [target convertRect:target.bounds toView:host];
    CGFloat gap = tf.origin.y;
    BOOL needRoom = (gap < 40);
    if (needRoom) {
        if (!DSAMakeRoom(target, host)) {
            DSADiagLog(@"[NATIVE] cannot make room (no top constraint found), keeping pill");
            return NO;   // 腾不出空间就别插，避免条跑到状态栏
        }
        tf = [target convertRect:target.bounds toView:host];
        gap = tf.origin.y;
        DSADiagLog([NSString stringWithFormat:@"[NATIVE] gap after push = %.0f", gap]);
        if (gap < 40) return NO;
    }

    UIView *bar = DSAMakeNativeBar();
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:bar];

    NSLayoutConstraint *bottom = [bar.bottomAnchor constraintEqualToAnchor:target.topAnchor];
    NSLayoutConstraint *h = [bar.heightAnchor constraintEqualToConstant:MIN(gap, 44.0)];
    NSLayoutConstraint *lead = [bar.leadingAnchor constraintEqualToAnchor:target.leadingAnchor];
    NSLayoutConstraint *trail = [bar.trailingAnchor constraintEqualToAnchor:target.trailingAnchor];
    NSLayoutConstraint *topGuard = [bar.topAnchor constraintGreaterThanOrEqualToAnchor:host.topAnchor];
    [NSLayoutConstraint activateConstraints:@[bottom, h, lead, trail, topGuard]];
    [host bringSubviewToFront:bar];

    objc_setAssociatedObject(target, &kDSANativeTag, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host, &kDSANativeBarTag, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DSADiagLog([NSString stringWithFormat:@"[NATIVE] inserted on %@ gap=%.0f",
                 NSStringFromClass([target class]), gap]);

    DSARemoveFloatingPill();
    DSARemoveProbePill();
    return YES;
}

void DSAEnsureNativeEntry(void) {
    @try { DSAInsertIntoNativeList(); }
    @catch (__unused NSException *e) {
        DSADiagLog([NSString stringWithFormat:@"[NATIVE] exception %@", e.reason]);
    }
}
