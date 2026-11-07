//
//  Sidebar.m — 智能体侧边栏（不 present，直接挂 UIWindow，和胶囊同一条已验证链路）
//
//  结构（自上而下）：
//    1. 顶部：标题 + 关闭 + 搜索框
//    2. 「智能体」区：每个智能体（点开 → 操作菜单）
//    3. 「智能体对话」区：该智能体名下的会话
//    4. 底部：＋ 新建智能体
//
//  挂载方式：直接 addSubview 到 UIWindow（已验证可靠），不用 presentViewController
//            （present 在 LiveContainer 容器里被拦，实测不显示）。
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"
#import "AgentStore.h"
#import "AgentListController.h"

void DSAHideSidebar(void);
static char kDSASidebarTag;
static char kDSAMaskTag;

@interface DSAEntryProxy : NSObject
+ (void)tapped;
@end

#pragma mark - 面板

@interface DSASidebarPanel : UIView <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@end

@implementation DSASidebarPanel {
    UITableView *_table;
    UITextField *_search;
    NSArray *_sections;
    NSArray<NSArray *> *_rows;
    NSString *_filter;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor systemGroupedBackgroundColor];
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.25;
        self.layer.shadowRadius = 12;
        self.layer.shadowOffset = CGSizeMake(4, 0);

        // 标题栏
        UILabel *title = [[UILabel alloc] init];
        title.text = @"智能体";
        title.font = [UIFont boldSystemFontOfSize:17];
        title.textAlignment = NSTextAlignmentLeft;
        [self addSubview:title];

        // 关闭按钮
        UIControl *close = [[UIControl alloc] initWithFrame:CGRectZero];
        close.tag = 90002;
        UILabel *closeLab = [[UILabel alloc] init];
        closeLab.text = @"✕";
        closeLab.font = [UIFont boldSystemFontOfSize:18];
        closeLab.textColor = [UIColor secondaryLabelColor];
        closeLab.textAlignment = NSTextAlignmentCenter;
        closeLab.frame = close.bounds;
        closeLab.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [close addSubview:closeLab];
        [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:close];

        // 搜索框
        _search = [[UITextField alloc] initWithFrame:CGRectZero];
        _search.placeholder = @"搜索对话";
        _search.borderStyle = UITextBorderStyleRoundedRect;
        _search.font = [UIFont systemFontOfSize:14];
        _search.returnKeyType = UIReturnKeySearch;
        _search.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _search.autocorrectionType = UITextAutocorrectionTypeNo;
        _search.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        _search.delegate = self;
        [_search addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventEditingChanged];
        [self addSubview:_search];

        // 表格
        _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
        _table.dataSource = self;
        _table.delegate = self;
        _table.rowHeight = 48;
        _table.separatorInset = UIEdgeInsetsMake(0, 14, 0, 0);
        [self addSubview:_table];

        [self rebuild];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) safeTop = self.safeAreaInsets.top;
    CGFloat top = safeTop > 0 ? safeTop + 4 : 44;
    [_table setFrame:CGRectMake(0, top + 44, w, self.bounds.size.height - top - 44)];
    [_search setFrame:CGRectMake(52, top + 6, w - 66, 32)];
}

- (void)rebuild {
    DSAStore *store = [DSAStore shared];
    [store loadIfNeeded];
    NSArray<DSAAgent *> *agents = store.agents;
    NSString *f = _filter.lowercaseString;

    NSMutableArray *secs = [NSMutableArray array];
    NSMutableArray *rows = [NSMutableArray array];

    // 智能体
    NSMutableArray *a = [NSMutableArray array];
    for (DSAAgent *ag in agents) {
        if (f.length && ![ag.name.lowercaseString containsString:f]) continue;
        [a addObject:@{ @"kind": @"agent", @"agent": ag }];
    }
    [secs addObject:@"智能体"];
    [rows addObject:a];

    // 智能体对话
    NSMutableArray *c = [NSMutableArray array];
    for (DSAAgent *ag in agents) {
        for (NSString *sid in [store sessionIdsForAgent:ag.agentId]) {
            if (f.length && ![sid.lowercaseString containsString:f]) continue;
            [c addObject:@{ @"kind": @"session", @"session": sid, @"agent": ag }];
        }
    }
    [secs addObject:@"智能体对话"];
    [rows addObject:c];

    // 新建
    [secs addObject:@""];
    [rows addObject:@[ @{ @"kind": @"newAgent" } ]];

    _sections = secs;
    _rows = rows;
    [_table reloadData];
}

- (void)filterChanged:(UITextField *)tf { _filter = tf.text; [self rebuild]; }
- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }
- (void)closePanel { DSAHideSidebar(); }

