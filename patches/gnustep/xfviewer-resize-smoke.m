/* Smoke test for XFormsViewer on GNUstep: open a sample the way the
 * viewer's Samples menu does, optionally sweep a real X pointer over the
 * window and type into its fields, grow the window to the screen (what a
 * maximize does), shrink it, quit. Exit status is the app's; "== survived"
 * on stderr means every step ran.
 *
 * It links the viewer's own document and window controller, so build it
 * after `make viewer`, from Apps/XFormsViewer:
 *
 *   V=obj/XFormsViewer.obj
 *   clang -c -g -fobjc-arc -fobjc-runtime=gnustep-2.2 `gnustep-config --objc-flags` \
 *       -I. -I../../Sources -I../../Sources/XFormsKit \
 *       -o /tmp/smoke.o ../../patches/gnustep/xfviewer-resize-smoke.m
 *   mkdir -p /tmp/Smoke.app/Resources
 *   clang -o /tmp/Smoke.app/Smoke /tmp/smoke.o $V/XFFormDocument.m.o \
 *       $V/XFDocumentWindowController.m.o -rdynamic -fobjc-arc \
 *       -L../../XFormsKit.framework/Versions/Current `gnustep-config --gui-libs` \
 *       -lXFormsKit -ldispatch -lX11
 *   printf '{ NSExecutable = "Smoke"; NSPrincipalClass = "NSApplication"; }\n' \
 *       > /tmp/Smoke.app/Resources/Info-gnustep.plist
 *
 * (an app wrapper, because gnustep-gui will not start a bare executable) and
 * run it under a real X server -- Xvfb is enough, the headless backend never
 * resizes anything:
 *
 *   LD_LIBRARY_PATH=$PWD/../../XFormsKit.framework/Versions/Current \
 *   XF_FILE=$PWD/../../Samples/validation.xhtml XF_DELAY=1 \
 *   XF_TYPE="ab@c 17" XF_TYPE_ALL=1 XF_HOVER=0.05 MALLOC_PERTURB_=165 \
 *   xvfb-run -a /tmp/Smoke.app/Smoke
 *
 * Environment (not argv: GNUstep's NSApplication hands every argument to
 * application:openFile:):
 *   XF_FILE      the sample to open
 *   XF_DELAY     seconds to wait after the window is up
 *   XF_TYPE      text to type (each character as a key event, then Return)
 *   XF_TYPE_ALL  type into every editable text field, not only the first
 *   XF_HOVER     sweep the pointer over the window before and after typing,
 *                lingering this many seconds per stop (0.7 shows tool tips)
 *   XF_NO_RETURN do not press Return after typing (incremental controls
 *                commit on every key; this shows what they did without a
 *                commit)
 *   XF_DUMP      after typing, print every NSTextField in the window with
 *                its address and value -- the same address after a commit
 *                means the widget was reused, not rebuilt
 *   XF_PAUSE     seconds to sit after typing (time for a screenshot)
 *   XF_HOVER_BADGES  park the pointer on every hint / alert badge first (its
 *                info box comes up) and leave it on the last one while typing
 *   XF_FILE2     a second sample to open after the first typing round, with
 *                the first window still up; the run then continues in it
 *   XF_CLOSE_FIRST  with XF_FILE2: close the first window once the second is up
 *
 * Run over Samples/*.xhtml with MALLOC_PERTURB_ set, it is the quickest way
 * to see whether a gnustep-gui build has the patches in README.md section 3.
 */
#import <AppKit/AppKit.h>
#import "XFFormDocument.h"
#import "XFDocumentWindowController.h"
#import <XFormsKit/XFormsKit.h>
#include <X11/Xlib.h>

/* Real pointer motion through the X server, so GNUstep's tracking rects and
 * tool tips see MotionNotify / Enter / Leave the way they do under a person's
 * mouse. Coordinates are screen pixels, origin top-left. */
