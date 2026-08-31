/* Design-mode overlay — the devtools-style element picker over the live
   preview. A transparent view that sits over the preview scroll view's
   content area: while design mode is on it swallows the mouse, hit-tests
   clicks through XFFormView's layout introspection (controlAtPoint:) and
   hands the picked control's HOST element to the window controller;
   hovering highlights the control under the pointer with its tag name.
   While design mode is off the overlay is hidden and the form behaves
   live, exactly as before — the two modes are the browser debugger's
   "inspect element" arrow vs. plain page interaction.

   The overlay lives OUTSIDE the form view (a sibling of the scroll view)
   on purpose: XFFormView's rebuild wipes all of its subviews, so an
   overlay inside it would be torn down on every host edit. Geometry is
   converted through the view hierarchy per draw, so scrolling and
   rebuilds never leave a stale highlight; a bounds-change observer on
   the clip view redraws on every scroll.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>

@class XFControl;
@class XFFormView;

@protocol XFDDesignOverlayDelegate <NSObject>
/// The form view to hit-test and highlight against (nil disables).
- (XFFormView *)formViewForOverlay:(id)overlay;
/// The current inspector selection (the overlay borders its frame).
- (NSXMLElement *)selectedElementForOverlay:(id)overlay;
/// A click picked this host element — select it.
- (void)overlay:(id)overlay pickedElement:(NSXMLElement *)element;
/// The drop slot for dragging `element` over this form-view point, nil
/// when nothing may drop there (invalid zone, inside its own subtree).
/// Keys: parent (NSXMLElement), index (NSNumber, child-node index into
/// the pre-move tree, -1 appends), line (NSValue — the insertion
/// marker's rectangle in FORM-VIEW coordinates).
- (NSDictionary *)overlay:(id)overlay dropSlotAtFormPoint:(NSPoint)point
               forElement:(NSXMLElement *)element;
/// Perform the move a completed drag chose.
- (void)overlay:(id)overlay dropElement:(NSXMLElement *)element
           slot:(NSDictionary *)slot;
@end

@interface XFDDesignOverlay : NSView

@property (nonatomic, weak) id<XFDDesignOverlayDelegate> delegate;
/// The scroll view whose content area the overlay covers; the overlay
/// observes its clip view to redraw on scroll and forwards wheel events
/// so the form still scrolls in design mode.
@property (nonatomic, weak) NSScrollView *scrollView;
/// The host element under the pointer — widget controls' elements and
/// SVG shapes alike (read by the selftest).
@property (nonatomic, strong, readonly) NSXMLElement *hoverElement;

/// Recompute the hover for the current pointer location and redraw.
- (void)refreshHighlights;

@end
