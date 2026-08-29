#import "XFXPath.h"
#import "XFXPathPriv.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFModel.h"
#import "XFInstance.h"
#import "XFXML.h"
#import "XFErrors.h"
#import <Foundation/NSXMLNode.h>
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLDocument.h>

#pragma mark - Evaluation

static NSXMLNode *XFRootNode(NSXMLNode *node)
{
    NSXMLNode *n = node;
    while (n.parent) {
        n = n.parent;
    }
    return n;
}

static void XFRecord(XFExprContext *ctx, NSXMLNode *node)
{
    [ctx addDependency:node];
}

static BOOL XFMatchesName(NSXMLNode *node, NSString *test)
{
    if ([test isEqualToString:@"*"] || [test isEqualToString:@"node"]) {
        return YES;
    }
    NSString *local = [node localName] ?: [node name];
    return [local isEqualToString:test] || [[node name] isEqualToString:test];
}

static NSArray<NSXMLNode *> *XFChildAxis(NSXMLNode *node, NSString *test)
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSXMLNode *child in [node children]) {
        if ([test isEqualToString:@"text"]) {
            if ([child kind] == NSXMLTextKind) {
                [out addObject:child];
            }
            continue;
        }
        if ([child kind] != NSXMLElementKind && ![test isEqualToString:@"node"]) {
            continue;
        }
        if ([test isEqualToString:@"node"] || [test isEqualToString:@"*"] || XFMatchesName(child, test)) {
            if ([test isEqualToString:@"node"] || [child kind] == NSXMLElementKind || [test isEqualToString:@"*"]) {
                if ([test isEqualToString:@"*"] && [child kind] != NSXMLElementKind) {
                    continue;
                }
                if (![test isEqualToString:@"node"] && [child kind] != NSXMLElementKind) {
                    continue;
                }
                if ([test isEqualToString:@"node"] || XFMatchesName(child, test) || [test isEqualToString:@"*"]) {
                    [out addObject:child];
                }
            }
        }
    }
    return out;
}

static NSArray<NSXMLNode *> *XFAttributeAxis(NSXMLNode *node, NSString *test)
{
    if ([node kind] != NSXMLElementKind) {
        return @[];
    }
    NSXMLElement *el = (NSXMLElement *)node;
    NSMutableArray *out = [NSMutableArray array];
    for (NSXMLNode *attr in [el attributes]) {
        if ([test isEqualToString:@"*"] || XFMatchesName(attr, test)) {
            [out addObject:attr];
        }
    }
    return out;
}

static void XFCollectDescendants(NSXMLNode *node, NSString *test, NSMutableArray *out, BOOL includeSelf)
{
    if (includeSelf) {
        if ([test isEqualToString:@"node"] ||
            ([node kind] == NSXMLElementKind && ([test isEqualToString:@"*"] || XFMatchesName(node, test)))) {
            [out addObject:node];
        }
    }
    for (NSXMLNode *child in [node children]) {
        XFCollectDescendants(child, test, out, YES);
    }
}

@implementation XFPathExpr

