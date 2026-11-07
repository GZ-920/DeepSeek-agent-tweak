//
//  SelfTest.m — 调试与自检
//    DSA_SELFTEST：右上角红角标 + 写沙盒标记文件（确认 dylib 已加载）
//    DSA_UI_FORCE：注入后 4 秒直接弹出智能体主页（确认 UI 本身没问题）
//    DSAScanControls：扫描当前界面的类名属性，找会话列表视图（确认 hook 名）
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"
#import "AgentListController.h"

void DSAInstallSelfTest(void);
void DSAScanControls(id vc);
void DSAForceShowAgents(void);

static NSString *DSALogPath(void) {
    static NSString *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        p = [dir stringByAppendingPathComponent:@"DSAgent_scan.txt"];
    });
    return p;
}

static void DSALogAppend(NSString *line) {
    NSLog(@"[DSAgent] %@", line);
    NSString *path = DSALogPath();
    NSString *old = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSString *next = [old stringByAppendingFormat:@"%@\n", line];
    [next writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

/// 把任意对象的所有属性/ivar 里「是 UIView / 名字像 table、list、collection」的列出来
static void DSADumpObject(id obj, NSString *label) {
    if (!obj) return;
    Class cls = object_getClass(obj);
    NSMutableArray *hits = [NSMutableArray array];
    unsigned int n = 0;
    Ivar *ivars = class_copyIvarList(cls, &n);
    for (unsigned int i = 0; i < n; i++) {
        const char *nm = ivar_getName(ivars[i]);
        if (!nm) continue;
        id val = nil;
        @try { val = object_getIvar(obj, ivars[i]); } @catch (__unused NSException *e) {}
        if (!val) continue;
        NSString *name = [NSString stringWithUTF8String:nm];
        NSString *vcls = NSStringFromClass([val class]);
        BOOL interesting = [name.lowercaseString containsString:@"table"] ||
                           [name.lowercaseString containsString:@"list"] ||
                           [name.lowercaseString containsString:@"collection"] ||
                           [name.lowercaseString containsString:@"sidebar"] ||
                           [vcls containsString:@"TableView"] ||
                           [vcls containsString:@"CollectionView"];
        if (interesting) {
            [hits addObject:[NSString stringWithFormat:@"%@ = (%@)", name, vcls]];
        }
    }
    free(ivars);
    if (hits.count) DSALogAppend([NSString stringWithFormat:@"%@  %@\n    %@", label, NSStringFromClass(cls),
                                  [hits componentsJoinedByString:@"\n    "]]);
}

/// 视觉扫描：找出屏幕上「纵向列表类」视图的祖先链，打印其 superview 的类
static void DSAScanVisibleLists(void) {
    UIWindow *w = DSAKeyWindow();
    if (!w) return;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
    NSMutableSet *seen = [NSMutableSet set];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        for (UIView *s in v.subviews) [stack addObject:s];
        NSString *cls = NSStringFromClass([v class]);
        BOOL isList = [v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]];
        if (isList && v.window) {
            UIView *p = v.superview;
            NSString *chain = @"";
            for (int i = 0; i < 3 && p; i++, p = p.superview) {
                chain = [chain stringByAppendingFormat:@" <- %@%@", NSStringFromClass([p class]),
                         (NSStringFromClass([p class]) == nil ? @"" : @"")];
            }
            NSString *key = [NSString stringWithFormat:@"%@%.0f", cls, v.frame.size.height];
            if (![seen containsObject:key]) {
                [seen addObject:key];
                DSALogAppend([NSString stringWithFormat:@"[LIST] %@ h=%.0f%@", cls, v.frame.size.height, chain]);
            }
        }
    }
}

void DSAScanControls(id vc) {
    if (!vc) return;
    DSADumpObject(vc, @"[VC]");
    // 再挖一层：常见容器
    for (NSString *k in @[ @"view", @"sessionList", @"sessionListVM", @"viewModel", @"vm" ]) {
        @try {
            id child = [vc valueForKey:k];
            if (child && child != vc) DSADumpObject(child, [@"    [child " stringByAppendingFormat:@"%@]", k]);
        } @catch (__unused NSException *e) {}
    }
}

void DSAForceShowAgents(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
        if (!top) return;
        DSALogAppend(@"[FORCE] presenting agent home");
        [top presentViewController:[DSAAgentListController presentedRoot] animated:YES completion:nil];
    });
}

void DSAInstallSelfTest(void) {
    NSLog(@"[DSAgent] ===== dylib loaded, pid=%d =====", (int)getpid());
    [@"loaded\n" writeToFile:DSALogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *path = [dir stringByAppendingPathComponent:@"DSAgent_loaded.txt"];
        [[NSString stringWithFormat:@"loaded %@ pid=%d\n", [NSDate date], (int)getpid()]
            writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];

        UIWindow *w = DSAKeyWindow();
        if (!w) { NSLog(@"[DSAgent] no key window yet"); return; }
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
        NSLog(@"[DSAgent] badge shown");
    });

#ifdef DSA_UI_FORCE
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ DSAForceShowAgents(); });
#endif
}
