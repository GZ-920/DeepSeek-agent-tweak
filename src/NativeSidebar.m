//
//  NativeSidebar.m — 智能体区块（作为侧边栏的子视图）
//
//  关键设计：
//    ① 区块 addSubview 到**侧边栏视图本身** → 随侧边栏一起滑入滑出（平滑，不再硬切/残留）
//    ② **不推任何约束**（之前 push 把搜索框一起推走了）→ 改用列表的 contentInset.top
//       把列表内容下移，腾出的位置正好放区块；搜索框完全不动
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"
#import "AgentStore.h"

static char kDSASidebarSectionTag;
static CGFloat sSectionTop = -1;      // ★ 区块 top 只算一次（避免追逐会移动的搜索框）
static CGFloat sMaxPushed = 0;        // 已推送总量（防失控）
static BOOL sPushBlocked = NO;        // 校正失败后永久停止推送

@interface DSAEntryProxy : NSObject
+ (void)tapped;
@end

void DSADiagLog(NSString *line);
static UIView *DSAFindNativeSidebar(UIWindow *w);   // 前置声明（定义在文件末尾）

/// 取侧边栏真实背景色：先看 backgroundColor 是否不透明，否则渲染后采样像素
static int DSAMedian5(int *arr) {
    for (int a = 0; a < 4; a++)
        for (int b = a + 1; b < 5; b++)
            if (arr[b] < arr[a]) { int t = arr[a]; arr[a] = arr[b]; arr[b] = t; }
    return arr[2];
}

