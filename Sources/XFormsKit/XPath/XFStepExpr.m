#import "XFXPathPriv.h"
#import <XFormsKit/XFXMLTypes.h>

static void XFPush(XFExprContext *ctx, NSMutableArray *list, XFXMLNode *node, XFNodeTest *test, NSString *axis)
{
    (void)ctx;
    if (node && [test matches:node resolver:ctx.nsResolver axis:axis] && !XFNodeInArray(node, list)) {
        [list addObject:node];
    }
}

static void XFPushList(XFExprContext *ctx, NSMutableArray *list, NSArray *nodes, XFNodeTest *test, NSString *axis)
{
    for (XFXMLNode *n in nodes) {
        XFPush(ctx, list, n, test, axis);
    }
}

static void XFPushDescendants(XFExprContext *ctx, NSMutableArray *list, XFXMLNode *node, XFNodeTest *test, NSString *axis)
{
    for (XFXMLNode *n in [node children]) {
        XFPush(ctx, list, n, test, axis);
        XFPushDescendants(ctx, list, n, test, axis);
    }
}

static void XFPushDescendantsRev(XFExprContext *ctx, NSMutableArray *list, XFXMLNode *node, XFNodeTest *test, NSString *axis)
{
    NSArray *children = [node children];
    for (NSInteger i = (NSInteger)children.count - 1; i >= 0; i--) {
        XFXMLNode *n = children[i];
        XFPushDescendantsRev(ctx, list, n, test, axis);
        XFPush(ctx, list, n, test, axis);
    }
}

static XFXMLNode *XFElementParent(XFXMLNode *input)
{
    if ([input kind] == XFXMLAttributeKind) {
        return [input parent];
    }
    return [input parent];
}

@implementation XFStepExpr

+ (instancetype)axis:(NSString *)axis test:(XFNodeTest *)test predicates:(NSArray<XFExpr *> *)predicates
{
    XFStepExpr *s = [[self alloc] init];
    s.axis = axis;
    s.nodetest = test;
    s.predicates = predicates ?: @[];
    return s;
}

- (XFXPathValue *)evaluate:(XFExprContext *)ctx error:(NSError **)error
{
    XFXMLNode *input = ctx.contextNode;
    NSMutableArray *list = [NSMutableArray array];
    if (input == nil) {
        return [XFXPathValue nodeSet:@[]];
    }
    NSString *axis = self.axis;
    XFNodeTest *test = self.nodetest;

    if ([axis isEqualToString:XFAxisAncestorOrSelf]) {
        XFPush(ctx, list, input, test, axis);
        XFXMLNode *n = XFElementParent(input);
        while (n) {
            XFPush(ctx, list, n, test, axis);
            n = [n parent];
        }
    } else if ([axis isEqualToString:XFAxisAncestor]) {
        XFXMLNode *n = XFElementParent(input);
        while (n) {
            XFPush(ctx, list, n, test, axis);
            n = [n parent];
        }
    } else if ([axis isEqualToString:XFAxisAttribute]) {
        if ([input kind] == XFXMLElementKind) {
            XFPushList(ctx, list, [(XFXMLElement *)input attributes], test, axis);
        }
    } else if ([axis isEqualToString:XFAxisChild]) {
        XFPushList(ctx, list, [input children], test, axis);
    } else if ([axis isEqualToString:XFAxisDescendantOrSelf]) {
        XFPush(ctx, list, input, test, axis);
        XFPushDescendants(ctx, list, input, test, axis);
    } else if ([axis isEqualToString:XFAxisDescendant]) {
        XFPushDescendants(ctx, list, input, test, axis);
    } else if ([axis isEqualToString:XFAxisFollowing]) {
        XFXMLNode *n = ([input kind] == XFXMLAttributeKind) ? [input parent] : input;
        while (n && [n kind] != XFXMLDocumentKind) {
            for (XFXMLNode *nn = [n nextSibling]; nn; nn = [nn nextSibling]) {
                XFPush(ctx, list, nn, test, axis);
                XFPushDescendants(ctx, list, nn, test, axis);
            }
            n = [n parent];
        }
    } else if ([axis isEqualToString:XFAxisFollowingSibling]) {
        for (XFXMLNode *ns = [input nextSibling]; ns; ns = [ns nextSibling]) {
            XFPush(ctx, list, ns, test, axis);
        }
    } else if ([axis isEqualToString:XFAxisNamespace]) {
        // Not implemented (same as XSLTForms).
    } else if ([axis isEqualToString:XFAxisParent]) {
        XFXMLNode *p = XFElementParent(input);
        if (p) {
            XFPush(ctx, list, p, test, axis);
        }
    } else if ([axis isEqualToString:XFAxisPreceding]) {
        XFXMLNode *p = ([input kind] == XFXMLAttributeKind) ? [input parent] : input;
        while (p && [p kind] != XFXMLDocumentKind) {
            for (XFXMLNode *ps = [p previousSibling]; ps; ps = [ps previousSibling]) {
                XFPushDescendantsRev(ctx, list, ps, test, axis);
                XFPush(ctx, list, ps, test, axis);
            }
            p = [p parent];
        }
    } else if ([axis isEqualToString:XFAxisPrecedingSibling]) {
        for (XFXMLNode *ps = [input previousSibling]; ps; ps = [ps previousSibling]) {
            XFPush(ctx, list, ps, test, axis);
        }
    } else if ([axis isEqualToString:XFAxisSelf]) {
        XFPush(ctx, list, input, test, axis);
    } else {
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorXPathEvaluation
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"no such axis: %@", axis] }];
        }
        return nil;
    }

    for (XFExpr *pred in self.predicates) {
        NSMutableArray *newList = [NSMutableArray array];
        NSUInteger len = list.count;
        for (NSUInteger j = 0; j < len; j++) {
            XFXMLNode *x = list[j];
            XFExprContext *newCtx = [ctx cloneWithNode:x position:j + 1 nodeList:list];
            XFXPathValue *pv = [pred evaluate:newCtx error:error];
            if (error && *error) {
                return nil;
            }
            if (pv.booleanValue) {
                [newList addObject:x];
            }
        }
        list = newList;
    }
    // Reverse axes are evaluated in proximity order (for position()); the
    // resulting node-set is reported in document order.
    if ([axis isEqualToString:XFAxisAncestor] || [axis isEqualToString:XFAxisAncestorOrSelf] ||
        [axis isEqualToString:XFAxisPreceding] || [axis isEqualToString:XFAxisPrecedingSibling]) {
        list = [[[list reverseObjectEnumerator] allObjects] mutableCopy];
    }
    return [XFXPathValue nodeSet:list];
}

@end
