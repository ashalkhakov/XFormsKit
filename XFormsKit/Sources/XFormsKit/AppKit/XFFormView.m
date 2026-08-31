#import "XFAppKitPriv.h"

const void *kXFBoundControlKey = &kXFBoundControlKey;

const CGFloat kLabelWidth = 110.0;
const CGFloat kRowHeight = 24.0;
const CGFloat kTextareaHeight = 72.0;
const CGFloat kRowGap = 8.0;
const CGFloat kMargin = 12.0;
const CGFloat kIndent = 16.0;
const CGFloat kFieldWidth = 280.0;
const CGFloat kInlineFieldWidth = 140.0;
const CGFloat kLineGap = 2.0;
const CGFloat kWrapWidth = 620.0;

@implementation XFLayoutAtom
@end

@implementation XFWidget
@end

// Every file split out of XFFormView.m defines one of these; referencing
// them here turns a translation unit missing from a build (GNUmakefile or
// an Xcode project) into a LINK error instead of a silent runtime gap.
FOUNDATION_EXPORT void XFAppKitHasWidgetsFile(void);
FOUNDATION_EXPORT void XFAppKitHasLayoutFile(void);
FOUNDATION_EXPORT void XFAppKitHasEditingFile(void);
FOUNDATION_EXPORT void XFAppKitHasTableAdapterFile(void);
FOUNDATION_EXPORT void XFAppKitHasRichTextEditorFile(void);
FOUNDATION_EXPORT void XFAppKitHasRichTextFile(void);
__attribute__((used)) static void (*const XFAppKitLinkChecks[])(void) = {
    XFAppKitHasWidgetsFile,
    XFAppKitHasLayoutFile,
    XFAppKitHasEditingFile,
    XFAppKitHasTableAdapterFile,
    XFAppKitHasRichTextEditorFile,
    XFAppKitHasRichTextFile,
};

@implementation XFFormView

- (instancetype)initWithProcessor:(XFProcessor *)processor
{
    return [self initWithProcessor:processor rootGroup:nil];
}

- (instancetype)initWithProcessor:(XFProcessor *)processor rootGroup:(XFGroup *)rootGroup
{
    self = [super initWithFrame:NSMakeRect(0, 0, 620, 240)];
    if (self) {
        _processor = processor;
        _rootGroup = rootGroup;
        _widgets = [NSMutableArray array];
        _tables = [NSMutableArray array];
        _listBoxes = [NSMutableArray array];
        _keyViews = [NSMutableArray array];
        [self setAutoresizingMask:NSViewNotSizable];
        if (rootGroup == nil) {
            __weak XFFormView *weakSelf = self;
            // xf:setfocus / xforms-focus → first responder (G-24)
            processor.focusRequestHandler = ^(XFControl *control) {
                [weakSelf makeControlFirstResponder:control];
            };
        }
        [self rebuild];
    }
    return self;
}

- (void)rebuildWidgets
{
    [self rebuild];
}

- (BOOL)isFlipped
{
    return YES;
}

/// The view Tab lands on for a widget (the scroll view's document view for
/// textareas / list boxes / tables).
NSView *XFKeyViewOf(NSView *view)
{
    if ([view isKindOfClass:[XFRichTextEditor class]]) {
        return [(XFRichTextEditor *)view textView];
    }
    return [view isKindOfClass:[NSScrollView class]] ? [(NSScrollView *)view documentView] : view;
}

- (void)registerKeyView:(NSView *)view control:(XFControl *)control
{
    // outputs and standalone labels are not tab stops (HTML: a span is not
    // focusable), even though a selectable text field would accept focus
    if (view == nil || [control isKindOfClass:[XFOutputControl class]]
        || [control isKindOfClass:[XFLabelControl class]]) {
        return;
    }
    [self.keyViews addObject:view];
}

- (NSTextField *)makeLabel:(NSString *)text
{
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [field setStringValue:text ?: @""];
    [field setBezeled:NO];
    [field setDrawsBackground:NO];
    [field setEditable:NO];
    [field setSelectable:NO];
    return field;
}

- (BOOL)isBooleanControl:(XFControl *)control
{
    XFNodeState *state = [XFNodeState existingStateOnNode:control.boundNode];
    NSString *type = state.typeName ?: @"";
    if ([type rangeOfString:@"boolean"].location != NSNotFound) {
        return YES;
    }
    NSString *v = control.stringValue ?: @"";
    return [v isEqualToString:@"true"] || [v isEqualToString:@"false"];
}

- (void)applyEnabled:(NSView *)view control:(XFControl *)control
{
    BOOL on = control.relevant && !control.readonly;
    if ([view respondsToSelector:@selector(setEnabled:)]) {
        [(NSControl *)view setEnabled:on];
    }
    [view setHidden:!control.relevant];
    if ([view respondsToSelector:@selector(setToolTip:)]) {
        NSMutableArray *bits = [NSMutableArray array];
        if (control.hint.length) [bits addObject:control.hint];
        if (!control.valid && control.alert.length) [bits addObject:control.alert];
        if (bits.count) {
            [view setToolTip:[bits componentsJoinedByString:@"\n"]];
        }
    }
}

