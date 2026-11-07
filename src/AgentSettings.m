//
//  AgentSettings.m — 智能体设置页（独立页面，不是弹出菜单）
//
//  挂载方式：直接 addSubview 到 UIWindow（和侧边栏面板同一条已验证链路），
//  不用 presentViewController（该环境不可靠）。
//
//  内容：
//    我的智能体 → 每行：名字 + 提示词摘要 + 删除按钮
//    ＋ 新建智能体（多行提示词编辑器）
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"
#import "AgentStore.h"

static char kDSSettingsTag;
static char kDSSettingsMaskTag;

void DSADiagLog(NSString *line);

@interface DSASettingsProxy : NSObject
+ (void)close;
+ (void)addAgent;
+ (void)deleteAgent:(UIButton *)sender;
@end

@interface DSASettingsView : UIView <UITableViewDataSource, UITableViewDelegate>
@end

@implementation DSASettingsView {
    UITableView *_table;
    NSArray<DSAAgent *> *_agents;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor systemGroupedBackgroundColor];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.text = @"智能体设置";
        title.font = [UIFont boldSystemFontOfSize:17];
        [self addSubview:title];

        UIControl *close = [[UIControl alloc] initWithFrame:CGRectZero];
        close.translatesAutoresizingMaskIntoConstraints = NO;
        [close addTarget:[DSASettingsProxy class] action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
        close.accessibilityLabel = @"关闭";
        UILabel *cl = [[UILabel alloc] initWithFrame:CGRectZero];
        cl.translatesAutoresizingMaskIntoConstraints = NO;
        cl.text = @"✕";
        cl.font = [UIFont boldSystemFontOfSize:18];
        cl.textColor = [UIColor secondaryLabelColor];
        cl.textAlignment = NSTextAlignmentCenter;
        [close addSubview:cl];
        [self addSubview:close];
        [NSLayoutConstraint activateConstraints:@[
            [cl.topAnchor constraintEqualToAnchor:close.topAnchor],
            [cl.bottomAnchor constraintEqualToAnchor:close.bottomAnchor],
            [cl.leadingAnchor constraintEqualToAnchor:close.leadingAnchor],
            [cl.trailingAnchor constraintEqualToAnchor:close.trailingAnchor],
        ]];

        UIButton *add = [UIButton buttonWithType:UIButtonTypeSystem];
        add.translatesAutoresizingMaskIntoConstraints = NO;
        [add setTitle:@"＋ 新建智能体" forState:UIControlStateNormal];
        add.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        add.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        [add setTitleColor:[UIColor colorWithRed:0.29 green:0.48 blue:1.0 alpha:1] forState:UIControlStateNormal];
        [add addTarget:[DSASettingsProxy class] action:@selector(addAgent) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:add];

        _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
        _table.dataSource = self;
        _table.delegate = self;
        _table.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_table];

        CGFloat top = 0;
        if (@available(iOS 11.0, *)) top = self.safeAreaInsets.top;
        if (top <= 0) top = 44;
        [NSLayoutConstraint activateConstraints:@[
            [title.topAnchor constraintEqualToAnchor:self.topAnchor constant:top + 8],
            [title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-56],
            [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
            [close.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [close.widthAnchor constraintEqualToConstant:32],
            [close.heightAnchor constraintEqualToConstant:32],
            [add.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
            [add.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [add.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
            [add.heightAnchor constraintEqualToConstant:40],
            [_table.topAnchor constraintEqualToAnchor:add.bottomAnchor],
            [_table.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_table.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_table.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];

        [self reload];
    }
    return self;
}

- (void)reload {
    DSAStore *store = [DSAStore shared];
    [store loadIfNeeded];
    _agents = store.agents;
    [_table reloadData];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)_agents.count; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return _agents.count ? @"点击行可编辑，右侧删除" : @"还没有智能体";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:nil];
    DSAAgent *a = _agents[(NSUInteger)ip.row];
    cell.textLabel.text = a.name;
    NSString *p = [a.systemPrompt stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    cell.detailTextLabel.text = p.length > 40 ? [[p substringToIndex:40] stringByAppendingString:@"…"] : p;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
    [del setTitle:@"删除" forState:UIControlStateNormal];
    [del setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    del.tag = 92000 + (NSInteger)ip.row;
    [del addTarget:[DSASettingsProxy class] action:@selector(deleteAgent:) forControlEvents:UIControlEventTouchUpInside];
    del.accessibilityLabel = [@"删除 " stringByAppendingString:a.name];
    [cell.contentView addSubview:del];
    del.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [del.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
        [del.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
    ]];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    DSAAgent *a = _agents[(NSUInteger)ip.row];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
        DSAPresentAgentEditor(top, a, ^(DSAAgent *saved, BOOL startNew) {
            [self reload];
            DSARefreshNativeSidebar();
            if (startNew) DSAOpenNewChatWithAgent(saved);
        });
    });
}

@end

@implementation DSASettingsProxy
+ (void)close { DSAHideSettings(); }
+ (void)addAgent {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
        DSAPresentAgentEditor(top, nil, ^(DSAAgent *saved, BOOL startNew) {
            DSARefreshSettings();
            DSARefreshNativeSidebar();
            if (startNew) DSAOpenNewChatWithAgent(saved);
        });
    });
}
+ (void)deleteAgent:(UIButton *)sender {
    NSInteger idx = sender.tag - 92000;
    NSArray<DSAAgent *> *agents = [DSAStore shared].agents;
    if (idx < 0 || idx >= (NSInteger)agents.count) return;
    DSAAgent *a = agents[(NSUInteger)idx];
    [[DSAStore shared] deleteAgentWithId:a.agentId];
    DSAToast([NSString stringWithFormat:@"已删除「%@」", a.name]);
    DSARefreshSettings();
    DSARefreshNativeSidebar();
}
@end

void DSARefreshSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = DSAKeyWindow();
        DSASettingsView *v = objc_getAssociatedObject(w, &kDSSettingsTag);
        if (v) [v reload];
    });
}

void DSAHideSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = DSAKeyWindow();
        UIView *v = objc_getAssociatedObject(w, &kDSSettingsTag);
        UIView *mask = objc_getAssociatedObject(w, &kDSSettingsMaskTag);
        [UIView animateWithDuration:0.2 animations:^{
            v.frame = CGRectMake(v.bounds.size.width, 0, v.bounds.size.width, v.bounds.size.height);
            mask.alpha = 0;
        } completion:^(BOOL done) {
            [v removeFromSuperview];
            [mask removeFromSuperview];
            objc_setAssociatedObject(w, &kDSSettingsTag, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(w, &kDSSettingsMaskTag, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }];
    });
}

void DSAShowSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = DSAKeyWindow();
        if (!w) return;
        if (objc_getAssociatedObject(w, &kDSSettingsTag)) return;

        UIView *mask = [[UIView alloc] initWithFrame:w.bounds];
        mask.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        mask.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:[DSASettingsProxy class]
                                                                            action:@selector(close)];
        [mask addGestureRecognizer:tap];
        [w addSubview:mask];

        CGFloat pw = MIN(w.bounds.size.width * 0.92, 400);
        DSASettingsView *page = [[DSASettingsView alloc] initWithFrame:CGRectMake(pw, 0, pw, w.bounds.size.height)];
        page.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleLeftMargin;
        [w addSubview:page];
        [UIView animateWithDuration:0.25 animations:^{
            page.frame = CGRectMake(w.bounds.size.width - pw, 0, pw, w.bounds.size.height);
        }];

        objc_setAssociatedObject(w, &kDSSettingsTag, page, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(w, &kDSSettingsMaskTag, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DSADiagLog(@"[SETTINGS] shown");
    });
}
