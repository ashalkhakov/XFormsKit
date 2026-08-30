#import <Foundation/Foundation.h>

@class XFExprContext;
@class XFXPathValue;
@class NSXMLNode;
@class NSXMLElement;

NS_ASSUME_NONNULL_BEGIN

@interface XFXPath : NSObject

@property (nonatomic, copy, readonly) NSString *expression;

+ (nullable instancetype)xpathWithString:(NSString *)expression
                                   error:(NSError **)error;

/// Compile (or fetch from the cache) and register the namespace prefixes
/// used by the expression from the in-scope declarations of `element`
/// (the host element carrying the expression). Prefer this form.
+ (nullable instancetype)xpathWithString:(NSString *)expression
                                 element:(nullable NSXMLElement *)element
                                   error:(NSError **)error;

- (nullable XFXPathValue *)evaluateInContext:(XFExprContext *)context
                                       error:(NSError **)error;

- (nullable NSString *)stringValueInContext:(XFExprContext *)context
                                      error:(NSError **)error;

- (nullable NSArray<NSXMLNode *> *)nodesInContext:(XFExprContext *)context
                                            error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