static UIColor *DSASampleBackground(UIView *sidebar) {
    UIColor *c = sidebar.backgroundColor;
    if (c) {
        CGFloat a = 1;
        if (![c getRed:NULL green:NULL blue:NULL alpha:&a]) { CGFloat w = 0; [c getWhite:&w alpha:&a]; }
        if (a >= 0.9) return c;
    }
    @try {
        CGSize sz = sidebar.bounds.size;
        if (sz.width < 4 || sz.height < 4) return [UIColor systemGroupedBackgroundColor];
        UIGraphicsImageRenderer *rend = [[UIGraphicsImageRenderer alloc] initWithSize:sz];
        UIImage *img = [rend imageWithActions:^(UIGraphicsImageRendererContext *rc) {
            [sidebar drawViewHierarchyInRect:CGRectMake(0, 0, sz.width, sz.height) afterScreenUpdates:NO];
        }];
        CGImageRef cg = img.CGImage;
        if (!cg) return [UIColor systemGroupedBackgroundColor];

        // 沿最左缘取 5 个点（x=1），按通道取中位数 → 避开采到文字
        int rs[5], gs[5], bs[5];
        for (int i = 0; i < 5; i++) {
            unsigned char px[4] = {0, 0, 0, 0};
            CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
            CGContextRef cc = CGBitmapContextCreate(px, 1, 1, 8, 4, cs,
                                                    (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
            CGColorSpaceRelease(cs);
            if (!cc) return [UIColor systemGroupedBackgroundColor];
            // CGBitmapContext y 轴向上：y=0 对应图像底边
            CGFloat yy = (i + 0.5) / 5.0;
            CGContextDrawImage(cc, CGRectMake(1, yy, 1, 1), cg);
            CGContextRelease(cc);
            rs[i] = px[0]; gs[i] = px[1]; bs[i] = px[2];
        }
        int R = DSAMedian5(rs), G = DSAMedian5(gs), B = DSAMedian5(bs);
        DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] sampled bg rgb(%d,%d,%d)", R, G, B]);
        return [UIColor colorWithRed:R / 255.0 green:G / 255.0 blue:B / 255.0 alpha:1];
    } @catch (__unused NSException *e) {
        return [UIColor systemGroupedBackgroundColor];
    }
}

#pragma mark - 区块内容

static UIView *DSAMakeAgentSection(UIColor *bg) {
    UIView *sec = [[UIView alloc] initWithFrame:CGRectZero];
    // ★ 用侧边栏同色、不透明 → 遮住后方被压到这一带的对话行
    sec.backgroundColor = bg ?: [UIColor systemGroupedBackgroundColor];
    sec.opaque = YES;

    DSAStore *store = [DSAStore shared];
    [store loadIfNeeded];
    NSArray<DSAAgent *> *agents = store.agents;

    CGFloat lead = 16, rowH = 47, fsz = 18;
    DSAMeasureListMetrics(&lead, &rowH, &fsz);

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [sec addSubview:stack];

    UILabel *(^makeHeader)(NSString *) = ^UILabel *(NSString *t) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
        l.translatesAutoresizingMaskIntoConstraints = NO;
        l.text = t;
        l.font = [UIFont systemFontOfSize:fsz - 5 weight:UIFontWeightSemibold];
        l.textColor = [UIColor secondaryLabelColor];
        [stack addArrangedSubview:l];                 // ★ 先加入，再加约束
        [NSLayoutConstraint activateConstraints:@[
            [l.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:lead],
            [l.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor constant:-lead],
            [l.heightAnchor constraintEqualToConstant:28],
        ]];
        return l;
    };

    void (^makeRow)(NSString *, NSString *, NSString *, SEL) =
    ^(NSString *title, NSString *accLabel, NSString *accValue, SEL act) {
        UIControl *row = [[UIControl alloc] initWithFrame:CGRectZero];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        row.accessibilityLabel = accLabel;
        row.accessibilityValue = accValue;
        [row addTarget:[DSAEntryProxy class] action:act forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:row];               // ★ 先加入

        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectZero];
        lab.translatesAutoresizingMaskIntoConstraints = NO;
        lab.text = title;
        lab.font = [UIFont systemFontOfSize:fsz - 3];
        lab.textColor = [UIColor labelColor];
        lab.userInteractionEnabled = NO;
        [row addSubview:lab];

        [NSLayoutConstraint activateConstraints:@[
            [row.heightAnchor constraintEqualToConstant:rowH * 0.85],
            [lab.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:lead],
            [lab.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-lead],
            [lab.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        ]];
    };

    UILabel *(^makeEmpty)(NSString *) = ^UILabel *(NSString *t) {
        UILabel *e = [[UILabel alloc] initWithFrame:CGRectZero];
        e.translatesAutoresizingMaskIntoConstraints = NO;
        e.text = t;
        e.font = [UIFont systemFontOfSize:fsz - 4];
        e.textColor = [UIColor tertiaryLabelColor];
        [stack addArrangedSubview:e];
        [e.heightAnchor constraintEqualToConstant:30].active = YES;
        [e.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:lead].active = YES;
        return e;
    };

    // 1) 智能体对话（置顶）
    makeHeader(@"智能体对话");
    NSInteger convCount = 0;
    for (DSAAgent *ag in agents) {
        for (NSString *sid in [store sessionIdsForAgent:ag.agentId]) {
            NSString *cn = [store conversationNameForSession:sid];
            NSString *label = cn.length ? [NSString stringWithFormat:@"%@ · %@", ag.name, cn] : ag.name;
            makeRow(label, label, sid, @selector(convRowTapped:));
            if (++convCount >= 8) break;
        }
        if (convCount >= 8) break;
    }
    if (!convCount) makeEmpty(@"暂无对话");

    // 2) 智能体（点击直接开新对话）
    makeHeader(@"智能体");
    for (DSAAgent *ag in agents) makeRow(ag.name, ag.name, ag.agentId, @selector(agentRowTapped:));
    if (!agents.count) makeEmpty(@"还没有智能体");

    // 3) 设置
    makeHeader(@"设置");
    makeRow(@"管理智能体", @"管理智能体", @"", @selector(settingsTapped:));

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:sec.topAnchor constant:4],
        [stack.leadingAnchor constraintEqualToAnchor:sec.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:sec.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:sec.bottomAnchor constant:-8],
    ]];

    DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] section built agents=%lu convs=%lu",
                 (unsigned long)agents.count, (unsigned long)convCount]);
    return sec;
}

#pragma mark - 插入（作为侧边栏子视图）

