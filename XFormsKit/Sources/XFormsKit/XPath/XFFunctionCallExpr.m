#import "XFXPathPriv.h"
#import "XFXMLEvents.h"
#import "XFExprContext.h"

@implementation XFFunctionCallExpr

+ (instancetype)name:(NSString *)name args:(NSArray<XFExpr *> *)args
{
    XFFunctionCallExpr *e = [[self alloc] init];
    e.name = name;
    e.args = args ?: @[];
    return e;
}

- (XFXPathValue *)evaluate:(XFExprContext *)ctx error:(NSError **)error
{
    XFXPathFunction *fn = [XFXPathCoreFunctions functionNamed:self.name];
    if (fn == nil) {
        // FunctionCallExpr.js → globals.error(..., "xforms-compute-exception")
        [XFXMLEvents raise:@"xforms-compute-exception" on:ctx.model
                   message:[NSString stringWithFormat:@"Function %@() not found", self.name]];
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorXPathEvaluation
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"Function %@() not found", self.name] }];
        }
        return nil;
    }
    NSMutableArray *arguments = [NSMutableArray array];
    for (XFExpr *arg in self.args) {
        XFXPathValue *v = [arg evaluate:ctx error:error];
        if (v == nil) {
            return nil;
        }
        [arguments addObject:v];
    }
    return [fn call:ctx arguments:arguments error:error];
}

@end
