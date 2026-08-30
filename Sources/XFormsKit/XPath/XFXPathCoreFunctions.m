#import "XFXPathPriv.h"
#import "XFModel.h"
#import "XFInstance.h"
#import "XFRepeat.h"
#import "XFXML.h"
#import <Foundation/NSXMLNode.h>
#import <math.h>

static NSString *XFLocalName(NSString *qname)
{
    NSRange c = [qname rangeOfString:@":"];
    if (c.location == NSNotFound) {
        return qname;
    }
    return [qname substringFromIndex:c.location + 1];
}

static XFXPathValue *XFArg(NSArray<XFXPathValue *> *args, NSUInteger i)
{
    return i < args.count ? args[i] : nil;
}

@implementation XFXPathCoreFunctions

+ (NSDictionary<NSString *, XFXPathFunction *> *)table
{
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @"last": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)args; (void)err;
                return [XFXPathValue number:(double)(ctx.nodeList.count ? ctx.nodeList.count : ctx.size)];
            }],
            @"position": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)args; (void)err;
                return [XFXPathValue number:(double)ctx.position];
            }],
            @"count": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue number:(double)XFArg(args, 0).nodes.count];
            }],
            @"local-name": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNodeSet body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSXMLNode *n = XFArg(args, 0).firstNode;
                if (n == nil) return [XFXPathValue string:@""];
                return [XFXPathValue string:([n localName] ?: [n name]) ?: @""];
            }],
            @"namespace-uri": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNodeSet body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSXMLNode *n = XFArg(args, 0).firstNode;
                return [XFXPathValue string:n.URI ?: @""];
            }],
            @"name": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNodeSet body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSXMLNode *n = XFArg(args, 0).firstNode;
                return [XFXPathValue string:[n name] ?: @""];
            }],
            @"string": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNodeSet body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                XFXPathValue *a = XFArg(args, 0);
                return [XFXPathValue string:a ? [a stringValue] : @""];
            }],
            @"concat": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSMutableString *s = [NSMutableString string];
                for (XFXPathValue *v in args) {
                    [s appendString:[v stringValue]];
                }
                return [XFXPathValue string:s];
            }],
            @"starts-with": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *a = [XFArg(args, 0) stringValue] ?: @"";
                NSString *b = [XFArg(args, 1) stringValue] ?: @"";
                return [XFXPathValue boolean:[a hasPrefix:b]];
            }],
            @"contains": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *a = [XFArg(args, 0) stringValue] ?: @"";
                NSString *b = [XFArg(args, 1) stringValue] ?: @"";
                return [XFXPathValue boolean:b.length == 0 || [a rangeOfString:b].location != NSNotFound];
            }],
            @"substring-before": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *a = [XFArg(args, 0) stringValue] ?: @"";
                NSString *b = [XFArg(args, 1) stringValue] ?: @"";
                NSRange r = [a rangeOfString:b];
                if (b.length == 0 || r.location == NSNotFound) return [XFXPathValue string:@""];
                return [XFXPathValue string:[a substringToIndex:r.location]];
            }],
            @"substring-after": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *a = [XFArg(args, 0) stringValue] ?: @"";
                NSString *b = [XFArg(args, 1) stringValue] ?: @"";
                NSRange r = [a rangeOfString:b];
                if (b.length == 0) return [XFXPathValue string:a];
                if (r.location == NSNotFound) return [XFXPathValue string:@""];
                return [XFXPathValue string:[a substringFromIndex:NSMaxRange(r)]];
            }],
            @"substring": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *s = [XFArg(args, 0) stringValue] ?: @"";
                double start = round([XFArg(args, 1) numberValue]);
                double len = args.count > 2 ? round([XFArg(args, 2) numberValue]) : (double)s.length;
                if (isnan(start) || isinf(start) || isnan(len)) return [XFXPathValue string:@""];
                NSInteger from = (NSInteger)start - 1;
                if (from < 0) {
                    len += from;
                    from = 0;
                }
                if (from >= (NSInteger)s.length || len <= 0) return [XFXPathValue string:@""];
                NSInteger end = from + (NSInteger)len;
                if (end > (NSInteger)s.length) end = (NSInteger)s.length;
                return [XFXPathValue string:[s substringWithRange:NSMakeRange((NSUInteger)from, (NSUInteger)(end - from))]];
            }],
            @"string-length": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultString body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue number:(double)([XFArg(args, 0) stringValue] ?: @"").length];
            }],
            @"normalize-space": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultString body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *s = [XFArg(args, 0) stringValue] ?: @"";
                NSArray *parts = [s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSMutableArray *nz = [NSMutableArray array];
                for (NSString *p in parts) {
                    if (p.length) [nz addObject:p];
                }
                return [XFXPathValue string:[nz componentsJoinedByString:@" "]];
            }],
            @"translate": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *s = [XFArg(args, 0) stringValue] ?: @"";
                NSString *from = [XFArg(args, 1) stringValue] ?: @"";
                NSString *to = [XFArg(args, 2) stringValue] ?: @"";
                NSMutableString *out = [NSMutableString string];
                for (NSUInteger i = 0; i < s.length; i++) {
                    unichar c = [s characterAtIndex:i];
                    NSRange r = [from rangeOfString:[NSString stringWithCharacters:&c length:1]];
                    if (r.location == NSNotFound) {
                        [out appendFormat:@"%C", c];
                    } else if (r.location < to.length) {
                        [out appendFormat:@"%C", [to characterAtIndex:r.location]];
                    }
                }
                return [XFXPathValue string:out];
            }],
            @"boolean": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue boolean:XFArg(args, 0).booleanValue];
            }],
            @"not": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue boolean:!XFArg(args, 0).booleanValue];
            }],
            @"true": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)args; (void)err;
                return [XFXPathValue boolean:YES];
            }],
            @"false": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)args; (void)err;
                return [XFXPathValue boolean:NO];
            }],
            @"number": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNodeSet body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue number:XFArg(args, 0).numberValue];
            }],
            @"sum": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                double sum = 0;
                for (NSXMLNode *n in XFArg(args, 0).nodes) {
                    sum += [XFXPathValue nodeSet:@[ n ]].numberValue;
                }
                return [XFXPathValue number:sum];
            }],
            @"floor": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue number:floor(XFArg(args, 0).numberValue)];
            }],
            @"ceiling": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue number:ceil(XFArg(args, 0).numberValue)];
            }],
            @"round": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue number:round(XFArg(args, 0).numberValue)];
            }],
            @"instance": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                XFModel *model = ctx.model;
                if (model == nil) {
                    if (err) {
                        *err = [NSError errorWithDomain:XFErrorDomain
                                                   code:XFErrorXPathEvaluation
                                               userInfo:@{ NSLocalizedDescriptionKey:
                                                               @"instance() requires a model on the evaluation context" }];
                    }
                    return nil;
                }
                NSString *ident = args.count > 0 ? [args[0] stringValue] : nil;
                XFInstance *inst = ident.length ? [model instanceWithIdentifier:ident] : [model defaultInstance];
                NSXMLElement *root = [inst documentElement];
                if (root) {
                    [ctx addDependency:root];
                    [ctx addDepElement:model];
                }
                return [XFXPathValue nodeSet:root ? @[ root ] : @[]];
            }],
            @"index": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)err;
                XFModel *model = ctx.model;
                NSString *ident = args.count > 0 ? [args[0] stringValue] : nil;
                XFRepeat *repeat = [model repeatWithIdentifier:ident];
                if (repeat == nil) {
                    return [XFXPathValue number:NAN];
                }
                return [XFXPathValue number:(double)repeat.index];
            }],
            @"context": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)args; (void)err;
                NSXMLNode *n = ctx.currentNode ?: ctx.contextNode;
                return [XFXPathValue nodeSet:n ? @[ n ] : @[]];
            }],
        };
            }
        }
    }
    (void)lock; (void)onceToken;
    return table;
}

+ (XFXPathFunction *)functionNamed:(NSString *)name
{
    NSString *local = XFLocalName(name);
    XFXPathFunction *fn = [self table][local];
    if (fn == nil) {
        fn = [self table][name];
    }
    return fn;
}

@end
