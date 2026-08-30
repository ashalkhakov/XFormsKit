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
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLNode.h>
#import <Foundation/NSXMLDocument.h>

@interface XFInsertAction ()
@property (nonatomic, strong) XFBinding *nodesetBinding;
@property (nonatomic, strong) XFXPath *originExpr;
@property (nonatomic, strong) XFXPath *atExpr;
@property (nonatomic, strong) XFXPath *contextExpr;
@property (nonatomic, copy, readwrite) NSString *position;
@property (nonatomic, copy, readwrite) NSArray<NSXMLNode *> *lastInsertedNodes;
@end

@implementation XFInsertAction

- (XFXPath *)compile:(NSString *)expr error:(NSError **)error
{
    if (expr.length == 0) {
        return nil;
    }
    return [XFXPath xpathWithString:expr element:self.element error:error];
}

- (instancetype)initWithElement:(NSXMLElement *)element
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
    NSXMLElement *originEl = [XFXML firstElementWithLocalName:@"origin"
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
    NSXMLElement *ctxEl = [XFXML firstElementWithLocalName:@"context"
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

- (XFExprContext *)ctxWithNode:(NSXMLNode *)node
                      position:(NSUInteger)position
                      nodeList:(NSArray<NSXMLNode *> *)nodeList
{
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:node];
    ctx.model = self.model;
    ctx.position = position > 0 ? position : 1;
    ctx.nodeList = nodeList ?: (node ? @[ node ] : @[]);
    ctx.size = ctx.nodeList.count;
    return ctx;
}

- (NSXMLNode *)insertClone:(NSXMLNode *)origin
                  intoParent:(NSXMLNode *)parent
                   beforeNode:(NSXMLNode *)before
{
    if (origin == nil || parent == nil) {
        return nil;
    }
    NSXMLNode *clone = [origin copy];
    if ([origin kind] == NSXMLAttributeKind) {
        if ([parent kind] != NSXMLElementKind) {
            return nil;
        }
        NSXMLElement *el = (NSXMLElement *)parent;
        NSXMLNode *existing = [el attributeForName:[origin name]];
        if (existing) {
            [existing setStringValue:[origin stringValue]];
            return existing;
        }
        [el addAttribute:clone];
        return clone;
    }
    if ([parent kind] == NSXMLDocumentKind) {
        NSXMLDocument *doc = (NSXMLDocument *)parent;
        if ([clone kind] == NSXMLElementKind) {
            [doc setRootElement:(NSXMLElement *)clone];
            return clone;
        }
        return nil;
    }
    if ([parent kind] != NSXMLElementKind) {
        return nil;
    }
    NSXMLElement *el = (NSXMLElement *)parent;
    if (before && [before parent] == el) {
        [el insertChild:clone atIndex:[before index]];
    } else {
        [el addChild:clone];
    }
    return clone;
}

- (void)runWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    (void)event;
    NSXMLNode *ctxNode = contextNode;
    if (self.contextExpr) {
        XFExprContext *c = [self ctxWithNode:contextNode position:1 nodeList:contextNode ? @[ contextNode ] : @[]];
        ctxNode = [self.contextExpr evaluateInContext:c error:NULL].firstNode;
    }
    if (ctxNode == nil) {
        return;
    }

    NSArray<NSXMLNode *> *nodes = @[];
    if (self.nodesetBinding) {
        XFExprContext *c = [self ctxWithNode:ctxNode position:1 nodeList:@[ ctxNode ]];
        nodes = [self.nodesetBinding evaluateInContext:c error:NULL].nodes ?: @[];
    }

    NSArray<NSXMLNode *> *originNodes = @[];
    if (self.originExpr) {
        XFExprContext *c = [self ctxWithNode:ctxNode position:1 nodeList:nodes.count ? nodes : @[ ctxNode ]];
        originNodes = [self.originExpr evaluateInContext:c error:NULL].nodes ?: @[];
    }
    if (originNodes.count == 0) {
        if (nodes.count == 0) {
            return;
        }
        originNodes = @[ nodes.lastObject ];
    }

    NSInteger pos = [self.position isEqualToString:@"after"] ? 1 : 0;
    NSMutableArray<NSXMLNode *> *inserted = [NSMutableArray array];
    NSXMLNode *parent = nil;
    NSUInteger location = 0;

    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"insert"];

    NSUInteger originIndex = 0;
    for (NSXMLNode *origin in originNodes) {
        NSXMLNode *before = nil;
        if (nodes.count == 0) {
            parent = ctxNode;
        } else {
            NSXMLNode *first = nodes.firstObject;
            if ([first kind] == NSXMLDocumentKind) {
                parent = first;
            } else if ([first kind] == NSXMLAttributeKind) {
                parent = [first parent];
            } else {
                parent = [first parent];
            }
            if ([parent kind] != NSXMLDocumentKind && [origin kind] != NSXMLAttributeKind) {
                XFExprContext *atCtx = [self ctxWithNode:ctxNode position:1 nodeList:nodes];
                double at = nodes.count;
                if (self.atExpr) {
                    at = [self.atExpr evaluateInContext:atCtx error:NULL].numberValue;
                }
                // XSLTForms: res = at ? round(at)+i-1 : nodes.length-1;
                // index = isNaN(res) ? nodes.length : res + pos
                NSInteger index;
                if (isnan(at)) {
                    index = (NSInteger)nodes.count;
                } else {
                    index = (NSInteger)lround(at) + (NSInteger)originIndex - 1 + pos;
                }
                if (index < 0) {
                    index = 0;
                }
                location = (NSUInteger)index;
                if ((NSUInteger)index >= nodes.count) {
                    NSXMLNode *last = nodes.lastObject;
                    before = [last nextSibling];
                } else {
                    before = nodes[(NSUInteger)index];
                }
            }
        }
        // empty nodeset + context: XSLTForms inserts before parent.firstChild
        if (nodes.count == 0 && [parent kind] == NSXMLElementKind) {
            before = [(NSXMLElement *)parent childCount] ? [parent childAtIndex:0] : nil;
        }
        NSXMLNode *clone = [self insertClone:origin intoParent:parent beforeNode:before];
        if (clone) {
            [inserted addObject:clone];
            NSMutableArray *grown = [nodes mutableCopy] ?: [NSMutableArray array];
            [grown addObject:clone];
            nodes = grown;
        }
        originIndex++;
    }

    self.lastInsertedNodes = inserted;
    if (inserted.count && parent) {
        [self.model addChange:parent];
        [self.model setRebuilded:YES];
        [du addChangedModel:self.model];
        NSDictionary *evctx = @{
            @"inserted-nodes": inserted,
            @"origin-nodes": originNodes,
            @"insert-location-node": @(location),
            @"position": self.position ?: @"after"
        };
        XFInstance *inst = [self.model instanceContainingNode:parent];
        [XFXMLEvents dispatch:inst ?: self.model name:@"xforms-insert" context:evctx];

        NSXMLNode *last = inserted.lastObject;
        NSString *rid = [XFNodeState existingStateOnNode:nodes.firstObject].repeatIdentifier
            ?: [XFNodeState existingStateOnNode:last].repeatIdentifier;
        if (rid.length) {
            XFRepeat *repeat = [self.model repeatWithIdentifier:rid];
            XFExprContext *rctx = [self ctxWithNode:[[self.model defaultInstance] documentElement]
                                           position:1
                                           nodeList:nil];
            [repeat rebuildItemsWithContext:rctx error:NULL];
            NSUInteger idx = 1;
            for (NSXMLNode *n in repeat.nodes) {
                if (n == last) {
                    [repeat setIndex:idx];
                    break;
                }
                idx++;
            }
        }
    }
    [du closeAction:@"insert"];
}

@end
