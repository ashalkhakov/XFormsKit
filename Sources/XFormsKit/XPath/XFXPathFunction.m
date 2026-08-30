#import "XFXPathPriv.h"
#import "XFXML.h"

@implementation XFXPathFunction

+ (instancetype)acceptContext:(BOOL)accept
                    defaultTo:(XFXPathFnDefault)defaultTo
                         body:(XFXPathFnBody)body
{
    XFXPathFunction *fn = [[self alloc] init];
    fn.acceptContext = accept;
    fn.defaultTo = defaultTo;
    fn.body = body;
    return fn;
}

- (XFXPathValue *)call:(XFExprContext *)ctx
             arguments:(NSArray<XFXPathValue *> *)args
                 error:(NSError **)error
{
    NSArray<XFXPathValue *> *arguments = args ?: @[];
    if (arguments.count == 0) {
        switch (self.defaultTo) {
            case XFXPathFnDefaultNode:
            case XFXPathFnDefaultNodeSet:
                if (ctx.contextNode) {
                    arguments = @[ [XFXPathValue nodeSet:@[ ctx.contextNode ]] ];
                    [ctx addDependency:ctx.contextNode];
                }
                break;
            case XFXPathFnDefaultString:
                if (ctx.contextNode) {
                    [ctx addDependency:ctx.contextNode];
                    arguments = @[ [XFXPathValue string:[XFXML stringValueOfNode:ctx.contextNode]] ];
                } else {
                    arguments = @[ [XFXPathValue string:@""] ];
                }
                break;
            case XFXPathFnDefaultNone:
                break;
        }
    }
    return self.body(ctx, arguments, error);
}

@end