- (XFWidget *)addWidget:(XFControl *)control view:(NSView *)view height:(CGFloat)height
                  atY:(CGFloat)y indent:(CGFloat)indent
{
    XFWidget *w = [[XFWidget alloc] init];
    w.control = control;
    w.view = view;
    w.height = height;
    if (control.label.length && ![control isKindOfClass:[XFTriggerControl class]]
        && ![control isKindOfClass:[XFGroup class]]) {
        NSString *caption = control.required
            ? [NSString stringWithFormat:@"%@ *", control.label]
            : control.label;
        NSTextField *label = [self makeLabel:caption];
        if (!control.valid && [label respondsToSelector:@selector(setTextColor:)]) {
            [label setTextColor:[NSColor redColor]];
        }
        [label setFrame:NSMakeRect(kMargin + indent, y, kLabelWidth, kRowHeight)];
        [self addSubview:label];
        w.labelField = label;
        [view setFrame:NSMakeRect(kMargin + indent + kLabelWidth + 8, y, kFieldWidth, height)];
    } else {
        [view setFrame:NSMakeRect(kMargin + indent, y, kLabelWidth + 8 + kFieldWidth, height)];
    }
    [self addSubview:view];
    [self.widgets addObject:w];
    [self registerKeyView:XFKeyViewOf(view) control:control];
    objc_setAssociatedObject(view, kXFBoundControlKey, control, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self applyEnabled:view control:control];
    [self noteRight:NSMaxX([view frame])];
    return w;
}

- (void)noteRight:(CGFloat)right
{
    if (right > self.maxRight) {
        self.maxRight = right;
    }
}

- (XFControl *)controlForSender:(id)sender
{
    id walk = sender;
    while (walk) {
        XFControl *bound = objc_getAssociatedObject(walk, kXFBoundControlKey);
        if (bound) {
            return bound;
        }
        if ([walk respondsToSelector:@selector(superview)]) {
            walk = [walk superview];
        } else {
            break;
        }
    }
    XFWidget *w = [self widgetForControlView:sender];
    return w.control;
}

- (NSTextField *)textFieldEditable:(BOOL)editable secure:(BOOL)secure
{
    NSTextField *field = secure ? [[NSSecureTextField alloc] initWithFrame:NSZeroRect]
                                : [[NSTextField alloc] initWithFrame:NSZeroRect];
    [field setEditable:editable];
    if (!editable) {
        [field setBezeled:NO];
        [field setDrawsBackground:NO];
    } else {
        // Commit when focus leaves the field too, not only on Return
        // (XSLTForms commits xf:input on the DOM change event).
        [[field cell] setSendsActionOnEndEditing:YES];
    }
    [field setTarget:self];
    [field setAction:@selector(textChanged:)];
    [field setDelegate:self];
    return field;
}

