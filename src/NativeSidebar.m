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
#import "DSALogos.h"

static char kDSASidebarSectionTag;
static char kDSATopConstraintTag;
static CGFloat sSectionTop = -1;      // ★ 区块 top 只算一次（避免追逐会移动的搜索框）
static CGFloat sSearchTop0 = -1;      // 搜索框原始 top（推送后强制按回）
static CGFloat sSearchH0 = -1;        // 搜索框原始 height
static CGFloat sMaxPushed = 0;        // 已推送总量（防失控）
static BOOL sPushBlocked = NO;        // 校正失败后永久停止推送

@interface DSAEntryProxy : NSObject
+ (void)tapped;
@end

void DSADiagLog(NSString *line);
static UIView *DSAFindNativeSidebar(UIWindow *w);   // 前置声明（定义在文件末尾）

/// 取侧边栏真实背景色：先看 backgroundColor 是否不透明，否则渲染后采样像素
#pragma mark - 面板视图（不透明主体 + 底部羽化渐变）

/// 背景：浅色纯白 / 深色 #0F0F0F（动态，随系统切换）
static UIColor *DSAPanelColor(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^(UITraitCollection *tc) {
            if (tc.userInterfaceStyle == UIUserInterfaceStyleDark)
                return [UIColor colorWithRed:15/255.0 green:15/255.0 blue:15/255.0 alpha:1];
            return [UIColor whiteColor];
        }];
    }
    return [UIColor whiteColor];
}

static const CGFloat kDSAFeatherH = 44;     // 羽化高度（半径大一点）
static CGFloat kFeatherSafe(CGFloat h) { return MIN(kDSAFeatherH, h); }

@interface DSAPanelView : UIView
@property (nonatomic, strong) UIView *bodyBg;
@property (nonatomic, strong) UIView *feather;
@property (nonatomic, strong) UIView *content;
@end

