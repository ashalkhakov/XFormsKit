#import "XFInsertAction.h"
#import "XFBinding.h"
#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFModel.h"
#import "XFInstance.h"
#import "XFBind.h"
#import "XFRepeat.h"
#import "XFNodeState.h"
#import "XFDeferredUpdates.h"
#import "XFXMLEvents.h"
#import "XFEvent.h"
#import "XFXML.h"
#import <math.h>
#import <XFormsKit/XFXMLTypes.h>

@interface XFInsertAction ()
@property (nonatomic, strong) XFBinding *nodesetBinding;
@property (nonatomic, strong) XFXPath *originExpr;
@property (nonatomic, strong) XFXPath *atExpr;
@property (nonatomic, strong) XFXPath *contextExpr;
@property (nonatomic, copy, readwrite) NSString *position;
@property (nonatomic, copy, readwrite) NSArray<XFXMLNode *> *lastInsertedNodes;
@end

@implementation XFInsertAction

- (XFXPath *)compile:(NSString *)expr error:(NSError **)error
{
    if (expr.length == 0) {
        return nil;
    }
    return [XFXPath xpathWithString:expr element:self.element error:error];
}

- (instancetype)initWithElement:(XFXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    // nodeset / ref, or bind="id" resolved to the bind's nodes (G-21)
    NSError *bindError = nil;
    self.nodesetBinding = [XFBinding bindingForElement:element attribute:@"nodeset" error:&bindError];
    if (bindError) {
        if (error) {
            *error = bindError;
        }
        return nil;
    }
    NSString *origin = [[element attributeForName:@"origin"] stringValue];
    XFXMLElement *originEl = [XFXML firstElementWithLocalName:@"origin"
                                                namespaceURI:@"http://www.w3.org/2002/xforms"
                                                      inNode:element];
    if (originEl) {
        NSString *v = [[originEl attributeForName:@"value"] stringValue];
        if (v.length) {
            origin = v;
        }
    }
    self.originExpr = [self compile:origin error:error];
    if (origin.length && self.originExpr == nil) {
        return nil;
    }
    self.atExpr = [self compile:[[element attributeForName:@"at"] stringValue] error:error];
    NSString *ctx = [[element attributeForName:@"context"] stringValue];
    XFXMLElement *ctxEl = [XFXML firstElementWithLocalName:@"context"
                                             namespaceURI:@"http://www.w3.org/2002/xforms"
                                                   inNode:element];
    if (ctxEl) {
        NSString *v = [[ctxEl attributeForName:@"value"] stringValue];
        if (v.length) {
            ctx = v;
        }
    }
    self.contextExpr = [self compile:ctx error:error];
    if (ctx.length && self.contextExpr == nil) {
        return nil;
    }
    NSString *pos = [[element attributeForName:@"position"] stringValue];
    self.position = [pos isEqualToString:@"before"] ? @"before" : @"after";
    self.lastInsertedNodes = @[];
    return self;
}

- (XFExprContext *)ctxWithNode:(XFXMLNode *)node
                      position:(NSUInteger)position
                      nodeList:(NSArray<XFXMLNode *> *)nodeList
{
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:node];
    ctx.model = self.model;
    ctx.position = position > 0 ? position : 1;
    ctx.nodeList = nodeList ?: (node ? @[ node ] : @[]);
    ctx.size = ctx.nodeList.count;
    return ctx;
}

- (XFXMLNode *)insertClone:(XFXMLNode *)origin
                  intoParent:(XFXMLNode *)parent
                   beforeNode:(XFXMLNode *)before
{
    if (origin == nil || parent == nil) {
        return nil;
    }
    XFXMLNode *clone = [origin copy];
    if ([origin kind] == XFXMLAttributeKind) {
        if ([parent kind] != XFXMLElementKind) {
            return nil;
        }
        XFXMLElement *el = (XFXMLElement *)parent;
        XFXMLNode *existing = [el attributeForName:[origin name]];
        if (existing) {
            [existing setStringValue:[origin stringValue]];
            return existing;
        }
        [el addAttribute:clone];
        return clone;
    }
    if ([parent kind] == XFXMLDocumentKind) {
        XFXMLDocument *doc = (XFXMLDocument *)parent;
        if ([clone kind] == XFXMLElementKind) {
            [doc setRootElement:(XFXMLElement *)clone];
            return clone;
        }
        return nil;
    }
    if ([parent kind] != XFXMLElementKind) {
        return nil;
    }
    XFXMLElement *el = (XFXMLElement *)parent;
    if (before && [before parent] == el) {
        [el insertChild:clone atIndex:[before index]];
    } else {
        [el addChild:clone];
    }
    return clone;
}

