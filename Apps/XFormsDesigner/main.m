/* XFormsDesigner — document-based XHTML+XForms form designer.
   The runner is XFormsViewer; this app edits the host XML through
   XFormsKit's XFHostEdit command layer, with the processor kept alive as
   a rebuildable projection for the live preview.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFSubmission.h>
#import <XFormsKit/XFSubmissionTransport.h>
#import <XFormsKit/XFXML.h>
#if defined(GNUSTEP)
#import <XFormsKit/XFCrashReporter.h>   // not in the Xcode project: GNUstep-only
#endif
#import "XFormsDesignKit.h"
#import "XFUpdater.h"
#import "XFMenuStyle.h"

/* The application's delegate, from MainMenu.xib: it holds the updater.
   Set up as the menu is loaded, before the app finishes launching (as
   Sparkle asks); not started in a self-test. Where there is no updater,
   no Check for Updates… item. */
@interface XFDesignerAppDelegate : NSObject
@property (nonatomic, weak) IBOutlet NSMenuItem *checkForUpdatesItem;
- (IBAction)checkForUpdates:(id)sender;
@end

@implementation XFDesignerAppDelegate {
    XFUpdater *_updater;
}

- (void)awakeFromNib
{
    _updater = [[XFUpdater alloc] initStarting:getenv("XFD_SELFTEST") == NULL];
    if (![_updater available] && self.checkForUpdatesItem != nil) {
        [[self.checkForUpdatesItem menu] removeItem:self.checkForUpdatesItem];
    }
}

- (IBAction)checkForUpdates:(id)sender
{
    [_updater checkForUpdates:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(checkForUpdates:)) {
        return [_updater canCheckForUpdates];
    }
    return YES;
}

// Where the menus are in the windows (XFMenuStyle.h), a designer with no
// window left shows nothing of itself: it quits with its last one.
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return XFMenusInWindows();
}

@end

static BOOL XFDLoadNib(NSString *name, id owner)
{
#if defined(__APPLE__)
    // Kept: the app delegate is one of them, and NSApp does not retain
    // its delegate.
    static NSMutableArray *kept;
    NSArray *top = nil;
    if (![[NSBundle mainBundle] loadNibNamed:name owner:owner topLevelObjects:&top]) {
        return NO;
    }
    if (kept == nil) {
        kept = [NSMutableArray array];
    }
    [kept addObjectsFromArray:top];
    return YES;
#else
    return [NSBundle loadNibNamed:name owner:owner];
#endif
}

/* XFD_SELFTEST=<form path>: the app's own smoke test, both platforms
   (`XFD_SELFTEST=... ./XFormsDesigner`): the form opens in the designer's
   window, and Check for Updates… is where the app has an updater. What
   the designer does is XFormsDesignKitTests'. */
static int XFDRunSelfTest(NSString *path)
{
    NSError *error = nil;
    XFDDocument *doc = [[XFDDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]
                                                           ofType:@"XHTML+XForms"
                                                            error:&error];
    if (doc == nil) {
        NSLog(@"SELFTEST open failed: %@", error);
        return 1;
    }
    [doc makeWindowControllers];
    XFDWindowController *wc = [[doc windowControllers] firstObject];
    if ([wc window] == nil || [wc.outlineViewController.outline numberOfRows] < 4) {
        NSLog(@"SELFTEST the window did not show the form");
        return 1;
    }
    // Check for Updates…: in the app menu where there is an updater
    // (Sparkle, on macOS), not where the image is updated from outside
    // (GNUstep's AppImage).
    BOOL hasUpdater = [[XFUpdater alloc] initStarting:NO].available;
    NSMenuItem *checkForUpdates = [[[[NSApp mainMenu] itemAtIndex:0] submenu]
                                   itemWithTag:XFCheckForUpdatesMenuItemTag];
    if ((checkForUpdates != nil) != hasUpdater
        || (checkForUpdates != nil && [checkForUpdates action] != @selector(checkForUpdates:))) {
        NSLog(@"SELFTEST Check for Updates… %@", hasUpdater ? @"missing from the app menu" : @"offered");
        return 1;
    }
    NSLog(@"SELFTEST OK (%lu controls)", (unsigned long)doc.processor.controls.count);
    return 0;
}

/// Host-registered XPath extension functions (XFXPath
/// registerHostFunctionNamed:) — the native stand-ins for the page
/// JavaScript XSLTForms lets samples define. gantt.xhtml's lastday(): the
/// latest of days-from-date(start[i]) + duration[i] over two comma-joined
/// lists.
static NSInteger XFDaysFromCivil(NSInteger y, NSInteger m, NSInteger d)
{
    // Howard Hinnant's days_from_civil — days since 1970-01-01
    y -= m <= 2;
    NSInteger era = (y >= 0 ? y : y - 399) / 400;
    NSInteger yoe = y - era * 400;
    NSInteger doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    NSInteger doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}

static void XFRegisterSampleFunctions(void)
{
    [XFXPath registerHostFunctionNamed:@"lastday"
                             evaluator:^XFXPathValue *(XFExprContext *ctx,
                                                       NSArray *args,
                                                       NSError **err) {
        (void)ctx;
        (void)err;
        NSArray *starts = [[args.firstObject stringValue] componentsSeparatedByString:@","];
        NSArray *durations = args.count > 1
            ? [[args[1] stringValue] componentsSeparatedByString:@","] : @[];
        double last = 0;
        for (NSUInteger i = 0; i < starts.count && i < durations.count; i++) {
            int y = 0, m = 0, d = 0;
            if (sscanf([starts[i] UTF8String], "%d%*[./-]%d%*[./-]%d", &y, &m, &d) != 3) {
                continue;
            }
            double t = (double)XFDaysFromCivil(y, m, d)
                + [durations[i] doubleValue];
            last = MAX(last, t);
        }
        return [XFXPathValue number:last];
    }];
}

int main(int argc, const char *argv[])
{
#if defined(GNUSTEP)
    // A crash in the AppImage reports its own backtrace on stderr: gdb
    // cannot be started against the image's libraries.
    XFInstallCrashReporter();
#endif
    XFRegisterSampleFunctions();
    (void)argc;
    (void)argv;
    @autoreleasepool {
        [NSApplication sharedApplication];
#ifdef __APPLE__
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
#endif
        (void)[NSDocumentController sharedDocumentController];
        if (!XFDLoadNib(@"MainMenu", NSApp)) {
            NSLog(@"XFormsDesigner: failed to load MainMenu.xib");
        }
        const char *selfTest = getenv("XFD_SELFTEST");
        if (selfTest != NULL) {
            return XFDRunSelfTest(@(selfTest));
        }
        [NSApp run];
    }
    return 0;
}
