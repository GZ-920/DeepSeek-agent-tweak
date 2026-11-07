//
//  NativeSidebar.m — 把智能体内容注入 App 原生侧边栏（SidebarViewController）
//
//  识别：窗口里可见、宽度 < 屏宽 0.9 的视图，类名含 "Sidebar"（抽屉）
//  插入：找到侧边栏里的搜索框/第一个列表，在其下方插入「智能体」区块
//        （用「调大原有约束常量」的方式腾空间，不新增冲突约束）
//  失败：返回 NO 并保留原来的滑出面板作为兜底
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"
#import "AgentStore.h"

static char kDSASidebarSectionTag;
static BOOL sSidebarPushed = NO;   // ★ 只推一次，避免每秒重复推导致搜索框不断变大

@interface DSAEntryProxy : NSObject
+ (void)tapped;
@end

void DSADiagLog(NSString *line);

#pragma mark - 区块内容

/// 造区块：智能体对话（顶部）→ 智能体（点击即开新对话）→ 设置（增删都在这里）
static UIView *DSAMakeAgentSection(void) {
    UIView *sec = [[UIView alloc] initWithFrame:CGRectZero];
    sec.backgroundColor = [UIColor clearColor];
    sec.translatesAutoresizingMaskIntoConstraints = NO;

    DSAStore *store = [DSAStore shared];
    [store loadIfNeeded];
    NSArray<DSAAgent *> *agents = store.agents;

    // ★ 套用原生对话列表的真实排版（左边距/行高/字号），避免文字紧贴左边缘、与下方不协调
    CGFloat lead = 16, rowH = 48, fsz = 15;
    if (!DSAMeasureListMetrics(&lead, &rowH, &fsz)) {
        DSADiagLog(@"[SIDEBAR] metrics unavailable, fallback 16/48/15");
    }

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [sec addSubview:stack];

    UILabel *(^makeHeader)(NSString *) = ^UILabel *(NSString *t) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
        l.translatesAutoresizingMaskIntoConstraints = NO;
        l.text = t;
        l.font = [UIFont systemFontOfSize:fsz - 2 weight:UIFontWeightSemibold];
        l.textColor = [UIColor secondaryLabelColor];
        // ★ 必须先加入 stack，否则两者无公共祖先，激活约束会抛异常
        [stack addArrangedSubview:l];
        [NSLayoutConstraint activateConstraints:@[
            [l.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:lead],
            [l.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor constant:-lead],
            [l.heightAnchor constraintEqualToConstant:rowH * 0.6],
        ]];
        return l;
    };

    UIControl *(^makeRow)(NSString *, NSString *, NSString *, NSString *, SEL) =
    ^UIControl *(NSString *title, NSString *sub, NSString *accLabel, NSString *accValue, SEL act) {
        UIControl *row = [[UIControl alloc] initWithFrame:CGRectZero];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        row.accessibilityLabel = accLabel;
        row.accessibilityValue = accValue;
        [row addTarget:[DSAEntryProxy class] action:act forControlEvents:UIControlEventTouchUpInside];

        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectZero];
        lab.translatesAutoresizingMaskIntoConstraints = NO;
        lab.text = title;
        lab.font = [UIFont systemFontOfSize:15];
        lab.textColor = [UIColor labelColor];
        lab.userInteractionEnabled = NO;
        [row addSubview:lab];

        UILabel *lab2 = [[UILabel alloc] initWithFrame:CGRectZero];
        lab2.translatesAutoresizingMaskIntoConstraints = NO;
        lab2.text = sub;
        lab2.font = [UIFont systemFontOfSize:12];
        lab2.textColor = [UIColor tertiaryLabelColor];
        lab2.userInteractionEnabled = NO;
        lab2.hidden = !sub.length;
        [row addSubview:lab2];

        lab.font = [UIFont systemFontOfSize:fsz];
        [stack addArrangedSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.heightAnchor constraintEqualToConstant:rowH],
            [lab.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:lead],
            [lab.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-lead],
            [lab.topAnchor constraintEqualToAnchor:row.topAnchor constant:rowH * 0.14],
            [lab2.leadingAnchor constraintEqualToAnchor:lab.leadingAnchor],
            [lab2.trailingAnchor constraintEqualToAnchor:lab.trailingAnchor],
            [lab2.topAnchor constraintEqualToAnchor:lab.bottomAnchor constant:1],
        ]];
        return row;
    };

    // —— 1) 智能体对话（顶部）——
    makeHeader(@"智能体对话");
    NSInteger convCount = 0;
    for (DSAAgent *ag in agents) {
        for (NSString *sid in [store sessionIdsForAgent:ag.agentId]) {
            NSString *cn = [store conversationNameForSession:sid];
            NSString *label = cn.length ? [NSString stringWithFormat:@"%@ · %@", ag.name, cn] : ag.name;
            makeRow(label, nil, label, sid, @selector(convRowTapped:));
            if (++convCount >= 8) break;
        }
        if (convCount >= 8) break;
    }
    if (!convCount) {
        UILabel *empty = [[UILabel alloc] initWithFrame:CGRectZero];
        empty.translatesAutoresizingMaskIntoConstraints = NO;
        empty.text = @"暂无对话";
        empty.font = [UIFont systemFontOfSize:14];
        empty.textColor = [UIColor tertiaryLabelColor];
        [empty.heightAnchor constraintEqualToConstant:30].active = YES;
        [stack addArrangedSubview:empty];
    }

    // —— 2) 智能体（点击直接开新对话）——
    makeHeader(@"智能体");
    for (DSAAgent *ag in agents) {
        makeRow(ag.name, nil, ag.name, ag.agentId, @selector(agentRowTapped:));
    }
    if (!agents.count) {
        UILabel *empty = [[UILabel alloc] initWithFrame:CGRectZero];
        empty.translatesAutoresizingMaskIntoConstraints = NO;
        empty.text = @"还没有智能体";
        empty.font = [UIFont systemFontOfSize:14];
        empty.textColor = [UIColor tertiaryLabelColor];
        [empty.heightAnchor constraintEqualToConstant:30].active = YES;
        [stack addArrangedSubview:empty];
    }

    // —— 3) 设置（新增/删除都在这里）——
    makeHeader(@"设置");
    makeRow(@"管理智能体", @"新增或删除", @"管理智能体", @"", @selector(settingsTapped:));

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:sec.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:sec.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:sec.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:sec.bottomAnchor],
    ]];
    DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] section built agents=%lu convs=%lu",
                 (unsigned long)agents.count, (unsigned long)convCount]);
    return sec;
}

