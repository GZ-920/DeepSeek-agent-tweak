//
//  DSAShared.h — 跨编译单元共用的 C 函数声明
//  （Tweak.xm 以 C++ 编译，必须 extern "C"，否则链接时符号名对不上）
//
#ifndef DSA_SHARED_H
#define DSA_SHARED_H

#import <UIKit/UIKit.h>
// CGPoint 需要 CoreGraphics（UIKit 已包含）
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
// NativeInsert.m
void DSAEnsureNativeEntry(void);
// NativeSidebar.m
void DSAEnsureNativeSidebar(void);
void DSARemoveFloatingPill(void);
// Inject.m
BOOL DSASendPrompt(NSString *prompt);
// Trigger.m
void DSAOpenNewChatWithAgent(DSAAgent *agent);
// SelfTest.m
void DSAInstallSelfTest(void);
void DSAScanControls(id vc);
void DSAForceShowAgents(void);
// Inject.m
void DSAInjectTick(void);
void DSAResetInjection(void);
void DSASetFillDelay(NSTimeInterval sec);
void DSAStartInjectionPolling(void);
void DSADiagLog(NSString *line);
// Sidebar.m
void DSAShowSidebar(void);
void DSAHideSidebar(void);
// Probe.m
void DSAProbeWindows(void);
void DSAProbeSquare(void);
void DSAProbeVariants(void);
void DSARemoveProbePill(void);

#ifdef __cplusplus
}
#endif

#endif
