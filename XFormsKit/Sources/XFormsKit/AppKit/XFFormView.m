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

static const CGFloat kBadgeSize = 14.0;

BOOL XFDarkTheme(void)
{
#if defined(__APPLE__)
    // NSAppearance (10.14+), by selector so older SDK targets still build;
    // the name constants' values are their own names
    id app = [NSApplication sharedApplication];
    if ([app respondsToSelector:@selector(effectiveAppearance)]) {
        id appearance = [app performSelector:@selector(effectiveAppearance)];
        if ([appearance respondsToSelector:@selector(bestMatchFromAppearancesWithNames:)]) {
            NSString *match = [appearance performSelector:@selector(bestMatchFromAppearancesWithNames:)
                                               withObject:@[@"NSAppearanceNameAqua", @"NSAppearanceNameDarkAqua"]];
            return [match isEqualToString:@"NSAppearanceNameDarkAqua"];
        }
    }
    return NO;
#else
    // GNUstep has no system appearance: a dark theme shows in the text
    // background's luminance
    NSColor *bg = [[NSColor textBackgroundColor]
        colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    if (bg == nil) {
        return NO;
    }
    CGFloat lum = 0.299 * [bg redComponent] + 0.587 * [bg greenComponent]
        + 0.114 * [bg blueComponent];
    return lum < 0.5;
#endif
}

NSColor *XFInvalidTextColor(void)
{
    if ([[NSColor class] respondsToSelector:@selector(systemRedColor)]) {
        return [[NSColor class] performSelector:@selector(systemRedColor)];
    }
    return [NSColor redColor];
}

@interface XFBadgeView ()
@property (nonatomic, assign) NSTrackingRectTag trackTag;
@end

@implementation XFBadgeView

+ (instancetype)badgeWithKind:(XFBadgeKind)kind text:(NSString *)text
{
    XFBadgeView *b = [[self alloc] initWithFrame:NSMakeRect(0, 0, kBadgeSize, kBadgeSize)];
    b.kind = kind;
    b.text = text ?: @"";
    return b;
}

- (XFFormView *)formView
{
    NSView *v = [self superview];
    return [v isKindOfClass:[XFFormView class]] ? (XFFormView *)v : nil;
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
    // remove while the old window is still current — a tag from another
    // window cannot be removed later
    if (self.trackTag != 0 && [self window] != nil) {
        [self removeTrackingRect:self.trackTag];
        self.trackTag = 0;
    }
    [super viewWillMoveToWindow:newWindow];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self refreshTracking];
}

- (void)refreshTracking
{
    if (self.trackTag != 0 && [self window] != nil) {
        [self removeTrackingRect:self.trackTag];
        self.trackTag = 0;
    }
    if ([self window] != nil) {
        self.trackTag = [self addTrackingRect:[self bounds]
                                        owner:self
                                     userData:NULL
                                 assumeInside:NO];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    (void)event;
    if (![self isHiddenOrHasHiddenAncestor]) {
        [[self formView] showBadgeInfo:self];
    }
}

- (void)mouseExited:(NSEvent *)event
{
    (void)event;
    XFFormView *fv = [self formView];
    if (fv.badgePopupBadge == self) {
        [fv hideBadgeInfo];
    }
}

- (void)mouseDown:(NSEvent *)event
{
    (void)event;
    XFFormView *fv = [self formView];
    if (fv.badgePopupBadge == self) {
        [fv hideBadgeInfo];
    } else {
        [fv showBadgeInfo:self];
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSRect r = NSInsetRect([self bounds], 1, 1);
    BOOL dark = XFDarkTheme();
    NSColor *fill = self.kind == XFBadgeAlert
        ? (dark ? [NSColor colorWithCalibratedRed:0.85 green:0.25 blue:0.25 alpha:1.0]
                : [NSColor colorWithCalibratedRed:0.80 green:0.10 blue:0.10 alpha:1.0])
        : (dark ? [NSColor colorWithCalibratedRed:0.45 green:0.55 blue:0.75 alpha:1.0]
                : [NSColor colorWithCalibratedRed:0.35 green:0.45 blue:0.65 alpha:1.0]);
    [fill setFill];
    [[NSBezierPath bezierPathWithOvalInRect:r] fill];
    NSString *glyph = self.kind == XFBadgeAlert ? @"!" : @"i";
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:10],
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };
    NSSize sz = [glyph sizeWithAttributes:attrs];
    [glyph drawAtPoint:NSMakePoint(NSMidX(r) - sz.width / 2, NSMidY(r) - sz.height / 2)
        withAttributes:attrs];
}

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
FOUNDATION_EXPORT void XFAppKitHasSVGFile(void);
__attribute__((used)) static void (*const XFAppKitLinkChecks[])(void) = {
    XFAppKitHasWidgetsFile,
    XFAppKitHasLayoutFile,
    XFAppKitHasEditingFile,
    XFAppKitHasTableAdapterFile,
    XFAppKitHasRichTextEditorFile,
    XFAppKitHasRichTextFile,
    XFAppKitHasSVGFile,
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
        _svgViews = [NSMutableArray array];
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
        // A minimal-appearance hint is the host `title` attribute in
        // XSLTForms (field.xsl) — a plain tooltip on the widget itself; a
        // default hint is carried by the ⓘ badge instead. The alert is
        // repeated here so hovering the invalid field also shows it.
        NSMutableArray *bits = [NSMutableArray array];
        if (control.hint.length && control.hintMinimal) [bits addObject:control.hint];
        if (!control.valid && control.alert.length) [bits addObject:control.alert];
        [view setToolTip:bits.count ? [bits componentsJoinedByString:@"\n"] : nil];
    }
}