- (void)rebuild
{
    for (NSView *view in [[self subviews] copy]) {
        [view removeFromSuperview];
    }
    [self.widgets removeAllObjects];
    [self.keyViews removeAllObjects];
    for (XFTableAdapter *t in self.tables) {
        [t.tableView setDataSource:nil];
        [t.tableView setDelegate:nil];
    }
    [self.tables removeAllObjects];
    [self.listBoxes removeAllObjects];
    self.maxRight = 0;
    self.wrapRight = MAX(kWrapWidth, [self frame].size.width) - kMargin;
    CGFloat y = kMargin;
    y = [self layoutNodes:self.rootGroup ? self.rootGroup.hostNodes : self.processor.hostNodes atY:y indent:0 font:nil];
    if (self.rootGroup == nil && self.widgets.count == 0 && self.processor.controls.count == 0) {
        NSTextField *empty = [self makeLabel:@"No XForms controls in the host body."];
        [empty setFrame:NSMakeRect(kMargin, y, 400, 40)];
        [self addSubview:empty];
        y += 48;
    }
    self.contentHeight = y + kMargin;
    [self setFrame:NSMakeRect(0, 0, MAX(kWrapWidth, self.maxRight + kMargin), MAX(self.contentHeight, 80))];
    [self setNeedsDisplay:YES];
    // Tab order (G-63): like HTML/XForms navigation — the widgets with a
    // positive @navindex first, ascending (stable), then every focusable
    // view in document order; the chain wraps. AppKit itself skips views
    // that refuse first responder (labels, disabled fields).
    NSMutableArray<NSView *> *chain = [NSMutableArray array];
    NSArray *ordered = [self.widgets sortedArrayWithOptions:NSSortStable
                                            usingComparator:^NSComparisonResult(XFWidget *a, XFWidget *b) {
        NSInteger na = a.control.navindex, nb = b.control.navindex;
        if (na == nb) return NSOrderedSame;
        if (na == 0) return NSOrderedDescending;
        if (nb == 0) return NSOrderedAscending;
        return na < nb ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (XFWidget *w in ordered) {
        if (w.control.navindex <= 0) {
            break;
        }
        NSView *v = XFKeyViewOf(w.view);
        if (v) {
            [chain addObject:v];
        }
    }
    for (NSView *v in self.keyViews) {
        if (![chain containsObject:v]) {
            [chain addObject:v];
        }
    }
    NSView *previous = chain.lastObject;   // wrap: last → first
    for (NSView *v in chain) {
        [previous setNextKeyView:v];
        previous = v;
    }
    self.firstKeyView = chain.firstObject;
    self.keyChain = chain;
    [self installInitialFirstResponder];
    // the widgets were recreated: give the engine's focused control its
    // first responder back — unless a Tab movement is about to place the
    // focus itself (G-63)
    if (self.processor.focusedControl && [self window] && self.pendingTabDirection == 0) {
        [self makeControlFirstResponder:self.processor.focusedControl];
    }
}

/// The first Tab press should land in the form: point the window at the
/// chain's first view (and keep our hand-built loop — macOS would
/// otherwise recalculate a geometric one over it).
- (void)installInitialFirstResponder
{
    NSWindow *window = [self window];
    if (window == nil) {
        return;
    }
    if ([window respondsToSelector:@selector(setAutorecalculatesKeyViewLoop:)]) {
        [window setAutorecalculatesKeyViewLoop:NO];
    }
    if (self.firstKeyView) {
        [window setInitialFirstResponder:self.firstKeyView];
    }
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self installInitialFirstResponder];
}

/// The widget whose textarea / rich editor owns `tv`.
- (XFWidget *)widgetForTextView:(NSTextView *)tv
{
    for (XFWidget *w in self.widgets) {
        if ([w.view isKindOfClass:[NSScrollView class]] && [(NSScrollView *)w.view documentView] == tv) {
            return w;
        }
        if ([w.view isKindOfClass:[XFRichTextEditor class]] && [(XFRichTextEditor *)w.view textView] == tv) {
            return w;
        }
    }
    return nil;
}

- (XFWidget *)widgetForView:(id)sender
{
    for (XFWidget *w in self.widgets) {
        if (w.view == sender || [w.view isKindOfClass:[NSScrollView class]] ) {
            if (w.view == sender) {
                return w;
            }
        }
    }
    return nil;
}

- (XFWidget *)widgetForControlView:(NSView *)view
{
    for (XFWidget *w in self.widgets) {
        if (w.view == view) {
            return w;
        }
    }
    return nil;
}

#pragma mark - Focus (G-24)

- (XFWidget *)widgetForControl:(XFControl *)control
{
    if (control == nil) {
        return nil;
    }
    for (XFWidget *w in self.widgets) {
        if (w.control == control) {
            return w;
        }
    }
    // repeat items recreate their controls on refresh: same element,
    // same bound node
    for (XFWidget *w in self.widgets) {
        if (w.control.element == control.element && w.control.boundNode == control.boundNode) {
            return w;
        }
    }
    return nil;
}

- (void)makeControlFirstResponder:(XFControl *)control
{
    XFWidget *w = [self widgetForControl:control];
    NSView *view = XFKeyViewOf(w.view);
    if (view && [view window] && [view acceptsFirstResponder]) {
        [[view window] makeFirstResponder:view];
    }
}

/// A widget took the keyboard focus: the engine's focus follows
/// (XsltForms_control.focusHandler).
- (void)widgetDidFocus:(id)sender
{
    XFControl *control = [self controlForSender:sender];
    if (control) {
        [self.processor focusControl:control fromUI:YES];
    }
}

- (void)reloadFromProcessor
{
    [self.processor refreshControls];
    [self rebuild];
    if (self.pendingTabDirection != 0) {
        // after the current event (AppKit's own movement attempt on the
        // detached old view is a no-op by then)
        [self performSelector:@selector(applyPendingTab) withObject:nil afterDelay:0];
    }
    if (self.instanceChangedHandler) {
        self.instanceChangedHandler();
    }
}

- (void)applyPendingTab
{
    XFControl *from = self.pendingTabControl;
    NSInteger direction = self.pendingTabDirection;
    self.pendingTabControl = nil;
    self.pendingTabDirection = 0;
    if (direction == 0 || self.keyChain.count == 0 || [self window] == nil) {
        return;
    }
    NSView *fromView = XFKeyViewOf([self widgetForControl:from].view);
    NSInteger count = (NSInteger)self.keyChain.count;
    NSInteger at = fromView ? (NSInteger)[self.keyChain indexOfObject:fromView] : NSNotFound;
    if (at == NSNotFound) {
        at = direction > 0 ? -1 : 0;   // control gone: start at an end
    }
    for (NSInteger step = 1; step <= count; step++) {
        NSInteger i = ((at + direction * step) % count + count) % count;
        NSView *v = self.keyChain[(NSUInteger)i];
        if ([v window] == [self window] && ![v isHiddenOrHasHiddenAncestor] && [v acceptsFirstResponder]) {
            [self scrollRectToVisible:[self convertRect:[v bounds] fromView:v]];
            [[self window] makeFirstResponder:v];
            return;
        }
    }
}

@end
