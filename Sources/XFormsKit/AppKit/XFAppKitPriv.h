// XFAppKitPriv.h — shared internals of the AppKit form view layer.
// The one header every file split out of XFFormView.m imports: layout
// constants, the widget/atom bookkeeping classes, the table / list box
// adapters, the rich text editor, the XFFormView class extension and
// the category interfaces of the split implementation files.

#ifndef XF_APPKIT_PRIV_H
#define XF_APPKIT_PRIV_H

#import "XFFormView.h"
#import <XFormsKit/XFXMLTypes.h>
#import "XFRichText.h"
#import "XFSVG.h"
#import "XFProcessor.h"
#import <objc/runtime.h>
#import "XFControl.h"
#import "XFInputControl.h"
#import "XFOutputControl.h"
#import "XFSecretControl.h"
#import "XFTextareaControl.h"
#import "XFTriggerControl.h"
#import "XFSubmitControl.h"
#import "XFSelectControl.h"
#import "XFRangeControl.h"
#import "XFLabelControl.h"
#import "XFVarControl.h"
#import "XFDialog.h"
#import "XFUploadControl.h"
#import "XFGroup.h"
#import "XFRepeat.h"
#import "XFSwitch.h"
#import "XFNodeState.h"
#import "XFXMLEvents.h"
#import "XFModel.h"
#import "XFSubmission.h"
#import "XFHostNode.h"
#import "XFTableModel.h"
#import "XFType.h"
#import "XFXML.h"

/// Associated-object key tying a cell view back to its XFControl.
FOUNDATION_EXPORT const void *kXFBoundControlKey;
/// Associated-object key holding the reconciliation key of a table adapter
/// or SVG view (widgets carry theirs in XFWidget.key).
FOUNDATION_EXPORT const void *kXFReconcileKey;

/// Layout constants (defined in XFFormView.m).
FOUNDATION_EXPORT const CGFloat kLabelWidth;
FOUNDATION_EXPORT const CGFloat kRowHeight;
FOUNDATION_EXPORT const CGFloat kTextareaHeight;
FOUNDATION_EXPORT const CGFloat kRowGap;
FOUNDATION_EXPORT const CGFloat kMargin;
FOUNDATION_EXPORT const CGFloat kIndent;
FOUNDATION_EXPORT const CGFloat kFieldWidth;
FOUNDATION_EXPORT const CGFloat kInlineFieldWidth;
FOUNDATION_EXPORT const CGFloat kLineGap;
FOUNDATION_EXPORT const CGFloat kWrapWidth;

typedef NS_ENUM(NSInteger, XFAtomKind) {
    XFAtomText,
    XFAtomControl,
    XFAtomBreak,
    XFAtomSpace,   // horizontal gap (between table cells)
};

/// One piece of an inline run: a styled text fragment, an inline control
/// or a line break (the flattened form of an XFHostNode inline subtree).
@interface XFLayoutAtom : NSObject
@property (nonatomic, assign) XFAtomKind kind;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSFont *font;
@property (nonatomic, strong) XFControl *control;
@property (nonatomic, assign) BOOL preformatted;
@end

typedef NS_ENUM(NSInteger, XFBadgeKind) {
    XFBadgeHint,    // grey ⓘ — xf:hint (non-minimal appearance)
    XFBadgeAlert,   // red ! — xf:alert, shown while the control is invalid
};

/// A 14×14 icon after a widget, the port of XSLTForms' hint / alert icons
/// (icones.css: span.xforms-hint-icon always visible, span.xforms-alert-icon
/// only under .xforms-invalid). Drawn with NSBezierPath — no image
/// resources, identical on Apple and GNUstep. Hovering or clicking shows
/// the text in the form view's own floating box (showBadgeInfo:) — the
/// port of XSLTForms' absolutely-positioned span.xforms-*-value hover box;
/// NSToolTipManager is NOT used, its display proved unreliable for plain
/// custom views. Mouse tracking is the classic tracking-rect API, the one
/// both platforms implement (GNUstep has no NSTrackingArea wiring).
@interface XFBadgeView : NSView
@property (nonatomic, assign) XFBadgeKind kind;
/// The hint / alert message the info box shows.
@property (nonatomic, copy) NSString *text;
/// The same content as host markup, when the form wrote any (an xf:hint
/// holding <b> or a heading). The info box draws this instead of `text`.
@property (nonatomic, copy) NSString *markup;
+ (instancetype)badgeWithKind:(XFBadgeKind)kind text:(NSString *)text;
/// Re-adds the mouse tracking rect. Apple converts tracking rects to
/// window coordinates when they are added, so the form view calls this on
/// every scroll of its clip view (GNUstep converts at event time).
- (void)refreshTracking;
@end

