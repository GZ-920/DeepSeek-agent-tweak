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
static char kDSANativeHostTag;

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
    lab.text = @"智能体";
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

/// 找搜索框（真机类名 DeepSeek_Chat.SessionListSearchBarView）
static UIView *DSAFindSearchBar(UIView *root) {
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    int guard = 0;
    UIView *best = nil;
    while (stack.count && guard++ < 4000) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        for (UIView *s2 in v.subviews) [stack addObject:s2];
        if (!v.window) continue;
        NSString *c = NSStringFromClass([v class]);
        if ([c containsString:@"SearchBar"] || [c containsString:@"SearchField"]) {
            // 取最靠上的那个
            CGRect r = [v convertRect:v.bounds toView:nil];
            if (!best || r.origin.y < [best convertRect:best.bounds toView:nil].origin.y) best = v;
        }
    }
    return best;
}

/// 把钉住 target.top 的**原有**约束常量加大 delta（不新增约束，避免和现有布局打架）
static BOOL DSAMakeRoom(UIView *target, UIView *host, CGFloat delta) {
    for (NSLayoutConstraint *c in host.constraints) {
        if (c.firstItem == target && c.firstAttribute == NSLayoutAttributeTop &&
            c.relation == NSLayoutRelationEqual) {
            c.constant += delta;
            DSADiagLog([NSString stringWithFormat:@"[NATIVE] pushed list down (host constraint constant=%.0f)", c.constant]);
            return YES;
        }
    }
    for (NSLayoutConstraint *c in target.constraints) {
        if (c.firstItem == host && c.firstAttribute == NSLayoutAttributeTop &&
            c.relation == NSLayoutRelationEqual) {
            c.constant += delta;
            DSADiagLog([NSString stringWithFormat:@"[NATIVE] pushed list down (target constraint constant=%.0f)", c.constant]);
            return YES;
        }
    }
    // 兜底：找任何把 target.top 约束到 host 系的等式约束
    for (NSLayoutConstraint *c in host.constraints) {
        if (c.firstItem == target && c.firstAttribute == NSLayoutAttributeTop &&
            c.relation != NSLayoutRelationGreaterThanOrEqual) {
            c.constant += delta;
            DSADiagLog([NSString stringWithFormat:@"[NATIVE] pushed list down (fallback constraint constant=%.0f)", c.constant]);
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

    // —— 优先：锚定到搜索框正下方 ——
    UIView *search = DSAFindSearchBar(target.window ?: target);
    UIView *bar = DSAMakeNativeBar();
    bar.translatesAutoresizingMaskIntoConstraints = NO;

    if (search && search != target) {
        UIView *shost = search.superview;
        if (!shost) shost = host;
        if (objc_getAssociatedObject(shost, &kDSANativeBarTag)) return NO;
        [shost addSubview:bar];

        // 条 = 搜索框下沿起，高 44
        [NSLayoutConstraint activateConstraints:@[
            [bar.topAnchor constraintEqualToAnchor:search.bottomAnchor],
            [bar.heightAnchor constraintEqualToConstant:44],
            [bar.leadingAnchor constraintEqualToAnchor:search.leadingAnchor],
            [bar.trailingAnchor constraintEqualToAnchor:search.trailingAnchor],
        ]];
        // 列表不能盖住条：按需把它的**原有**顶部约束加大，而不是新增冲突约束
        if (target.superview == shost || [target isDescendantOfView:shost]) {
            [shost layoutIfNeeded];
            CGFloat searchBottomInHost = [search convertRect:search.bounds toView:shost].origin.y +
                                         search.bounds.size.height;
            CGFloat targetTopInHost = [target convertRect:target.bounds toView:shost].origin.y;
            CGFloat need = (searchBottomInHost + 44) - targetTopInHost;
            DSADiagLog([NSString stringWithFormat:@"[NATIVE] searchBottom=%.0f targetTop=%.0f need=%.0f",
                         searchBottomInHost, targetTopInHost, need]);
            if (need > 1) {
                CGFloat hBefore = search.bounds.size.height;
                // 找到要改的那条约束，先记下原值以便回滚
                NSLayoutConstraint *hitC = nil;
                for (NSLayoutConstraint *c in shost.constraints) {
                    if (c.firstItem == target && c.firstAttribute == NSLayoutAttributeTop &&
                        c.relation == NSLayoutRelationEqual) { hitC = c; break; }
                }
                if (!hitC) {
                    for (NSLayoutConstraint *c in target.constraints) {
                        if (c.firstAttribute == NSLayoutAttributeTop && c.relation == NSLayoutRelationEqual) {
                            hitC = c; break;
                        }
                    }
                }
                if (!hitC) {
                    DSADiagLog(@"[NATIVE] no top constraint to push, abort");
                    [bar removeFromSuperview];
                    return NO;
                }
                CGFloat c0 = hitC.constant;
                // 与 NativeSidebar 共用累计 key，避免同一列表被推两次
                static NSString *const kTot = @"DSATotalPush";
                NSNumber *prev = objc_getAssociatedObject(target, (__bridge const void *)kTot);
                CGFloat already = prev ? prev.doubleValue : 0;
                CGFloat add = need - already;
                if (add <= 1) add = 0;
                DSADiagLog([NSString stringWithFormat:@"[NATIVE] need=%.0f already=%.0f add=%.0f",
                             need, already, add]);
                if (add == 0) {
                    DSADiagLog(@"[NATIVE] already pushed enough, skip");
                    [shost bringSubviewToFront:bar];
                    objc_setAssociatedObject(target, &kDSANativeTag, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(shost, &kDSANativeBarTag, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    objc_setAssociatedObject(w, &kDSANativeHostTag, shost, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    DSADiagLog(@"[NATIVE] inserted BELOW SEARCH (no extra push)");
                    DSARemoveFloatingPill();
                    DSARemoveProbePill();
                    return YES;
                }
                hitC.constant += add;
                objc_setAssociatedObject(target, (__bridge const void *)kTot, @(already + add),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [shost layoutIfNeeded];
                CGFloat hAfter = search.bounds.size.height;
                DSADiagLog([NSString stringWithFormat:@"[NATIVE] pushed by %.0f; search h %.0f -> %.0f",
                             add, hBefore, hAfter]);
                if (fabs(hAfter - hBefore) > 12) {          // 搜索框被拉伸了 → 回滚
                    hitC.constant = c0;
                    objc_setAssociatedObject(target, (__bridge const void *)kTot, @(already),
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    [shost layoutIfNeeded];
                    DSADiagLog(@"[NATIVE] search bar stretched → rolled back");
                    [bar removeFromSuperview];
                    return NO;
                }
            }
        }
        [shost bringSubviewToFront:bar];
        objc_setAssociatedObject(target, &kDSANativeTag, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(shost, &kDSANativeBarTag, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(w, &kDSANativeHostTag, shost, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DSADiagLog([NSString stringWithFormat:@"[NATIVE] inserted BELOW SEARCH on %@ (shost %@)",
                     NSStringFromClass([search class]), NSStringFromClass([shost class])]);
        DSARemoveFloatingPill();
        DSARemoveProbePill();
        return YES;
    }

    // —— 兜底：列表上方空隙 ——
    UIView *host2 = host;
    CGRect tf = [target convertRect:target.bounds toView:host2];
    CGFloat gap = tf.origin.y;
    if (gap < 40) {
        if (!DSAMakeRoom(target, host2, 44)) {
            DSADiagLog(@"[NATIVE] cannot make room (no top constraint found), keeping pill");
            return NO;
        }
        tf = [target convertRect:target.bounds toView:host2];
        gap = tf.origin.y;
        DSADiagLog([NSString stringWithFormat:@"[NATIVE] gap after push = %.0f", gap]);
        if (gap < 40) return NO;
    }

    [host2 addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [bar.bottomAnchor constraintEqualToAnchor:target.topAnchor],
        [bar.heightAnchor constraintEqualToConstant:MIN(gap, 44.0)],
        [bar.leadingAnchor constraintEqualToAnchor:target.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:target.trailingAnchor],
        [bar.topAnchor constraintGreaterThanOrEqualToAnchor:host2.topAnchor],
    ]];
    [host2 bringSubviewToFront:bar];

    objc_setAssociatedObject(target, &kDSANativeTag, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host, &kDSANativeBarTag, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(w, &kDSANativeHostTag, host, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DSADiagLog([NSString stringWithFormat:@"[NATIVE] inserted on %@ gap=%.0f",
                 NSStringFromClass([target class]), gap]);

    DSARemoveFloatingPill();
    DSARemoveProbePill();
    return YES;
}

/// 侧边栏打开时把列表入口条藏起来（避免出现两个「智能体」）
static void DSAHideEntryIfSidebarOpen(UIWindow *w) {
    BOOL sidebarOpen = NO;
    NSMutableArray *st = [NSMutableArray arrayWithObject:w];
    int g = 0;
    while (st.count && g++ < 3000) {
        UIView *v = st.lastObject; [st removeLastObject];
        for (UIView *s2 in v.subviews) [st addObject:s2];
        if (!v.window || v.hidden || v.alpha < 0.05) continue;
        if (![NSStringFromClass([v class]) containsString:@"Sidebar"]) continue;
        CGRect r = [v convertRect:v.bounds toView:nil];
        if (v.bounds.size.width > 40 && v.bounds.size.width < w.bounds.size.width * 0.95 &&
            r.origin.x >= -v.bounds.size.width * 0.5) { sidebarOpen = YES; break; }
    }
    UIView *host = objc_getAssociatedObject(w, &kDSANativeHostTag);
    UIView *bar = host ? objc_getAssociatedObject(host, &kDSANativeBarTag) : nil;
    if (bar && bar.hidden != sidebarOpen) bar.hidden = sidebarOpen;
}

void DSAEnsureNativeEntry(void) {
    @try {
        UIWindow *w = DSAKeyWindow();
        if (w) DSAHideEntryIfSidebarOpen(w);
        DSAInsertIntoNativeList();
    } @catch (__unused NSException *e) {
        DSADiagLog([NSString stringWithFormat:@"[NATIVE] exception %@", e.reason]);
    }
}
