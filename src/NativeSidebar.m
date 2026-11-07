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

@interface DSAEntryProxy : NSObject
+ (void)tapped;
@end

void DSADiagLog(NSString *line);

#pragma mark - 区块内容

/// 造「智能体」区块：标题 + 每个智能体一行 + 新建按钮
static UIView *DSAMakeAgentSection(void) {
    UIView *sec = [[UIView alloc] initWithFrame:CGRectZero];
    sec.backgroundColor = [UIColor clearColor];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"智能体";
    title.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    title.textColor = [UIColor secondaryLabelColor];
    [sec addSubview:title];

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 2;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [sec addSubview:stack];

    DSAStore *store = [DSAStore shared];
    [store loadIfNeeded];
    NSArray<DSAAgent *> *agents = store.agents;

    // 每个智能体一行
    for (DSAAgent *ag in agents) {
        UIControl *row = [[UIControl alloc] initWithFrame:CGRectZero];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        row.tag = 91000;
        [row addTarget:[DSAEntryProxy class] action:@selector(agentRowTapped:)
       forControlEvents:UIControlEventTouchUpInside];
        row.accessibilityLabel = ag.name;
        row.accessibilityValue = ag.agentId;

        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectZero];
        lab.translatesAutoresizingMaskIntoConstraints = NO;
        lab.text = [NSString stringWithFormat:@"· %@", ag.name];
        lab.font = [UIFont systemFontOfSize:15];
        lab.textColor = [UIColor labelColor];
        lab.userInteractionEnabled = NO;
        lab.tag = 91001;
        [row addSubview:lab];
        [stack addArrangedSubview:row];
        [row.heightAnchor constraintEqualToConstant:36].active = YES;
        [lab.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:4].active = YES;
        [lab.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
        [lab.trailingAnchor constraintEqualToAnchor:row.trailingAnchor].active = YES;
    }

    // 新建按钮
    UIControl *add = [[UIControl alloc] initWithFrame:CGRectZero];
    add.translatesAutoresizingMaskIntoConstraints = NO;
    [add addTarget:[DSAEntryProxy class] action:@selector(newAgentTapped:)
  forControlEvents:UIControlEventTouchUpInside];
    add.accessibilityLabel = @"新建智能体";
    UILabel *addLab = [[UILabel alloc] initWithFrame:CGRectZero];
    addLab.translatesAutoresizingMaskIntoConstraints = NO;
    addLab.text = @"＋ 新建智能体";
    addLab.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    addLab.textColor = [UIColor colorWithRed:0.29 green:0.48 blue:1.0 alpha:1];
    addLab.userInteractionEnabled = NO;
    [add addSubview:addLab];
    [stack addArrangedSubview:add];
    [add.heightAnchor constraintEqualToConstant:36].active = YES;
    [addLab.leadingAnchor constraintEqualToAnchor:add.leadingAnchor constant:4].active = YES;
    [addLab.centerYAnchor constraintEqualToAnchor:add.centerYAnchor].active = YES;
    [addLab.trailingAnchor constraintEqualToAnchor:add.trailingAnchor].active = YES;

    // 布局
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:sec.topAnchor],
        [title.leadingAnchor constraintEqualToAnchor:sec.leadingAnchor constant:4],
        [title.trailingAnchor constraintEqualToAnchor:sec.trailingAnchor],
        [title.heightAnchor constraintEqualToConstant:22],
        [stack.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [stack.leadingAnchor constraintEqualToAnchor:sec.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:sec.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:sec.bottomAnchor],
    ]];
    sec.translatesAutoresizingMaskIntoConstraints = NO;
    DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] section built rows=%lu",
                 (unsigned long)([DSAStore shared].agents.count + 1)]);
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
    NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
    int guard = 0;
    UIView *seed = nil;
    while (stack.count && guard++ < 4000) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        for (UIView *s in v.subviews) [stack addObject:s];
        if (!v.window || v.hidden || v.alpha < 0.05) continue;
        if ([NSStringFromClass([v class]) containsString:@"Sidebar"]) { seed = v; break; }
    }
    if (!seed) return nil;

    // 从 seed 向上找：尺寸像抽屉（宽 100~95% 屏宽）且露在屏幕内的最高祖先
    UIView *best = nil;
    UIView *p = seed;
    for (int i = 0; i < 8 && p; i++, p = p.superview) {
        if (DSALooksLikeOpenDrawer(p, w)) best = p;     // 越往上越可能是整块抽屉
    }
    if (best) return best;

    // 向上都太大/不可见 → 退回 seed 本身（若它自己像抽屉）
    if (DSALooksLikeOpenDrawer(seed, w)) return seed;

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
    if (objc_getAssociatedObject(sidebar, &kDSASidebarSectionTag)) return YES;

    // 找锚点：搜索框 → SessionList 类 → 滚动视图 → 最大的内容视图
    UIView *anchor = nil;
    NSMutableString *dump = [NSMutableString string];
    NSMutableArray *stack = [NSMutableArray arrayWithObject:sidebar];
    int guard = 0;
    NSMutableArray<UIView *> *cands = [NSMutableArray array];
    while (stack.count && guard++ < 4000) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        for (UIView *s2 in v.subviews) [stack addObject:s2];
        if (!v.window) continue;
        NSString *c = NSStringFromClass([v class]);
        [dump appendFormat:@"\n    %@ %.0fx%.0f", c, v.bounds.size.width, v.bounds.size.height];
        if ([c containsString:@"Search"] || [c containsString:@"SessionList"] ||
            [v isKindOfClass:[UIScrollView class]]) [cands addObject:v];
    }
    // 优先级：Search > SessionList > 滚动视图
    for (NSString *key in @[ @"Search", @"SessionList" ]) {
        for (UIView *c in cands) {
            if ([NSStringFromClass([c class]) containsString:key]) { anchor = c; break; }
        }
        if (anchor) break;
    }
    if (!anchor) {
        for (UIView *c in cands) { if ([c isKindOfClass:[UIScrollView class]]) { anchor = c; break; } }
    }
    if (!anchor) {
        DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] no anchor in %@", dump]);
        return NO;
    }

    UIView *host = anchor.superview;
    if (!host) return NO;

    UIView *sec = DSAMakeAgentSection();
    [host addSubview:sec];

    // 锚点下方
    [NSLayoutConstraint activateConstraints:@[
        [sec.topAnchor constraintEqualToAnchor:anchor.bottomAnchor constant:8],
        [sec.leadingAnchor constraintEqualToAnchor:anchor.leadingAnchor],
        [sec.trailingAnchor constraintEqualToAnchor:anchor.trailingAnchor],
    ]];

    // 找「被区块挡住的列表」：host 的后代里第一个不是锚点的列表
    UIView *below = nil;
    {
        NSMutableArray *st = [NSMutableArray arrayWithObject:host];
        int g2 = 0;
        while (st.count && g2++ < 3000) {
            UIView *v = st.lastObject;
            [st removeLastObject];
            for (UIView *s2 in v.subviews) [st addObject:s2];
            if (v == anchor || v == sec) continue;
            if ([v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]]) {
                below = v; break;
            }
        }
    }

    [host layoutIfNeeded];
    CGFloat secTop = [sec convertRect:sec.bounds toView:host].origin.y;
    CGFloat secH = [sec systemLayoutSizeFittingSize:CGSizeMake(host.bounds.size.width, 0)
                    withHorizontalFittingPriority:UILayoutPriorityRequired
                          verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] sec top=%.0f h=%.0f below=%@",
                 secTop, secH, below ? NSStringFromClass([below class]) : @"nil"]);

    if (below) {
        CGFloat cur = [below convertRect:below.bounds toView:host].origin.y;
        CGFloat want = secTop + secH + 8;
        CGFloat delta = want - cur;
        DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] cur=%.0f want=%.0f delta=%.0f", cur, want, delta]);
        if (delta > 1) {
            BOOL pushed = NO;
            // 在多个容器里找「钉住 below.top 的等式约束」
            NSArray *owners = @[ below.superview ?: (id)[NSNull null], host, below ];
            for (id owner in owners) {
                if (![owner isKindOfClass:[UIView class]]) continue;
                UIView *ov = (UIView *)owner;
                for (NSLayoutConstraint *c in ov.constraints) {
                    if (c.firstItem == below && c.firstAttribute == NSLayoutAttributeTop &&
                        c.relation == NSLayoutRelationEqual) {
                        c.constant += delta; pushed = YES;
                        DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] pushed in %@ constant=%.0f",
                                     NSStringFromClass([ov class]), c.constant]);
                        break;
                    }
                }
                if (pushed) break;
            }
            if (!pushed) {
                DSADiagLog(@"[SIDEBAR] cannot push list down");
                [sec removeFromSuperview];
                return NO;
            }
        }
    } else {
        DSADiagLog(@"[SIDEBAR] no list below anchor");
    }

    [host bringSubviewToFront:sec];
    objc_setAssociatedObject(sidebar, &kDSASidebarSectionTag, sec, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] section inserted (anchor %@, host %@)",
                 NSStringFromClass([anchor class]), NSStringFromClass([host class])]);
    return YES;
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