- (CGFloat)attachBadgesToWidget:(XFWidget *)w
{
    XFControl *control = w.control;
    NSView *view = w.view;
    CGFloat x = NSMaxX([view frame]) + 4;
    // Centre on the first row of the widget (a textarea's badge sits by
    // its top line, like XSLTForms' inline icons).
    CGFloat rowH = MIN([view frame].size.height, kRowHeight);
    CGFloat y = [view frame].origin.y + (rowH - kBadgeSize) / 2;
    if (control.hint.length && !control.hintMinimal) {
        w.hintBadge = [XFBadgeView badgeWithKind:XFBadgeHint text:control.hint];
        [w.hintBadge setFrameOrigin:NSMakePoint(x, y)];
        [self addSubview:w.hintBadge];
        x += kBadgeSize + 2;
    }
    if ((control.alert.length || !control.valid)
        && ![control isKindOfClass:[XFTriggerControl class]]
        && ![control isKindOfClass:[XFGroup class]]) {
        // The slot exists (hidden while valid) for any control with an
        // xf:alert, so a validity flip during incremental editing shows the
        // badge without moving the layout; a control without an alert gets
        // its badge at the rebuild that follows a commit
        // (.xforms-invalid span.xforms-alert { display: inline }).
        w.alertBadge = [XFBadgeView badgeWithKind:XFBadgeAlert text:control.alert];
        [w.alertBadge setFrameOrigin:NSMakePoint(x, y)];
        [self addSubview:w.alertBadge];
        x += kBadgeSize + 2;
    }
    [self updateBadgesForWidget:w];
    return x - 4;
}

- (void)updateBadgesForWidget:(XFWidget *)w
{
    XFControl *control = w.control;
    if (w.hintBadge) {
        [w.hintBadge setHidden:!control.relevant];
        w.hintBadge.text = control.hint ?: @"";
    }
    if (w.alertBadge) {
        [w.alertBadge setHidden:control.valid || !control.relevant];
        w.alertBadge.text = control.alert ?: @"";
    }
    XFBadgeView *shown = self.badgePopupBadge;
    if (shown != nil && (shown == w.hintBadge || shown == w.alertBadge) && [shown isHidden]) {
        [self hideBadgeInfo];
    }
}

