//
// XFUpdater — the viewer's and the designer's updates.
//
// On macOS, Sparkle: the newest release's appcast for this app
// (SUFeedURL in <App>-Info.plist, appcast-<App>.xml, signed with the key
// SUPublicEDKey names) is checked once a day if the user allows it, and
// Check for Updates… checks now. On GNUstep, nothing: the AppImage carries
// its update information, for AppImageUpdate, Gear Lever and the like
// (docs/packaging.md).
//
// XFUpdater-Apple.m is the Xcode targets', XFUpdater.m the GNUmakefiles'.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// The tag of the Check for Updates… menu item, which goes where there is
// no updater.
enum { XFCheckForUpdatesMenuItemTag = 7100 };

@interface XFUpdater : NSObject
// Started at once unless told not to (a self-test reaches no network).
- (instancetype)initStarting:(BOOL)start;
// Whether this system has an updater at all (Check for Updates… shown).
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly) BOOL canCheckForUpdates;
- (IBAction)checkForUpdates:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
