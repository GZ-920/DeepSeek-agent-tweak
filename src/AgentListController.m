//
//  AgentListController.m
//
//  纯 UIKit 实现，不依赖 App 内部任何类；只依赖 AgentStore。
//
#import "AgentListController.h"
#import <objc/runtime.h>


static UIColor *DSAAccent(void) { return [UIColor colorWithRed:0.29 green:0.48 blue:1.0 alpha:1.0]; }
static NSInteger const kTagAgentChats = 1001;
static NSInteger const kTagAgents = 1002;

static UITableView *DSAMakeTable(id target) {
    UITableView *t = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    t.dataSource = (id<UITableViewDataSource>)target;
    t.delegate = (id<UITableViewDelegate>)target;
    t.backgroundColor = [UIColor clearColor];
    t.rowHeight = 56;
    t.translatesAutoresizingMaskIntoConstraints = NO;
    return t;
}

static UILabel *DSAHeaderLabel(NSString *text) {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    l.textColor = [UIColor secondaryLabelColor];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [l.heightAnchor constraintEqualToConstant:26].active = YES;
    return l;
}

#pragma mark - 智能体主页

@interface DSAAgentListController () {
    UITableView *_agentChats;
    UITableView *_agents;
    NSArray<NSDictionary *> *_chatRows;
}
@end

@implementation DSAAgentListController

+ (UINavigationController *)presentedRoot {
    DSAAgentListController *c = [DSAAgentListController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:c];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    return nav;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"智能体";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self action:@selector(addAgent)];

    _agentChats = DSAMakeTable(self);
    _agentChats.tag = kTagAgentChats;
    _agents = DSAMakeTable(self);
    _agents.tag = kTagAgents;

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        DSAHeaderLabel(@"智能体对话"),
        _agentChats,
        DSAHeaderLabel(@"我的智能体"),
        _agents,
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:8],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-40],
        [_agentChats.heightAnchor constraintEqualToConstant:200],
        [_agents.heightAnchor constraintEqualToConstant:300],
    ]];

    [self reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadData];
}

- (void)reloadData {
    DSAStore *store = [DSAStore shared];
    [store loadIfNeeded];
    NSMutableArray *rows = [NSMutableArray array];
    for (DSAAgent *a in store.agents) {
        [rows addObject:@{ @"agent": a, @"sessionIds": [store sessionIdsForAgent:a.agentId] }];
    }
    _chatRows = rows;
    [_agentChats reloadData];
    [_agents reloadData];
}

- (void)addAgent { [self openEditor:nil]; }