/// A filled, 1px-bordered rectangle to host a view in — what
/// `NSTextField bordered:YES` gave the plain hint box, for a box whose
/// content is a text view instead. NSBox is the obvious alternative, but
/// its custom-fill styling is not dependable across GNUstep themes and
/// this is twelve lines.
@interface XFInfoBoxView : NSView
@property (nonatomic, strong) NSColor *fillColor;
@end

@interface XFWidget : NSObject
@property (nonatomic, strong) XFControl *control;
@property (nonatomic, strong) NSView *view;
@property (nonatomic, strong) NSTextField *labelField;
@property (nonatomic, assign) CGFloat height;
/// The widget's identity across layout passes: the control's host element
/// and bound instance node (a repeat item's controls are recreated on every
/// refresh, with the same element and the same node), the repeat items it
/// sits in, and for a full-appearance select the item value. A widget whose
/// key comes up again in the next pass is reused; see -[XFFormView rebuild].
@property (nonatomic, copy) NSString *key;
/// Which kind of view the factory chose for the control (popup, list box,
/// date picker, checkbox ...). Same key with a different variant means the
/// control needs a different view: the old one is retired.
@property (nonatomic, copy) NSString *variant;
/// ⓘ after the widget when the control has a non-minimal hint.
@property (nonatomic, strong) XFBadgeView *hintBadge;
/// Red ! after the widget, hidden unless the control is invalid.
@property (nonatomic, strong) XFBadgeView *alertBadge;
@end

@class XFFormView;

/// Data source / delegate of one host `<table>` shown as a cell-based
/// NSTableView (G-20 phase 2). Cells come from XFTableModel: a control-only
/// cell gets the matching NSCell (text, secure, popup, button, switch,
/// slider), anything else is static text.
@interface XFTableAdapter : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, weak) XFFormView *formView;
@property (nonatomic, strong) XFTableModel *model;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSCell *> *cells;
@property (nonatomic, assign) BOOL selecting;
- (instancetype)initWithModel:(XFTableModel *)model formView:(XFFormView *)formView;
- (NSSize)build;
/// The same table for a freshly built model of the same host `<table>`
/// (the next layout pass): the scroll view and, when the columns still
/// match, the table view are kept and only reloaded. Returns the size
/// like -build.
- (NSSize)rebuildWithModel:(XFTableModel *)model;
- (void)refreshInPlace;
@end

/// Data source / delegate of an appearance="compact" select list box (G-43).
@interface XFListBoxAdapter : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) XFSelectControl *select;
@property (nonatomic, weak) XFFormView *formView;
@property (nonatomic, assign) BOOL selecting;
@end

/* XFRichTextEditor is public now (the designer's label editors need it) —
   see XFRichTextEditor.h. */
#import "XFRichTextEditor.h"

/// The view AppKit focuses for a widget (the field editor host, the
/// scroll view document, or the view itself). Defined in XFFormView.m.
FOUNDATION_EXPORT NSView *XFKeyViewOf(NSView *view);

/// YES when the effective theme is dark: the system appearance on Apple,
/// the theme's text background luminance on GNUstep. Badge and info-box
/// colors are hard values chosen per theme — neither platform has a
/// semantic "pale warning background". Defined in XFFormView.m.
FOUNDATION_EXPORT BOOL XFDarkTheme(void);
/// The color of invalid labels / cells (systemRedColor where it exists —
/// it keeps its contrast in dark mode — plain red elsewhere).
FOUNDATION_EXPORT NSColor *XFInvalidTextColor(void);