#pragma mark - 找原生侧边栏

/// 判断视图是否「露在屏幕内、宽度像抽屉」
static BOOL DSALooksLikeOpenDrawer(UIView *v, UIWindow *w) {
    if (!v || !v.window || v.hidden || v.alpha < 0.05) return NO;
    CGFloat vw = v.bounds.size.width;
    if (vw <= 40) return NO;
    if (vw >= w.bounds.size.width * 0.95) return NO;      // 全屏 = 不是抽屉
    CGRect r = [v convertRect:v.bounds toView:nil];
    if (r.origin.x + r.size.width <= 4) return NO;         // 完全在屏幕左边外
    if (r.origin.x < -vw * 0.5) return NO;                 // 大半在屏幕外 = 收起
    return YES;
}

/// 找原生侧边栏容器。
/// 注意：Swift UIViewController 的 view 类名就是 "UIView"（不含 Sidebar），
/// 带 Sidebar 字样的往往是装饰子视图 → 所以找到后要**向上找**真正的抽屉容器。
static UIView *DSAFindNativeSidebar(UIWindow *w) {
    if (!w) return nil;
    // 种子：优先用已确认存在的 SessionListSearchBarView（它一定在抽屉里），
    // 其次任何含 Sidebar / SessionList 的视图
    NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
    int guard = 0;
    UIView *seed = nil;
    UIView *seedAny = nil;
    while (stack.count && guard++ < 5000) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        for (UIView *s in v.subviews) [stack addObject:s];
        if (!v.window || v.hidden || v.alpha < 0.05) continue;
        NSString *c = NSStringFromClass([v class]);
        if (v.bounds.size.width < 100) continue;              // 太小的不算（按钮/装饰件）
        if ([c containsString:@"MultiSelect"]) continue;      // 多选底栏不是侧边栏
        if ([c containsString:@"SearchBar"]) {
            if (!seed) seed = v;                              // 最优先：真正的搜索栏
        } else if ([c containsString:@"SessionList"] && !seed) {
            seed = v;
        } else if ([c containsString:@"Sidebar"] && !seedAny) {
            seedAny = v;
        }
        if (seed && [NSStringFromClass([seed class]) containsString:@"SearchBar"]) break;
    }
    if (!seed) seed = seedAny;
    if (!seed) {
        static int noSeed = 0;
        if (++noSeed == 1 || noSeed % 30 == 0)
            DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] no seed found (attempt %d)", noSeed]);
        return nil;
    }

    // 从 seed 向上找：尺寸像抽屉（宽 100~95% 屏宽）且露在屏幕内的最高祖先
    UIView *best = nil;
    UIView *p = seed;
    for (int i = 0; i < 8 && p; i++, p = p.superview) {
        if (DSALooksLikeOpenDrawer(p, w)) best = p;     // 越往上越可能是整块抽屉
    }
    if (best) {
        static BOOL wasNil = YES;
        if (wasNil) { wasNil = NO;
            DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] FOUND drawer %@ (seed %@)",
                         NSStringFromClass([best class]), NSStringFromClass([seed class])]); }
        return best;
    }

    // 向上都太大/不可见 → 退回 seed 自己（若它像抽屉）
    if (DSALooksLikeOpenDrawer(seed, w)) return seed;

    // 打印祖先链，便于定位（每次状态变化打一次）
    static int failLog = 0;
    if (++failLog == 1 || failLog % 30 == 0) {
        NSMutableString *chain = [NSMutableString string];
        UIView *p = seed;
        for (int i = 0; i < 8 && p; i++, p = p.superview) {
            CGRect r = [p convertRect:p.bounds toView:nil];
            [chain appendFormat:@"\n    L%d %@ %.0fx%.0f at %.0f,%.0f",
             i, NSStringFromClass([p class]), p.bounds.size.width, p.bounds.size.height,
             r.origin.x, r.origin.y];
        }
        DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] drawer not resolved (attempt %d) seed=%@%@",
                     failLog, NSStringFromClass([seed class]), chain]);
    }

    // seed 自己不可见（装饰件可能常驻）→ 再向下找一个像抽屉的
    NSMutableArray *st2 = [NSMutableArray arrayWithObject:seed];
    int g2 = 0;
    while (st2.count && g2++ < 3000) {
        UIView *v = st2.lastObject;
        [st2 removeLastObject];
        for (UIView *s2 in v.subviews) [st2 addObject:s2];
        if (DSALooksLikeOpenDrawer(v, w) && v.bounds.size.width > 100) return v;
    }
    return nil;
}