- (void)showBadgeInfo:(XFBadgeView *)badge
{
    [self hideBadgeInfo];
    NSString *text = badge.text;
    if (text.length == 0) {
        return;
    }
    // The port of XSLTForms' span.xforms-hint-value / -alert-value box
    // (icones.css: pale yellow / pale pink, bordered, ~200px, absolutely
    // positioned under the icon).
    NSFont *font = [NSFont systemFontOfSize:11];
    const CGFloat maxTextWidth = 220;
    const CGFloat pad = 5;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    CGFloat widest = 0;
    for (NSString *para in [text componentsSeparatedByString:@"\n"]) {
        NSMutableString *line = [NSMutableString string];
        for (NSString *word in [para componentsSeparatedByString:@" "]) {
            NSString *joined = line.length ? [NSString stringWithFormat:@"%@ %@", line, word] : word;
            if (line.length && [self widthOfText:joined font:font] > maxTextWidth) {
                [lines addObject:[line copy]];
                [line setString:word];
            } else {
                [line setString:joined];
            }
        }
        [lines addObject:[line copy]];
    }
    for (NSString *l in lines) {
        widest = MAX(widest, [self widthOfText:l font:font]);
    }
    CGFloat lineH = [self lineHeightForFont:font];
    CGFloat w = MIN(widest, maxTextWidth) + 2 * pad;
    CGFloat h = lines.count * lineH + 2 * pad;
    CGFloat x = badge.frame.origin.x - 16;
    x = MAX(4, MIN(x, NSWidth([self bounds]) - w - 4));
    CGFloat y = NSMaxY(badge.frame) + 3;
    NSTextField *box = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, w, h)];
    [box setEditable:NO];
    [box setSelectable:NO];
    [box setBezeled:NO];
    [box setBordered:YES];
    [box setDrawsBackground:YES];
    // XSLTForms' pale yellow / pink boxes in light themes; their dark
    // counterparts otherwise — with an explicit text color either way, so
    // the theme's default text never lands on the wrong background
    if (XFDarkTheme()) {
        [box setBackgroundColor:badge.kind == XFBadgeAlert
            ? [NSColor colorWithCalibratedRed:0.33 green:0.16 blue:0.16 alpha:1.0]
            : [NSColor colorWithCalibratedRed:0.27 green:0.26 blue:0.16 alpha:1.0]];
        [box setTextColor:[NSColor colorWithCalibratedWhite:0.93 alpha:1.0]];
    } else {
        [box setBackgroundColor:badge.kind == XFBadgeAlert
            ? [NSColor colorWithCalibratedRed:1.0 green:0.93 blue:0.93 alpha:1.0]
            : [NSColor colorWithCalibratedRed:1.0 green:1.0 blue:0.93 alpha:1.0]];
        [box setTextColor:[NSColor colorWithCalibratedWhite:0.10 alpha:1.0]];
    }
    [box setFont:font];
    [[box cell] setWraps:YES];
    [box setStringValue:text];
    [self addSubview:box];   // added last — draws above every widget
    self.badgePopup = box;
    self.badgePopupBadge = badge;
}

- (void)hideBadgeInfo
{
    [self.badgePopup removeFromSuperview];
    self.badgePopup = nil;
    self.badgePopupBadge = nil;
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
            [label setTextColor:XFInvalidTextColor()];
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
    [self noteRight:[self attachBadgesToWidget:w]];
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
    [self hideBadgeInfo];
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
    [self.svgViews removeAllObjects];
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
    // Apple snapshots tracking rects in window coordinates when they are
    // added, so badge tracking is re-registered on every scroll (GNUstep
    // converts at event time and would not need this).
    NSView *clip = [[self enclosingScrollView] contentView];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSViewBoundsDidChangeNotification
                                                  object:nil];
    if (clip != nil) {
        [(NSClipView *)clip setPostsBoundsChangedNotifications:YES];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(xfClipViewScrolled:)
                                                     name:NSViewBoundsDidChangeNotification
                                                   object:clip];
    }
}

