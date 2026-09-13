/* GNUstep: -[NSMenu performActionForItemAtIndex:] keeps using the menu after
 * the action it just sent has released it.
 *
 * AppKit only -- no XFormsKit. A popup button whose action rebuilds the
 * view that holds it (the pattern of every form that regenerates its
 * widgets when a value changes: XFormsKit's XFFormView does exactly this),
 * then two key presses on the popup -- Space opens it, Return chooses --
 * which go through -[NSPopUpButton keyDown:] -> -[NSMenu
 * performActionForItemAtIndex:]. (A mouse choice ends in the same method.)
 *
 *   clang -o nsmenu-action-releases-sender nsmenu-action-releases-sender.m \
 *       `gnustep-config --objc-flags` `gnustep-config --gui-libs`
 *   mkdir -p Repro.app/Resources && cp nsmenu-action-releases-sender Repro.app/Repro
 *   printf '{ NSExecutable = "Repro"; NSPrincipalClass = "NSApplication"; }\n' \
 *       > Repro.app/Resources/Info-gnustep.plist
 *   xvfb-run -a env MALLOC_PERTURB_=165 ./Repro.app/Repro     # segfault
 *   xvfb-run -a valgrind -q ./Repro.app/Repro                  # Invalid read in
 *       # postNotificationName:object:userInfo: <- performActionForItemAtIndex:
 *
 * What happens. performActionForItemAtIndex: sends the item's (or the
 * popup's) action and then posts NSMenuDidSendActionNotification with
 * `self` as the object. The action removed the popup from its superview and
 * dropped the last reference to it; the popup owned the menu, so `self` is
 * freed by the time the notification is posted, and NSNotificationCenter
 * retains a freed object. The same shape recurs in
 * -[NSTextField textDidEndEditing:], which sends the field's action and then
 * asks `_window` for its first responder.
 *
 * On Cocoa the sender of an action is kept alive by the event dispatch until
 * the autorelease pool drains, so application code that regenerates its
 * views from inside an action is safe there and only dies on GNUstep.
 *
 * The accompanying patch, gnustep-gui-action-sender-lifetime.patch, retains
 * the receiver for the current autorelease scope before the action is sent
 * in both places. With it this program prints "survived".
 */
#import <AppKit/AppKit.h>

@interface Host : NSView
@property (nonatomic, strong) NSPopUpButton *popup;
@property (nonatomic, assign) int generation;
@end

@implementation Host
- (void)rebuild
{
  /* Throw the widget away and make a new one -- from inside the action of
   * the widget being thrown away.  The superview and this property were its
   * only owners, so it is freed right here, the way a form view that
   * regenerates its widgets frees them. */
  [self.popup removeFromSuperview];
  self.popup = nil;
  NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(20, 20, 200, 24)
                                                    pullsDown: NO];
  [popup addItemsWithTitles: @[ @"alpha", @"beta", @"gamma" ]];
  [popup setTarget: self];
  [popup setAction: @selector(changed:)];
  [self addSubview: popup];
  self.popup = popup;
  [[self window] makeFirstResponder: popup];
  self.generation++;
}
- (void)changed: (id)sender
{
  (void)sender;   /* deliberately unused: a reference here would keep it alive */
  fprintf(stderr, "action, rebuilding (generation %d)\n", self.generation);
  [self rebuild];
}
@end

@interface Repro : NSObject
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) Host *host;
@end

@implementation Repro
- (void)applicationDidFinishLaunching: (NSNotification *)n
{
  NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(40, 40, 400, 200)
    styleMask: NSTitledWindowMask | NSResizableWindowMask | NSClosableWindowMask
    backing: NSBackingStoreBuffered defer: NO];
  Host *host = [[Host alloc] initWithFrame: NSMakeRect(0, 0, 400, 200)];
  [[w contentView] addSubview: host];
  [w makeKeyAndOrderFront: nil];
  self.window = w;
  self.host = host;
  [host rebuild];
  [self performSelector: @selector(press) withObject: nil afterDelay: 0.5];
}
- (void)key: (NSString *)chars
{
  NSEvent *e = [NSEvent keyEventWithType: NSKeyDown location: NSZeroPoint modifierFlags: 0
    timestamp: 0 windowNumber: [self.window windowNumber] context: nil
    characters: chars charactersIgnoringModifiers: chars isARepeat: NO keyCode: 0];
  [NSApp sendEvent: e];
  [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]];
}
- (void)press
{
  /* Space opens the popup's menu, Return chooses the highlighted item:
   * -[NSPopUpButton keyDown:] -> -[NSMenu performActionForItemAtIndex:]. */
  [self key: @" "];
  [self key: @"\r"];
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
