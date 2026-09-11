#import <AppKit/AppKit.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFProcessor;
@class XFGroup;
@class XFControl;

NS_ASSUME_NONNULL_BEGIN

/// Lays out the control tree with stock AppKit widgets
/// (NSTextField, NSSecureTextField, NSTextView, NSButton, NSPopUpButton,
/// NSSlider, NSBox, NSDatePicker). Shared between GNUstep GUI and Apple AppKit.
@interface XFFormView : NSView

@property (nonatomic, strong, readonly) XFProcessor *processor;
@property (nonatomic, copy, nullable) void (^documentReplaceHandler)(NSString *xml);
/// Called after any user interaction that went through the processor
/// (value commit, trigger, selection, ...): the instance data may have
/// changed, so hosts can refresh live views of it.
@property (nonatomic, copy, nullable) void (^instanceChangedHandler)(void);

- (instancetype)initWithProcessor:(XFProcessor *)processor;
/// A view for the content of one container only (an `xf:dialog` shown by
/// the host, G-93); nil lays out the whole host body.
- (instancetype)initWithProcessor:(XFProcessor *)processor rootGroup:(nullable XFGroup *)rootGroup;
@property (nonatomic, strong, readonly, nullable) XFGroup *rootGroup;

/// Refresh the controls, rebuild the widgets and call instanceChangedHandler.
- (void)reloadFromProcessor;
/// Rebuild the widgets from the current control state only (for a host
/// that refreshed the processor itself, e.g. after another view's edit).
- (void)rebuildWidgets;

/* Design-support introspection: the current layout's geometry, for hosts
   that draw editing overlays on top of the form (a designer's hit-test /
   selection-highlight mode). Purely read-only — the form view itself has
   no editing UI. */

/// The rectangle the current layout gave `control`, in the form view's
/// coordinates: the union of its widget views and labels (all of them for
/// multi-widget controls such as full-appearance selects), the group box
/// for a group, the cell rectangle for a control shown inside a host
/// <table>, and the union of the children for containers with no visual
/// of their own (repeat, switch). NSZeroRect when the control is not laid
/// out (e.g. non-relevant).
- (NSRect)layoutFrameOfControl:(XFControl *)control;

/// The innermost laid-out control whose rectangle contains `point` (form
/// view coordinates): widgets first (label and field count as the
/// widget), then cells of host <table>s, then group boxes. nil over
/// plain host markup or empty space.
- (nullable XFControl *)controlAtPoint:(NSPoint)point;

/// The host element of the SVG shape painted at `point` (form-view
/// coordinates) — an editing overlay checks this before controlAtPoint:,
/// since SVG shapes are painted geometry, not widgets. nil off SVG or
/// over an SVG's empty space.
- (nullable XFXMLElement *)svgElementAtPoint:(NSPoint)point;

/// The union of the rectangles the layout's SVG views paint for
/// `element` (a repeat template element paints once per item), in
/// form-view coordinates. NSZeroRect when nothing paints it.
- (NSRect)layoutFrameOfSVGElement:(XFXMLElement *)element;

@end

NS_ASSUME_NONNULL_END