@interface XFFormView () <NSTextViewDelegate, NSTextFieldDelegate>
@property (nonatomic, strong, readwrite) XFProcessor *processor;
@property (nonatomic, strong) NSMutableArray<XFWidget *> *widgets;
@property (nonatomic, assign) CGFloat nextY;
@property (nonatomic, assign) CGFloat contentHeight;
/// Right-most edge laid out so far (group boxes and the form width follow it).
@property (nonatomic, assign) CGFloat maxRight;
/// Right edge inline runs wrap at.
@property (nonatomic, assign) CGFloat wrapRight;
/// One adapter per host table in the current layout.
@property (nonatomic, strong) NSMutableArray<XFTableAdapter *> *tables;
/// Debounce timer for `delay` on incremental controls (G-40).
@property (nonatomic, strong) NSTimer *delayTimer;
/// Adapters of compact select list boxes (G-43).
@property (nonatomic, strong) NSMutableArray<XFListBoxAdapter *> *listBoxes;
/// SVG widgets in the current layout (G-20 phase 3) — rebuilt on refresh
/// so AVT and output values stay live.
@property (nonatomic, strong) NSMutableArray *svgViews;
/// The in-scope context node for host markup being laid out (repeat item
/// nodes, a bound group's node) — what SVG AVTs evaluate against.
@property (nonatomic, strong) XFXMLNode *svgContextNode;
/// Focusable inner views in layout (document) order — the tab chain (G-63).
@property (nonatomic, strong) NSMutableArray<NSView *> *keyViews;
@property (nonatomic, weak) NSView *firstKeyView;
/// The chain as last built (navindex order applied).
@property (nonatomic, copy) NSArray<NSView *> *keyChain;
/// A Tab/Backtab that ended a field's editing: the commit rebuilds every
/// widget before AppKit can move the focus, so the movement is replayed on
/// the NEW widgets after the reload (G-63).
@property (nonatomic, weak) XFControl *pendingTabControl;
@property (nonatomic, assign) NSInteger pendingTabDirection;
/// The control whose Return key ended editing: DOMActivate after the
/// commit (XsltForms_input.keyUpActivate, G-42).
@property (nonatomic, weak) XFControl *pendingActivate;

/* Reconciliation state, live only during a layout pass (-rebuild). The
   pass walks the host tree as before, but every view it wants is first
   looked up by key in the previous generation; a hit is reused and
   updated in place, a miss is created, and whatever the pass did not
   claim is retired at the end. */
/// Last generation's widgets by key; a widget is removed when claimed.
@property (nonatomic, strong) NSMutableDictionary<NSString *, XFWidget *> *previousWidgets;
/// Group / fieldset boxes by key, this generation and the last.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSView *> *containers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSView *> *previousContainers;
/// Table adapters and SVG views by key, last generation.
@property (nonatomic, strong) NSMutableDictionary<NSString *, XFTableAdapter *> *previousTables;
@property (nonatomic, strong) NSMutableDictionary<NSString *, XFSVGView *> *previousSVGs;
/// Every subview the current pass created or claimed.
@property (nonatomic, strong) NSMutableSet<NSView *> *liveViews;
/// Key prefix naming the repeat items the walk is inside of, so the
/// same control element in two items gets two keys.
@property (nonatomic, copy) NSString *keyPrefix;
/// The view being typed into during an incremental commit: its value is
/// not pushed back while the user is editing it.
@property (nonatomic, weak) NSView *reconcileEditingView;
/// The current pass (0 before the first).
@property (nonatomic, assign) NSUInteger generation;

