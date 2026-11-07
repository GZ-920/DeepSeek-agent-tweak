//
//  AgentSettings.m — 智能体设置（原生 presentViewController + 导航栈）
//
//  结构：
//    设置列表（我的智能体 / 新建）
//      → 点行进入「编辑页」：名字输入框 + 多行提示词 + 保存 / 删除（全部内联，无弹窗）
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"
#import "AgentStore.h"

void DSADiagLog(NSString *line);

#pragma mark - 编辑页（内联表单）

@interface DSAgentFormController : UIViewController <UITextFieldDelegate, UITextViewDelegate>
@property (nonatomic, strong) DSAAgent *agent;   // nil = 新建
@property (nonatomic, copy) void (^onChanged)(void);
@end

@implementation DSAgentFormController {
    UITextField *_nameField;
    UITextView *_promptView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    BOOL isNew = (self.agent == nil);
    self.title = isNew ? @"新建智能体" : @"编辑智能体";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    _nameField = [[UITextField alloc] initWithFrame:CGRectZero];
    _nameField.translatesAutoresizingMaskIntoConstraints = NO;
    _nameField.placeholder = @"名字，例如：论文导师";
    _nameField.text = self.agent.name;
    _nameField.borderStyle = UITextBorderStyleRoundedRect;
    _nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _nameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _nameField.delegate = self;

    _promptView = [[UITextView alloc] initWithFrame:CGRectZero];
    _promptView.translatesAutoresizingMaskIntoConstraints = NO;
    _promptView.font = [UIFont systemFontOfSize:15];
    _promptView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    _promptView.layer.cornerRadius = 10;
    _promptView.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    _promptView.text = self.agent.systemPrompt ?: @"";

    UILabel *cap = [[UILabel alloc] initWithFrame:CGRectZero];
    cap.translatesAutoresizingMaskIntoConstraints = NO;
    cap.text = @"设定提示词（每次新对话自动发送）";
    cap.font = [UIFont systemFontOfSize:13];
    cap.textColor = [UIColor secondaryLabelColor];

    UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
    save.translatesAutoresizingMaskIntoConstraints = NO;
    [save setTitle:isNew ? @"保存并开始对话" : @"保存" forState:UIControlStateNormal];
    save.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    save.backgroundColor = [UIColor colorWithRed:0.29 green:0.48 blue:1.0 alpha:1];
    [save setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    save.layer.cornerRadius = 12;
    [save addTarget:self action:@selector(save:) forControlEvents:UIControlEventTouchUpInside];

    UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
    del.translatesAutoresizingMaskIntoConstraints = NO;
    [del setTitle:@"删除此智能体" forState:UIControlStateNormal];
    [del setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    [del addTarget:self action:@selector(deleteAgent:) forControlEvents:UIControlEventTouchUpInside];
    del.hidden = isNew;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[cap, _promptView, save, del]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *nameCap = [[UILabel alloc] initWithFrame:CGRectZero];
    nameCap.translatesAutoresizingMaskIntoConstraints = NO;
    nameCap.text = @"名字";
    nameCap.font = [UIFont systemFontOfSize:13];
    nameCap.textColor = [UIColor secondaryLabelColor];

    UIStackView *outer = [[UIStackView alloc] initWithArrangedSubviews:@[nameCap, _nameField, stack]];
    outer.axis = UILayoutConstraintAxisVertical;
    outer.spacing = 8;
    outer.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:scroll];
    [scroll addSubview:outer];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [outer.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:16],
        [outer.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:20],
        [outer.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-20],
        [outer.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-24],
        [outer.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-40],
        [_nameField.heightAnchor constraintEqualToConstant:44],
        [_promptView.heightAnchor constraintEqualToConstant:180],
        [save.heightAnchor constraintEqualToConstant:48],
    ]];

    if (isNew) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                              dispatch_get_main_queue(), ^{ [_nameField becomeFirstResponder]; });
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

- (void)save:(id)sender {
    NSString *name = [_nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *prompt = [_promptView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!name.length || !prompt.length) { DSAToast(@"名字和提示词都不能为空"); return; }

    BOOL isNew = (self.agent == nil);
    DSAAgent *a = self.agent ?: [DSAAgent new];
    if (!a.agentId.length) a.agentId = [[NSUUID UUID] UUIDString];
    a.name = name;
    a.systemPrompt = prompt;
    if (!a.emoji.length) a.emoji = @"";
    if (!a.createdAt) a.createdAt = [[NSDate date] timeIntervalSince1970];
    [[DSAStore shared] saveAgent:a];
    DSADiagLog([NSString stringWithFormat:@"[SETTINGS] saved agent=%@ new=%d", a.name, isNew]);
    DSARefreshNativeSidebar();

    if (isNew) {
        [self.navigationController popViewControllerAnimated:YES];
        DSAOpenNewChatWithAgent(a);
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)deleteAgent:(id)sender {
    [[DSAStore shared] deleteAgentWithId:self.agent.agentId];
    DSADiagLog([NSString stringWithFormat:@"[SETTINGS] deleted agent=%@", self.agent.name]);
    DSARefreshNativeSidebar();
    [self.navigationController popViewControllerAnimated:YES];
}

@end

#pragma mark - 设置列表

@interface DSAgentSettingsController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@end

@implementation DSAgentSettingsController {
    UITableView *_table;
    NSArray<DSAAgent *> *_agents;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"智能体设置";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                      target:self action:@selector(close)];

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _table.dataSource = self;
    _table.delegate = self;
    _table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_table];
    [NSLayoutConstraint activateConstraints:@[
        [_table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)reload {
    [[DSAStore shared] loadIfNeeded];
    _agents = [DSAStore shared].agents;
    [_table reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? (NSInteger)_agents.count : 1;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"我的智能体" : nil;
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return s == 1 ? @"新增或编辑智能体都在本页完成" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:nil];
    if (ip.section == 0) {
        DSAAgent *a = _agents[(NSUInteger)ip.row];
        cell.textLabel.text = a.name;
        NSString *p = [a.systemPrompt stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        cell.detailTextLabel.text = p.length > 40 ? [[p substringToIndex:40] stringByAppendingString:@"…"] : p;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = @"＋ 新建智能体";
        cell.textLabel.textColor = [UIColor colorWithRed:0.29 green:0.48 blue:1.0 alpha:1];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    DSAgentFormController *form = [DSAAgentFormController new];
    form.agent = (ip.section == 0) ? _agents[(NSUInteger)ip.row] : nil;
    [self.navigationController pushViewController:form animated:YES];
}

@end

#pragma mark - 弹出

void DSAShowSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static BOOL showing = NO;
        if (showing) return;
        UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
        if (!top) return;
        // 已经在设置页里就不重复弹
        if ([top isKindOfClass:[DSAAgentSettingsController class]]) return;

        DSAgentSettingsController *page = [DSAAgentSettingsController new];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:page];
        if (@available(iOS 13.0, *)) {
            nav.modalPresentationStyle = UIModalPresentationFormSheet;
        }
        showing = YES;
        [top presentViewController:nav animated:YES completion:^{
            showing = NO;
            DSADiagLog(@"[SETTINGS] presented natively");
        }];
        DSADiagLog(@"[SETTINGS] present called");
    });
}

void DSAHideSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
        if ([top isKindOfClass:[UINavigationController class]] &&
            [[(UINavigationController *)top topViewController] isKindOfClass:[DSAAgentSettingsController class]])
            [top dismissViewControllerAnimated:YES completion:nil];
    });
}

void DSARefreshSettings(void) {
    // 列表在 viewWillAppear 里自动刷新，无需额外处理
}
