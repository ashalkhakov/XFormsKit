/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* The center pane: the Form / Source toggle, the live preview's design
   mode (the devtools-style element picker â overlay delegate, pick,
   drag-reorder drop slots), and the XML source view. */
#import "XFDWindowControllerPriv.h"
#import "XFDDocument.h"

@implementation XFDWindowController (XFDPreview)

- (void)buildFormView
{
    self.formView = [[XFFormView alloc] initWithProcessor:[self processor]];
    [self.previewScroll setDocumentView:self.formView];
}

#pragma mark - Center pane (Form / Source)

- (IBAction)modeChanged:(NSSegmentedControl *)sender
{
    NSInteger mode = [sender selectedSegment];
    if (mode == 1) {
        [self refreshSourceText];
    }
    [self.centerTabView selectTabViewItemAtIndex:mode];
}

- (IBAction)toggleDesignMode:(id)sender
{
    (void)sender;
    BOOL on = [self.designModeCheckbox state] == NSOnState;
    [self.designOverlay setHidden:!on];
    [[self window] setAcceptsMouseMovedEvents:on];
    if (on) {
        [[self window] makeFirstResponder:self.designOverlay];
        [self.designOverlay refreshHighlights];
    } else if ([[self window] firstResponder] == self.designOverlay) {
        [[self window] makeFirstResponder:nil];
    }
}

#pragma mark - Design overlay (the element picker)

- (XFFormView *)formViewForOverlay:(id)overlay
{
    (void)overlay;
    return self.formView;
}

- (NSXMLElement *)selectedElementForOverlay:(id)overlay
{
    (void)overlay;
    return self.selected;
}

- (void)overlay:(id)overlay pickedElement:(NSXMLElement *)element
{
    (void)overlay;
    // widget hits come through control.element (repeat-item and
    // table-cell controls instantiate straight from host children, so
    // that IS the host element); SVG hits are host elements already
    if (element != nil && [element rootDocument] == [self processor].hostDocument) {
        [self selectElement:element];
    }
}

- (NSXMLElement *)bodyElement
{
    for (NSXMLNode *c in [[self rootElement] children]) {
        if ([c kind] == NSXMLElementKind
            && [[(NSXMLElement *)c localName] isEqualToString:@"body"]) {
            return (NSXMLElement *)c;
        }
    }
    return nil;
}

static NSDictionary *XFDDropSlot(NSXMLElement *parent, NSInteger index, NSRect line)
{
    return @{ @"parent": parent, @"index": @(index),
              @"line": [NSValue valueWithRect:line] };
}

static NSString * const XFDSVGNamespaceURI = @"http://www.w3.org/2000/svg";

/// The zone gate the drop slots use: XForms elements follow XFHostEdit's
/// insertion zones; SVG shapes reorder freely among SVG parents (the
/// engine's moveElement applies the same rule).
static BOOL XFDZoneAccepts(NSXMLElement *dragged, NSXMLElement *parent)
{
    if ([[dragged URI] isEqualToString:XFDSVGNamespaceURI]) {
        return [[parent URI] isEqualToString:XFDSVGNamespaceURI];
    }
    return [XFHostEdit canInsertElementNamed:[dragged localName] underParent:parent];
}

