#import "XFXPathPriv.h"
#import "XFModel.h"
#import <XFormsKit/XFXMLTypes.h>

@implementation XFLocationExpr

+ (instancetype)absolute:(BOOL)absolute steps:(NSArray<XFStepExpr *> *)steps
{
    XFLocationExpr *e = [[self alloc] init];
    e.absolute = absolute;
    e.steps = steps ?: @[];
    return e;
}

- (void)xPathStep:(NSMutableArray<XFXMLNode *> *)nodes
            steps:(NSArray<XFStepExpr *> *)steps
             step:(NSUInteger)step
            input:(XFXMLNode *)input
              ctx:(XFExprContext *)ctx
            error:(NSError **)error
{
    XFStepExpr *s = steps[step];
    XFExprContext *stepCtx = [ctx cloneWithNode:input position:1 nodeList:@[ input ]];
    XFXPathValue *listVal = [s evaluate:stepCtx error:error];
    if (listVal == nil) {
        return;
    }
    NSArray<XFXMLNode *> *nodelist = listVal.nodes;
    for (XFXMLNode *node in nodelist) {
        if (step == steps.count - 1) {
            if (!XFNodeInArray(node, nodes)) {
                [nodes addObject:node];
            }
            [ctx addDependency:node];
        } else {
            [self xPathStep:nodes steps:steps step:step + 1 input:node ctx:ctx error:error];
            if (error && *error) {
                return;
            }
        }
    }
}

- (XFXPathValue *)evaluate:(XFExprContext *)ctx error:(NSError **)error
{
    XFXMLNode *start = nil;
    if (self.absolute) {
        start = ctx.contextNode ? XFRootNode(ctx.contextNode) : nil;
    } else {
        start = ctx.contextNode;
    }
    if (start == nil) {
        return [XFXPathValue nodeSet:@[]];
    }
    if (ctx.model) {
        [ctx addDepElement:ctx.model];
    }
    NSMutableArray<XFXMLNode *> *nodes = [NSMutableArray array];
    if (self.steps.count > 0) {
        [self xPathStep:nodes steps:self.steps step:0 input:start ctx:ctx error:error];
        if (error && *error) {
            return nil;
        }
    } else {
        [nodes addObject:start];
        [ctx addDependency:start];
    }
    return [XFXPathValue nodeSet:nodes];
}

@end
