#import <Foundation/Foundation.h>

@class XFBinding;
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
@property (nonatomic, weak, nullable) id owner; // XFProcessor
@property (nonatomic, weak, nullable) XFControl *parentControl;

- (instancetype)initWithElement:(NSXMLElement *)element
                        binding:(nullable XFBinding *)binding
                          label:(nullable NSString *)label;

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error;
- (void)focus;
- (BOOL)commitStringValue:(nullable NSString *)value error:(NSError **)error;
- (void)applyMIPsFromBoundNode;
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
