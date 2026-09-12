/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#import "XFMobileAppDelegate.h"
#import "XFFormBrowserViewController.h"

@implementation XFMobileAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)options
{
    (void)application; (void)options;
    XFFormBrowserViewController *browser = [[XFFormBrowserViewController alloc] init];
    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:browser];
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

/// A form handed over by another app (Files' "Open in", AirDrop, a
/// download). The browser opens it as if it had been picked.
- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
{
    (void)application; (void)options;
    UINavigationController *nav = (UINavigationController *)self.window.rootViewController;
    XFFormBrowserViewController *browser = nav.viewControllers.firstObject;
    if (![browser isKindOfClass:[XFFormBrowserViewController class]]) {
        return NO;
    }
    [nav popToRootViewControllerAnimated:NO];
    return [browser openFormAtURL:url];
}

@end
