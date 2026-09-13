/* XFDDesignOverlay.m — see the header for the design. Element-centric
   since ms58: the hit test asks the form view for SVG shapes first
   (painted geometry), then widgets — so a pie wedge picks exactly like
   an input row.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDDesignOverlay.h"
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFFormView.h>

@interface XFDDesignOverlay ()
@property (nonatomic, strong, readwrite) XFXMLElement *hoverElement;
/* Drag-reorder state: a press remembers its element; crossing the drag
   threshold turns the gesture into a move (insertion marker follows the
   pointer), releasing without it is the click that picks. */
@property (nonatomic, strong) XFXMLElement *pressElement;
@property (nonatomic, assign) NSPoint pressPoint;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, copy) NSDictionary *dropSlot;
@end

@implementation XFDDesignOverlay

static NSColor *XFDOverlayAccent(void)
{
    if ([[NSColor class] respondsToSelector:@selector(systemBlueColor)]) {
        return [[NSColor class] performSelector:@selector(systemBlueColor)];
    }
    return [NSColor colorWithCalibratedRed:0.16 green:0.45 blue:0.86 alpha:1.0];
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self setHidden:YES];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return ![self isHidden];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    (void)event;
    return YES;
}

- (void)setScrollView:(NSScrollView *)scrollView
{
    NSClipView *old = [_scrollView contentView];
    if (old != nil) {
        [[NSNotificationCenter defaultCenter]
            removeObserver:self name:NSViewBoundsDidChangeNotification object:old];
    }
    _scrollView = scrollView;
    NSClipView *clip = [scrollView contentView];
    if (clip != nil) {
        [clip setPostsBoundsChangedNotifications:YES];
        [[NSNotificationCenter defaultCenter]
            addObserver:self selector:@selector(clipBoundsChanged:)
                   name:NSViewBoundsDidChangeNotification object:clip];
    }
}

- (void)clipBoundsChanged:(NSNotification *)note
{
    (void)note;
    if (![self isHidden]) {
        [self refreshHighlights];
    }
}

/// The overlay covers the whole scroll view, scrollers included — let
/// clicks over a visible scroller fall through to it so scrolling by
/// scroller keeps working in design mode.
- (NSView *)hitTest:(NSPoint)point
{
    NSView *hit = [super hitTest:point];
    if (hit != self || self.scrollView == nil) {
        return hit;
    }
    NSPoint wp = [[self superview] convertPoint:point toView:nil];
    NSScroller *scrollers[2] = { [self.scrollView verticalScroller],
                                 [self.scrollView horizontalScroller] };
    for (NSUInteger i = 0; i < 2; i++) {
        NSScroller *s = scrollers[i];
        if (s == nil || [s isHidden] || [s superview] == nil) {
            continue;
        }
        if (NSPointInRect([s convertPoint:wp fromView:nil], [s bounds])) {
            return nil;   // the scroll view's own hit test finds the scroller
        }
    }
    return self;
}

#pragma mark - Geometry

- (XFFormView *)formView
{
    return [self.delegate formViewForOverlay:self];
}

/// A form-view rectangle in the overlay's coordinates (empty when the
/// form view is gone or the rectangle is).
- (NSRect)overlayRectOfFormRect:(NSRect)rect
{
    XFFormView *form = [self formView];
    if (form == nil || [form window] != [self window] || NSIsEmptyRect(rect)) {
        return NSZeroRect;
    }
    return [self convertRect:[form convertRect:rect toView:nil] fromView:nil];
}

/// The host element painted or laid out at an overlay point: SVG shapes
/// first, then widgets.
- (XFXMLElement *)elementAtOverlayPoint:(NSPoint)point
{
    XFFormView *form = [self formView];
    if (form == nil || [form window] != [self window]) {
        return nil;
    }
    NSPoint fp = [form convertPoint:[self convertPoint:point toView:nil] fromView:nil];
    XFXMLElement *svg = [form svgElementAtPoint:fp];
    if (svg != nil) {
        return svg;
    }
    return [[form controlAtPoint:fp] element];
}