#pragma mark - 插入

static BOOL DSAInsertSection(UIView *sidebar) {
    UIWindow *w = sidebar.window ?: DSAKeyWindow();
    if (!w) return NO;

    // 找锚点：侧边栏里的搜索框（用于定位 + 取排版参数）
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

    // ★ 区块挂到 window（App 清不掉），用绝对坐标定位
    UIView *sec = objc_getAssociatedObject(w, &kDSASidebarSectionTag);
    if (!sec) {
        sec = DSAMakeAgentSection();
        sec.translatesAutoresizingMaskIntoConstraints = YES;   // 用 frame 定位
        [w addSubview:sec];
        objc_setAssociatedObject(w, &kDSASidebarSectionTag, sec, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DSADiagLog(@"[SIDEBAR] section created on window");
    }

    // 定位：搜索框下沿（窗口坐标）
    CGFloat sidebarX = [sidebar convertRect:sidebar.bounds toView:nil].origin.x;
    CGFloat sidebarW = sidebar.bounds.size.width;
    CGFloat top = 0;
    if (anchor) {
        CGRect r = [anchor convertRect:anchor.bounds toView:nil];
        top = r.origin.y + r.size.height + 4;
    } else {
        CGRect r = [sidebar convertRect:sidebar.bounds toView:nil];
        top = r.origin.y + 60;
    }
    CGFloat width = sidebarW;

    // 算高度（内容自适应）
    CGFloat h = [sec systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                  withHorizontalFittingPriority:UILayoutPriorityRequired
                        verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    if (h < 40) h = 160;

    sec.frame = CGRectMake(sidebarX, top, width, h);
    [w bringSubviewToFront:sec];
    DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] placed at %.0f,%.0f %.0fx%.0f (anchor %@)",
                 sidebarX, top, width, h, anchor ? NSStringFromClass([anchor class]) : @"nil"]);

    // ★ 只在第一次放置时推送一次。
    // 之前每秒都按「搜索框下沿」重算目标，而搜索框会随推送下移 → 目标不断上移 → 正反馈，
    // 表现就是「搜索框每秒变大一点」。
    if (!sSidebarPushed) {
        UIView *list = DSAFindSessionListView();
        if (list) {
            CGRect lr = [list convertRect:list.bounds toView:nil];
            CGFloat need = (top + h + 8) - lr.origin.y;
            if (need > 1) {
                UIView *container = list.superview ?: sidebar;
                if (DSAPushListToTotal(list, container, need, nil)) {
                    sSidebarPushed = YES;
                    DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] pushed once by %.0f", need]);
                } else {
                    DSADiagLog(@"[SIDEBAR] push failed → section stays, will retry next tick");
                }
            } else {
                sSidebarPushed = YES;   // 本来就有空间，不用推
            }
        } else {
            sSidebarPushed = YES;
        }
    }
    return YES;
}

