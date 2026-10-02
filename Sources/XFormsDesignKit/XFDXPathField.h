/* XFDXPathField — the designer's XPath entry component: a text field with
   a built-in "…" node-picker button and built-in validation. Every place
   an XPath is edited uses this one view (xib: a customView with this
   customClass), so picker and validation behavior exist exactly once.

   The component validates by compiling through XFXPath whenever its text
   changes (red text + parse-error tooltip on failure; the value is still
   accepted — the author may be mid-thought), and its picker button runs
   the node-picker panel over the provider's instances. The host supplies
   context through XFDXPathFieldProvider and receives the target/action
   send after every committed change, exactly like a plain control.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>

@class XFDXPathField;

/// What the attribute being edited wants from the expression — the picker
/// evaluates live and warns (never blocks) when the result disagrees:
/// a nodeset attribute getting a string, a single-node ref selecting
/// three nodes (XPath uses the first), an empty node-set.
typedef NS_ENUM(NSInteger, XFDXPathExpectation) {
    XFDXPathExpectAny = 0,      /* no opinion */
    XFDXPathExpectNodeSet,      /* bind/repeat/itemset nodeset, insert/delete */
    XFDXPathExpectNode,         /* value-control ref, setvalue ref, label/value ref */
    XFDXPathExpectValue,        /* calculate, constraint, value, if, while, … */
};

/// Location-path step model (exposed for the selftest). Split decomposes
/// a SIMPLE location path into { start: context|root|instance,
/// instance: id?, steps: [ { axis, test, predicates } ] } — nil when the
/// expression is anything richer (functions, unions, //, operators): the
/// picker then keeps it editable as text with the steps table disabled.
/// Join renders the canonical spelling back (.. / . / @name shorthands).
FOUNDATION_EXPORT NSDictionary *XFDSplitLocationPath(NSString *expression);
FOUNDATION_EXPORT NSString *XFDJoinLocationPath(NSDictionary *path);

/// The predicate sub-editor's preview (exposed for the selftest): how
/// `predicates` filters the nodes `baseExpression` selects. A bare
/// expression normalizes to one [bracketed] predicate; a bracket list
/// passes through. Returns { ok, normalized, error?, total, matching,
/// rows: [ { index, node, value, match } ] } — rows are the CANDIDATE
/// nodes (capped at 200) with match flags, so the editor can show what
/// the predicate keeps and what it drops.
FOUNDATION_EXPORT NSDictionary *XFDPredicatePreview(NSString *baseExpression,
                                                    NSString *predicates,
                                                    XFXMLElement *_Nullable hostElement,
                                                    XFXMLNode *_Nullable contextNode,
                                                    XFModel *_Nullable model);

/// Refs suggested from the data's implied schema, relative to `context`
/// (positional clones collapse to one entry — the schema XForms infers).
FOUNDATION_EXPORT NSArray *XFDSchemaPathsFromNode(XFXMLNode *context, NSUInteger cap);
/// The context properties event() exposes for `eventName` (XForms 1.1
/// §4). nil = unknown event; empty = known to carry none.
FOUNDATION_EXPORT NSArray *XFDEventContextProperties(NSString *eventName);

/// NSBeep raises on a headless GNUstep (no display server) — the selftest
/// would hang on a modal exception panel. Every beep in the designer goes
/// through here.
static inline void XFDBeep(void)
{
    if (getenv("XFD_SELFTEST") == NULL) {
        NSBeep();
    }
}

@protocol XFDXPathFieldProvider <NSObject>
/// The host element the expression belongs to (namespace prefixes resolve
/// against it). nil disables validation and the picker.
- (XFXMLElement *)hostElementForXPathField:(XFDXPathField *)field;
/// The processor whose instances the picker shows.
- (XFProcessor *)processorForXPathField:(XFDXPathField *)field;
/// The node relative picker paths start from (nil = no Relative style).
- (XFXMLNode *)contextNodeForXPathField:(XFDXPathField *)field;
@end

@interface XFDXPathField : NSView

@property (nonatomic, weak) id<XFDXPathFieldProvider> provider;
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;

/// The expression. Setting revalidates.
@property (nonatomic, copy) NSString *stringValue;
/// NO when the current text does not compile as XPath.
@property (nonatomic, readonly, getter=isValid) BOOL valid;
/// What the edited attribute wants (see above). Informs the picker's
/// result preview; default XFDXPathExpectAny.
@property (nonatomic, assign) XFDXPathExpectation expectation;

- (void)setEnabled:(BOOL)enabled;
/// Recompile the current text (call after the validation context moved).
- (void)validate;

/// The node-picker modal itself, for other components that need a path
/// chosen the same way (the rich text field's Insert Output). Returns the
/// chosen expression, nil on cancel.
+ (NSString *)runPickerForProcessor:(XFProcessor *)processor
                        contextNode:(XFXMLNode *)contextNode
                        hostElement:(XFXMLElement *)hostElement
                              title:(NSString *)title;
+ (NSString *)runPickerForProcessor:(XFProcessor *)processor
                        contextNode:(XFXMLNode *)contextNode
                        hostElement:(XFXMLElement *)hostElement
                              title:(NSString *)title
                            initial:(NSString *)initial
                        expectation:(XFDXPathExpectation)expectation;

@end