static void warp(int x, int y)
{
    static Display *d = NULL;
    if (!d) d = XOpenDisplay(NULL);
    if (!d) return;
    XWarpPointer(d, None, DefaultRootWindow(d), 0, 0, 0, 0, x, y);
    XFlush(d);
}

@interface Driver : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) double delay;
@property (nonatomic, strong) XFFormDocument *doc;
@property (nonatomic, assign) BOOL secondOpened;
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
    [self performSelector:@selector(typeText) withObject:nil afterDelay:self.delay];
}
static void collectEditableFields(NSView *v, NSMutableArray *out)
{
    if ([v isKindOfClass:[NSTextField class]] && [(NSTextField *)v isEditable]) {
        [out addObject:v];
    }
    for (NSView *sub in [v subviews]) {
        collectEditableFields(sub, out);
    }
}
static void collectAllFields(NSView *v, NSMutableArray *out)
{
    if ([v isKindOfClass:[NSTextField class]]) [out addObject:v];
    for (NSView *sub in [v subviews]) collectAllFields(sub, out);
}
static NSTextField *firstEditableField(NSView *v)
{
    NSMutableArray *all = [NSMutableArray array];
    collectEditableFields(v, all);
    return [all firstObject];
}
- (void)keyDown:(NSString *)chars inWindow:(NSWindow *)w
{
    NSEvent *down = [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:0
        timestamp:[NSDate timeIntervalSinceReferenceDate] windowNumber:[w windowNumber]
        context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:0];
    NSEvent *up = [NSEvent keyEventWithType:NSKeyUp location:NSZeroPoint modifierFlags:0
        timestamp:[NSDate timeIntervalSinceReferenceDate] windowNumber:[w windowNumber]
        context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:0];
    [NSApp sendEvent:down];
    [NSApp sendEvent:up];
}
/* Sweep the pointer over the window in a grid, lingering long enough at
 * each stop for a tool tip to come up, then move on (which takes it down). */