- (void)xfClipViewScrolled:(NSNotification *)note
{
    (void)note;
    [self hideBadgeInfo];
    for (XFWidget *w in self.widgets) {
        [w.hintBadge refreshTracking];
        [w.alertBadge refreshTracking];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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

#pragma mark - Design-support introspection

/// The visual rectangle of one widget: its view plus its label column.
static NSRect XFWidgetRect(XFWidget *w)
{
    NSRect r = [w.view frame];
    if (w.labelField != nil) {
        r = NSUnionRect(r, [w.labelField frame]);
    }
    return r;
}

- (NSRect)layoutFrameOfControl:(XFControl *)control
{
    if (control == nil) {
        return NSZeroRect;
    }
    NSRect out = NSZeroRect;
    for (XFWidget *w in self.widgets) {
        if (w.control != control) {
            continue;
        }
        NSRect r = XFWidgetRect(w);
        out = NSIsEmptyRect(out) ? r : NSUnionRect(out, r);
    }
    if (!NSIsEmptyRect(out)) {
        return out;
    }
    // groups: the layout ties the NSBox to its group with the same
    // associated key the widgets use
    for (NSView *sub in [self subviews]) {
        if (objc_getAssociatedObject(sub, kXFBoundControlKey) == control
            && ![sub isHidden]) {
            out = NSIsEmptyRect(out) ? [sub frame] : NSUnionRect(out, [sub frame]);
        }
    }
    if (!NSIsEmptyRect(out)) {
        return out;
    }
    // controls rendered as cells inside a host <table> (G-20 phase 2)
    for (XFTableAdapter *t in self.tables) {
        NSArray<XFTableRow *> *rows = t.model.rows;
        for (NSUInteger ri = 0; ri < rows.count; ri++) {
            for (XFTableCell *cell in rows[ri].cells) {
                if (cell.control != control && ![cell.controls containsObject:control]) {
                    continue;
                }
                NSInteger ci = [t.tableView columnWithIdentifier:
                    [NSString stringWithFormat:@"%lu", (unsigned long)cell.column]];
                if (ci < 0) {
                    continue;
                }
                NSRect r = [t.tableView frameOfCellAtColumn:ci row:(NSInteger)ri];
                r = [self convertRect:r fromView:t.tableView];
                out = NSIsEmptyRect(out) ? r : NSUnionRect(out, r);
            }
        }
    }
    if (!NSIsEmptyRect(out)) {
        return out;
    }
    // containers with no visual of their own: the union of the children
    if ([control isKindOfClass:[XFSwitch class]]) {
        return [self layoutFrameOfControl:[(XFSwitch *)control selectedCase]];
    }
    if ([control isKindOfClass:[XFRepeat class]]) {
        for (XFRepeatItem *item in [(XFRepeat *)control items]) {
            for (XFControl *child in item.controls) {
                NSRect r = [self layoutFrameOfControl:child];
                if (!NSIsEmptyRect(r)) {
                    out = NSIsEmptyRect(out) ? r : NSUnionRect(out, r);
                }
            }
        }
        return out;
    }
    if ([control isKindOfClass:[XFGroup class]]) {
        for (XFControl *child in [(XFGroup *)control children]) {
            NSRect r = [self layoutFrameOfControl:child];
            if (!NSIsEmptyRect(r)) {
                out = NSIsEmptyRect(out) ? r : NSUnionRect(out, r);
            }
        }
    }
    return out;
}

- (XFControl *)controlAtPoint:(NSPoint)point
{
    // widgets: the innermost (smallest) rectangle wins — widget frames
    // are flat siblings, children lie inside their group's box
    XFControl *best = nil;
    CGFloat bestArea = CGFLOAT_MAX;
    for (XFWidget *w in self.widgets) {
        if ([w.view isHidden]) {
            continue;
        }
        NSRect r = XFWidgetRect(w);
        if (!NSPointInRect(point, r)) {
            continue;
        }
        CGFloat area = NSWidth(r) * NSHeight(r);
        if (area < bestArea) {
            bestArea = area;
            best = w.control;
        }
    }
    if (best != nil) {
        return best;
    }
    // cells of host <table>s
    for (XFTableAdapter *t in self.tables) {
        if (t.scrollView.superview == nil
            || !NSPointInRect(point, [self convertRect:[t.scrollView bounds] fromView:t.scrollView])) {
            continue;
        }
        NSPoint tp = [t.tableView convertPoint:point fromView:self];
        NSInteger row = [t.tableView rowAtPoint:tp];
        NSInteger col = [t.tableView columnAtPoint:tp];
        if (row < 0 || col < 0 || (NSUInteger)row >= t.model.rows.count) {
            continue;
        }
        NSUInteger modelColumn = (NSUInteger)
            [[[[t.tableView tableColumns] objectAtIndex:(NSUInteger)col] identifier] integerValue];
        XFTableRow *tableRow = t.model.rows[(NSUInteger)row];
        XFTableCell *cell = [tableRow cellAtColumn:modelColumn];
        XFControl *found = cell.control ?: cell.controls.firstObject;
        if (found != nil) {
            return found;
        }
        if (tableRow.repeat != nil) {
            return tableRow.repeat;   // a repeat row's static cell still names the repeat
        }
    }
    // group boxes, innermost (smallest) first
    XFControl *box = nil;
    CGFloat boxArea = CGFLOAT_MAX;
    for (NSView *sub in [self subviews]) {
        XFControl *bound = objc_getAssociatedObject(sub, kXFBoundControlKey);
        if (bound == nil || [sub isHidden] || !NSPointInRect(point, [sub frame])) {
            continue;
        }
        CGFloat area = NSWidth([sub frame]) * NSHeight([sub frame]);
        if (area < boxArea) {
            boxArea = area;
            box = bound;
        }
    }
    return box;
}

- (NSXMLElement *)svgElementAtPoint:(NSPoint)point
{
    for (XFSVGView *svg in self.svgViews) {
        if ([svg superview] == nil || ![svg isKindOfClass:[XFSVGView class]]
            || !NSPointInRect(point, [svg frame])) {
            continue;
        }
        NSXMLElement *element = [svg hostElementAtPoint:
            [svg convertPoint:point fromView:self]];
        if (element != nil) {
            return element;
        }
    }
    return nil;
}

- (NSRect)layoutFrameOfSVGElement:(NSXMLElement *)element
{
    NSRect out = NSZeroRect;
    for (XFSVGView *svg in self.svgViews) {
        if ([svg superview] == nil) {
            continue;
        }
        NSRect r = [svg frameOfHostElement:element];
        if (!NSIsEmptyRect(r)) {
            r = [self convertRect:r fromView:svg];
            out = NSIsEmptyRect(out) ? r : NSUnionRect(out, r);
        }
    }
    return out;
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
