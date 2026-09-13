/* main.m — XForms Mobile, the iOS host for XFormsKit.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#import <UIKit/UIKit.h>
#import "XFMobileAppDelegate.h"

int main(int argc, char *argv[])
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
                                 NSStringFromClass([XFMobileAppDelegate class]));
    }
}