+ (void)agentRowTapped:(UIControl *)sender {
    NSString *agentId = sender.accessibilityValue;
    DSAAgent *ag = [[DSAStore shared] agentWithId:agentId];
    if (!ag) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
        if (!top) return;
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:ag.name
                                                                      message:ag.systemPrompt
                                                               preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:@"新建对话（自动发送设定提示词）"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *x) {
            DSAOpenNewChatWithAgent(ag);
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *x) {
            [[DSAStore shared] deleteAgentWithId:ag.agentId];
            UIView *sb = DSAFindNativeSidebar(DSAKeyWindow());
            UIView *sec = objc_getAssociatedObject(sb, &kDSASidebarSectionTag);
            if (sec) {
                [sec removeFromSuperview];
                objc_setAssociatedObject(sb, &kDSASidebarSectionTag, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.sourceView = sender;
        [top presentViewController:sheet animated:YES completion:nil];
    });
}

+ (void)newAgentTapped:(UIControl *)sender {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
        if (!top) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新建智能体"
                                                                      message:@"名字 + 设定提示词"
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *f) {
            f.placeholder = @"名字，例如：论文导师";
        }];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *f) {
            f.placeholder = @"设定提示词（每次新对话自动发送）";
            f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存并开始对话" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *x) {
            NSString *name = [alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *prompt = [alert.textFields[1].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!name.length || !prompt.length) { DSAToast(@"名字和提示词都不能为空"); return; }
            DSAAgent *a = [DSAAgent new];
            a.agentId = [[NSUUID UUID] UUIDString];
            a.name = name; a.systemPrompt = prompt; a.emoji = @"";
            a.createdAt = [[NSDate date] timeIntervalSince1970];
            [[DSAStore shared] saveAgent:a];
            UIView *sb = DSAFindNativeSidebar(DSAKeyWindow());
            UIView *sec = objc_getAssociatedObject(sb, &kDSASidebarSectionTag);
            if (sec) {
                [sec removeFromSuperview];
                objc_setAssociatedObject(sb, &kDSASidebarSectionTag, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            DSAOpenNewChatWithAgent(a);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *x) {
            NSString *name = [alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *prompt = [alert.textFields[1].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!name.length || !prompt.length) { DSAToast(@"名字和提示词都不能为空"); return; }
            DSAAgent *a = [DSAAgent new];
            a.agentId = [[NSUUID UUID] UUIDString];
            a.name = name; a.systemPrompt = prompt; a.emoji = @"";
            a.createdAt = [[NSDate date] timeIntervalSince1970];
            [[DSAStore shared] saveAgent:a];
            UIView *sb = DSAFindNativeSidebar(DSAKeyWindow());
            UIView *sec = objc_getAssociatedObject(sb, &kDSASidebarSectionTag);
            if (sec) {
                [sec removeFromSuperview];
                objc_setAssociatedObject(sb, &kDSASidebarSectionTag, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

@end
