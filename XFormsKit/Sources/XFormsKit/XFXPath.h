#import <Foundation/Foundation.h>

@class XFExprContext;
@class XFXPathValue;
@class NSXMLNode;

NS_ASSUME_NONNULL_BEGIN

@interface XFXPath : NSObject

@property (nonatomic, copy, readonly) NSString *expression;

+ (nullable instancetype)xpathWithString:(NSString *)expression
                                   error:(NSError **)error;

- (nullable XFXPathValue *)evaluateInContext:(XFExprContext *)context
                                       error:(NSError **)error;

- (nullable NSString *)stringValueInContext:(XFExprContext *)context
                                      error:(NSError **)error;

- (nullable NSArray<NSXMLNode *> *)nodesInContext:(XFExprContext *)context
                                            error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