- (void)runWithContextNode:(XFXMLNode *)contextNode event:(XFEvent *)event
{
    (void)event;
    // @model switches the in-scope evaluation context BEFORE @context and
    // the nodeset are applied (the 10.3.b "evaluation context changed b4
    // special attributes" case): the context node moves to that model's
    // default instance root unless it already belongs to it.
    XFModel *model = [self actionTargetModel];
    XFXMLNode *ctxNode = contextNode;
    if (model != self.model && ![model instanceOwningNode:ctxNode]) {
        ctxNode = [[model defaultInstance] documentElement];
    }
    if (self.contextExpr) {
        XFExprContext *c = [self ctxWithNode:ctxNode position:1 nodeList:ctxNode ? @[ ctxNode ] : @[]];
        c.model = model;
        ctxNode = [self.contextExpr evaluateInContext:c error:NULL].firstNode;
    }
    if (ctxNode == nil) {
        return;
    }

    NSArray<XFXMLNode *> *nodes = @[];
    if (self.nodesetBinding) {
        XFExprContext *c = [self ctxWithNode:ctxNode position:1 nodeList:@[ ctxNode ]];
        c.model = model;
        nodes = [self.nodesetBinding evaluateInContext:c error:NULL].nodes ?: @[];
    }

    NSArray<XFXMLNode *> *originNodes = @[];
    if (self.originExpr) {
        XFExprContext *c = [self ctxWithNode:ctxNode position:1 nodeList:nodes.count ? nodes : @[ ctxNode ]];
        c.model = model;
        originNodes = [self.originExpr evaluateInContext:c error:NULL].nodes ?: @[];
    }
    if (originNodes.count == 0) {
        if (self.originExpr != nil) {
            // an origin that is SPECIFIED but selects nothing terminates
            // the insert with no effect (10.3.c) — no fallback clone
            return;
        }
        if (nodes.count == 0) {
            return;
        }
        originNodes = @[ nodes.lastObject ];
    }

    NSInteger pos = [self.position isEqualToString:@"after"] ? 1 : 0;
    NSMutableArray<XFXMLNode *> *inserted = [NSMutableArray array];
    XFXMLNode *parent = nil;
    NSUInteger location = 0;

    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"insert"];

    NSUInteger originIndex = 0;
    for (XFXMLNode *origin in originNodes) {
        XFXMLNode *before = nil;
        if (nodes.count == 0) {
            parent = ctxNode;
        } else {
            XFXMLNode *first = nodes.firstObject;
            if ([first kind] == XFXMLDocumentKind) {
                parent = first;
            } else if ([first kind] == XFXMLAttributeKind) {
                parent = [first parent];
            } else {
                parent = [first parent];
            }
            if ([parent kind] != XFXMLDocumentKind && [origin kind] != XFXMLAttributeKind) {
                XFExprContext *atCtx = [self ctxWithNode:ctxNode position:1 nodeList:nodes];
                atCtx.model = model;
                double at = nodes.count;
                if (self.atExpr) {
                    at = [self.atExpr evaluateInContext:atCtx error:NULL].numberValue;
                }
                // XSLTForms: res = at ? round(at)+i-1 : nodes.length-1;
                // index = isNaN(res) ? nodes.length : res + pos.
                // An out-of-range @at CLAMPS (10.3.d: <1 → 1, >size → size;
                // NaN → after the last node).
                NSInteger index;
                if (isnan(at)) {
                    index = (NSInteger)nodes.count;
                } else {
                    NSInteger atRound = (NSInteger)lround(at);
                    if (atRound < 1) {
                        atRound = 1;
                    }
                    if ((NSUInteger)atRound > nodes.count) {
                        atRound = (NSInteger)nodes.count;
                    }
                    index = atRound + (NSInteger)originIndex - 1 + pos;
                }
                if (index < 0) {
                    index = 0;
                }
                location = (NSUInteger)index;
                // the REFERENCE node picks the parent: a heterogeneous
                // nodeset (chapter/*) spans sibling parents, so the
                // clone must land beside the node @at names, not inside
                // the first node's parent (b.15.a)
                if ((NSUInteger)index >= nodes.count) {
                    XFXMLNode *last = nodes.lastObject;
                    before = [last nextSibling];
                    parent = [last parent];
                } else {
                    before = nodes[(NSUInteger)index];
                    parent = [before parent];
                }
            }
        }
        // empty nodeset + context: XSLTForms inserts before parent.firstChild
        if (nodes.count == 0 && [parent kind] == XFXMLElementKind) {
            before = [(XFXMLElement *)parent childCount] ? [parent childAtIndex:0] : nil;
        }
        XFXMLNode *clone = [self insertClone:origin intoParent:parent beforeNode:before];
        if (clone) {
            // debugConsole: "insert node in parent at index - ctx"
            XFTraceWrite(XFTraceKindAction, nil, self.element,
                         @"insert %@ in %@ at %lu - %@",
                         XFTraceDescribeNode(clone), XFTraceDescribeNode(parent),
                         (unsigned long)location, XFTraceDescribeNode(ctxNode));
            [inserted addObject:clone];
            NSMutableArray *grown = [nodes mutableCopy] ?: [NSMutableArray array];
            [grown addObject:clone];
            nodes = grown;
        }
        originIndex++;
    }

    self.lastInsertedNodes = inserted;
    if (inserted.count && parent) {
        [model addChange:parent];
        [model setRebuilded:YES];
        [du addChangedModel:model];
        NSDictionary *evctx = @{
            @"inserted-nodes": inserted,
            @"origin-nodes": originNodes,
            @"insert-location-node": @(location),
            @"position": self.position ?: @"after"
        };
        XFInstance *inst = [model instanceContainingNode:parent];
        [XFXMLEvents dispatch:inst ?: model name:@"xforms-insert" context:evctx];

        XFXMLNode *last = inserted.lastObject;
        NSString *rid = [XFNodeState existingStateOnNode:nodes.firstObject].repeatIdentifier
            ?: [XFNodeState existingStateOnNode:last].repeatIdentifier;
        if (rid.length) {
            XFRepeat *repeat = [model repeatWithIdentifier:rid];
            XFExprContext *rctx = [self ctxWithNode:[[model defaultInstance] documentElement]
                                           position:1
                                           nodeList:nil];
            rctx.model = model;
            [repeat rebuildItemsWithContext:rctx error:NULL];
            NSUInteger idx = 1;
            for (XFXMLNode *n in repeat.nodes) {
                if (n == last) {
                    [repeat setIndex:idx];
                    break;
                }
                idx++;
            }
            // the indexed item is NEW even when the index number did not
            // change — its inner repeats start at their startindex
            [repeat resetNestedRepeatIndexes];
        }
    }
    [du closeAction:@"insert"];
}

@end
