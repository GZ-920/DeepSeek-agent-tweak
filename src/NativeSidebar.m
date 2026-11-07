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

static UIView *DSAFindNativeSidebar(UIWindow *w) {
    if (!w) return nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
    int guard = 0;
    UIView *best = nil;
    while (stack.count && guard++ < 4000) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        for (UIView *s in v.subviews) [stack addObject:s];
        if (!v.window || v.hidden || v.alpha < 0.05) continue;
        NSString *c = NSStringFromClass([v class]);
        if (![c containsString:@"Sidebar"]) continue;
        // 抽屉：宽度小于屏宽 0.9
        if (v.bounds.size.width > 0 && v.bounds.size.width < w.bounds.size.width * 0.9) {
            if (!best || v.bounds.size.width > best.bounds.size.width) best = v;
        }
    }
    return best;
}

#pragma mark - 插入

static BOOL DSAInsertSection(UIView *sidebar) {
    if (objc_getAssociatedObject(sidebar, &kDSASidebarSectionTag)) return YES;

    // 找侧边栏里的搜索框（或第一个列表）作为锚点
    UIView *anchor = nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:sidebar];
    int guard = 0;
    while (stack.count && guard++ < 3000) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        for (UIView *s in v.subviews) [stack addObject:s];
        if (!v.window) continue;
        NSString *c = NSStringFromClass([v class]);
        if ([c containsString:@"Search"]) { anchor = v; break; }
    }
    if (!anchor) {
        // 没有搜索框 → 用侧边栏里第一个 UITableView / UICollectionView
        stack = [NSMutableArray arrayWithObject:sidebar];
        guard = 0;
        while (stack.count && guard++ < 3000) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            for (UIView *s in v.subviews) [stack addObject:s];
            if (!v.window) continue;
            if ([v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]]) {
                anchor = v; break;
            }
        }
    }
    if (!anchor) {
        DSADiagLog(@"[SIDEBAR] no anchor (search/list) found");
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

    // 把锚点之后的内容往下推：调大列表原有的顶部约束
    UIView *below = nil;
    if (anchor != sidebar) {
        for (UIView *s in host.subviews) {
            if (s == anchor || s == sec) continue;
            if ([s isKindOfClass:[UITableView class]] || [s isKindOfClass:[UICollectionView class]]) {
                below = s; break;
            }
        }
    }
    if (below) {
        CGFloat secHeight = 26 + 36 * ((NSInteger)[DSAStore shared].agents.count + 1);
        CGFloat cur = [below convertRect:below.bounds toView:host].origin.y;
        CGFloat want = [sec convertRect:sec.bounds toView:host].origin.y + secHeight + 8;
        CGFloat delta = want - cur;
        DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] below=%@ cur=%.0f want=%.0f delta=%.0f",
                     NSStringFromClass([below class]), cur, want, delta]);
        if (delta > 1) {
            BOOL pushed = NO;
            for (NSLayoutConstraint *c in host.constraints) {
                if (c.firstItem == below && c.firstAttribute == NSLayoutAttributeTop &&
                    c.relation == NSLayoutRelationEqual) {
                    c.constant += delta; pushed = YES;
                    DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] pushed via host constraint constant=%.0f", c.constant]);
                    break;
                }
            }
            if (!pushed) {
                for (NSLayoutConstraint *c in below.constraints) {
                    if (c.firstAttribute == NSLayoutAttributeTop &&
                        c.relation == NSLayoutRelationEqual) {
                        c.constant += delta; pushed = YES;
                        DSADiagLog([NSString stringWithFormat:@"[SIDEBAR] pushed via below constraint constant=%.0f", c.constant]);
                        break;
                    }
                }
            }
            if (!pushed) {
                DSADiagLog(@"[SIDEBAR] cannot push, remove section to avoid overlap");
                [sec removeFromSuperview];
                return NO;
            }
        }
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
        if (!sb) return;
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
