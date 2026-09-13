/* GNUstep: -[NSWindow _checkTrackingRectangles:forEvent:] walks a snapshot
 * of each view's subviews that holds no references, so a mouseEntered: /
 * mouseExited: handler that removes a sibling view -- and thereby frees
 * it -- leaves the walk holding a dangling pointer it then messages.
 *
 * AppKit only -- no XFormsKit. Two views with tracking rects, side by
 * side, and a third view after them in the subview list. Entering the
 * first rect removes that third view: the pattern of a hover box (a hint,
 * a tool tip drawn by the app) that a badge shows on mouseEntered: and
 * takes down on mouseExited:, or replaces when the pointer moves from
 * one badge straight to another -- XFormsKit's XFFormView does exactly
 * this, and input.xhtml died the moment the pointer went from the second
 * hint's badge to the first's.
 *
 *   clang -o nswindow-tracking-walk-freed-subview nswindow-tracking-walk-freed-subview.m \
 *       `gnustep-config --objc-flags` `gnustep-config --gui-libs`
 *   mkdir -p Repro.app/Resources && cp nswindow-tracking-walk-freed-subview Repro.app/Repro
 *   printf '{ NSExecutable = "Repro"; NSPrincipalClass = "NSApplication"; }\n' \
 *       > Repro.app/Resources/Info-gnustep.plist
 *   xvfb-run -a env MALLOC_PERTURB_=165 ./Repro.app/Repro     # segfault
 *   xvfb-run -a valgrind -q ./Repro.app/Repro                  # Invalid read in
 *       # -[NSWindow _checkTrackingRectangles:forEvent:] ... free'd by
 *       # -[NSView removeFromSuperview]
 *
 * What happens. For each view the walk copies the subview array into a C
 * array with -getObjects: (no retain), sends the enter / exit events the
 * view's own tracking rects call for, then recurses into subs[i] --
 * `[subs[i] isHidden]` first. If an enter / exit handler earlier in the
 * same walk removed one of those subviews from the view, and the view was
 * its only owner, subs[i] is freed memory by the time it is reached. The
 * same shape is in -_checkCursorRectangles:forEvent:. Whether it dies
 * depends on what the allocator has done with the chunk since, which is
 * why one machine sees it every time and another never.
 *
 * The accompanying patch, gnustep-gui-tracking-walk-retains-subviews.patch,
 * takes an autoreleased copy of the subview array instead, which keeps
 * every entry alive for the walk. With it this program prints "survived".
 */
#import <AppKit/AppKit.h>

@interface Repro : NSObject
@property (nonatomic, strong) NSWindow *window;
/* The hover box currently up. Unretained: its superview is its only owner, the
 * way a view a form puts up and takes down again is. */
@property (nonatomic, assign) NSView *box;
@end

@interface Badge : NSView
@property (nonatomic, assign) Repro *host;
@end

@implementation Badge
- (void)viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  [self addTrackingRect: [self bounds] owner: self userData: NULL assumeInside: NO];
}
- (void)mouseEntered: (NSEvent *)e
{
  (void)e;
  fprintf(stderr, "entered %s\n", [[self description] UTF8String]);
  /* Take the current hover box down and put up a new one: the superview
   * was the box's only owner, so this frees it while the walk still has
   * it in its list. */
  [self.host.box removeFromSuperview];
  NSView *box = [[[NSView alloc] initWithFrame: NSMakeRect(20, 100, 200, 40)] autorelease];
  [[self superview] addSubview: box];   /* the superview: its only owner */
  self.host.box = box;
}
@end

@implementation Repro
- (void)applicationDidFinishLaunching: (NSNotification *)n
{
  NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(40, 40, 400, 200)
    styleMask: NSTitledWindowMask | NSResizableWindowMask | NSClosableWindowMask
    backing: NSBackingStoreBuffered defer: NO];
  NSView *cv = [w contentView];
  Badge *first = [[Badge alloc] initWithFrame: NSMakeRect(20, 20, 40, 40)];
  Badge *second = [[Badge alloc] initWithFrame: NSMakeRect(200, 20, 40, 40)];
  [cv addSubview: first];
  [cv addSubview: second];
  NSView *box = [[[NSView alloc] initWithFrame: NSMakeRect(20, 100, 200, 40)] autorelease];
  [cv addSubview: box];          /* after the badges in the subview list */
  self.box = box;
  first.host = self;
  second.host = self;
  [w makeKeyAndOrderFront: nil];
  self.window = w;
  [self performSelector: @selector(move) withObject: nil afterDelay: 0.5];
}
- (void)mouseTo: (NSPoint)p
{
  NSEvent *e = [NSEvent mouseEventWithType: NSMouseMoved location: p modifierFlags: 0
    timestamp: 0 windowNumber: [self.window windowNumber] context: nil
    eventNumber: 0 clickCount: 0 pressure: 0];
  [NSApp sendEvent: e];
  [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
}
- (void)move
{
  /* Outside, into the second badge (its handler swaps the box), then
   * straight into the first: the walk that delivers this last move frees
   * the box through the first badge's handler and then recurses into it. */
  [self mouseTo: NSMakePoint(300, 150)];
  [self mouseTo: NSMakePoint(220, 40)];
  [self mouseTo: NSMakePoint(40, 40)];
  fprintf(stderr, "survived\n");
  [NSApp terminate: nil];
}
@end

int main(int argc, const char **argv)
{
  @autoreleasepool
    {
      [NSApplication sharedApplication];
      Repro *r = [[Repro alloc] init];
      [NSApp setDelegate: (id)r];
      return NSApplicationMain(argc, argv);
    }
}