static BOOL DSAInsertSection(UIView *sidebar) {
    UIView *list = DSAFindSessionListView();
    if (!list || !list.superview) { DSADiagLog(@"[SIDEBAR] no list/superview"); return NO; }
    UIView *host = list.superview;                 // ★ 和列表同一个父视图，必然同层

    // 区块放进 host，并**直接插到列表上方**（aboveSubview 保证 z 序在列表之上）
    UIView *sec = objc_getAssociatedObject(host, &kDSASidebarSectionTag);
    BOOL fresh = (sec == nil);
    if (fresh) {
        sec = DSAMakeAgentSection(sidebar.backgroundColor);
        [host insertSubview:sec aboveSubview:list];
        objc_setAssociatedObject(host, &kDSASidebarSectionTag, sec, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (sec.superview != host) {
        [host insertSubview:sec aboveSubview:list];
    } else {
        [host insertSubview:sec aboveSubview:list];   // 每次都重新压到列表之上
    }

    // ★ 定位只算一次：之后沿用。否则搜索框被推送拖走 → 目标跟着变 → 无限追（实测 listTop 一路涨到 2093）
    CGRect lr = [list convertRect:list.bounds toView:host];
    CGFloat width = lr.size.width;
    if (sSectionTop < 0) {
        CGFloat top0 = lr.origin.y;
        NSMutableArray *st = [NSMutableArray arrayWithObject:host];
        int g2 = 0;
        while (st.count && g2++ < 2000) {
            UIView *v = st.lastObject; [st removeLastObject];
            for (UIView *s2 in v.subviews) [st addObject:s2];
            if (!v.window) continue;
            if ([NSStringFromClass([v class]) containsString:@"SearchBar"] && v.bounds.size.width > 100) {
                CGRect r = [v convertRect:v.bounds toView:host];
                CGFloat sb = r.origin.y + r.size.height + 4;
                if (sb > top0) top0 = sb;
                break;
            }
        }
        sSectionTop = top0;
        DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] section top locked at %.0f", sSectionTop]);
    }
    CGFloat top = sSectionTop;

    CGFloat h = [sec systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                  withHorizontalFittingPriority:UILayoutPriorityRequired
                        verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    if (h < 40) h = 200;

    sec.frame = CGRectMake(lr.origin.x, top, width, h);
    // ★ clearColor 也是「非 nil」，?: 兜底会失效 → 必须显式判断透明度
    sec.backgroundColor = DSASampleBackground(sidebar);
    sec.opaque = YES;
    sec.clipsToBounds = YES;
    sec.layer.zPosition = 10000;
    [host bringSubviewToFront:sec];

    // 诊断：这个点上到底是谁在最上层
    static int diagCount = 0;
    if (diagCount++ % 10 == 0) {
        CGPoint p = CGPointMake(CGRectGetMidX(sec.frame), CGRectGetMidY(sec.frame));
        UIView *hit = [host hitTest:p withEvent:nil];
        DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] host=%@ sec=%@ hit=%@ hostCls=%@",
                     NSStringFromClass([host class]),
                     NSStringFromCGRect(sec.frame),
                     hit ? NSStringFromClass([hit class]) : @"nil",
                     NSStringFromClass([host class])]);
    }

    // ★ 腾出空间：一次性推到位；带防失控（上限 + 搜索框校正失败即回滚并停手）
    CGFloat wantListTop = top + h + 4;
    CGFloat listTopNow = [list convertRect:list.bounds toView:host].origin.y;
    CGFloat need = wantListTop - listTopNow;
    if (need > 1 && !sPushBlocked && sMaxPushed < 700) {
        // 找搜索框（全局），推送前记位置
        UIView *sb = nil;
        UIWindow *win = host.window ?: DSAKeyWindow();
        NSMutableArray *st = [NSMutableArray arrayWithObject:(UIView *)win];
        int g2 = 0;
        while (st.count && g2++ < 3000) {
            UIView *v = st.lastObject; [st removeLastObject];
            for (UIView *s2 in v.subviews) [st addObject:s2];
            if (!v.window) continue;
            if ([NSStringFromClass([v class]) containsString:@"SearchBar"] && v.bounds.size.width > 100) { sb = v; break; }
        }
        CGFloat sbBefore = sb ? [sb convertRect:sb.bounds toView:win].origin.y : -1;
        CGFloat c0list = 0;
        NSLayoutConstraint *listC = nil;
        for (NSLayoutConstraint *c in host.constraints) {
            if (c.firstItem == list && c.firstAttribute == NSLayoutAttributeTop &&
                c.relation == NSLayoutRelationEqual) { listC = c; break; }
        }
        if (listC) c0list = listC.constant;

        if (DSAPushListToTotal(list, host, MIN(need, 700 - sMaxPushed), nil)) {
            sMaxPushed += MIN(need, 700 - sMaxPushed);
            [host layoutIfNeeded];
            BOOL ok = YES;
            if (sb && sbBefore >= 0) {
                CGFloat sbAfter = [sb convertRect:sb.bounds toView:win].origin.y;
                CGFloat d = sbAfter - sbBefore;
                if (fabs(d) > 1) {
                    // 沿搜索框的祖先链找它的 top 等式约束
                    NSLayoutConstraint *sc = nil;
                    UIView *p = sb;
                    for (int i = 0; i < 5 && p; i++, p = p.superview) {
                        for (NSLayoutConstraint *c in p.constraints) {
                            if (c.firstItem == sb && c.firstAttribute == NSLayoutAttributeTop &&
                                c.relation == NSLayoutRelationEqual) { sc = c; break; }
                        }
                        if (sc) break;
                    }
                    if (sc) {
                        sc.constant -= d;
                        [host layoutIfNeeded];
                        DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] search corrected by %.0f", -d]);
                    } else {
                        ok = NO;
                        DSADiagLog(@"[SIDEBAR] cannot correct search bar → rollback + stop pushing");
                    }
                }
            }
            if (!ok) {
                if (listC) { listC.constant = c0list; [host layoutIfNeeded]; }
                sPushBlocked = YES;
                sMaxPushed = 0;
            } else {
                DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] reserved listTop %.0f -> %.0f (total pushed %.0f)",
                             listTopNow, [list convertRect:list.bounds toView:host].origin.y, sMaxPushed]);
            }
        }
    } else if (sPushBlocked) {
        // 已停手
    }

    if (fresh) DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] section inserted above list (host %@) at y=%.0f h=%.0f",
                             NSStringFromClass([host class]), top, h]);
    return YES;
}

