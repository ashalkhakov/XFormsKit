// XFAppKitPriv.h — shared internals of the AppKit form view layer.
// The one header every file split out of XFFormView.m imports: layout
// constants, the widget/atom bookkeeping classes, the table / list box
// adapters, the rich text editor, the XFFormView class extension and
// the category interfaces of the split implementation files.

#ifndef XF_APPKIT_PRIV_H
#define XF_APPKIT_PRIV_H

#import "XFFormView.h"
#import "XFRichText.h"
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

@interface XFWidget : NSObject
@property (nonatomic, strong) XFControl *control;
@property (nonatomic, strong) NSView *view;
@property (nonatomic, strong) NSTextField *labelField;
@property (nonatomic, assign) CGFloat height;
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
- (void)refreshInPlace;
@end

/// Data source / delegate of an appearance="compact" select list box (G-43).
@interface XFListBoxAdapter : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) XFSelectControl *select;
@property (nonatomic, weak) XFFormView *formView;
@property (nonatomic, assign) BOOL selecting;
@end

/// A minimal rich text editor: a toolbar (block popup + B I U S) over an
/// NSTextView. The instance stores the XHTML subset (XFRichText); the text
/// view holds the attributed form. No WebKit anywhere.
@interface XFRichTextEditor : NSView
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, strong) NSPopUpButton *blockPopup;
@property (nonatomic, strong) NSFont *baseFont;
- (instancetype)initWithFrame:(NSRect)frame baseFont:(NSFont *)font;
- (void)setHTML:(NSString *)html;
- (NSString *)HTML;
/// Return inside a list continues it (next bullet / number); Return on an
/// empty item leaves the list. NO = not in a list, insert normally.
- (BOOL)handleNewline;
@end

/// The view AppKit focuses for a widget (the field editor host, the
/// scroll view document, or the view itself). Defined in XFFormView.m.
FOUNDATION_EXPORT NSView *XFKeyViewOf(NSView *view);

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

/// Methods implemented in XFFormView.m (core).
- (void)registerKeyView:(NSView *)view control:(XFControl *)control;
- (NSTextField *)makeLabel:(NSString *)text;
- (BOOL)isBooleanControl:(XFControl *)control;
- (void)applyEnabled:(NSView *)view control:(XFControl *)control;
- (XFWidget *)addWidget:(XFControl *)control view:(NSView *)view height:(CGFloat)height atY:(CGFloat)y indent:(CGFloat)indent;
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
