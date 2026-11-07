//
//  SelfTest.m — 调试与自检（全部包 @try，任何异常都不能让 App 崩）
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"
#import "AgentListController.h"

static NSString *DSADocPath(NSString *name) {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (!dir) dir = NSTemporaryDirectory();
    return [dir stringByAppendingPathComponent:name];
}

static void DSALogAppend(NSString *line) {
    @try {
        NSLog(@"[DSAgent] %@", line);
        NSString *path = DSADocPath(@"DSAgent_scan.txt");
        NSString *old = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
        if (old.length > 200000) old = @"";
        [[old stringByAppendingFormat:@"%@\n", line] writeToFile:path atomically:YES
                                                      encoding:NSUTF8StringEncoding error:nil];
    } @catch (__unused NSException *e) {}
}

static void DSADumpObject(id obj, NSString *label) {
    @try {
        if (!obj) return;
        Class cls = object_getClass(obj);
        if (!cls) return;
        NSMutableArray *hits = [NSMutableArray array];
        unsigned int n = 0;
        Ivar *ivars = class_copyIvarList(cls, &n);
        if (!ivars) return;
        for (unsigned int i = 0; i < n && i < 400; i++) {
            const char *nm = ivar_getName(ivars[i]);
            if (!nm) continue;
            NSString *name = [NSString stringWithUTF8String:nm];
            NSString *low = name.lowercaseString;
            BOOL interesting = [low containsString:@"table"] || [low containsString:@"list"] ||
                               [low containsString:@"collection"] || [low containsString:@"sidebar"];
            if (!interesting) continue;
            id val = nil;
            @try { val = object_getIvar(obj, ivars[i]); } @catch (__unused NSException *e) {}
            [hits addObject:[NSString stringWithFormat:@"%@ = (%@)", name,
                             val ? NSStringFromClass([val class]) : @"nil"]];
        }
        free(ivars);
        if (hits.count) {
            DSALogAppend([NSString stringWithFormat:@"%@ %@\n    %@", label,
                          NSStringFromClass(cls), [hits componentsJoinedByString:@"\n    "]]);
        }
    } @catch (__unused NSException *e) {}
}

void DSAScanControls(id vc) {
    @try {
        if (!vc) return;
        DSADumpObject(vc, @"[VC]");
    } @catch (__unused NSException *e) {}
}

static void DSAScanVisibleLists(void) {
    @try {
        UIWindow *w = DSAKeyWindow();
        if (!w) return;
        NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
        int guard = 0;
        while (stack.count && guard++ < 4000) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            for (UIView *s in v.subviews) [stack addObject:s];
            BOOL isList = [v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]];
            if (!isList || !v.window) continue;
            NSString *chain = NSStringFromClass([v class]);
            UIView *p = v.superview;
            for (int i = 0; i < 2 && p; i++, p = p.superview)
                chain = [chain stringByAppendingFormat:@" <- %@", NSStringFromClass([p class])];
            DSALogAppend([NSString stringWithFormat:@"[LIST] %@ h=%.0f w=%.0f",
                          chain, v.frame.size.height, v.frame.size.width]);
        }
    } @catch (__unused NSException *e) {}
}

void DSAForceShowAgents(void) {
    @try {
        UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
        if (!top) return;
        DSALogAppend(@"[FORCE] presenting agent home");
        [top presentViewController:[DSAAgentListController presentedRoot] animated:YES completion:nil];
    } @catch (__unused NSException *e) {
        DSALogAppend([NSString stringWithFormat:@"[FORCE] failed: %@", e.reason]);
    }
}

void DSAInstallSelfTest(void) {
    NSLog(@"[DSAgent] ===== dylib loaded, pid=%d =====", (int)getpid());
    @try {
        [@"loaded\n" writeToFile:DSADocPath(@"DSAgent_scan.txt") atomically:YES
                        encoding:NSUTF8StringEncoding error:nil];
    } @catch (__unused NSException *e) {}

    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UIWindow *w = DSAKeyWindow();
            if (!w) return;
            UILabel *badge = [UILabel new];
            badge.text = @"DSAgent ✓";
            badge.font = [UIFont boldSystemFontOfSize:11];
            badge.textColor = UIColor.whiteColor;
            badge.backgroundColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:0.85];
            badge.textAlignment = NSTextAlignmentCenter;
            badge.layer.cornerRadius = 6;
            badge.clipsToBounds = YES;
            badge.frame = CGRectMake(w.bounds.size.width - 96, 60, 84, 22);
            badge.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
            [w addSubview:badge];
        } @catch (__unused NSException *e) {}
    });

#ifdef DSA_SCAN
    // 延时扫描：避开 App 启动阶段（之前在这里崩过）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @try {
            UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
            DSALogAppend(@"[SCAN] begin");
            DSAScanControls(top);
            DSAScanVisibleLists();
            DSALogAppend(@"[SCAN] end");
        } @catch (__unused NSException *e) {}
    });
#endif

#ifdef DSA_UI_FORCE
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ DSAForceShowAgents(); });
#endif
}