- (void)openEditor:(DSAAgent *)agent {
    DSAAgentEditController *edit = [DSAAgentEditController new];
    edit.agent = agent;
    __weak typeof(self) weakSelf = self;
    edit.onSaved = ^(DSAAgent *saved, BOOL startNewChat) {
        [[DSAStore shared] saveAgent:saved];
        [weakSelf reloadData];
        if (startNewChat) {
            [weakSelf dismissViewControllerAnimated:YES completion:^{
                DSAOpenNewChatWithAgent(saved);
            }];
        } else {
            [weakSelf.navigationController popViewControllerAnimated:YES];
        }
    };
    [self.navigationController pushViewController:edit animated:YES];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (tv.tag == kTagAgents) return (NSInteger)[DSAStore shared].agents.count + 1;   // 末行 = 新建
    return (NSInteger)_chatRows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:nil];
    if (tv.tag == kTagAgents) {
        NSArray<DSAAgent *> *agents = [DSAStore shared].agents;
        if (ip.row >= (NSInteger)agents.count) {
            cell.textLabel.text = @"＋ 新建智能体";
            cell.textLabel.textColor = DSAAccent();
            cell.detailTextLabel.text = @"设定名字 + 首条系统提示词";
        } else {
            DSAAgent *a = agents[(NSUInteger)ip.row];
            cell.textLabel.text = [NSString stringWithFormat:@"%@  %@", a.emoji ?: @"🤖", a.name];
            NSString *p = [a.systemPrompt stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            cell.detailTextLabel.text = p.length > 36 ? [[p substringToIndex:36] stringByAppendingString:@"…"] : p;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else {
        NSDictionary *row = _chatRows[(NSUInteger)ip.row];
        DSAAgent *a = row[@"agent"];
        NSUInteger n = [(NSArray *)row[@"sessionIds"] count];
        cell.textLabel.text = [NSString stringWithFormat:@"%@  %@", a.emoji ?: @"🕘", a.name];
        cell.detailTextLabel.text = n ? [NSString stringWithFormat:@"%lu 个对话", (unsigned long)n]
                                      : @"暂无对话，点进去新建";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (tv.tag != kTagAgents) {
        NSDictionary *row = _chatRows[(NSUInteger)ip.row];
        DSAAgentChatListController *c = [DSAAgentChatListController new];
        c.agent = row[@"agent"];
        [self.navigationController pushViewController:c animated:YES];
        return;
    }
    NSArray<DSAAgent *> *agents = [DSAStore shared].agents;
    if (ip.row >= (NSInteger)agents.count) { [self addAgent]; return; }
    DSAAgent *a = agents[(NSUInteger)ip.row];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:a.name
                                                                  message:a.systemPrompt
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"新建对话（自动发送设定提示词）"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *x) { DSAOpenNewChatWithAgent(a); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"查看对话列表"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *x) {
        DSAAgentChatListController *c = [DSAAgentChatListController new];
        c.agent = a;
        [self.navigationController pushViewController:c animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"编辑" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *x) { [self openEditor:a]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *x) {
        [[DSAStore shared] deleteAgentWithId:a.agentId];
        [self reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = tv;
    sheet.popoverPresentationController.sourceRect = [tv rectForRowAtIndexPath:ip];
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

#pragma mark - 新建 / 编辑

@implementation DSAAgentEditController {
    UITextField *_nameField;
    UITextField *_emojiField;
    UITextView *_promptView;
    UITextView *_greetingView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    BOOL isNew = (self.agent == nil);
    self.title = isNew ? @"新建智能体" : @"编辑智能体";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    _nameField = [UITextField new];
    _nameField.placeholder = @"名字，例如：论文导师";
    _nameField.text = self.agent.name;
    _nameField.borderStyle = UITextBorderStyleRoundedRect;
    _nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _nameField.returnKeyType = UIReturnKeyDone;
    _nameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _nameField.delegate = self;

    _emojiField = [UITextField new];
    _emojiField.text = self.agent.emoji.length ? self.agent.emoji : @"🤖";
    _emojiField.borderStyle = UITextBorderStyleRoundedRect;
    _emojiField.textAlignment = NSTextAlignmentCenter;
    _emojiField.delegate = self;

    _promptView = [self textView:self.agent.systemPrompt height:200];
    _greetingView = [self textView:self.agent.greeting height:80];

    UILabel *hint = [UILabel new];
    hint.numberOfLines = 0;
    hint.font = [UIFont systemFontOfSize:12];
    hint.textColor = [UIColor secondaryLabelColor];
    hint.text = @"每次用这个智能体开始新对话，App 都会先把「设定提示词」作为第一条消息发出去，再进入正常对话。\n"
                 @"建议以「你将扮演…」开头，并写清输出格式与禁忌。";

    UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
    [save setTitle:isNew ? @"保存并开始对话" : @"保存" forState:UIControlStateNormal];
    save.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    save.backgroundColor = DSAAccent();
    [save setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    save.layer.cornerRadius = 12;
    [save addTarget:self action:@selector(save:) forControlEvents:UIControlEventTouchUpInside];
    [save.heightAnchor constraintEqualToConstant:48].active = YES;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_emojiField, _nameField]];
    row.spacing = 8;
    row.distribution = UIStackViewDistributionFill;
    [_emojiField.widthAnchor constraintEqualToConstant:64].active = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        DSAHeaderLabel(@"图标"), row,
        DSAHeaderLabel(@"名字"),
        DSAHeaderLabel(@"设定提示词（每次新对话自动发送）"), _promptView,
        DSAHeaderLabel(@"开场白（可选，只显示不发送）"), _greetingView,
        hint, save,
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:scroll];
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-40],
    ]];

    if (isNew) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self->_nameField becomeFirstResponder]; });
    }
}

- (UITextView *)textView:(NSString *)text height:(CGFloat)h {
    UITextView *v = [UITextView new];
    v.text = text ?: @"";
    v.font = [UIFont systemFontOfSize:15];
    v.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    v.layer.cornerRadius = 10;
    v.textContainerInset = UIEdgeInsetsMake(8, 6, 8, 6);
    v.delegate = self;
    [v.heightAnchor constraintEqualToConstant:h].active = YES;
    return v;
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

- (void)save:(id)sender {
    [self.view endEditing:YES];
    NSString *name = [_nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *prompt = [_promptView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *err = nil;
    if (!name.length) err = @"请填写名字";
    else if (!prompt.length) err = @"设定提示词不能为空（它就是每次新对话的第一条消息）";
    if (err) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"还差一点"
                                                                   message:err
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    BOOL isNew = (self.agent == nil);
    DSAAgent *a = self.agent ?: [DSAAgent new];
    a.name = name;
    a.emoji = _emojiField.text.length ? _emojiField.text : @"🤖";
    a.systemPrompt = prompt;
    a.greeting = [_greetingView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!a.agentId.length) a.agentId = [[NSUUID UUID] UUIDString];
    if (!a.createdAt) a.createdAt = [[NSDate date] timeIntervalSince1970];
    if (self.onSaved) self.onSaved(a, isNew);
}

@end

#pragma mark - 单个智能体的对话列表

@implementation DSAAgentChatListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.agent.name ?: @"智能体";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose
                                                      target:self action:@selector(newChat)];
    UITableView *t = DSAMakeTable(self);
    t.frame = self.view.bounds;
    t.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:t];
}

- (void)newChat {
    DSAOpenNewChatWithAgent(self.agent);
    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    NSUInteger n = [[DSAStore shared] sessionIdsForAgent:self.agent.agentId].count;
    return n ? (NSInteger)n : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                   reuseIdentifier:nil];
    NSArray<NSString *> *sids = [[DSAStore shared] sessionIdsForAgent:self.agent.agentId];
    if (!sids.count) {
        cell.textLabel.text = @"还没有对话";
        cell.detailTextLabel.text = @"点右上角 ✎ 新建一个，会自动发送设定提示词";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSString *sid = sids[(NSUInteger)ip.row];
    cell.textLabel.text = [NSString stringWithFormat:@"对话 %@",
                           [sid substringToIndex:MIN((NSUInteger)8, sid.length)]];
    cell.detailTextLabel.text = sid;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
}

@end
