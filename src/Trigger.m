//
//  Trigger.m — 「用某智能体新建对话」
//
//  App 内部建新会话的入口不唯一，这里不硬编码具体方法：
//    1. 记录 pendingAgentId（会话页出现时 Inject.m 会接管）
//    2. 广播 DSANewChatRequest 给可能的内部监听
//
#import <UIKit/UIKit.h>
#import "AgentStore.h"

extern void DSAToast(NSString *text);

void DSAOpenNewChatWithAgent(DSAAgent *agent) {
    if (!agent) return;
    [[DSAStore shared] setPendingAgentId:agent.agentId];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DSANewChatRequest"
                                                            object:nil
                                                          userInfo:@{ @"agentId": agent.agentId }];
        DSAToast([NSString stringWithFormat:@"已选好「%@」\n点「新建对话」后会自动发送设定提示词", agent.name]);
    });
}