- (XFXPathValue *)eval:(XFExprContext *)ctx error:(NSError **)error
{
    NSMutableArray<NSXMLNode *> *nodes = [NSMutableArray array];
    NSXMLNode *start = ctx.contextNode;
    if (start == nil) {
        return [XFXPathValue nodeSet:@[]];
    }
    if (self.absolute) {
        start = XFRootNode(start);
    }
    if (self.descendantOrSelfFirst) {
        NSMutableArray *desc = [NSMutableArray array];
        XFCollectDescendants(start, @"node", desc, YES);
        [nodes addObjectsFromArray:desc];
    } else if (self.absolute && self.steps.count == 0) {
        [nodes addObject:start];
        XFRecord(ctx, start);
        return [XFXPathValue nodeSet:nodes];
    } else {
        [nodes addObject:start];
    }

    for (XFStep *step in self.steps) {
        NSMutableArray<NSXMLNode *> *next = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (NSXMLNode *node in nodes) {
            NSArray<NSXMLNode *> *matched = nil;
            if ([step.axis isEqualToString:@"self"]) {
                matched = @[ node ];
            } else if ([step.axis isEqualToString:@"parent"]) {
                matched = node.parent ? @[ node.parent ] : @[];
            } else if ([step.axis isEqualToString:@"attribute"]) {
                matched = XFAttributeAxis(node, step.test);
            } else if ([step.axis isEqualToString:@"descendant-or-self"]) {
                NSMutableArray *desc = [NSMutableArray array];
                XFCollectDescendants(node, step.test, desc, YES);
                matched = desc;
            } else {
                matched = XFChildAxis(node, step.test);
            }
            for (NSXMLNode *m in matched) {
                NSValue *key = [NSValue valueWithNonretainedObject:m];
                if (![seen containsObject:key]) {
                    [seen addObject:key];
                    [next addObject:m];
                }
            }
        }

        if (step.predicates.count > 0) {
            NSMutableArray *filtered = [NSMutableArray array];
            NSUInteger size = next.count;
            for (NSUInteger i = 0; i < next.count; i++) {
                NSXMLNode *n = next[i];
                BOOL keep = YES;
                for (XFExpr *pred in step.predicates) {
                    XFExprContext *pctx = [ctx copy];
                    pctx.contextNode = n;
                    pctx.position = i + 1;
                    pctx.size = size;
                    XFXPathValue *pv = [pred eval:pctx error:error];
                    if (*error) {
                        return nil;
                    }
                    if (pv.type == XFXPathValueTypeNumber ||
                        (pv.type == XFXPathValueTypeString && pv.string.length > 0 &&
                         !isnan(pv.numberValue) && pv.stringValue.doubleValue == pv.numberValue)) {
                        double num = pv.numberValue;
                        if ((NSUInteger)num != i + 1) {
                            keep = NO;
                            break;
                        }
                    } else if (!pv.booleanValue) {
                        keep = NO;
                        break;
                    }
                }
                if (keep) {
                    [filtered addObject:n];
                }
            }
            next = filtered;
        }
        nodes = next;
    }

    for (NSXMLNode *n in nodes) {
        XFRecord(ctx, n);
    }
    return [XFXPathValue nodeSet:nodes];
}

@end

@implementation XFBinaryExpr

- (XFXPathValue *)eval:(XFExprContext *)ctx error:(NSError **)error
{
    XFXPathValue *l = [self.left eval:ctx error:error];
    if (*error) {
        return nil;
    }
    if ([self.op isEqualToString:@"or"]) {
        if (l.booleanValue) {
            return [XFXPathValue boolean:YES];
        }
        XFXPathValue *r = [self.right eval:ctx error:error];
        if (*error) {
            return nil;
        }
        return [XFXPathValue boolean:r.booleanValue];
    }
    if ([self.op isEqualToString:@"and"]) {
        if (!l.booleanValue) {
            return [XFXPathValue boolean:NO];
        }
        XFXPathValue *r = [self.right eval:ctx error:error];
        if (*error) {
            return nil;
        }
        return [XFXPathValue boolean:r.booleanValue];
    }

    XFXPathValue *r = [self.right eval:ctx error:error];
    if (*error) {
        return nil;
    }

    if ([self.op isEqualToString:@"+"]) {
        return [XFXPathValue number:l.numberValue + r.numberValue];
    }
    if ([self.op isEqualToString:@"-"]) {
        return [XFXPathValue number:l.numberValue - r.numberValue];
    }
    if ([self.op isEqualToString:@"|"]) {
        NSMutableArray *nodes = [NSMutableArray arrayWithArray:l.nodes];
        NSMutableSet *seen = [NSMutableSet set];
        for (NSXMLNode *n in l.nodes) {
            [seen addObject:[NSValue valueWithNonretainedObject:n]];
        }
        for (NSXMLNode *n in r.nodes) {
            NSValue *key = [NSValue valueWithNonretainedObject:n];
            if (![seen containsObject:key]) {
                [seen addObject:key];
                [nodes addObject:n];
            }
        }
        return [XFXPathValue nodeSet:nodes];
    }

    if ([self.op isEqualToString:@"="] || [self.op isEqualToString:@"!="]) {
        BOOL eq = [[l stringValue] isEqualToString:[r stringValue]];
        return [XFXPathValue boolean:[self.op isEqualToString:@"="] ? eq : !eq];
    }
    double ln = l.numberValue;
    double rn = r.numberValue;
    if ([self.op isEqualToString:@"<"])  return [XFXPathValue boolean:ln < rn];
    if ([self.op isEqualToString:@">"])  return [XFXPathValue boolean:ln > rn];
    if ([self.op isEqualToString:@"<="]) return [XFXPathValue boolean:ln <= rn];
    if ([self.op isEqualToString:@">="]) return [XFXPathValue boolean:ln >= rn];

    if (error) {
        *error = [NSError errorWithDomain:XFErrorDomain
                                     code:XFErrorXPathEvaluation
                                 userInfo:@{ NSLocalizedDescriptionKey:
                                                 [NSString stringWithFormat:@"unknown operator %@", self.op] }];
    }
    return nil;
}

