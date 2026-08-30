#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "XFXPath.h"
#import "XFXPathPriv.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFErrors.h"

@interface XFXPath ()
@property (nonatomic, copy, readwrite) NSString *expression;
@property (nonatomic, strong) XFExpr *compiled;
@property (nonatomic, strong) XFNSResolver *nsresolver;
@end

@implementation XFXPath

+ (NSMutableDictionary<NSString *, XFXPath *> *)expressions
{
    static NSMutableDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = [NSMutableDictionary dictionary];
    });
    return map;
}

+ (instancetype)xpathWithString:(NSString *)expression error:(NSError **)error
{
    if (expression == nil) {
        return nil;
    }
    XFXPath *cached = [self expressions][expression];
    if (cached) {
        return cached;
    }
    NSError *inner = nil;
    XFXPathParser *parser = [[XFXPathParser alloc] initWithString:expression];
    XFExpr *ast = [parser parseExpression:&inner];
    if (ast == nil) {
        if (error) {
            *error = inner;
        }
        return nil;
    }
    XFXPath *xp = [[self alloc] init];
    xp.expression = expression;
    xp.compiled = ast;
    xp.nsresolver = [[XFNSResolver alloc] init];
    [self expressions][expression] = xp;
    return xp;
}

- (XFXPathValue *)evaluateInContext:(XFExprContext *)context error:(NSError **)error
{
    if (context.nsResolver == nil) {
        context.nsResolver = self.nsresolver;
    }
    NSError *inner = nil;
    XFXPathValue *value = [self.compiled evaluate:context error:&inner];
    if (value == nil) {
        if (error) {
            *error = inner ?: [NSError errorWithDomain:XFErrorDomain
                                                  code:XFErrorXPathEvaluation
                                              userInfo:@{ NSLocalizedDescriptionKey:
                                                              [NSString stringWithFormat:
                                                               @"Error evaluating XPath: %@", self.expression] }];
        }
        return nil;
    }
    return value;
}

- (NSString *)stringValueInContext:(XFExprContext *)context error:(NSError **)error
{
    XFXPathValue *value = [self evaluateInContext:context error:error];
    return value ? [value stringValue] : nil;
}

- (NSArray<NSXMLNode *> *)nodesInContext:(XFExprContext *)context error:(NSError **)error
{
    XFXPathValue *value = [self evaluateInContext:context error:error];
    return value ? value.nodes : nil;
}

@end
