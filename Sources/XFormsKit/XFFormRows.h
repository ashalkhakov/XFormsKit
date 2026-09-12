#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFControl;
@class XFGroup;
@class XFRepeat;
@class XFHostNode;
@class XFProcessor;

NS_ASSUME_NONNULL_BEGIN

/// What a row shows. One per idiom of the iOS form, not one per XForms
/// control: several controls share a kind (every single-line input is a
/// text field, whatever its datatype), and one control can want different
/// kinds by appearance (a full-appearance select1 with three items is a
/// segmented control, with thirty it is a list of check rows).
typedef NS_ENUM(NSInteger, XFFormRowKind) {
    XFFormRowKindTextField,   // xf:input, xf:secret — UITextField
    XFFormRowKindTextView,    // xf:textarea — UITextView
    XFFormRowKindSwitch,      // boolean xf:input — UISwitch as accessoryView
    XFFormRowKindSelector,    // xf:select1 — value + disclosure, picker on tap
    XFFormRowKindSegmented,   // xf:select1 appearance=full, few items
    XFFormRowKindCheck,       // one item of a full select/select1 — checkmark
    XFFormRowKindDate,        // date/time/dateTime — UIDatePicker
    XFFormRowKindSlider,      // xf:range — UISlider
    XFFormRowKindButton,      // xf:trigger, xf:submit
    XFFormRowKindValue,       // xf:output — label + detail
    XFFormRowKindUpload,      // xf:upload — disclosure to a document picker
    XFFormRowKindImage,       // xf:output with an image mediatype
    XFFormRowKindTable,       // a host <table> with no controls in it
    XFFormRowKindMarkup,      // host markup: prose, rules, SVG
    XFFormRowKindNote,        // the xf:hint, or the xf:alert while invalid
    XFFormRowKindRepeatAdd,   // the "add one" row closing a repeat section
    XFFormRowKindInlineFlow,  // prose with controls in it, flowed as a line
};

/// One row of the form. A row is a VIEW of a control, never its owner:
/// the control keeps the value, the MIP state and the focus, and the cell
/// is bound to it when the table asks for one. That is what lets cells
/// recycle while controls do not.
@interface XFFormRow : NSObject
@property (nonatomic, assign) XFFormRowKind kind;
@property (nonatomic, strong, nullable) XFControl *control;
/// The item this row stands for, when `kind` is Check: an index into the
/// select's items.
@property (nonatomic, assign) NSUInteger itemIndex;
/// Host nodes this row renders, when `kind` is Markup or Table (where
/// there is exactly one, the <table>).
@property (nonatomic, copy, nullable) NSArray<XFHostNode *> *hostNodes;
/// The in-scope evaluation context those `hostNodes` belong to: the
/// repeat item's node, or the bound node of the enclosing group. Host
/// markup is evaluated against it — an SVG's AVTs and its xf:output
/// children resolve there — so a chart inside a repeat reads THIS item's
/// values. nil outside any binding, which means the default context.
@property (nonatomic, strong, nullable) XFXMLNode *contextNode;
/// How deep the group nesting was. A table view has two levels and XForms
/// nests without limit, so anything below the first group flattens and
/// carries its depth here for indentation.
@property (nonatomic, assign) NSUInteger depth;
@property (nonatomic, copy, nullable) NSString *label;
/// Note rows only: the text to show, and whether it reports a problem
/// (an xf:alert) rather than guidance (an xf:hint).
@property (nonatomic, copy, nullable) NSString *note;
/// The same note as host markup, when the form wrote any: `<xf:hint>Enter
/// your <b>full</b> name</xf:hint>`. nil for a plain note, and the cell
/// then takes its plain path.
@property (nonatomic, copy, nullable) NSString *noteMarkup;
@property (nonatomic, assign) BOOL noteIsProblem;
/// The repeat this row belongs to, and which of its items (1-based),
/// where the row came from one — what a host's own add / remove gesture
/// acts on. `repeatPosition` is 0 on the section's RepeatAdd row, which
/// stands for the repeat rather than for any one item.
///
/// Nested repeats tag their rows first and are not overwritten: the
/// innermost repeat owns the row, which is the one a swipe on it means.
@property (nonatomic, strong, nullable) XFRepeat *repeat;
@property (nonatomic, assign) NSUInteger repeatPosition;
@end

/// One section: a top-level xf:group, a repeat, or the implicit section
/// that holds whatever sits outside any group.
@interface XFFormSection : NSObject
@property (nonatomic, copy, nullable) NSString *title;     // group label
@property (nonatomic, copy, nullable) NSString *footer;    // group hint
@property (nonatomic, copy) NSArray<XFFormRow *> *rows;
/// Set when the section came from an xf:repeat: its add / remove / reorder
/// are xf:insert / xf:delete on this repeat.
@property (nonatomic, strong, nullable) XFRepeat *repeat;
@end

/// Flattens the host tree into sections and rows.
///
/// Deliberately free of any view framework: this is the half worth
/// testing, and the same rows drive whatever renders them. Non-relevant
/// controls are dropped, as the AppKit layout drops them.
@interface XFFormRows : NSObject

+ (NSArray<XFFormSection *> *)sectionsForProcessor:(XFProcessor *)processor;
+ (NSArray<XFFormSection *> *)sectionsForHostNodes:(NSArray<XFHostNode *> *)nodes;

/// The row kind a control wants, by class, datatype and appearance.
+ (XFFormRowKind)kindForControl:(XFControl *)control;

@end

NS_ASSUME_NONNULL_END