/// The drop slot for dragging `dragged` over `fp` (form-view coords):
/// hover a widget's or SVG shape's edge bands to become its sibling
/// (before / after), hover a container's middle to drop inside it,
/// hover below everything to land at the end of the body. nil = nothing
/// may drop here.
- (NSDictionary *)overlay:(id)overlay dropSlotAtFormPoint:(NSPoint)fp
               forElement:(NSXMLElement *)dragged
{
    (void)overlay;
    XFFormView *form = self.formView;
    if (form == nil || dragged == nil
        || [dragged rootDocument] != [self processor].hostDocument) {
        return nil;
    }
    NSString *local = [dragged localName];
    (void)local;

    NSDictionary * (^siblingSlot)(NSXMLElement *, NSRect, BOOL) =
        ^NSDictionary *(NSXMLElement *te, NSRect r, BOOL before) {
        NSXMLElement *parent = (NSXMLElement *)[te parent];
        if ([parent kind] != NSXMLElementKind || !XFDZoneAccepts(dragged, parent)) {
            return nil;
        }
        NSInteger index = (NSInteger)[te index] + (before ? 0 : 1);
        if (parent == [dragged parent]) {
            NSInteger own = (NSInteger)[dragged index];
            if (index == own || index == own + 1) {
                return nil;   // dropping right where it already is
            }
        }
        CGFloat y = before ? NSMinY(r) - 3 : NSMaxY(r) + 1;
        return XFDDropSlot(parent, index,
                           NSMakeRect(NSMinX(r) - 4, y, NSWidth(r) + 8, 3));
    };

    NSXMLElement *te = [form svgElementAtPoint:fp];
    NSRect targetRect = NSZeroRect;
    if (te != nil) {
        targetRect = [form layoutFrameOfSVGElement:te];
    } else {
        XFControl *target = [form controlAtPoint:fp];
        te = target.element;
        if (target != nil) {
            targetRect = [form layoutFrameOfControl:target];
        }
    }
    if (te != nil && te != dragged) {
        // never into (or beside a node inside) the dragged subtree
        for (NSXMLNode *walk = te; walk != nil; walk = [walk parent]) {
            if (walk == dragged) {
                return nil;
            }
        }
        if ([te rootDocument] != [self processor].hostDocument) {
            return nil;
        }
        NSRect r = targetRect;
        if (NSIsEmptyRect(r)) {
            return nil;
        }
        CGFloat band = MIN(8.0, NSHeight(r) / 3.0);
        if (fp.y < NSMinY(r) + band) {
            return siblingSlot(te, r, YES);
        }
        if (fp.y > NSMaxY(r) - band) {
            return siblingSlot(te, r, NO);
        }
        // middle: into the target when its zone takes this kind
        // (containers — group, case, repeat, and SVG parents for SVG
        // shapes); plain widgets refuse and fall back to the nearer edge
        if (XFDZoneAccepts(dragged, te)) {
            NSRect line = NSMakeRect(NSMinX(r) + 6, NSMaxY(r) - 8,
                                     NSWidth(r) - 12, 3);
            return XFDDropSlot(te, -1, line);
        }
        return siblingSlot(te, r, fp.y < NSMidY(r));
    }

    // over empty space below the last widget: append to the body
    NSXMLElement *body = [self bodyElement];
    if (body == nil || !XFDZoneAccepts(dragged, body)) {
        return nil;
    }
    CGFloat maxY = 0;
    for (XFControl *top in [self processor].controls) {
        NSRect r = [form layoutFrameOfControl:top];
        if (!NSIsEmptyRect(r)) {
            maxY = MAX(maxY, NSMaxY(r));
        }
    }
    if (fp.y <= maxY + 4) {
        return nil;
    }
    // a no-op when the dragged element already closes the body
    NSXMLNode *lastChild = [body childCount] ? [body childAtIndex:[body childCount] - 1] : nil;
    if (lastChild == dragged) {
        return nil;
    }
    NSRect line = NSMakeRect(8, maxY + 6, MAX(NSWidth([form bounds]) - 16, 120), 3);
    return XFDDropSlot(body, -1, line);
}

- (void)overlay:(id)overlay dropElement:(NSXMLElement *)dragged slot:(NSDictionary *)slot
{
    (void)overlay;
    NSXMLElement *parent = slot[@"parent"];
    if (dragged == nil || parent == nil) {
        return;
    }
    NSUndoManager *undo = [[self document] undoManager];
    [undo beginUndoGrouping];
    BOOL moved = [[self formDocument].hostEdit moveElement:dragged
                                              underParent:parent
                                                  atIndex:[slot[@"index"] integerValue]];
    [undo endUndoGrouping];
    if (moved) {
        [self selectElement:dragged];
    } else {
        XFDBeep();
    }
}

- (void)refreshSourceText
{
    [self.sourceView setString:[[self formDocument] hostXMLString] ?: @""];
}

- (IBAction)applySource:(id)sender
{
    (void)sender;
    NSError *error = nil;
    if (![[self formDocument] applySourceXML:[self.sourceView string] error:&error]) {
        [self presentError:error];
    }
}

- (IBAction)resetInstances:(id)sender
{
    (void)sender;
    NSError *error = nil;
    if (![[self formDocument] resetPreview:&error]) {
        [self presentError:error];
    }
}

@end

void XFDWindowControllerPreviewFilePresent(void) {}