#pragma mark 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return (NSInteger)_sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)[_rows[s] count]; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return _sections[s]; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:nil];
    NSDictionary *row = _rows[ip.section][(NSUInteger)ip.row];
    NSString *kind = row[@"kind"];
    if ([kind isEqualToString:@"agent"]) {
        DSAAgent *ag = row[@"agent"];
        cell.textLabel.text = [NSString stringWithFormat:@"%@  %@", ag.emoji ?: @"", ag.name];
        NSString *p = [ag.systemPrompt stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        cell.detailTextLabel.text = p.length > 30 ? [[p substringToIndex:30] stringByAppendingString:@"…"] : p;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([kind isEqualToString:@"session"]) {
        DSAAgent *ag = row[@"agent"];
        NSString *sid = row[@"session"];
        cell.textLabel.text = [sid substringToIndex:MIN((NSUInteger)12, sid.length)];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"所属：%@", ag.name];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = @"＋ 新建智能体";
        cell.textLabel.textColor = [UIColor colorWithRed:0.29 green:0.48 blue:1.0 alpha:1];
        cell.detailTextLabel.text = @"设定名字 + 首条设定提示词";
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *row = _rows[ip.section][(NSUInteger)ip.row];
    NSString *kind = row[@"kind"];
    if ([kind isEqualToString:@"agent"]) {
        DSAAgent *ag = row[@"agent"];
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:ag.name
                                                                      message:ag.systemPrompt
                                                               preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:@"新建对话（自动发送设定提示词）"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *x) {
            DSAOpenNewChatWithAgent(ag);
            DSAHideSidebar();
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive
                                                handler:^(UIAlertAction *x) {
            [[DSAStore shared] deleteAgentWithId:ag.agentId];
            [self rebuild];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.sourceView = tv;
        sheet.popoverPresentationController.sourceRect = [tv rectForRowAtIndexPath:ip];
        // 找最上层 VC 来 present
        UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
        [top presentViewController:sheet animated:YES completion:nil];
    } else if ([kind isEqualToString:@"session"]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DSAOpenSessionRequest" object:nil
                                                          userInfo:@{ @"sessionId": row[@"session"] }];
        DSAHideSidebar();
    } else {
        // 新建智能体：弹一个简易表单（不走 push，因为这里不是 nav）
        [self showNewAgentForm];
    }
}

/// 简易新建表单：alert 里放输入框（iOS 13+ 用 textFields）
- (void)showNewAgentForm {
    UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新建智能体"
                                                                  message:@"名字 + 设定提示词"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"名字，例如：论文导师";
        f.tag = 90010;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"设定提示词（每次新对话自动发送）";
        f.tag = 90011;
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
        [self rebuild];
        DSAHideSidebar();
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
        [self rebuild];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - 挂载 / 关闭

void DSAHideSidebar(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = DSAKeyWindow();
        UIView *panel = objc_getAssociatedObject(w, &kDSASidebarTag);
        UIView *mask = objc_getAssociatedObject(w, &kDSAMaskTag);
        if (panel) {
            [UIView animateWithDuration:0.2 animations:^{
                panel.frame = CGRectMake(-panel.bounds.size.width, 0,
                                         panel.bounds.size.width, panel.bounds.size.height);
                mask.alpha = 0;
            } completion:^(BOOL done) {
                [panel removeFromSuperview];
                [mask removeFromSuperview];
                objc_setAssociatedObject(w, &kDSASidebarTag, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(w, &kDSAMaskTag, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }];
        }
    });
}

void DSAShowSidebar(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = DSAKeyWindow();
        if (!w) return;
        if (objc_getAssociatedObject(w, &kDSASidebarTag)) return;

        // 遮罩
        UIView *mask = [[UIView alloc] initWithFrame:w.bounds];
        mask.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        mask.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        mask.tag = 90003;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:[DSAEntryProxy class]
                                                                            action:@selector(tapMask)];
        [mask addGestureRecognizer:tap];
        [w addSubview:mask];

        // 面板：宽 = 屏宽 0.86，从左滑入
        CGFloat pw = MIN(w.bounds.size.width * 0.86, 340);
        DSASidebarPanel *panel = [[DSASidebarPanel alloc] initWithFrame:CGRectMake(-pw, 0, pw, w.bounds.size.height)];
        panel.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleRightMargin;
        [w addSubview:panel];

        [UIView animateWithDuration:0.25 animations:^{
            panel.frame = CGRectMake(0, 0, pw, w.bounds.size.height);
        }];

        objc_setAssociatedObject(w, &kDSASidebarTag, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(w, &kDSAMaskTag, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSLog(@"[DSAgent] sidebar shown");
    });
}



@implementation DSAEntryProxy

/// 点入口条 → 优先打开 App 原生侧边栏（智能体区块在里面）；找不到再退回自绘面板
+ (void)tapped {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = DSAKeyWindow();
        // 找 accessibilityLabel = "open_sidebar" 的按钮（真机 diag 实测存在）
        __block UIView *hit = nil;
        NSMutableArray *stack = [NSMutableArray arrayWithObject:(UIView *)w];
        int guard = 0;
        while (stack.count && guard++ < 4000) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            for (UIView *s2 in v.subviews) [stack addObject:s2];
            if (!v.window || !v.isUserInteractionEnabled) continue;
            NSString *lab = v.accessibilityLabel ?: @"";
            if ([lab isEqualToString:@"open_sidebar"] || [lab containsString:@"sidebar"]) { hit = v; break; }
        }
        if (hit && [hit isKindOfClass:[UIControl class]]) {
            [(UIControl *)hit sendActionsForControlEvents:UIControlEventTouchUpInside];
            DSADiagLog(@"[ENTRY] opened native sidebar via open_sidebar");
            return;
        }
        DSADiagLog(@"[ENTRY] open_sidebar not found, fallback to own panel");
        DSAShowSidebar();
    });
}

+ (void)tapMask { DSAHideSidebar(); }
+ (void)closePanel { DSAHideSidebar(); }
@end