void DSAEnsureNativeSidebar(void) {
    @try {
        UIView *sb = DSAFindNativeSidebar(DSAKeyWindow());
        if (!sb) return;                 // 收起时不处理（区块在侧栏内部，随它一起隐藏）
        DSAInsertSection(sb);
    } @catch (__unused NSException *e) {
        DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] exception %@", e.reason]);
    }
}

void DSARefreshNativeSidebar(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = DSAKeyWindow();
        UIView *sb = DSAFindNativeSidebar(w);
        UIView *list = DSAFindSessionListView();
        UIView *sec = (list.superview ? objc_getAssociatedObject(list.superview, &kDSASidebarSectionTag) : nil)
                      ?: (sb ? objc_getAssociatedObject(sb, &kDSASidebarSectionTag) : nil);
        if (sec) {
            [sec removeFromSuperview];
            if (sec.superview) objc_setAssociatedObject(sec.superview, &kDSASidebarSectionTag, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            sSectionTop = -1;
            sMaxPushed = 0;
            sPushBlocked = NO;
            DSADiagLog(@"[SIDEBAR] section cleared for rebuild");
        }
        // 不再改 contentInset，无需还原
    });
}

#pragma mark - 侧边栏查找（可见才算）

static BOOL DSALooksLikeOpenDrawer(UIView *v, UIWindow *w) {
    if (!v || !v.window || v.hidden || v.alpha < 0.05) return NO;
    CGFloat vw = v.bounds.size.width;
    if (vw <= 40 || vw >= w.bounds.size.width * 0.95) return NO;
    CGRect r = [v convertRect:v.bounds toView:nil];
    if (r.origin.x + r.size.width <= 4) return NO;
    if (r.origin.x < -vw * 0.5) return NO;
    return YES;
}

static UIView *DSAFindNativeSidebar(UIWindow *w) {
    if (!w) return nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
    int guard = 0;
    UIView *seed = nil;
    while (stack.count && guard++ < 5000) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        for (UIView *s2 in v.subviews) [stack addObject:s2];
        if (!v.window || v.hidden || v.alpha < 0.05) continue;
        if (v.bounds.size.width < 100) continue;
        NSString *c = NSStringFromClass([v class]);
        if ([c containsString:@"MultiSelect"]) continue;
        if ([c containsString:@"SearchBar"] || [c containsString:@"SessionList"]) { seed = v; break; }
    }
    if (!seed) return nil;
    UIView *best = nil;
    UIView *p = seed;
    for (int i = 0; i < 8 && p; i++, p = p.superview)
        if (DSALooksLikeOpenDrawer(p, w)) best = p;
    if (best) return best;
    if (DSALooksLikeOpenDrawer(seed, w)) return seed;
    return nil;
}

#pragma mark - 行点击

@implementation DSAEntryProxy (SidebarRows)

+ (void)agentRowTapped:(UIControl *)sender {
    DSAAgent *ag = [[DSAStore shared] agentWithId:sender.accessibilityValue];
    if (!ag) return;
    DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] tap agent=%@ → new chat", ag.name]);
    DSAOpenNewChatWithAgent(ag);
}

+ (void)convRowTapped:(UIControl *)sender {
    NSString *sid = sender.accessibilityValue;
    if (!sid.length) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DSAOpenSessionRequest" object:nil
                                                      userInfo:@{ @"sessionId": sid }];
}

+ (void)settingsTapped:(UIControl *)sender {
    DSADiagLog(@"[SIDEBAR] open settings");
    DSAShowSettings();
}

@end
