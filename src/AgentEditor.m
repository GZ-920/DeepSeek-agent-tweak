//
//  AgentEditor.m — 新建/编辑智能体（提示词用多行 UITextView）
//
//  UIAlertController 的 textField 只能单行，所以往 alert.view 里嵌一个 UITextView。
//
#import <UIKit/UIKit.h>
#import "DSAShared.h"
#import "AgentStore.h"

void DSADiagLog(NSString *line);

/// 弹出智能体编辑器。existing = nil 表示新建
/// done(saved, startNewChat)
void DSAPresentAgentEditor(UIViewController *top, DSAAgent *existing,
                           void (^done)(DSAAgent *saved, BOOL startNew)) {
    if (!top) return;
    BOOL isNew = (existing == nil);

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:isNew ? @"新建智能体" : @"编辑智能体"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];

    // 名字（单行）
    [alert addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"名字，例如：论文导师";
        f.text = existing.name;
        f.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    // 提示词（多行）：嵌进 alert.view
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectZero];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.font = [UIFont systemFontOfSize:14];
    tv.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    tv.layer.cornerRadius = 8;
    tv.text = existing.systemPrompt ?: @"";
    tv.textContainerInset = UIEdgeInsetsMake(8, 6, 8, 6);
    tv.accessibilityLabel = @"设定提示词";
    [alert.view addSubview:tv];

    UILabel *cap = [[UILabel alloc] initWithFrame:CGRectZero];
    cap.translatesAutoresizingMaskIntoConstraints = NO;
    cap.text = @"设定提示词（每次新对话自动发送）";
    cap.font = [UIFont systemFontOfSize:12];
    cap.textColor = [UIColor secondaryLabelColor];
    [alert.view addSubview:cap];

    [NSLayoutConstraint activateConstraints:@[
        [cap.topAnchor constraintEqualToAnchor:alert.view.topAnchor constant:54],
        [cap.leadingAnchor constraintEqualToAnchor:alert.view.leadingAnchor constant:20],
        [cap.trailingAnchor constraintEqualToAnchor:alert.view.trailingAnchor constant:-20],
        [tv.topAnchor constraintEqualToAnchor:cap.bottomAnchor constant:4],
        [tv.leadingAnchor constraintEqualToAnchor:alert.view.leadingAnchor constant:20],
        [tv.trailingAnchor constraintEqualToAnchor:alert.view.trailingAnchor constant:-20],
        [tv.heightAnchor constraintEqualToConstant:140],
    ]];

    void (^saveBlock)(BOOL) = ^(BOOL startNew) {
        NSString *name = [alert.textFields.firstObject.text
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *prompt = [tv.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!name.length || !prompt.length) {
            DSAToast(@"名字和提示词都不能为空");
            return;
        }
        DSAAgent *a = existing ?: [DSAAgent new];
        if (!a.agentId.length) a.agentId = [[NSUUID UUID] UUIDString];
        a.name = name;
        a.systemPrompt = prompt;
        if (!a.emoji.length) a.emoji = @"";
        if (!a.createdAt) a.createdAt = [[NSDate date] timeIntervalSince1970];
        [[DSAStore shared] saveAgent:a];
        DSADiagLog([NSString stringWithFormat:@"[EDITOR] saved agent=%@ startNew=%d", a.name, startNew]);
        if (done) done(a, startNew);
    };

    [alert addAction:[UIAlertAction actionWithTitle:@"保存并开始对话" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *x) { saveBlock(YES); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *x) { saveBlock(NO); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    [top presentViewController:alert animated:YES completion:^{
        [alert.view layoutIfNeeded];
        [tv becomeFirstResponder];
    }];
}