/// 让区块在下次轮询时重建（先移除）
void DSARefreshNativeSidebar(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = DSAKeyWindow();
        UIView *sec = objc_getAssociatedObject(w, &kDSASidebarSectionTag);
        if (sec) {
            [sec removeFromSuperview];
            objc_setAssociatedObject(w, &kDSASidebarSectionTag, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            sSidebarPushed = NO;
            DSADiagLog(@"[SIDEBAR] section cleared for rebuild");
        }
    });
}

/// 由定时任务调用
void DSAEnsureNativeSidebar(void) {
    @try {
        UIWindow *w = DSAKeyWindow();
        UIView *sb = DSAFindNativeSidebar(w);
        if (!sb) {
            static BOOL logged = NO;
            if (!logged) { logged = YES; DSADiagLog(@"[SIDEBAR] not visible yet (waiting for open)"); }
            return;
        }
        DSAInsertSection(sb);
    } @catch (__unused NSException *e) {
        DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] exception %@", e.reason]);
    }
}

#pragma mark - 行点击

@implementation DSAEntryProxy (SidebarRows)

/// 点智能体 → 直接开始新对话
+ (void)agentRowTapped:(UIControl *)sender {
    DSAAgent *ag = [[DSAStore shared] agentWithId:sender.accessibilityValue];
    if (!ag) return;
    DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] tap agent=%@ → new chat", ag.name]);
    DSAOpenNewChatWithAgent(ag);
}

/// 点对话 → 打开该会话
+ (void)convRowTapped:(UIControl *)sender {
    NSString *sid = sender.accessibilityValue;
    if (!sid.length) return;
    DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] tap conv %@", sid]);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DSAOpenSessionRequest" object:nil
                                                      userInfo:@{ @"sessionId": sid }];
}

/// 设置：新增 / 删除都在这里
+ (void)settingsTapped:(UIControl *)sender {
    DSADiagLog(@"[SIDEBAR] open settings page");
    DSAShowSettings();
}


@end