/// Methods implemented in XFFormView.m (core).
/// The full pass: refresh every widget from the processor, reusing the
/// views whose key comes up again. `editing` is excluded from value
/// updates (the field being typed into).
- (void)reconcileExcept:(NSView *)editing;
- (NSString *)keyForControl:(XFControl *)control item:(NSString *)item;
- (NSString *)keyForElement:(XFXMLElement *)element kind:(NSString *)kind;
/// Adds `view` (if not yet a subview) and marks it live for this pass.
- (void)keepView:(NSView *)view;
/// Same, for a box that must draw behind the widgets.
- (void)keepBoxView:(NSView *)view;
/// The previous generation's widget for the control, if it exists and has
/// the same variant; removed from the previous generation when returned.
- (XFWidget *)takeWidgetForControl:(XFControl *)control item:(NSString *)item variant:(NSString *)variant;
- (NSView *)takeContainerForKey:(NSString *)key;
/// The widget for `control`: reused from the previous pass when its key
/// and variant match, otherwise freshly made. Its state is brought up to
/// date either way. nil when the control has no single view.
- (XFWidget *)widgetForControl:(XFControl *)control item:(NSString *)item;
/// Places a widget: caption, frames, key view, badges; adds it to `widgets`.
- (void)placeWidget:(XFWidget *)w atY:(CGFloat)y indent:(CGFloat)indent caption:(BOOL)caption;
/// YES if `view` (or the field editor working for it) is the window's
/// first responder.
- (BOOL)isViewFocused:(NSView *)view;
- (void)registerKeyView:(NSView *)view control:(XFControl *)control;
- (NSTextField *)makeLabel:(NSString *)text;
- (BOOL)isBooleanControl:(XFControl *)control;
- (void)applyEnabled:(NSView *)view control:(XFControl *)control;
/// Creates the hint / alert badges after the widget view (x = the view's
/// right edge) and returns the x after the last badge slot.
- (CGFloat)attachBadgesToWidget:(XFWidget *)w;
/// Re-applies visibility (validity, relevance) and the badge texts.
- (void)updateBadgesForWidget:(XFWidget *)w;
/// The floating info box under a hovered / clicked badge (one at a time).
/// Either the plain wrapped NSTextField or, for a badge carrying
/// markup, the bordered box around a read-only rich text view.
@property (nonatomic, strong) NSView *badgePopup;
@property (nonatomic, weak) XFBadgeView *badgePopupBadge;
- (void)showBadgeInfo:(XFBadgeView *)badge;
- (void)hideBadgeInfo;
- (XFWidget *)addWidget:(XFControl *)control view:(NSView *)view height:(CGFloat)height atY:(CGFloat)y indent:(CGFloat)indent;
- (XFWidget *)addWidget:(XFControl *)control view:(NSView *)view height:(CGFloat)height atY:(CGFloat)y indent:(CGFloat)indent caption:(BOOL)caption;
- (void)noteRight:(CGFloat)right;
- (XFControl *)controlForSender:(id)sender;
- (NSTextField *)textFieldEditable:(BOOL)editable secure:(BOOL)secure;
- (void)rebuild;
- (void)installInitialFirstResponder;
- (XFWidget *)widgetForTextView:(NSTextView *)tv;
- (XFWidget *)widgetForView:(id)sender;
- (XFWidget *)widgetForControlView:(NSView *)view;
- (XFWidget *)widgetForControl:(XFControl *)control;
- (void)makeControlFirstResponder:(XFControl *)control;
- (void)widgetDidFocus:(id)sender;
- (void)applyPendingTab;
@end

/// Widget construction (XFFormView+Widgets.m).
@interface XFFormView (XFWidgets)
- (NSView *)makeViewForControl:(XFControl *)control height:(CGFloat *)height;
/// Which view -makeViewForControl:height: would build for the control now.
- (NSString *)variantForControl:(XFControl *)control;
/// The row height of a widget of this variant (what the factory reports
/// through `height`, recomputed for a reused view).
- (CGFloat)heightForWidget:(XFWidget *)w;
/// Pushes the control's current state into an existing view: value,
/// items, title, placeholder, enabled/hidden, tooltip. The widget's
/// `control` may be a new object with the same key (repeat items).
- (void)configureWidget:(XFWidget *)w;
/// (Re)fills a popup with the select's items and selects the current one.
- (void)populatePopup:(NSPopUpButton *)popup forSelect:(XFSelectControl *)select;
- (BOOL)isNumericControl:(XFControl *)control;
- (NSString *)displayValueOf:(XFControl *)control;
- (NSView *)makeListBoxForSelect:(XFSelectControl *)select;
- (void)listBox:(XFListBoxAdapter *)adapter didSelectRows:(NSIndexSet *)rows;
- (BOOL)viewCarriesLabel:(NSView *)view control:(XFControl *)control;
- (NSArray<NSString *> *)fileTypesForMediaTypes:(NSArray<NSString *> *)mediaTypes;
- (void)uploadClicked:(NSButton *)sender;
@end