/// The rectangle an element occupies in form coordinates: its widget's
/// layout frame when it is a control, its painted SVG frame otherwise.
- (NSRect)formFrameOfElement:(XFXMLElement *)element
{
    XFFormView *form = [self formView];
    if (form == nil || element == nil) {
        return NSZeroRect;
    }
    XFControl *control = [form.processor controlForElement:element];
    NSRect r = control != nil ? [form layoutFrameOfControl:control] : NSZeroRect;
    if (NSIsEmptyRect(r)) {
        r = [form layoutFrameOfSVGElement:element];
    }
    return r;
}

#pragma mark - Events

- (void)mouseDown:(NSEvent *)event
{
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    self.pressPoint = p;
    self.pressElement = [self elementAtOverlayPoint:p];
    self.dragging = NO;
    self.dropSlot = nil;
    self.hoverElement = self.pressElement;
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event
{
    if (self.pressElement == nil) {
        return;
    }
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    if (!self.dragging) {
        if (fabs(p.x - self.pressPoint.x) < 4 && fabs(p.y - self.pressPoint.y) < 4) {
            return;   // still a click
        }
        self.dragging = YES;
        self.hoverElement = nil;
    }
    XFFormView *form = [self formView];
    NSDictionary *slot = nil;
    if (form != nil && [form window] == [self window]) {
        NSPoint fp = [form convertPoint:[self convertPoint:p toView:nil] fromView:nil];
        slot = [self.delegate overlay:self dropSlotAtFormPoint:fp
                           forElement:self.pressElement];
    }
    self.dropSlot = slot;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event
{
    (void)event;
    XFXMLElement *element = self.pressElement;
    BOOL dragged = self.dragging;
    NSDictionary *slot = self.dropSlot;
    self.pressElement = nil;
    self.dragging = NO;
    self.dropSlot = nil;
    if (element == nil) {
        [self setNeedsDisplay:YES];
        return;
    }
    if (dragged) {
        if (slot != nil) {
            [self.delegate overlay:self dropElement:element slot:slot];
        }
        [self setNeedsDisplay:YES];
        return;
    }
    // no drag: the press was the click that picks
    [self.delegate overlay:self pickedElement:element];
    [self setNeedsDisplay:YES];
}

- (void)mouseMoved:(NSEvent *)event
{
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    XFXMLElement *element = NSPointInRect(p, [self bounds])
        ? [self elementAtOverlayPoint:p] : nil;
    if (element != self.hoverElement) {
        self.hoverElement = element;
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseExited:(NSEvent *)event
{
    (void)event;
    if (self.hoverElement != nil) {
        self.hoverElement = nil;
        [self setNeedsDisplay:YES];
    }
}

- (void)scrollWheel:(NSEvent *)event
{
    // design mode must not kill scrolling — hand the wheel to the scroll
    // view (the bounds-change observer repaints the highlights)
    if (self.scrollView != nil) {
        [self.scrollView scrollWheel:event];
    } else {
        [super scrollWheel:event];
    }
}

- (void)refreshHighlights
{
    NSWindow *window = [self window];
    // querying the pointer needs a display server — headless GNUstep
    // raises subclassResponsibility (the NSBeep hang family), so the
    // selftest keeps whatever hover it set programmatically
    if (window != nil && getenv("XFD_SELFTEST") == NULL) {
        NSPoint p = [self convertPoint:[window mouseLocationOutsideOfEventStream]
                              fromView:nil];
        self.hoverElement = NSPointInRect(p, [self bounds])
            ? [self elementAtOverlayPoint:p] : nil;
    }
    [self setNeedsDisplay:YES];
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirty
{
    (void)dirty;
    NSColor *accent = XFDOverlayAccent();
    XFFormView *form = [self formView];
    if (form == nil) {
        return;
    }

    if (self.dragging) {
        // the source keeps a dashed ghost; the insertion marker shows
        // where the drop would land (no marker = nothing may drop here)
        NSRect ghost = [self overlayRectOfFormRect:
            [self formFrameOfElement:self.pressElement]];
        if (!NSIsEmptyRect(ghost)) {
            [[accent colorWithAlphaComponent:0.7] setStroke];
            NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSInsetRect(ghost, -2, -2)];
            CGFloat dashes[2] = { 5.0, 3.0 };
            [path setLineDash:dashes count:2 phase:0];
            [path setLineWidth:1.5];
            [path stroke];
        }
        NSValue *lineValue = self.dropSlot[@"line"];
        if (lineValue != nil) {
            NSRect line = [self overlayRectOfFormRect:[lineValue rectValue]];
            if (!NSIsEmptyRect(line)) {
                [accent setFill];
                NSRectFillUsingOperation(line, NSCompositeSourceOver);
                // end caps, the classic reorder marker
                NSRect cap = NSMakeRect(NSMinX(line) - 2, NSMidY(line) - 3, 3, 7);
                NSRectFillUsingOperation(cap, NSCompositeSourceOver);
                cap.origin.x = NSMaxX(line) - 1;
                NSRectFillUsingOperation(cap, NSCompositeSourceOver);
            }
        }
        return;   // no hover / selection chrome while dragging
    }

    // hover: filled wash + tag badge, the devtools inspect look
    XFXMLElement *hover = self.hoverElement;
    if (hover != nil) {
        NSRect r = [self overlayRectOfFormRect:[self formFrameOfElement:hover]];
        if (!NSIsEmptyRect(r)) {
            [[accent colorWithAlphaComponent:0.12] setFill];
            NSRectFillUsingOperation(NSInsetRect(r, -2, -2), NSCompositeSourceOver);
            [[accent colorWithAlphaComponent:0.8] setStroke];
            NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSInsetRect(r, -2, -2)];
            [path setLineWidth:1.0];
            [path stroke];
            [self drawTag:[self tagForElement:hover] atRect:r];
        }
    }

    // selection: a firm border around the inspector's current element
    XFXMLElement *selected = [self.delegate selectedElementForOverlay:self];
    if (selected != nil && selected != hover) {
        NSRect r = [self overlayRectOfFormRect:[self formFrameOfElement:selected]];
        if (!NSIsEmptyRect(r)) {
            [accent setStroke];
            NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSInsetRect(r, -3, -3)];
            [path setLineWidth:2.0];
            [path stroke];
        }
    }
}

- (NSString *)tagForElement:(XFXMLElement *)e
{
    NSString *name = [e name] ?: [e localName] ?: @"?";
    NSString *ref = [[e attributeForName:@"ref"] stringValue]
        ?: [[e attributeForName:@"nodeset"] stringValue]
        ?: [[e attributeForName:@"id"] stringValue];
    return ref.length ? [NSString stringWithFormat:@"%@  %@", name, ref] : name;
}

/// The little name plate above the hovered rectangle (clamped inside).
- (void)drawTag:(NSString *)tag atRect:(NSRect)rect
{
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:10],
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };
    NSSize size = [tag sizeWithAttributes:attrs];
    NSRect plate = NSMakeRect(NSMinX(rect) - 2, NSMinY(rect) - size.height - 8,
                              size.width + 10, size.height + 5);
    if (NSMinY(plate) < 0) {
        plate.origin.y = NSMinY(rect) + 2;   // no room above — tuck inside
    }
    if (NSMaxX(plate) > NSMaxX([self bounds])) {
        plate.origin.x = MAX(0, NSMaxX([self bounds]) - NSWidth(plate));
    }
    [XFDOverlayAccent() setFill];
    NSRectFillUsingOperation(plate, NSCompositeSourceOver);
    [tag drawAtPoint:NSMakePoint(NSMinX(plate) + 5, NSMinY(plate) + 2)
      withAttributes:attrs];
}

@end
