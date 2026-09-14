//
// XFLauncherAppDelegate — the chooser the AppImage opens.
//
// An AppImage has one entry point and this image carries two applications, so
// launching it opens this: a window with a button per app. Ported from
// UDQuakeTools' UDLauncher (Sources/UDLauncher), which solves the same problem
// for three apps in one image; the menu here is built in code rather than
// loaded from a xib, the way the viewer and the designer build theirs.
//
// Only GNUstep builds it. On a Mac each app is its own bundle in
// /Applications and there is nothing to choose between.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface XFLauncherAppDelegate : NSObject
@end

NS_ASSUME_NONNULL_END
