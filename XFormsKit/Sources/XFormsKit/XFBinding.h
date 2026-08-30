#import <Foundation/Foundation.h>

@class XFXPath;
@class XFExprContext;
@class XFXPathValue;
@class NSXMLNode;

@class NSXMLElement;

NS_ASSUME_NONNULL_BEGIN

@interface XFBinding : NSObject

@property (nonatomic, strong, readonly) XFXPath *xpath;
@property (nonatomic, copy, readonly) NSString *expression;

+ (nullable instancetype)bindingWithExpression:(NSString *)expression
                                         error:(NSError **)error;
/// Same, registering namespace prefixes from the element carrying the
/// expression (see -[XFXPath xpathWithString:element:error:]).
+ (nullable instancetype)bindingWithExpression:(NSString *)expression
                                       element:(nullable NSXMLElement *)element
                                         error:(NSError **)error;

- (nullable XFXPathValue *)evaluateInContext:(XFExprContext *)context
                                       error:(NSError **)error;

- (nullable NSXMLNode *)boundNodeInContext:(XFExprContext *)context
                                     error:(NSError **)error;

- (nullable NSString *)stringValueInContext:(XFExprContext *)context
                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
