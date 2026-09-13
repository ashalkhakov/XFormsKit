/* Resize smoke test for XFormsViewer on GNUstep: open a sample the way the
 * viewer's Samples menu does, grow the window to the screen (what a maximize
 * does), shrink it, quit. Exit status is the app's; "== survived" on stderr
 * means all three steps ran.
 *
 * It links the viewer's own document and window controller, so build it
 * after `make viewer`, from Apps/XFormsViewer:
 *
 *   V=obj/XFormsViewer.obj
 *   clang -c -g -fobjc-arc -fobjc-runtime=gnustep-2.2 `gnustep-config --objc-flags` \
 *       -I. -I../../Sources -I../../Sources/XFormsKit \
 *       -o /tmp/smoke.o ../../patches/gnustep/xfviewer-resize-smoke.m
 *   clang -o /tmp/Smoke.app/Smoke /tmp/smoke.o $V/XFFormDocument.m.o \
 *       $V/XFDocumentWindowController.m.o -rdynamic -fobjc-arc \
 *       -L../../XFormsKit.framework/Versions/Current `gnustep-config --gui-libs` \
 *       -lXFormsKit -ldispatch
 *   printf '{ NSExecutable = "Smoke"; NSPrincipalClass = "NSApplication"; }\n' \
 *       > /tmp/Smoke.app/Resources/Info-gnustep.plist
 *
 * (an app wrapper, because gnustep-gui will not start a bare executable) and
 * run it under a real X server -- Xvfb is enough, the headless backend never
 * resizes anything:
 *
 *   LD_LIBRARY_PATH=$PWD/../../XFormsKit.framework/Versions/Current \
 *   XF_FILE=$PWD/../../Samples/input.xhtml XF_DELAY=2 xvfb-run -a /tmp/Smoke.app/Smoke
 *
 * The file and delay come from the environment rather than argv because
 * GNUstep's NSApplication hands every argument to application:openFile:.
 * Running it over Samples/*.xhtml with MALLOC_PERTURB_ set is the quickest
 * way to see whether a gnustep-gui build has the GSCSTableau fix; see
 * README.md section 3.
 */
#import <AppKit/AppKit.h>
#import "XFFormDocument.h"
#import "XFDocumentWindowController.h"
#import <XFormsKit/XFormsKit.h>

@interface Driver : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) double delay;
@property (nonatomic, strong) XFFormDocument *doc;
@end

@implementation Driver
- (void)applicationWillFinishLaunching:(NSNotification *)n
{
    (void)[XFFormDocument class];
    (void)[XFDocumentWindowController class];
    (void)[NSDocumentController sharedDocumentController];
}
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)s { return NO; }
- (void)applicationDidFinishLaunching:(NSNotification *)n
{
    NSError *error = nil;
    NSURL *url = [NSURL fileURLWithPath:self.path];
    XFFormDocument *doc = [[XFFormDocument alloc] init];
    fprintf(stderr, "== reading %s\n", [self.path UTF8String]);
    if (![doc readFromURL:url ofType:@"xhtml" error:&error]) {
        fprintf(stderr, "read failed: %s\n", [[error description] UTF8String]);
        exit(2);
    }
    [doc setFileURL:url];
    [doc setFileType:@"xhtml"];
    [[NSDocumentController sharedDocumentController] addDocument:doc];
    fprintf(stderr, "== makeWindowControllers\n");
    [doc makeWindowControllers];
    fprintf(stderr, "== showWindows\n");
    [doc showWindows];
    self.doc = doc;
    fprintf(stderr, "== shown; frame %s\n",
        [NSStringFromRect([[[[doc windowControllers] firstObject] window] frame]) UTF8String]);
    [self performSelector:@selector(maximize) withObject:nil afterDelay:self.delay];
}
- (void)maximize
{
    NSWindow *w = [[[self.doc windowControllers] firstObject] window];
    NSRect screen = [[NSScreen mainScreen] visibleFrame];
    fprintf(stderr, "== maximizing to %s\n", [NSStringFromRect(screen) UTF8String]);
    [w setFrame:screen display:YES];
    fprintf(stderr, "== after setFrame; frame %s\n", [NSStringFromRect([w frame]) UTF8String]);
    [self performSelector:@selector(shrink) withObject:nil afterDelay:1.0];
}
- (void)shrink
{
    NSWindow *w = [[[self.doc windowControllers] firstObject] window];
    NSRect f = [w frame];
    f.size.width -= 200; f.size.height -= 150;
    fprintf(stderr, "== shrinking to %s\n", [NSStringFromRect(f) UTF8String]);
    [w setFrame:f display:YES];
    [self performSelector:@selector(done) withObject:nil afterDelay:1.0];
}
- (void)done
{
    fprintf(stderr, "== survived\n");
    [NSApp terminate:nil];
}
@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        Driver *d = [[Driver alloc] init];
        // Not argv: GNUstep hands every argument to application:openFile:.
        const char *file = getenv("XF_FILE");
        const char *delay = getenv("XF_DELAY");
        d.path = file ? [NSString stringWithUTF8String:file] : @"Samples/input.xhtml";
        d.delay = delay ? atof(delay) : 2.0;
        [NSApp setDelegate:(id)d];
        return NSApplicationMain(argc, argv);
    }
}
