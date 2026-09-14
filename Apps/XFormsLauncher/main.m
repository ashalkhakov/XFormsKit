//
// XFormsLauncher — the chooser the AppImage opens. See
// XFLauncherAppDelegate.h.
//

#import <AppKit/AppKit.h>
#import "XFLauncherAppDelegate.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        XFLauncherAppDelegate *delegate = [[XFLauncherAppDelegate alloc] init];
        [app setDelegate:(id)delegate];
        [app run];
    }
    (void)argc; (void)argv;
    return 0;
}
