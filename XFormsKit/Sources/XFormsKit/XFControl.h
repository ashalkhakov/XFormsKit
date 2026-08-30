#import <Foundation/Foundation.h>

@class XFBinding;
@class XFProcessor;
@class XFExprContext;
@class NSXMLElement;
@class NSXMLNode;

NS_ASSUME_NONNULL_BEGIN

@interface XFControl : NSObject

@property (nonatomic, strong, readonly) NSXMLElement *element;
@property (nonatomic, copy, readonly, nullable) NSString *identifier;
@property (nonatomic, copy, readonly, nullable) NSString *label;
@property (nonatomic, strong, readonly, nullable) XFBinding *binding;
@property (nonatomic, strong, nullable) NSXMLNode *boundNode;
@property (nonatomic, copy) NSString *stringValue;
@property (nonatomic, assign) BOOL relevant;
@property (nonatomic, assign) BOOL readonly;
@property (nonatomic, assign) BOOL required;
@property (nonatomic, assign) BOOL valid;
@property (nonatomic, assign) BOOL focused;
@property (nonatomic, copy, nullable) NSString *hint;
@property (nonatomic, copy, nullable) NSString *help;
@property (nonatomic, copy, nullable) NSString *alert;
@property (nonatomic, copy, readonly) NSArray<NSString *> *mipEvents;
@property (nonatomic, copy, nullable) NSString *appearance;
/// `incremental="true"`: the host UI commits on every keystroke (XForms 1.1
/// 8.1.2 / XSLTForms incremental), not only on Return / focus loss.
@property (nonatomic, assign) BOOL incremental;
/// Pass-through host attributes (G-63): navindex, accesskey, placeholder
/// (xf:input/@placeholder or the XSLTForms hint placeholder), rows/cols.
@property (nonatomic, assign) NSInteger navindex;
@property (nonatomic, copy, nullable) NSString *accesskey;
@property (nonatomic, copy, nullable) NSString *placeholder;
@property (nonatomic, assign) NSInteger rows;
@property (nonatomic, assign) NSInteger cols;
/// `xf:help/@href` (G-62).
@property (nonatomic, copy, nullable) NSString *helpHref;
/// `@mediatype` (xf:textarea "application/xhtml+xml" = rich text, XForms 1.1 §8.1.5).
@property (nonatomic, copy, nullable) NSString *mediatype;
/// `inputmode` (XsltForms_input.InputMode): lowerCase | upperCase |
/// titleCase | digits, applied to committed values (G-41).
@property (nonatomic, copy, nullable) NSString *inputmode;
/// `delay="ms"` (XSLTForms): incremental commits are debounced by this
/// many milliseconds (G-40).
@property (nonatomic, assign) NSTimeInterval delay;
@property (nonatomic, weak, nullable) id owner; // XFProcessor
/// The in-scope evaluation context node of the last refresh (XSLTForms
/// `element.node` for unbound elements): the context handlers run in.
@property (nonatomic, strong, nullable) NSXMLNode *inScopeContextNode;
/// Value displayed by the last refresh (XsltForms_control.currentValue).
@property (nonatomic, copy, nullable) NSString *currentValue;
@property (nonatomic, strong, nullable) NSXMLNode *currentNode;
@property (nonatomic, weak, nullable) XFControl *parentControl;

- (instancetype)initWithElement:(NSXMLElement *)element
                        binding:(nullable XFBinding *)binding
                          label:(nullable NSString *)label;

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error;
- (void)focus;
/// The processor owning this control (directly or through its model).
- (nullable XFProcessor *)processor;
- (BOOL)commitStringValue:(nullable NSString *)value error:(NSError **)error;
/// XsltForms_input.InputMode transformation of a UI value (G-41).
- (NSString *)applyInputMode:(NSString *)value;
- (void)applyMIPsFromBoundNode;

/// Refresh in `context` and, like XsltForms_control.refresh, dispatch
/// `xforms-value-changed` when the displayed value changed while still bound
/// to the same node. Hosts call this rather than -refreshWithContext:error:.
- (void)refreshInContext:(XFExprContext *)context error:(NSError **)error;
/// YES for controls that carry a value (not group/repeat/switch/trigger).
- (BOOL)isValueControl;
/// YES for controls laid out as a block of their own (group, repeat, switch,
/// textarea, full-appearance selects); NO for controls that flow inline
/// with surrounding host text like XSLTForms' `<span>` wrappers (G-20).
- (BOOL)isBlockLevel;
/// XsltForms_control.isTrigger: triggers/submits never emit MIP or
/// value-changed events (G-47).
- (BOOL)isTrigger;
/// The context the control's children (label, hint, items, itemsets)
/// evaluate in: the bound node when there is one, else `ctx`.
- (XFExprContext *)childContextFrom:(XFExprContext *)ctx;
/// Apply MIPs from an arbitrary node (nil with a binding = non-relevant).
- (void)applyMIPsFromNode:(nullable NSXMLNode *)node;
/// YES for `value="..."` (xf:output) with no `ref` / `bind`.
@property (nonatomic, assign, readonly) BOOL usesValueBinding;
/// XsltForms_control.eventDispatch for help/hint default UI.
- (void)showHelp;
- (void)showHint;
/// Re-read id / binding / label / hint / appearance from the live element.
- (BOOL)reconfigureFromElement:(NSError **)error;

+ (BOOL)isControlElement:(NSXMLElement *)element;
+ (BOOL)isStandaloneLabelElement:(NSXMLElement *)element;
+ (BOOL)shouldInstantiateElement:(NSXMLElement *)element;
+ (nullable NSString *)labelForElement:(NSXMLElement *)element;
+ (nullable XFBinding *)bindingOnElement:(NSXMLElement *)element
                    preferredAttribute:(nullable NSString *)preferred
                                 error:(NSError **)error;
+ (nullable instancetype)controlWithElement:(NSXMLElement *)element
                                      model:(nullable id)model
                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