/// Block/inline/host-markup layout (XFFormView+Layout.m).
@interface XFFormView (XFLayout)
- (CGFloat)layoutControl:(XFControl *)control atY:(CGFloat)y indent:(CGFloat)indent;
- (CGFloat)layoutGroup:(XFGroup *)group atY:(CGFloat)y indent:(CGFloat)indent;
- (CGFloat)layoutRepeat:(XFRepeat *)repeat atY:(CGFloat)y indent:(CGFloat)indent;
- (NSFont *)bodyFont;
- (NSFont *)fontForTag:(NSString *)tag base:(NSFont *)base;
- (NSFont *)headingFontForLevel:(NSInteger)level;
- (CGFloat)lineHeightForFont:(NSFont *)font;
- (CGFloat)widthOfText:(NSString *)text font:(NSFont *)font;
- (NSTextField *)makeText:(NSString *)text font:(NSFont *)font;
- (void)collectAtomsFrom:(NSArray<XFHostNode *> *)nodes font:(NSFont *)font into:(NSMutableArray<XFLayoutAtom *> *)atoms;
- (CGFloat)placeInlineControl:(XFControl *)control x:(CGFloat *)x y:(CGFloat)y left:(CGFloat)left lineHeight:(CGFloat *)lineHeight lineY:(CGFloat *)lineY;
- (CGFloat)layoutAtoms:(NSArray<XFLayoutAtom *> *)atoms atY:(CGFloat)y indent:(CGFloat)indent;
- (CGFloat)layoutRun:(NSArray<XFHostNode *> *)run atY:(CGFloat)y indent:(CGFloat)indent font:(NSFont *)font;
- (CGFloat)layoutNodes:(NSArray<XFHostNode *> *)nodes atY:(CGFloat)y indent:(CGFloat)indent font:(NSFont *)font;
- (CGFloat)layoutBlockNode:(XFHostNode *)node atY:(CGFloat)y indent:(CGFloat)indent font:(NSFont *)font;
- (CGFloat)layoutTable:(XFHostNode *)node atY:(CGFloat)y indent:(CGFloat)indent font:(NSFont *)font;
- (XFHostNode *)textNode:(NSString *)text;
@end

/// Commits, incremental editing, control actions (XFFormView+Editing.m).
@interface XFFormView (XFEditing)
- (void)endEditingInProgress;
- (void)tableAdapter:(XFTableAdapter *)adapter didCommitControl:(XFControl *)control value:(NSString *)value;
- (void)tableAdapter:(XFTableAdapter *)adapter didActivateTrigger:(XFTriggerControl *)trigger;
- (void)reloadAfterTrigger;
- (void)tableAdapter:(XFTableAdapter *)adapter didSelectRow:(XFTableRow *)row;
- (void)commitControl:(XFControl *)control value:(NSString *)value;
- (void)controlTextDidBeginEditing:(NSNotification *)note;
- (void)controlTextDidEndEditing:(NSNotification *)note;
- (void)textDidBeginEditing:(NSNotification *)note;
- (void)textChanged:(NSTextField *)sender;
- (void)commitIncremental:(XFControl *)control value:(NSString *)value editingView:(NSView *)editing;
- (void)delayedCommit:(NSTimer *)timer;
- (void)commitIncrementalNow:(XFControl *)control value:(NSString *)value editingView:(NSView *)editing;
- (void)controlTextDidChange:(NSNotification *)note;
- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector;
- (void)textDidChange:(NSNotification *)note;
/// Incremental typing: the same reconcile pass, with the field being typed
/// into left alone.
- (void)refreshWidgetsInPlaceExcept:(NSView *)editing;
- (void)textDidEndEditing:(NSNotification *)note;
- (void)notifyDocumentReplaceIfNeeded;
- (void)buttonClicked:(NSButton *)sender;
- (void)sliderChanged:(NSSlider *)sender;
- (void)popupChanged:(NSPopUpButton *)sender;
- (void)checkClicked:(NSButton *)sender;
- (void)boolClicked:(NSButton *)sender;
- (void)dateChanged:(NSDatePicker *)sender;
@end

#endif /* XF_APPKIT_PRIV_H */
