//
//  Entry.m — 侧栏顶部「智能体」入口
//
#import <UIKit/UIKit.h>
#import "DSAShared.h"
#import <objc/runtime.h>
#import "AgentListController.h"


static char kDSAEntryTag;

@interface DSAEntryProxy : NSObject
+ (void)tapped;
@end

@implementation DSAEntryProxy
+ (void)tapped {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = DSATopMost(DSAKeyWindow().rootViewController);
        if (!top || [top isKindOfClass:[UIAlertController class]] ||
            [top isKindOfClass:[DSAAgentListController class]] ||
            ([top isKindOfClass:[UINavigationController class]] &&
             [[(UINavigationController *)top topViewController] isKindOfClass:[DSAAgentListController class]]))
            return;
        [top presentViewController:[DSAAgentListController presentedRoot] animated:YES completion:nil];
    });
}
@end

/// 在列表视图上方插入 44pt 入口条（同一视图只插一次）
void DSAEnsureEntry(UIView *view) {
    if (!view || objc_getAssociatedObject(view, &kDSAEntryTag)) return;
    UIView *host = view.superview;
    if (!host) return;
    if (![view isKindOfClass:[UIScrollView class]]) return;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    btn.contentEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 16);
    btn.backgroundColor = UIColor.clearColor;
    btn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [btn setTitle:@"🤖  智能体" forState:UIControlStateNormal];
    [btn sizeToFit];
    [btn addTarget:[DSAEntryProxy class] action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];

    UIView *line = [UIView new];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = [UIColor separatorColor];

    [host addSubview:btn];
    [host addSubview:line];
    [NSLayoutConstraint activateConstraints:@[
        [btn.topAnchor constraintEqualToAnchor:host.topAnchor],
        [btn.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [btn.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [btn.heightAnchor constraintEqualToConstant:44],
        [line.topAnchor constraintEqualToAnchor:btn.bottomAnchor],
        [line.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:16],
        [line.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-16],
        [line.heightAnchor constraintEqualToConstant:0.5],
        [view.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:2],
    ]];
    objc_setAssociatedObject(view, &kDSAEntryTag, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
