#import "XFXPathPriv.h"
#import <Foundation/NSXMLNode.h>
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLDocument.h>

static void XFPush(XFExprContext *ctx, NSMutableArray *list, NSXMLNode *node, XFNodeTest *test, NSString *axis)
{
    (void)ctx;
    if (node && [test matches:node resolver:ctx.nsResolver axis:axis] && !XFNodeInArray(node, list)) {
        [list addObject:node];
    }
}

static void XFPushList(XFExprContext *ctx, NSMutableArray *list, NSArray *nodes, XFNodeTest *test, NSString *axis)
{
    for (NSXMLNode *n in nodes) {
        XFPush(ctx, list, n, test, axis);
    }
}

static void XFPushDescendants(XFExprContext *ctx, NSMutableArray *list, NSXMLNode *node, XFNodeTest *test, NSString *axis)
{
    for (NSXMLNode *n in [node children]) {
        XFPush(ctx, list, n, test, axis);
        XFPushDescendants(ctx, list, n, test, axis);
    }
}

static void XFPushDescendantsRev(XFExprContext *ctx, NSMutableArray *list, NSXMLNode *node, XFNodeTest *test, NSString *axis)
{
    NSArray *children = [node children];
    for (NSInteger i = (NSInteger)children.count - 1; i >= 0; i--) {
        NSXMLNode *n = children[i];
        XFPushDescendantsRev(ctx, list, n, test, axis);
        XFPush(ctx, list, n, test, axis);
    }
}

static NSXMLNode *XFElementParent(NSXMLNode *input)
{
    if ([input kind] == NSXMLAttributeKind) {
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
    NSXMLNode *input = ctx.contextNode;
    NSMutableArray *list = [NSMutableArray array];
    if (input == nil) {
        return [XFXPathValue nodeSet:@[]];
    }
    NSString *axis = self.axis;
    XFNodeTest *test = self.nodetest;

    if ([axis isEqualToString:XFAxisAncestorOrSelf]) {
        XFPush(ctx, list, input, test, axis);
        NSXMLNode *n = XFElementParent(input);
        while (n) {
            XFPush(ctx, list, n, test, axis);
            n = [n parent];
        }
    } else if ([axis isEqualToString:XFAxisAncestor]) {
        NSXMLNode *n = XFElementParent(input);
        while (n) {
            XFPush(ctx, list, n, test, axis);
            n = [n parent];
        }
    } else if ([axis isEqualToString:XFAxisAttribute]) {
        if ([input kind] == NSXMLElementKind) {
            XFPushList(ctx, list, [(NSXMLElement *)input attributes], test, axis);
        }
    } else if ([axis isEqualToString:XFAxisChild]) {
        XFPushList(ctx, list, [input children], test, axis);
    } else if ([axis isEqualToString:XFAxisDescendantOrSelf]) {
        XFPush(ctx, list, input, test, axis);
        XFPushDescendants(ctx, list, input, test, axis);
    } else if ([axis isEqualToString:XFAxisDescendant]) {
        XFPushDescendants(ctx, list, input, test, axis);
    } else if ([axis isEqualToString:XFAxisFollowing]) {
        NSXMLNode *n = ([input kind] == NSXMLAttributeKind) ? [input parent] : input;
        while (n && [n kind] != NSXMLDocumentKind) {
            for (NSXMLNode *nn = [n nextSibling]; nn; nn = [nn nextSibling]) {
                XFPush(ctx, list, nn, test, axis);
                XFPushDescendants(ctx, list, nn, test, axis);
            }
            n = [n parent];
        }
    } else if ([axis isEqualToString:XFAxisFollowingSibling]) {
        for (NSXMLNode *ns = [input nextSibling]; ns; ns = [ns nextSibling]) {
            XFPush(ctx, list, ns, test, axis);
        }
    } else if ([axis isEqualToString:XFAxisNamespace]) {
        // Not implemented (same as XSLTForms).
    } else if ([axis isEqualToString:XFAxisParent]) {
        NSXMLNode *p = XFElementParent(input);
        if (p) {
            XFPush(ctx, list, p, test, axis);
        }
    } else if ([axis isEqualToString:XFAxisPreceding]) {
        NSXMLNode *p = ([input kind] == NSXMLAttributeKind) ? [input parent] : input;
        while (p && [p kind] != NSXMLDocumentKind) {
            for (NSXMLNode *ps = [p previousSibling]; ps; ps = [ps previousSibling]) {
                XFPushDescendantsRev(ctx, list, ps, test, axis);
                XFPush(ctx, list, ps, test, axis);
            }
            p = [p parent];
        }
    } else if ([axis isEqualToString:XFAxisPrecedingSibling]) {
        for (NSXMLNode *ps = [input previousSibling]; ps; ps = [ps previousSibling]) {
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
            NSXMLNode *x = list[j];
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
    return [XFXPathValue nodeSet:list];
}

@end
