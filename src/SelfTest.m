//
//  SelfTest.m — 用于确认 dylib 是否真的被注入
//  DSA_SELFTEST 宏由 Makefile 控制（DEBUG 构建打开）
//
#import <UIKit/UIKit.h>
#import "DSAShared.h"

void DSAInstallSelfTest(void) {
    NSLog(@"[DSAgent] ===== dylib loaded, pid=%d =====", (int)getpid());
    // 写一个文件到沙盒，用来确认「代码确实运行过」（即使 UI 没反应）
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *path = [dir stringByAppendingPathComponent:@"DSAgent_loaded.txt"];
        NSString *info = [NSString stringWithFormat:@"loaded %@ pid=%d\n",
                          [NSDate date], (int)getpid()];
        [info writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[DSAgent] wrote %@", path);

        // 无条件浮层：不依赖任何 App 内部类，只要 dylib 在跑就一定看得到
        UIWindow *w = DSAKeyWindow();
        if (!w) { NSLog(@"[DSAgent] no key window yet, retry"); return; }
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
        badge.userInteractionEnabled = YES;
        [w addSubview:badge];
        NSLog(@"[DSAgent] badge shown");
    });
}
