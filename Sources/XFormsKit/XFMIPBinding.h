#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFBinding;
@class XFExprContext;
@class XFXPathValue;
@class XFModel;


NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_mipbinding: a computed MIP expression that
/// caches its last result per instance node together with the XPath
/// dependency nodes collected during evaluation.
@interface XFMIPBinding : NSObject

@property (nonatomic, strong, readonly) XFBinding *binding;
@property (nonatomic, copy, readonly) NSString *expression;

+ (nullable instancetype)mipBindingWithExpression:(NSString *)expression
                                            error:(NSError **)error;
+ (nullable instancetype)mipBindingWithExpression:(NSString *)expression
                                          element:(nullable XFXMLElement *)element
                                            error:(NSError **)error;

/// Evaluate against `node` (XPath context item). Rebuilds when the model
/// is rebuilded or any recorded dependency is in `model.nodesChanged`.
- (nullable XFXPathValue *)evaluateInContext:(XFExprContext *)context
                                        node:(XFXMLNode *)node
                                       model:(nullable XFModel *)model
                                       error:(NSError **)error;

- (void)disposeNode:(XFXMLNode *)node;

@end

NS_ASSUME_NONNULL_END