- (void)hoverOver:(NSWindow *)w linger:(double)linger
{
    NSRect f = [w frame];
    CGFloat screenH = [[NSScreen mainScreen] frame].size.height;
    int x0 = (int)NSMinX(f), y0 = (int)(screenH - NSMaxY(f)), wd = (int)NSWidth(f), ht = (int)NSHeight(f);
    for (int gy = 1; gy < 12; gy++) {
        for (int gx = 1; gx < 16; gx++) {
            warp(x0 + wd * gx / 16, y0 + ht * gy / 12);
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:linger]];
        }
    }
}
- (void)typeText
{
    if (getenv("XF_HOVER")) {
        NSWindow *w = [[[self.doc windowControllers] firstObject] window];
        fprintf(stderr, "== hovering\n");
        [self hoverOver:w linger:atof(getenv("XF_HOVER"))];
    }
    const char *text = getenv("XF_TYPE");
    if (!text) { [self maximize]; return; }
    NSWindow *w = [[[self.doc windowControllers] firstObject] window];
    if (getenv("XF_HOVER_BADGES")) {
        // Park the pointer on each hint / alert badge (its info box comes
        // up), and leave it on the last one while typing: the refresh that
        // every keystroke runs then happens with the pointer inside a
        // tracking rect it re-registers.
        NSMutableArray *badges = [NSMutableArray array];
        NSMutableArray *stack = [NSMutableArray arrayWithObject:[w contentView]];
        while (stack.count) {
            NSView *v = stack.lastObject; [stack removeLastObject];
            if ([NSStringFromClass([v class]) isEqualToString:@"XFBadgeView"]) [badges addObject:v];
            [stack addObjectsFromArray:[v subviews]];
        }
        fprintf(stderr, "== hovering %lu badges\n", (unsigned long)badges.count);
        CGFloat screenH = [[NSScreen mainScreen] frame].size.height;
        for (NSView *b in badges) {
            NSRect r = [b convertRect:[b bounds] toView:nil];
            NSPoint p = [w convertBaseToScreen:NSMakePoint(NSMidX(r), NSMidY(r))];
            warp((int)p.x, (int)(screenH - p.y));
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.6]];
            warp((int)p.x + 1, (int)(screenH - p.y));
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        }
    }
    NSMutableArray *fields = [NSMutableArray array];
    collectEditableFields([w contentView], fields);
    NSUInteger count = getenv("XF_TYPE_ALL") ? [fields count] : MIN(1u, [fields count]);
    for (NSUInteger idx = 0; idx < count; idx++) {
    // Re-collect every time: a commit rebuilds the form's widgets, and a
    // field kept from before the rebuild is no longer in the window.
    [fields removeAllObjects];
    collectEditableFields([w contentView], fields);
    if (idx >= [fields count]) break;
    NSTextField *f = fields[idx];
    [fields removeAllObjects];
    fprintf(stderr, "== typing '%s' into %s\n", text, f ? [[f description] UTF8String] : "(no field)");
    if (f) {
        if (getenv("XF_HOVER") && !getenv("XF_HOVER_BADGES")) {
            NSRect r = [f convertRect:[f bounds] toView:nil];
            NSPoint p = [w convertBaseToScreen:NSMakePoint(NSMidX(r), NSMidY(r))];
            CGFloat screenH = [[NSScreen mainScreen] frame].size.height;
            warp((int)p.x, (int)(screenH - p.y));
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.2]];
        }
        [w makeFirstResponder:f];
        NSString *str = [NSString stringWithUTF8String:text];
        for (NSUInteger i = 0; i < [str length]; i++) {
            NSString *ch = [str substringWithRange:NSMakeRange(i, 1)];
            if ([ch isEqualToString:@"\t"]) { ch = @"\t"; }
            [self keyDown:ch inWindow:w];
            // let the run loop breathe between keys, as a person would
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        // Return commits the value. Drop our own reference first: in the
        // real viewer nothing but the form view retains the field, and the
        // commit rebuilds the form.
        f = nil;
        if (getenv("XF_DUMP")) {
            NSMutableArray *all = [NSMutableArray array];
            collectAllFields([w contentView], all);
            for (NSTextField *t in all) fprintf(stderr, "   field %p %s editable=%d '%s'\n", t, [[t className] UTF8String], [t isEditable], [[t stringValue] UTF8String]);
        }
        if (getenv("XF_PAUSE")) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:atof(getenv("XF_PAUSE"))]];
        }
        if (!getenv("XF_NO_RETURN")) {
        [self keyDown:@"\r" inWindow:w];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        }
        fprintf(stderr, "== typed\n");
    }
    }
    if (getenv("XF_HOVER")) {
        fprintf(stderr, "== hovering again\n");
        [self hoverOver:w linger:atof(getenv("XF_HOVER"))];
    }
    // A second form, opened while the first one is still up (its field
    // possibly mid-edit): what a person does from File > Open Sample.
    const char *second = getenv("XF_FILE2");
    if (second && !self.secondOpened) {
        self.secondOpened = YES;
        NSError *error = nil;
        NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:second]];
        XFFormDocument *doc = [[XFFormDocument alloc] init];
        fprintf(stderr, "== opening second %s\n", second);
        if (![doc readFromURL:url ofType:@"xhtml" error:&error]) {
            fprintf(stderr, "read failed: %s\n", [[error description] UTF8String]);
            exit(2);
        }
        [doc setFileURL:url];
        [doc setFileType:@"xhtml"];
        [[NSDocumentController sharedDocumentController] addDocument:doc];
        [doc makeWindowControllers];
        [doc showWindows];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        if (getenv("XF_CLOSE_FIRST")) {
            fprintf(stderr, "== closing first\n");
            [[[[self.doc windowControllers] firstObject] window] performClose:nil];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        }
        self.doc = doc;   // the rest of the run works the second window
        fprintf(stderr, "== second shown; typing into it\n");
        [self typeText];
        return;
    }
    [self maximize];
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
