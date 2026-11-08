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
static char kDSABeforeInsetTag;    // 记录列表原始 contentInset.top，便于还原

@interface DSAEntryProxy : NSObject
+ (void)tapped;
@end

void DSADiagLog(NSString *line);
static UIView *DSAFindNativeSidebar(UIWindow *w);   // 前置声明（定义在文件末尾）
BOOL DSAMeasureListMetrics(CGFloat *outLeading, CGFloat *outRowH, CGFloat *outFont);
UIView *DSAFindSessionListView(void);

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
    // 锚点：侧边栏里的搜索框
    UIView *anchor = nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:sidebar];
    int guard = 0;
    while (stack.count && guard++ < 4000) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        for (UIView *s2 in v.subviews) [stack addObject:s2];
        if (!v.window) continue;
        NSString *c = NSStringFromClass([v class]);
        if ([c containsString:@"SearchBar"] && v.bounds.size.width > 100) { anchor = v; break; }
    }
    if (!anchor) { DSADiagLog(@"[SIDEBAR] no search anchor"); return NO; }

    // 已有区块？只更新位置
    UIView *sec = objc_getAssociatedObject(sidebar, &kDSASidebarSectionTag);
    BOOL fresh = (sec == nil);
    if (fresh) {
        sec = DSAMakeAgentSection(sidebar.backgroundColor);
        [sidebar addSubview:sec];
        objc_setAssociatedObject(sidebar, &kDSASidebarSectionTag, sec, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // 定位：搜索框下沿（侧边栏坐标系）
    CGFloat top = [anchor convertRect:anchor.bounds toView:sidebar].origin.y +
                  anchor.bounds.size.height + 4;
    CGFloat width = sidebar.bounds.size.width;

    CGFloat h = [sec systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                  withHorizontalFittingPriority:UILayoutPriorityRequired
                        verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    if (h < 40) h = 160;
    sec.frame = CGRectMake(0, top, width, h);
    sec.hidden = NO;
    sec.alpha = 1;
    sec.layer.zPosition = 10000;
    [sidebar bringSubviewToFront:sec];
    [sidebar.superview bringSubviewToFront:sidebar];   // 侧边栏本身也置顶

    // ★ 不碰 contentInset：日志显示 App 每帧把它重置回原值（35 次重复），纯属打架。
    //   改为纯遮挡：不透明背景 + zPosition 强制置顶。
    sec.backgroundColor = sidebar.backgroundColor ?: [UIColor systemGroupedBackgroundColor];
    sec.opaque = YES;
    sec.layer.zPosition = 10000;                 // 同层渲染里排到最前
    [sidebar bringSubviewToFront:sec];

    if (fresh) DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] section added to sidebar at y=%.0f h=%.0f", top, h]);
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
        if (!sb) return;
        UIView *sec = objc_getAssociatedObject(sb, &kDSASidebarSectionTag);
        if (sec) {
            [sec removeFromSuperview];
            objc_setAssociatedObject(sb, &kDSASidebarSectionTag, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            DSADiagLog(@"[SIDEBAR] section cleared for rebuild");
        }
        // 还原 contentInset（下次插入会重新计算）
        UIView *list = DSAFindSessionListView();
        if (list && [list isKindOfClass:[UIScrollView class]]) {
            UIScrollView *sv = (UIScrollView *)list;
            NSNumber *orig = objc_getAssociatedObject(sv, &kDSABeforeInsetTag);
            if (orig) {
                UIEdgeInsets ni = sv.contentInset;
                ni.top = orig.doubleValue;
                sv.contentInset = ni;
                sv.scrollIndicatorInsets = ni;
            }
        }
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
