//
//  AgentListController.h
//  智能体主页 / 编辑器 / 单个智能体的对话列表
//
#import <UIKit/UIKit.h>
#import "AgentStore.h"

@interface DSAAgentListController : UIViewController <UITableViewDataSource, UITableViewDelegate>
+ (UINavigationController *)presentedRoot;
@end

@interface DSAAgentEditController : UIViewController <UITextFieldDelegate, UITextViewDelegate>
@property (nonatomic, strong) DSAAgent *agent;   // nil = 新建
@property (nonatomic, copy) void (^onSaved)(DSAAgent *saved, BOOL startNewChat);
@end

@interface DSAAgentChatListController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) DSAAgent *agent;
@end