@implementation DSAPanelView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.clipsToBounds = YES;

        _bodyBg = [UIView new];
        _bodyBg.backgroundColor = DSAPanelColor();
        _bodyBg.opaque = YES;
        [self addSubview:_bodyBg];

        // 底部羽化：主体色 → 透明
        _feather = [UIView new];
        _feather.backgroundColor = UIColor.clearColor;
        [self addSubview:_feather];
        CAGradientLayer *g = [CAGradientLayer layer];
        g.colors = @[(id)DSAPanelColor().CGColor, (id)[DSAPanelColor() colorWithAlphaComponent:0].CGColor];
        g.startPoint = CGPointMake(0.5, 0);
        g.endPoint = CGPointMake(0.5, 1);
        [_feather.layer addSublayer:g];
        objc_setAssociatedObject(_feather, "grad", g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        _content = [UIView new];
        _content.backgroundColor = UIColor.clearColor;
        [self addSubview:_content];
    }
    return self;
}
/// 内容高度（供外部算面板总高：内容 + 羽化）
- (CGFloat)contentHeightForWidth:(CGFloat)w {
    UIView *first = self.content.subviews.firstObject;
    if (!first || w < 1) return 0;
    return [first systemLayoutSizeFittingSize:CGSizeMake(w, 0)
                  withHorizontalFittingPriority:UILayoutPriorityRequired
                        verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat bodyH = MAX(0, h - kDSAFeatherH);
    self.bodyBg.frame = CGRectMake(0, 0, w, bodyH);
    self.feather.frame = CGRectMake(0, bodyH, w, kFeatherSafe(h));
    CAGradientLayer *g = objc_getAssociatedObject(self.feather, "grad");
    g.frame = self.feather.bounds;
    self.content.frame = CGRectMake(0, 0, w, h);
}
@end

#pragma mark - 区块内容

/// 复用原版对话 cell（拿它的排版/样式），失败则退回普通 label
static UIView *DSAMakeNativeStyleRow(NSString *title, NSString *accLabel, NSString *accValue, SEL act) {
    UIControl *row = [[UIControl alloc] initWithFrame:CGRectZero];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.accessibilityLabel = accLabel;
    row.accessibilityValue = accValue;
    [row addTarget:[DSAEntryProxy class] action:act forControlEvents:UIControlEventTouchUpInside];
    [row.heightAnchor constraintEqualToConstant:47].active = YES;

    Class cls = NSClassFromString(@"_TtCC13DeepSeek_Chat25SessionListCollectionView4Cell");
    UIView *native = nil;
    if (cls) {
        @try { native = [[cls alloc] initWithFrame:CGRectMake(0, 0, 326, 47)]; }
        @catch (__unused NSException *e) { native = nil; }
    }
    if (native) {
        native.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:native];
        [NSLayoutConstraint activateConstraints:@[
            [native.topAnchor constraintEqualToAnchor:row.topAnchor],
            [native.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
            [native.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [native.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        ]];
        // 把 cell 里第一个有文字的 label 换成我们的标题
        NSMutableArray *st = [NSMutableArray arrayWithObject:native];
        while (st.count) {
            UIView *v = st.lastObject; [st removeLastObject];
            for (UIView *c in v.subviews) [st addObject:c];
            if (![v isKindOfClass:[UILabel class]]) continue;
            UILabel *l = (UILabel *)v;
            if (!l.text.length) continue;
            l.text = title;
            break;
        }
        DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] reused native cell %@", NSStringFromClass(cls)]);
        return row;
    }

    // 退回：自绘 label（按实测排版）
    CGFloat lead = 22, fsz = 18;
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectZero];
    lab.translatesAutoresizingMaskIntoConstraints = NO;
    lab.text = title;
    lab.font = [UIFont systemFontOfSize:fsz - 3];
    lab.textColor = [UIColor labelColor];
    lab.userInteractionEnabled = NO;
    [row addSubview:lab];
    [NSLayoutConstraint activateConstraints:@[
        [lab.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:lead],
        [lab.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-lead],
        [lab.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    return row;
}

/// 区块：logo 标题 + 智能体列表 + 设置（不再放「智能体对话」）
static UIView *DSAMakeAgentSection(void) {
    DSAPanelView *panel = [[DSAPanelView alloc] initWithFrame:CGRectZero];
    panel.translatesAutoresizingMaskIntoConstraints = NO;

    DSAStore *store = [DSAStore shared];
    [store loadIfNeeded];
    NSArray<DSAAgent *> *agents = store.agents;

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [panel.content addSubview:stack];

    // —— 标题：用 logo 图（深色用白字，浅色用黑字）——
    BOOL dark = NO;
    if (@available(iOS 13.0, *)) dark = (UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    UIImage *logo = DSALogoImage(dark);
    if (logo) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:logo];
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.tintColor = [UIColor labelColor];
        [stack addArrangedSubview:iv];
        // 1797x456 → 高 24 时宽约 95
        [NSLayoutConstraint activateConstraints:@[
            [iv.heightAnchor constraintEqualToConstant:24],
            [iv.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:22],
            [iv.widthAnchor constraintEqualToConstant:24 * (1797.0 / 456.0)],
            [iv.topAnchor constraintEqualToAnchor:stack.topAnchor constant:8],
        ]];
        UILabel *spacer = [[UILabel alloc] initWithFrame:CGRectZero];
        spacer.text = @" ";
        spacer.font = [UIFont systemFontOfSize:6];
        [stack addArrangedSubview:spacer];
    } else {
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectZero];
        t.translatesAutoresizingMaskIntoConstraints = NO;
        t.text = @"智能体";
        t.font = [UIFont boldSystemFontOfSize:18];
        [stack addArrangedSubview:t];
        [t.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:22].active = YES;
        [t.heightAnchor constraintEqualToConstant:32].active = YES;
    }

    // —— 智能体列表 ——
    for (DSAAgent *ag in agents) {
        UIView *r = DSAMakeNativeStyleRow(ag.name, ag.name, ag.agentId, @selector(agentRowTapped:));
        [stack addArrangedSubview:r];
    }
    if (!agents.count) {
        UILabel *e = [[UILabel alloc] initWithFrame:CGRectZero];
        e.translatesAutoresizingMaskIntoConstraints = NO;
        e.text = @"还没有智能体";
        e.font = [UIFont systemFontOfSize:15];
        e.textColor = [UIColor tertiaryLabelColor];
        [stack addArrangedSubview:e];
        [e.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:22].active = YES;
        [e.heightAnchor constraintEqualToConstant:36].active = YES;
    }

    // —— 设置 ——
    UILabel *sh = [[UILabel alloc] initWithFrame:CGRectZero];
    sh.translatesAutoresizingMaskIntoConstraints = NO;
    sh.text = @"设置";
    sh.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    sh.textColor = [UIColor secondaryLabelColor];
    [stack addArrangedSubview:sh];
    [NSLayoutConstraint activateConstraints:@[
        [sh.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:22],
        [sh.heightAnchor constraintEqualToConstant:28],
    ]];
    [stack addArrangedSubview:DSAMakeNativeStyleRow(@"管理智能体", @"管理智能体", @"", @selector(settingsTapped:))];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:panel.content.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:panel.content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:panel.content.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:panel.content.bottomAnchor],
    ]];

    DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] panel built agents=%lu", (unsigned long)agents.count]);
    return panel;
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
        sec = DSAMakeAgentSection();
        // ★ 必须关掉自动约束：否则在纯约束容器里会生成与搜索框冲突的约束，
        //   Auto Layout 会把搜索框撑高来化解（实测 49 → 219）
        sec.translatesAutoresizingMaskIntoConstraints = NO;
        [host insertSubview:sec aboveSubview:list];
        objc_setAssociatedObject(host, &kDSASidebarSectionTag, sec, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (sec.superview != host) {
        [host insertSubview:sec aboveSubview:list];
    } else {
        [host insertSubview:sec aboveSubview:list];
    }

    // ★ 定位只算一次：之后沿用。否则搜索框被推送拖走 → 目标跟着变 → 无限追（实测 listTop 一路涨到 2093）
    CGRect lr = [list convertRect:list.bounds toView:host];
    CGFloat width = lr.size.width;
    if (sSectionTop < 0) {
        CGFloat top0 = lr.origin.y;
        UIView *sb0 = DSAFindSearchBarView();
        if (sb0) {
            CGRect r = [sb0 convertRect:sb0.bounds toView:host];
            CGFloat sb = r.origin.y + r.size.height + 4;
            if (sb > top0) top0 = sb;
        }
        sSectionTop = top0;
        DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] section top locked at %.0f", sSectionTop]);
    }
    CGFloat top = sSectionTop;

    CGFloat h = 0;
    if ([sec isKindOfClass:[DSAPanelView class]])
        h = [(DSAPanelView *)sec contentHeightForWidth:width] + kDSAFeatherH;
    if (h < 60) h = 160;

    // ★ 用约束定位（不能用 frame：自动约束会和搜索框的约束打架，把它撑到 219 高）
    sec.clipsToBounds = YES;
    sec.layer.zPosition = 10000;

    NSLayoutConstraint *topC = objc_getAssociatedObject(sec, &kDSATopConstraintTag);
    if (!topC) {
        topC = [NSLayoutConstraint constraintWithItem:sec attribute:NSLayoutAttributeTop
                                           relatedBy:NSLayoutRelationEqual
                                              toItem:host attribute:NSLayoutAttributeTop
                                          multiplier:1 constant:top];
        [NSLayoutConstraint activateConstraints:@[
            topC,
            [sec.leadingAnchor constraintEqualToAnchor:list.leadingAnchor],
            [sec.trailingAnchor constraintEqualToAnchor:list.trailingAnchor],
            [sec.heightAnchor constraintEqualToConstant:h],
        ]];
        objc_setAssociatedObject(sec, &kDSATopConstraintTag, topC, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] constraints activated top=%.0f h=%.0f", top, h]);
    } else if (fabs(topC.constant - top) > 0.5) {
        topC.constant = top;
    }
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
    CGFloat wantListTop = top + h - 10;      // 稍微少留一点（之前 +4 偏大）
    CGFloat listTopNow = [list convertRect:list.bounds toView:host].origin.y;
    CGFloat need = wantListTop - listTopNow;
    if (need > 1 && !sPushBlocked && sMaxPushed < 700) {
        // 找搜索框（全局），推送前记位置
        UIView *sb = DSAFindSearchBarView();          // ★ 用导出的查找器（带缓存，节流 2s）
        UIWindow *win = host.window ?: DSAKeyWindow();
        CGFloat sbBefore = sb ? [sb convertRect:sb.bounds toView:win].origin.y : -1;
        if (sb && sSearchTop0 < 0) {
            sSearchTop0 = sbBefore;
            sSearchH0 = sb.bounds.size.height;
            DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] search baseline top=%.0f h=%.0f",
                         sSearchTop0, sSearchH0]);
        }
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
            // ★ 搜索框底边被钉在列表顶边 → 推列表必然拉伸它。推完把 top/height 按回原值。
            BOOL ok = YES;
            if (sb && sSearchTop0 >= 0 && sSearchH0 > 0) {
                [win layoutIfNeeded];
                CGFloat curTop = [sb convertRect:sb.bounds toView:win].origin.y;
                CGFloat curH = sb.bounds.size.height;
                CGFloat needTop = sSearchTop0 - curTop;
                CGFloat needH = sSearchH0 - curH;
                if (fabs(needTop) > 1 || fabs(needH) > 1) {
                    NSArray *owners = @[ sb.superview ?: (id)[NSNull null], host, sb ];
                    int fixed = 0;
                    // 修 top
                    if (fabs(needTop) > 1) {
                        for (id o in owners) {
                            if (![o isKindOfClass:[UIView class]]) continue;
                            for (NSLayoutConstraint *c in ((UIView *)o).constraints) {
                                if (c.firstItem == sb && c.firstAttribute == NSLayoutAttributeTop &&
                                    c.relation == NSLayoutRelationEqual) { c.constant += needTop; fixed = 1; break; }
                            }
                            if (fixed) break;
                        }
                    }
                    // 修 height
                    if (fabs(needH) > 1) {
                        int hf = 0;
                        for (id o in owners) {
                            if (![o isKindOfClass:[UIView class]]) continue;
                            for (NSLayoutConstraint *c in ((UIView *)o).constraints) {
                                if (c.firstItem == sb && c.firstAttribute == NSLayoutAttributeHeight &&
                                    c.relation == NSLayoutRelationEqual) { c.constant += needH; hf = 1; break; }
                            }
                            if (hf) break;
                        }
                        if (!hf) {
                            @try {
                                NSLayoutConstraint *hc = [sb.heightAnchor constraintEqualToConstant:sSearchH0];
                                hc.active = YES;
                                fixed = 1;
                            } @catch (__unused NSException *e) { fixed = 0; }
                        } else fixed = 1;
                    }
                    [win layoutIfNeeded];
                    CGFloat afterTop = [sb convertRect:sb.bounds toView:win].origin.y;
                    CGFloat afterH = sb.bounds.size.height;
                    DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] search fix top %.0f->%.0f h %.0f->%.0f (fixed=%d)",
                                 curTop, afterTop, curH, afterH, fixed]);
                    if (fabs(afterTop - sSearchTop0) > 2 || fabs(afterH - sSearchH0) > 2) ok = NO;
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
