#import "XFXPathPriv.h"

@implementation XFPathExpr

+ (instancetype)filter:(XFExpr *)filter rel:(XFExpr *)rel
{
    XFPathExpr *e = [[self alloc] init];
    e.filter = filter;
    e.rel = rel;
    return e;
}

- (XFXPathValue *)evaluate:(XFExprContext *)ctx error:(NSError **)error
{
    XFXPathValue *fv = [self.filter evaluate:ctx error:error];
    if (fv == nil) {
        return nil;
    }
    NSArray<NSXMLNode *> *nodes = fv.nodes;
    NSMutableArray<NSXMLNode *> *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < nodes.count; i++) {
        XFExprContext *newCtx = [ctx cloneWithNode:nodes[i] position:i + 1 nodeList:nodes];
        XFXPathValue *relv = [self.rel evaluate:newCtx error:error];
        if (relv == nil) {
            return nil;
        }
        for (NSXMLNode *n in relv.nodes) {
            if (!XFNodeInArray(n, out)) {
                [out addObject:n];
            }
        }
    }
    return [XFXPathValue nodeSet:out];
}

@end

@implementation XFFilterExpr

+ (instancetype)expr:(XFExpr *)expr predicates:(NSArray<XFExpr *> *)predicates
{
    XFFilterExpr *e = [[self alloc] init];
    e.expr = expr;
    e.predicates = predicates ?: @[];
    return e;
}

- (XFXPathValue *)evaluate:(XFExprContext *)ctx error:(NSError **)error
{
    XFXPathValue *ev = [self.expr evaluate:ctx error:error];
    if (ev == nil) {
        return nil;
    }
    NSArray<NSXMLNode *> *nodes = ev.nodes;
    for (XFExpr *pred in self.predicates) {
        NSMutableArray *next = [NSMutableArray array];
        NSUInteger len = nodes.count;
        for (NSUInteger j = 0; j < len; j++) {
            NSXMLNode *n = nodes[j];
            XFExprContext *newCtx = [ctx cloneWithNode:n position:j + 1 nodeList:nodes];
            XFXPathValue *pv = [pred evaluate:newCtx error:error];
            if (error && *error) {
                return nil;
            }
            if (pv.booleanValue) {
                [next addObject:n];
            }
        }
        nodes = next;
    }
    return [XFXPathValue nodeSet:nodes];
}

@end

@implementation XFUnionExpr

+ (instancetype)expr1:(XFExpr *)e1 expr2:(XFExpr *)e2
{
    XFUnionExpr *e = [[self alloc] init];
    e.expr1 = e1;
    e.expr2 = e2;
    return e;
}

- (XFXPathValue *)evaluate:(XFExprContext *)ctx error:(NSError **)error
{
    XFXPathValue *a = [self.expr1 evaluate:ctx error:error];
    if (a == nil) {
        return nil;
    }
    XFXPathValue *b = [self.expr2 evaluate:ctx error:error];
    if (b == nil) {
        return nil;
    }
    NSMutableArray *nodes = [NSMutableArray arrayWithArray:a.nodes];
    for (NSXMLNode *n in b.nodes) {
        if (!XFNodeInArray(n, nodes)) {
            [nodes addObject:n];
        }
    }
    // A union is in document order (XSLTForms sorts when its `unordered`
    // flag is set; we always do, which is what callers expect).
    return [XFXPathValue nodeSet:XFSortDocumentOrder(nodes)];
}

@end
