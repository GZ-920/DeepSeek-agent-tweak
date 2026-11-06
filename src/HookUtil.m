//
//  HookUtil.m
//  三个 .m 之间共用的小工具（放独立翻译单元，避免重复定义）
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

UIWindow *DSAKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows)
                if (w.isKeyWindow) return w;
        }
    }
    return UIApplication.sharedApplication.keyWindow ?: UIApplication.sharedApplication.delegate.window;
}

UIViewController *DSATopMost(UIViewController *base) {
    if (!base) return nil;
    while (base.presentedViewController) base = base.presentedViewController;
    if ([base isKindOfClass:[UINavigationController class]])
        return DSATopMost([(UINavigationController *)base visibleViewController]);
    if ([base isKindOfClass:[UITabBarController class]])
        return DSATopMost([(UITabBarController *)base selectedViewController]);
    return base;
}

void DSAToast(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = DSAKeyWindow();
        if (!w || !text.length) return;
        UILabel *l = [UILabel new];
        l.text = text;
        l.numberOfLines = 0;
        l.textAlignment = NSTextAlignmentCenter;
        l.font = [UIFont systemFontOfSize:14];
        l.textColor = UIColor.whiteColor;
        l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.82];
        l.layer.cornerRadius = 10;
        l.clipsToBounds = YES;
        CGSize size = [l sizeThatFits:CGSizeMake(w.bounds.size.width - 96, CGFLOAT_MAX)];
        l.frame = CGRectMake(48, 0, w.bounds.size.width - 96, size.height + 20);
        l.center = CGPointMake(w.bounds.size.width / 2, w.bounds.size.height * 0.72);
        [w addSubview:l];
        [UIView animateWithDuration:0.35 delay:2.0 options:0 animations:^{ l.alpha = 0; }
                         completion:^(BOOL finished) { [l removeFromSuperview]; }];
    });
}

/// 找 Swift / ObjC 类：先精确名，再按模块前缀后缀匹配
Class DSAClassNamed(NSString *name) {
    if (!name.length) return Nil;
    Class c = NSClassFromString(name);
    if (c) return c;
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return Nil;
    Class *classes = (Class *)malloc(sizeof(Class) * (size_t)count);
    if (!classes) return Nil;
    count = objc_getClassList(classes, count);
    Class found = Nil;
    NSString *suffix = [@"." stringByAppendingString:name];
    for (int i = 0; i < count; i++) {
        if ([NSStringFromClass(classes[i]) hasSuffix:suffix]) { found = classes[i]; break; }
    }
    free(classes);
    return found;
}
