#import "XFXPathPriv.h"

@implementation XFExpr
- (XFXPathValue *)evaluate:(XFExprContext *)ctx error:(NSError **)error
{
    (void)ctx;
    if (error) {
        *error = [NSError errorWithDomain:XFErrorDomain
                                     code:XFErrorXPathEvaluation
                                 userInfo:@{ NSLocalizedDescriptionKey: @"abstract expression" }];
    }
    return nil;
}
@end

@implementation XFCteExpr
+ (instancetype)string:(NSString *)s
{
    XFCteExpr *e = [[self alloc] init];
    e.value = [XFXPathValue string:s];
    return e;
}
+ (instancetype)number:(double)n
{
    XFCteExpr *e = [[self alloc] init];
    e.value = [XFXPathValue number:n];
    return e;
}
- (XFXPathValue *)evaluate:(XFExprContext *)ctx error:(NSError **)error
{
    (void)ctx; (void)error;
    return self.value;
}
@end

@implementation XFUnaryMinusExpr
+ (instancetype)expr:(XFExpr *)expr
{
    XFUnaryMinusExpr *e = [[self alloc] init];
    e.expr = expr;
    return e;
}
- (XFXPathValue *)evaluate:(XFExprContext *)ctx error:(NSError **)error
{
    XFXPathValue *v = [self.expr evaluate:ctx error:error];
    if (v == nil) {
        return nil;
    }
    return [XFXPathValue number:-v.numberValue];
}
@end

@implementation XFVarRef
+ (instancetype)name:(NSString *)name
{
    XFVarRef *e = [[self alloc] init];
    e.name = name;
    return e;
}
- (XFXPathValue *)evaluate:(XFExprContext *)ctx error:(NSError **)error
{
    (void)error;
    XFXPathValue *v = ctx.variables[self.name];
    if (v) {
        return v;
    }
    // XSLTForms VarRef.js: an unbound variable evaluates to "".
    return [XFXPathValue string:@""];
}
@end

@implementation XFPredicateExpr
+ (instancetype)expr:(XFExpr *)expr
{
    XFPredicateExpr *e = [[self alloc] init];
    e.expr = expr;
    return e;
}
- (XFXPathValue *)evaluate:(XFExprContext *)ctx error:(NSError **)error
{
    XFXPathValue *v = [self.expr evaluate:ctx error:error];
    if (v == nil) {
        return nil;
    }
    if (v.type == XFXPathValueTypeNumber) {
        return [XFXPathValue boolean:v.number == (double)ctx.position];
    }
    return [XFXPathValue boolean:v.booleanValue];
}
@end
