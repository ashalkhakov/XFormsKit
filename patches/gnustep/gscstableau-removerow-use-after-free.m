/* GNUstep: -[GSCSTableau removeRowForVariable:] uses the row expression
 * after the row dictionary -- its only owner -- has released it.
 *
 * AppKit only -- no XFormsKit. A window whose content view holds a few
 * plain autoresizing subviews, a single -layoutSubtreeIfNeeded (the Cocoa
 * idiom for "lay this out now"), then a resize. That is all the XFormsViewer
 * window does, and on GNUstep it is enough:
 *
 *   clang -o gscstableau-removerow-use-after-free gscstableau-removerow-use-after-free.m \
 *       `gnustep-config --objc-flags` `gnustep-config --gui-libs`
 *   mkdir -p Repro.app/Resources && cp gscstableau-removerow-use-after-free Repro.app/Repro
 *   printf '{ NSExecutable = "Repro"; NSPrincipalClass = "NSApplication"; }\n' \
 *       > Repro.app/Resources/Info-gnustep.plist
 *   xvfb-run -a valgrind -q ./Repro.app/Repro
 *       # Invalid read ... -[GSCSTableau removeRowForVariable:]
 *       #   ... Address ... free'd ... -[NSDictionary removeObjectForKey:]
 *   xvfb-run -a env MALLOC_PERTURB_=165 ./Repro.app/Repro   # usually a segfault
 *
 * (An app wrapper, because a bare executable has no NSPrincipalClass and
 * gnustep-gui refuses to start; xvfb-run, because the headless backend
 * never resizes a window.)
 *
 * What happens. On GNUstep -layoutSubtreeIfNeeded is not a no-op for a
 * window that never asked for Auto Layout: -updateConstraintsForSubtreeIfNeeded
 * runs -updateConstraints on every view in the subtree, and because
 * translatesAutoresizingMaskIntoConstraints is YES by default each one adds
 * NSAutoresizingMaskLayoutConstraints for its mask. The first addConstraint:
 * creates the window's GSAutoLayoutEngine (-_bootstrapAutoLayout), and from
 * then on every resize of the content view runs
 * -[GSAutoLayoutEngine updateContentViewSize], which removes and re-adds
 * the content view's size constraints in the Cassowary solver.
 *
 * Removing a constraint pivots the tableau. -pivotWithEntryVariable:exitVariable:
 * fetches the exit variable's row expression, calls -removeRowForVariable:,
 * and goes on to rewrite that expression. -removeRowForVariable: does
 *
 *     GSCSLinearExpression *expression = [_rows objectForKey: variable];
 *     [_rows removeObjectForKey: variable];      // releases it: sole owner
 *     ... [expression termVariables] ...          // freed
 *
 * and the caller continues to use the same freed object. Whether that is a
 * segfault, a corrupted tableau, or nothing depends on what the allocator
 * has since put in the chunk -- which is why the same window survives a
 * resize on one machine and dies on maximize on another.
 *
 * The accompanying patch, gnustep-gui-gscstableau-removerow-use-after-free.patch,
 * retains the expression for the current autorelease scope before the row
 * is removed (the pattern -[GSCassowarySolver removeConstraintFromTableau:]
 * already uses for its marker variable). With it valgrind is clean and
 * gnustep-gui's own NSLayoutConstraint / GSAutoLayoutEngine tests pass.
 */
#import <AppKit/AppKit.h>

@interface Repro : NSObject
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, assign) int round;
@end

@implementation Repro
- (void)applicationDidFinishLaunching:(NSNotification *)n
{
  NSRect content = NSMakeRect(0, 0, 900, 600);
  NSWindow *w = [[NSWindow alloc] initWithContentRect: NSOffsetRect(content, 40, 40)
    styleMask: NSTitledWindowMask | NSResizableWindowMask | NSClosableWindowMask
    backing: NSBackingStoreBuffered defer: NO];
  [w setTitle: @"repro"];
  NSView *cv = [w contentView];

  /* A handful of plain views with the usual masks: a sidebar, a body that
   * follows the window, a footer.  No NSLayoutConstraint anywhere. */
  NSView *side = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 250, 600)];
  [side setAutoresizingMask: NSViewHeightSizable | NSViewMaxXMargin];
  NSView *body = [[NSView alloc] initWithFrame: NSMakeRect(250, 40, 650, 560)];
  [body setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  NSView *foot = [[NSView alloc] initWithFrame: NSMakeRect(250, 0, 650, 40)];
  [foot setAutoresizingMask: NSViewWidthSizable | NSViewMaxYMargin];
  for (int i = 0; i < 12; i++)
    {
      NSTextField *f = [[NSTextField alloc] initWithFrame: NSMakeRect(10, 20 + 40 * i, 300, 24)];
      [f setStringValue: [NSString stringWithFormat: @"field %d", i]];
      [f setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
      [body addSubview: f];
    }
  [cv addSubview: side];
  [cv addSubview: body];
  [cv addSubview: foot];
  [w makeKeyAndOrderFront: nil];

  /* The one line that engages the layout engine. */
  [cv layoutSubtreeIfNeeded];

  self.window = w;
  [self performSelector: @selector(resize) withObject: nil afterDelay: 0.5];
}

- (void)resize
{
  /* Grow, then shrink, a few times: each content-view resize removes and
   * re-adds the size constraints, i.e. pivots. */
  NSRect f = [self.window frame];
  if (self.round % 2 == 0) { f.size.width += 400; f.size.height += 300; }
  else { f.size.width -= 400; f.size.height -= 300; }
  fprintf(stderr, "round %d: setFrame %s\n", self.round, [NSStringFromRect(f) UTF8String]);
  [self.window setFrame: f display: YES];
  if (++self.round < 6)
    {
      [self performSelector: @selector(resize) withObject: nil afterDelay: 0.3];
    }
  else
    {
      fprintf(stderr, "survived\n");
      [NSApp terminate: nil];
    }
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
