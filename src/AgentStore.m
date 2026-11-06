//
//  AgentStore.m
//
//  数据不落在 App 的 MMKV/SQLite 里（容易被升级覆盖），单独存成
//  Library/Application Support/DSAgent/agents.json + sessions.json。
//
#import "AgentStore.h"

static NSString *DSADir(void) {
    static NSString *dir;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
        dir = [base stringByAppendingPathComponent:@"DSAgent"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return dir;
}
static NSString *DSAPath(NSString *name) { return [DSADir() stringByAppendingPathComponent:name]; }

@implementation DSAAgent
+ (instancetype)fromDictionary:(NSDictionary *)d {
    DSAAgent *a = [DSAAgent new];
    a.agentId = d[@"id"] ?: [[NSUUID UUID] UUIDString];
    a.name = d[@"name"] ?: @"智能体";
    a.emoji = d[@"emoji"] ?: @"🤖";
    a.systemPrompt = d[@"systemPrompt"] ?: @"";
    a.greeting = d[@"greeting"] ?: @"";
    a.createdAt = [d[@"createdAt"] doubleValue];
    return a;
}
- (NSDictionary *)dictionaryRepresentation {
    return @{ @"id": self.agentId ?: @"",
              @"name": self.name ?: @"",
              @"emoji": self.emoji ?: @"🤖",
              @"systemPrompt": self.systemPrompt ?: @"",
              @"greeting": self.greeting ?: @"",
              @"createdAt": @(self.createdAt) };
}
- (NSString *)description { return [NSString stringWithFormat:@"<Agent %@ %@>", self.emoji, self.name]; }
@end

@interface DSAStore () {
    NSMutableArray<DSAAgent *> *_agents;
    NSMutableDictionary<NSString *, NSString *> *_bindings;   // sessionId -> agentId
    NSMutableDictionary<NSString *, NSNumber *> *_injected;   // sessionId -> 1
    NSString *_pendingAgentId;
}
- (void)load;
@end

@implementation DSAStore

+ (instancetype)shared {
    static DSAStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [DSAStore new]; [s load]; });
    return s;
}

- (void)loadIfNeeded { if(!_agents) [self load]; }

- (void)load {
    _agents = [NSMutableArray array];
    _bindings = [NSMutableDictionary dictionary];
    _injected = [NSMutableDictionary dictionary];

    NSData *d = [NSData dataWithContentsOfFile:DSAPath(@"agents.json")];
    if (d) {
        id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        if ([obj isKindOfClass:[NSArray class]]) {
            for (NSDictionary *item in obj) {
                if ([item isKindOfClass:[NSDictionary class]])
                    [_agents addObject:[DSAAgent fromDictionary:item]];
            }
        }
    }
    d = [NSData dataWithContentsOfFile:DSAPath(@"sessions.json")];
    if (d) {
        id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        if ([obj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *root = obj;
            if ([root[@"bindings"] isKindOfClass:[NSDictionary class]])
                [_bindings addEntriesFromDictionary:root[@"bindings"]];
            if ([root[@"injected"] isKindOfClass:[NSDictionary class]])
                [_injected addEntriesFromDictionary:root[@"injected"]];
            if ([root[@"pending"] isKindOfClass:[NSString class]])
                _pendingAgentId = root[@"pending"];
        }
    }
    [_agents sortUsingComparator:^NSComparisonResult(DSAAgent *a, DSAAgent *b) {
        return a.createdAt < b.createdAt ? NSOrderedAscending : NSOrderedDescending;
    }];
}

- (void)synchronize {
    NSMutableArray *arr = [NSMutableArray array];
    for (DSAAgent *a in _agents) [arr addObject:[a dictionaryRepresentation]];
    NSData *d = [NSJSONSerialization dataWithJSONObject:arr options:0 error:nil];
    [d writeToFile:DSAPath(@"agents.json") atomically:YES];

    NSDictionary *root = @{ @"bindings": _bindings ?: @{},
                            @"injected": _injected ?: @{},
                            @"pending": _pendingAgentId ?: @"" };
    d = [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
    [d writeToFile:DSAPath(@"sessions.json") atomically:YES];
}

#pragma mark - agents

- (NSArray<DSAAgent *> *)agents { return [_agents copy]; }

- (DSAAgent *)agentWithId:(NSString *)agentId {
    if (!agentId.length) return nil;
    for (DSAAgent *a in _agents) if ([a.agentId isEqualToString:agentId]) return a;
    return nil;
}

- (void)saveAgent:(DSAAgent *)agent {
    if (!agent.agentId.length) agent.agentId = [[NSUUID UUID] UUIDString];
    if (!agent.createdAt) agent.createdAt = [[NSDate date] timeIntervalSince1970];
    DSAAgent *old = [self agentWithId:agent.agentId];
    if (old) [_agents removeObject:old];
    [_agents addObject:agent];
    [self synchronize];
}

- (void)deleteAgentWithId:(NSString *)agentId {
    DSAAgent *old = [self agentWithId:agentId];
    if (old) [_agents removeObject:old];
    NSMutableArray *drop = [NSMutableArray array];
    for (NSString *sid in _bindings.allKeys)
        if ([_bindings[sid] isEqualToString:agentId]) [drop addObject:sid];
    [_bindings removeObjectsForKeys:drop];
    [self synchronize];
}

#pragma mark - sessions

- (NSString *)agentIdForSession:(NSString *)sessionId {
    return sessionId.length ? _bindings[sessionId] : nil;
}

- (void)bindSession:(NSString *)sessionId toAgent:(NSString *)agentId {
    if (!sessionId.length || !agentId.length) return;
    _bindings[sessionId] = agentId;
    [self synchronize];
}

- (void)unbindSession:(NSString *)sessionId {
    if (!sessionId.length) return;
    [_bindings removeObjectForKey:sessionId];
    [self synchronize];
}

- (NSArray<NSString *> *)sessionIdsForAgent:(NSString *)agentId {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *sid in _bindings.allKeys)
        if ([_bindings[sid] isEqualToString:agentId]) [out addObject:sid];
    return out;
}

- (BOOL)sessionInjected:(NSString *)sessionId {
    return sessionId.length && _injected[sessionId] != nil;
}

- (void)markSessionInjected:(NSString *)sessionId {
    if (!sessionId.length) return;
    _injected[sessionId] = @1;
    [self synchronize];
}

#pragma mark - pending

- (NSString *)pendingAgentId { return _pendingAgentId; }
- (void)setPendingAgentId:(NSString *)agentId { _pendingAgentId = [agentId copy]; [self synchronize]; }
- (NSString *)consumePendingAgentId {
    NSString *p = _pendingAgentId;
    _pendingAgentId = nil;
    if (p) [self synchronize];
    return p;
}

@end
