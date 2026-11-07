//
//  Probe.m — 诊断：红色角标能显示，但按钮不行，所以先确认窗口结构
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "DSAShared.h"

/// 把场景里所有 window 的层级/尺寸/keyWindow/rootVC 写进文件
void DSAProbeWindows(void) {
    @try {
        NSMutableString *out = [NSMutableString string];
        [out appendFormat:@"%@\n", [NSDate date]];
        NSMutableArray *windows = [NSMutableArray array];
        if (@available(iOS 13.0, *)) {
            for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
                if (![s isKindOfClass:[UIWindowScene class]]) continue;
                [out appendFormat:@"scene %@ state=%ld\n", NSStringFromClass([s class]), (long)s.activationState];
                for (UIWindow *w in ((UIWindowScene *)s).windows) {
                    [windows addObject:w];
                    [out appendFormat:@"  window %@ level=%.1f hidden=%d alpha=%.2f key=%d frame=%@\n",
                     NSStringFromClass([w class]), w.windowLevel, w.hidden, w.alpha, w.isKeyWindow,
                     NSStringFromCGRect(w.frame)];
                    UIView *root = w.rootViewController.view;
                    [out appendFormat:@"    rootVC=%@ rootView.frame=%@ subviews=%lu\n",
                     NSStringFromClass([w.rootViewController class]),
                     NSStringFromCGRect(root.frame), (unsigned long)root.subviews.count];
                    // 顶层子视图
                    for (UIView *sv in root.subviews) {
                        [out appendFormat:@"      - %@ frame=%@ hidden=%d alpha=%.2f\n",
                         NSStringFromClass([sv class]), NSStringFromCGRect(sv.frame), sv.hidden, sv.alpha];
                    }
                }
            }
        }
        UIWindow *kw = UIApplication.sharedApplication.keyWindow;
        [out appendFormat:@"app.keyWindow=%@\n", kw ? NSStringFromClass([kw class]) : @"nil"];
        [out appendFormat:@"delegate.window=%@\n",
         UIApplication.sharedApplication.delegate.window ? NSStringFromClass([UIApplication.sharedApplication.delegate.window class]) : @"nil"];
        NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [out writeToFile:[dir stringByAppendingPathComponent:@"DSAgent_windows.txt"]
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[DSAgent] probe written");
    } @catch (__unused NSException *e) {
        NSLog(@"[DSAgent] probe failed %@", e.reason);
    }
}

/// 对照探针：同一位置三种画法，判断到底哪一步让视图消失
///   A 纯 UIView + 背景（已知可见）
///   B UIView + 背景 + label 子视图
///   C UIControl + 背景 + 圆角（已知不显示）
///   D UIView + 背景 + 圆角（判断是不是圆角/裁剪的锅）
void DSAProbeVariants(void) {
    @try {
        UIWindow *w = DSAKeyWindow();
        if (!w) return;
        CGFloat baseY = 200;
        NSArray *colors = @[ [UIColor greenColor],
                             [UIColor orangeColor],
                             [UIColor purpleColor],
                             [UIColor blueColor] ];
        for (int i = 0; i < 4; i++) {
            CGRect f = CGRectMake(8 + i * 84, baseY, 76, 34);
            UIView *v;
            if (i == 2) v = [[UIControl alloc] initWithFrame:f];
            else v = [[UIView alloc] initWithFrame:f];
            v.backgroundColor = colors[i];
            if (i == 3) { v.layer.cornerRadius = 17; v.clipsToBounds = YES; }
            if (i == 1) {
                UILabel *l = [[UILabel alloc] initWithFrame:v.bounds];
                l.text = @"字";
                l.textColor = UIColor.whiteColor;
                l.textAlignment = NSTextAlignmentCenter;
                l.font = [UIFont boldSystemFontOfSize:13];
                [v addSubview:l];
            }
            [w addSubview:v];
        }

        // ★ 第 5 个：真正的「智能体」胶囊，和上面完全同一段代码、同一时机
        if (!objc_getAssociatedObject(w, @"DSAProbePill")) {
            CGRect f = CGRectMake(8 + 4 * 84, baseY, 76, 34);
            UIControl *pill = [[UIControl alloc] initWithFrame:f];
            pill.backgroundColor = [UIColor colorWithRed:0.29 green:0.48 blue:1.0 alpha:1.0];
            pill.layer.cornerRadius = 17;
            pill.clipsToBounds = YES;
            UILabel *l = [[UILabel alloc] initWithFrame:pill.bounds];
            l.text = @"智能体";
            l.textColor = UIColor.whiteColor;
            l.textAlignment = NSTextAlignmentCenter;
            l.font = [UIFont boldSystemFontOfSize:13];
            [pill addSubview:l];
            [w addSubview:pill];
            objc_setAssociatedObject(w, @"DSAProbePill", pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSLog(@"[DSAgent] probe pill at %@ / window %@ bounds %@",
                  NSStringFromCGRect(pill.frame), NSStringFromClass([w class]), NSStringFromCGRect(w.bounds));
        }
    } @catch (__unused NSException *e) {
        NSLog(@"[DSAgent] variants failed %@", e.reason);
    }
}

/// 最原始的探针：不依赖约束/阴影/圆角，只在窗口原点画一个绿方块
void DSAProbeSquare(void) {
    @try {
        UIWindow *w = DSAKeyWindow();
        if (!w) return;
        UIView *sq = [[UIView alloc] initWithFrame:CGRectMake(8, 120, 60, 60)];
        sq.backgroundColor = [UIColor greenColor];
        sq.userInteractionEnabled = NO;
        [w addSubview:sq];
        NSLog(@"[DSAgent] square added to %@ at %@", NSStringFromClass([w class]),
              NSStringFromCGRect(sq.frame));
    } @catch (__unused NSException *e) {
        NSLog(@"[DSAgent] square failed %@", e.reason);
    }
}
