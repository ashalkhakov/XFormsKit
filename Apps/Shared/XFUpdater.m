#import "XFUpdater.h"

/* GNUstep: the AppImage is updated from outside it (XFUpdater.h). */
@implementation XFUpdater

- (instancetype)initStarting:(BOOL)start
{
    (void)start;
    return [super init];
}

- (BOOL)available
{
    return NO;
}

- (BOOL)canCheckForUpdates
{
    return NO;
}

- (IBAction)checkForUpdates:(id)sender
{
    (void)sender;
}

@end
