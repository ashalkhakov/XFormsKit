#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFXPath;
@class XFExprContext;
@class XFXPathValue;


NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_binding: an XPath expression, or a `bind="id"`
/// reference whose result is the bind's node list (G-21), evaluated against
/// the `model="id"` named on the element when the context node is not in
/// that model's instances (G-22).
@interface XFBinding : NSObject

@property (nonatomic, strong, readonly, nullable) XFXPath *xpath;
@property (nonatomic, copy, readonly) NSString *expression;
/// `bind="id"`: the binding resolves to that bind's nodes.
@property (nonatomic, copy, readonly, nullable) NSString *bindID;
/// `model="id"` on the element carrying the binding.
@property (nonatomic, copy, readonly, nullable) NSString *modelID;

/// The binding an element carries: `bind="id"` wins, else the expression
/// in `attribute` (nil = first of nodeset / ref / value). nil when the
/// element has none (and no error).
+ (nullable instancetype)bindingForElement:(XFXMLElement *)element
                                 attribute:(nullable NSString *)attribute
                                     error:(NSError **)error;

+ (nullable instancetype)bindingWithExpression:(NSString *)expression
                                         error:(NSError **)error;
/// Same, registering namespace prefixes from the element carrying the
/// expression (see -[XFXPath xpathWithString:element:error:]).
+ (nullable instancetype)bindingWithExpression:(NSString *)expression
                                       element:(nullable XFXMLElement *)element
                                         error:(NSError **)error;

- (nullable XFXPathValue *)evaluateInContext:(XFExprContext *)context
                                       error:(NSError **)error;

- (nullable XFXMLNode *)boundNodeInContext:(XFExprContext *)context
                                     error:(NSError **)error;

- (nullable NSString *)stringValueInContext:(XFExprContext *)context
                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
