//
//  DSAShared.h — 跨编译单元共用的 C 函数声明
//  （Tweak.xm 以 C++ 编译，必须 extern "C"，否则链接时符号名对不上）
//
#ifndef DSA_SHARED_H
#define DSA_SHARED_H

#import <UIKit/UIKit.h>
#import "AgentStore.h"

#ifdef __cplusplus
extern "C" {
#endif

UIWindow *DSAKeyWindow(void);
UIViewController *DSATopMost(UIViewController *base);
void DSAToast(NSString *text);
Class DSAClassNamed(NSString *name);

// Entry.m
void DSAEnsureEntry(UIView *view);
void DSAEnsureFloatingEntry(void);
// Inject.m
void DSAOnSessionShown(NSString *sessionId);
BOOL DSASendPrompt(NSString *prompt);
// Trigger.m
void DSAOpenNewChatWithAgent(DSAAgent *agent);
// SelfTest.m
void DSAInstallSelfTest(void);
void DSAScanControls(id vc);
void DSAForceShowAgents(void);
// Probe.m
void DSAProbeWindows(void);
void DSAProbeSquare(void);

#ifdef __cplusplus
}
#endif

#endif
