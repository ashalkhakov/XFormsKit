/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDPreviewViewController.h"
#import <XFormsKit/XFXMLTypes.h>
#import "XFDEventsConsole.h"
#import "XFDXPathField.h"

@interface XFDPreviewViewController ()
@property (nonatomic, strong, readwrite) XFFormView *formView;
@property (nonatomic, strong, readwrite) XFDDesignOverlay *designOverlay;
@property (nonatomic, strong, readwrite) NSTextView *sourceView;
@end

@implementation XFDPreviewViewController {
    NSScrollView *_previewScroll;
}

- (instancetype)initWithFormEditor:(XFDFormEditor *)formEditor nibName:(NSString *)nibName
{
    if ((self = [super initWithFormEditor:formEditor nibName:nibName])) {
        _showsSource = YES;
        _showsEventsConsoleButton = YES;
    }
    return self;
}

- (void)viewDidLoadFromNib
{
    [self.modeControl setSelectedSegment:0];

    // the live preview and the source text view are code: the XIB keeps
    // their hosts
    _previewScroll = [[NSScrollView alloc] initWithFrame:[self.previewHost bounds]];
    [_previewScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_previewScroll setHasVerticalScroller:YES];
    [_previewScroll setHasHorizontalScroller:YES];
    [_previewScroll setBorderType:NSNoBorder];
    [self.previewHost addSubview:_previewScroll];

    // the design overlay: a sibling ABOVE the scroll view, hidden until
    // the Design checkbox turns the element picker on
    self.designOverlay = [[XFDDesignOverlay alloc] initWithFrame:[self.previewHost bounds]];
    [self.designOverlay setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    self.designOverlay.delegate = self;
    self.designOverlay.scrollView = _previewScroll;
    [self.previewHost addSubview:self.designOverlay];

    NSScrollView *sourceScroll = [[NSScrollView alloc] initWithFrame:[self.sourceHost bounds]];
    [sourceScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [sourceScroll setHasVerticalScroller:YES];
    [sourceScroll setBorderType:NSNoBorder];
    NSTextView *text = [[NSTextView alloc] initWithFrame:
        NSMakeRect(0, 0, [sourceScroll contentSize].width, [sourceScroll contentSize].height)];
    [text setFont:[NSFont userFixedPitchFontOfSize:11]];
    [text setRichText:NO];
    [text setAllowsUndo:YES];
    [text setVerticallyResizable:YES];
    [text setHorizontallyResizable:NO];
    [text setAutoresizingMask:NSViewWidthSizable];
    [[text textContainer] setWidthTracksTextView:YES];
    [sourceScroll setDocumentView:text];
    [self.sourceHost addSubview:sourceScroll];
    self.sourceView = text;

    [self buildFormView];
    [self showControls];
}

- (void)setShowsSource:(BOOL)showsSource
{
    _showsSource = showsSource;
    [self showControls];
}

- (void)setShowsEventsConsoleButton:(BOOL)shows
{
    _showsEventsConsoleButton = shows;
    [self showControls];
}

/// The controls a host wants, the others hidden; Design and the console
/// button move left when Form / Source goes.
- (void)showControls
{
    if (![self isViewLoaded]) {
        return;
    }
    if (!self.showsSource && [self.centerTabView indexOfTabViewItem:[self.centerTabView selectedTabViewItem]] != 0) {
        [self.modeControl setSelectedSegment:0];
        [self.centerTabView selectTabViewItemAtIndex:0];
    }
    [self.modeControl setHidden:!self.showsSource];
    [self.consoleButton setHidden:!self.showsEventsConsoleButton];
    CGFloat x = self.showsSource ? NSMaxX([self.modeControl frame]) + 8 : NSMinX([self.modeControl frame]);
    NSRect design = [self.designModeCheckbox frame];
    design.origin.x = x;
    [self.designModeCheckbox setFrame:design];
    NSRect console = [self.consoleButton frame];
    console.origin.x = NSMaxX(design) + 8;
    [self.consoleButton setFrame:console];
}

- (void)buildFormView
{
    self.formView = [[XFFormView alloc] initWithProcessor:self.formEditor.processor];
    [_previewScroll setDocumentView:self.formView];
}

- (void)refreshSourceText
{
    [self.sourceView setString:[self.formEditor hostXMLString] ?: @""];
}

- (BOOL)showsSourceTab
{
    return [self.centerTabView indexOfTabViewItem:[self.centerTabView selectedTabViewItem]] == 1;
}

#pragma mark The form editor's news

- (void)formEditorSelectionDidChange:(XFDFormEditor *)editor
{
    (void)editor;
    [self.designOverlay setNeedsDisplay:YES];
}

- (void)formEditor:(XFDFormEditor *)editor hostDidChange:(XFXMLElement *)element
{
    (void)editor;
    (void)element;
    [self.formView rebuildWidgets];
    [self.designOverlay setNeedsDisplay:YES];
    if ([self showsSourceTab]) {
        [self refreshSourceText];
    }
}

- (void)formEditorProcessorWasReplaced:(XFDFormEditor *)editor
{
    (void)editor;
    if ([self isViewLoaded]) {
        [self buildFormView];
        [self.designOverlay setNeedsDisplay:YES];
    }
}

#pragma mark Form / Source, Design

- (IBAction)modeChanged:(id)sender
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
    NSWindow *window = [[self view] window];
    [self.designOverlay setHidden:!on];
    [window setAcceptsMouseMovedEvents:on];
    if (on) {
        [window makeFirstResponder:self.designOverlay];
        [self.designOverlay refreshHighlights];
    } else if ([window firstResponder] == self.designOverlay) {
        [window makeFirstResponder:nil];
    }
}

- (IBAction)toggleEventsConsole:(id)sender
{
    (void)sender;
    // the XSLTForms F1 console: the trace sink is the engine's, so the
    // console follows preview rebuilds; the duplicate-id scan runs against
    // the host document when it opens, as the original's does
    [[XFDEventsConsole sharedConsole] toggleWithHostDocument:self.formEditor.processor.hostDocument];
}

- (IBAction)applySource:(id)sender
{
    (void)sender;
    NSError *error = nil;
    if (![self.formEditor applySourceXMLString:[self.sourceView string] error:&error]) {
        [self presentError:error];
    }
}

- (IBAction)resetInstances:(id)sender
{
    (void)sender;
    NSError *error = nil;
    if (![self.formEditor resetPreview:&error]) {
        [self presentError:error];
    }
}

#pragma mark The design overlay (the element picker)

- (XFFormView *)formViewForOverlay:(id)overlay
{
    (void)overlay;
    return self.formView;
}

- (XFXMLElement *)selectedElementForOverlay:(id)overlay
{
    (void)overlay;
    return self.formEditor.selection;
}

- (void)overlay:(id)overlay pickedElement:(XFXMLElement *)element
{
    (void)overlay;
    // widget hits come through control.element (repeat-item and
    // table-cell controls instantiate straight from host children, so
    // that IS the host element); SVG hits are host elements already
    if (element != nil && [element rootDocument] == self.formEditor.processor.hostDocument) {
        self.formEditor.selection = element;
    }
}

static NSDictionary *XFDDropSlot(XFXMLElement *parent, NSInteger index, NSRect line)
{
    return @{ @"parent": parent, @"index": @(index),
              @"line": [NSValue valueWithRect:line] };
}

static NSString * const XFDSVGNamespaceURI = @"http://www.w3.org/2000/svg";

/// The zone gate the drop slots use: XForms elements follow XFHostEdit's
/// insertion zones; SVG shapes reorder freely among SVG parents (the
/// engine's moveElement applies the same rule).
static BOOL XFDZoneAccepts(XFXMLElement *dragged, XFXMLElement *parent)
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
               forElement:(XFXMLElement *)dragged
{
    (void)overlay;
    XFFormView *form = self.formView;
    XFXMLDocument *host = self.formEditor.processor.hostDocument;
    if (form == nil || dragged == nil || [dragged rootDocument] != host) {
        return nil;
    }

    NSDictionary * (^siblingSlot)(XFXMLElement *, NSRect, BOOL) =
        ^NSDictionary *(XFXMLElement *te, NSRect r, BOOL before) {
        XFXMLElement *parent = (XFXMLElement *)[te parent];
        if ([parent kind] != XFXMLElementKind || !XFDZoneAccepts(dragged, parent)) {
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

    XFXMLElement *te = [form svgElementAtPoint:fp];
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
        for (XFXMLNode *walk = te; walk != nil; walk = [walk parent]) {
            if (walk == dragged) {
                return nil;
            }
        }
        if ([te rootDocument] != host) {
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
    XFXMLElement *body = [self.formEditor bodyElement];
    if (body == nil || !XFDZoneAccepts(dragged, body)) {
        return nil;
    }
    CGFloat maxY = 0;
    for (XFControl *top in self.formEditor.processor.controls) {
        NSRect r = [form layoutFrameOfControl:top];
        if (!NSIsEmptyRect(r)) {
            maxY = MAX(maxY, NSMaxY(r));
        }
    }
    if (fp.y <= maxY + 4) {
        return nil;
    }
    // a no-op when the dragged element already closes the body
    XFXMLNode *lastChild = [body childCount] ? [body childAtIndex:[body childCount] - 1] : nil;
    if (lastChild == dragged) {
        return nil;
    }
    NSRect line = NSMakeRect(8, maxY + 6, MAX(NSWidth([form bounds]) - 16, 120), 3);
    return XFDDropSlot(body, -1, line);
}

- (void)overlay:(id)overlay dropElement:(XFXMLElement *)dragged slot:(NSDictionary *)slot
{
    (void)overlay;
    XFXMLElement *parent = slot[@"parent"];
    if (dragged == nil || parent == nil) {
        return;
    }
    if (![self.formEditor moveElement:dragged underParent:parent
                              atIndex:[slot[@"index"] integerValue]]) {
        XFDBeep();
    }
}

@end