@end

@implementation XFFunctionExpr

- (XFXPathValue *)eval:(XFExprContext *)ctx error:(NSError **)error
{
    NSString *fn = [self.name lowercaseString];
    NSMutableArray<XFXPathValue *> *vals = [NSMutableArray array];
    for (XFExpr *arg in self.args) {
        XFXPathValue *v = [arg eval:ctx error:error];
        if (*error) {
            return nil;
        }
        [vals addObject:v];
    }

    if ([fn isEqualToString:@"concat"]) {
        NSMutableString *s = [NSMutableString string];
        for (XFXPathValue *v in vals) {
            [s appendString:[v stringValue]];
        }
        return [XFXPathValue string:s];
    }
    if ([fn isEqualToString:@"string"]) {
        if (vals.count == 0) {
            XFRecord(ctx, ctx.contextNode);
            return [XFXPathValue string:ctx.contextNode ? [XFXML stringValueOfNode:ctx.contextNode] : @""];
        }
        return [XFXPathValue string:[vals[0] stringValue]];
    }
    if ([fn isEqualToString:@"name"] || [fn isEqualToString:@"local-name"]) {
        NSXMLNode *n = vals.count > 0 ? vals[0].firstNode : ctx.contextNode;
        if (n == nil) {
            return [XFXPathValue string:@""];
        }
        XFRecord(ctx, n);
        NSString *name = [fn isEqualToString:@"local-name"] ? ([n localName] ?: [n name]) : [n name];
        return [XFXPathValue string:name ?: @""];
    }
    if ([fn isEqualToString:@"instance"]) {
        XFModel *model = ctx.model;
        if (model == nil) {
            if (error) {
                *error = [NSError errorWithDomain:XFErrorDomain
                                             code:XFErrorXPathEvaluation
                                         userInfo:@{ NSLocalizedDescriptionKey:
                                                         @"instance() requires a model on the evaluation context" }];
            }
            return nil;
        }
        NSString *ident = vals.count > 0 ? [vals[0] stringValue] : nil;
        XFInstance *inst = ident.length ? [model instanceWithIdentifier:ident] : [model defaultInstance];
        if (inst == nil) {
            return [XFXPathValue nodeSet:@[]];
        }
        NSXMLElement *root = [inst documentElement];
        XFRecord(ctx, root);
        return [XFXPathValue nodeSet:root ? @[ root ] : @[]];
    }
    if ([fn isEqualToString:@"true"]) {
        return [XFXPathValue boolean:YES];
    }
    if ([fn isEqualToString:@"false"]) {
        return [XFXPathValue boolean:NO];
    }
    if ([fn isEqualToString:@"not"]) {
        BOOL b = vals.count > 0 ? vals[0].booleanValue : NO;
        return [XFXPathValue boolean:!b];
    }
    if ([fn isEqualToString:@"count"]) {
        return [XFXPathValue number:(double)(vals.count > 0 ? vals[0].nodes.count : 0)];
    }
    if ([fn isEqualToString:@"position"]) {
        return [XFXPathValue number:(double)ctx.position];
    }
    if ([fn isEqualToString:@"last"]) {
        return [XFXPathValue number:(double)ctx.size];
    }

    if (error) {
        *error = [NSError errorWithDomain:XFErrorDomain
                                     code:XFErrorXPathEvaluation
                                 userInfo:@{ NSLocalizedDescriptionKey:
                                                 [NSString stringWithFormat:@"unknown function %@", self.name] }];
    }
    return nil;
}

@end

#pragma mark - Public

@interface XFXPath ()
@property (nonatomic, copy, readwrite) NSString *expression;
@property (nonatomic, strong) XFExpr *ast;
@end

@implementation XFXPath

+ (instancetype)xpathWithString:(NSString *)expression error:(NSError **)error
{
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
    xp.ast = ast;
    return xp;
}

- (XFXPathValue *)evaluateInContext:(XFExprContext *)context error:(NSError **)error
{
    NSError *inner = nil;
    XFXPathValue *value = [self.ast eval:context error:&inner];
    if (value == nil) {
        if (error) {
            *error = inner;
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
