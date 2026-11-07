//
//  AgentStore.h
//  智能体（Agent）本地存储：智能体定义 + 会话↔智能体绑定
//
#ifndef DS_AGENT_STORE_H
#define DS_AGENT_STORE_H

#import <Foundation/Foundation.h>

@interface DSAAgent : NSObject
@property (nonatomic, copy) NSString *agentId;      // UUID
@property (nonatomic, copy) NSString *name;         // 显示名
@property (nonatomic, copy) NSString *emoji;        // 头像/图标
@property (nonatomic, copy) NSString *systemPrompt; // 首条设定提示词
@property (nonatomic, copy) NSString *greeting;     // 可选：开场白（只显示不发送）
@property (nonatomic, assign) NSTimeInterval createdAt;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface DSAStore : NSObject
+ (instancetype)shared;
- (void)loadIfNeeded;
- (void)synchronize;

// —— 智能体 ——
- (NSArray<DSAAgent *> *)agents;                    // 按 createdAt 升序
- (DSAAgent *)agentWithId:(NSString *)agentId;
- (void)saveAgent:(DSAAgent *)agent;
- (void)deleteAgentWithId:(NSString *)agentId;

// —— 会话绑定 ——
- (NSString *)agentIdForSession:(NSString *)sessionId;
- (void)bindSession:(NSString *)sessionId toAgent:(NSString *)agentId;
- (void)unbindSession:(NSString *)sessionId;
- (NSArray<NSString *> *)sessionIdsForAgent:(NSString *)agentId;
- (NSString *)lastBoundSessionId;
- (void)setConversationName:(NSString *)name forSession:(NSString *)sessionId;
- (NSString *)conversationNameForSession:(NSString *)sessionId;

// —— 防重复注入 ——
- (BOOL)sessionInjected:(NSString *)sessionId;
- (void)markSessionInjected:(NSString *)sessionId;
- (void)uninjectMark:(NSString *)sessionId;   // 撤销标记（重置用）

// —— 待启动智能体 ——
- (NSString *)pendingAgentId;
- (void)setPendingAgentId:(NSString *)agentId;
- (NSString *)consumePendingAgentId;

@end

#endif
