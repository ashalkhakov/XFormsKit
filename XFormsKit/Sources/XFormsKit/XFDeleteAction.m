#import "XFDeleteAction.h"
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

@interface XFDeleteAction ()
@property (nonatomic, strong) XFBinding *nodesetBinding;
@property (nonatomic, strong) XFXPath *atExpr;
@property (nonatomic, strong) XFXPath *contextExpr;
@property (nonatomic, copy, readwrite) NSArray<NSXMLNode *> *lastDeletedNodes;
@end

@implementation XFDeleteAction

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
    NSString *at = [[element attributeForName:@"at"] stringValue];
    if (at.length) {
        self.atExpr = [XFXPath xpathWithString:at element:element error:error];
        if (self.atExpr == nil) {
            return nil;
        }
    }
    NSString *ctx = [[element attributeForName:@"context"] stringValue];
    if (ctx.length) {
        self.contextExpr = [XFXPath xpathWithString:ctx element:element error:error];
        if (self.contextExpr == nil) {
            return nil;
        }
    }
    self.lastDeletedNodes = @[];
    return self;
}

- (void)runWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    (void)event;
    // @model switches the in-scope evaluation context BEFORE @context and
    // the nodeset are applied (the 10.4.b "evaluation context changed b4
    // special attributes" case): the context node moves to that model's
    // default instance root unless it already belongs to it.
    XFModel *model = [self actionTargetModel];
    NSXMLNode *ctxNode = contextNode;
    if (model != self.model && ![model instanceOwningNode:ctxNode]) {
        ctxNode = [[model defaultInstance] documentElement];
    }
    if (self.contextExpr) {
        XFExprContext *c = [[XFExprContext alloc] initWithNode:ctxNode];
        c.model = model;
        ctxNode = [self.contextExpr evaluateInContext:c error:NULL].firstNode;
    }
    if (ctxNode == nil || self.nodesetBinding == nil) {
        return;
    }
    XFExprContext *listCtx = [[XFExprContext alloc] initWithNode:ctxNode];
    listCtx.model = model;
    NSArray<NSXMLNode *> *nodes = [self.nodesetBinding evaluateInContext:listCtx error:NULL].nodes ?: @[];
    if (nodes.count == 0) {
        return;
    }
    NSUInteger location = 0;
    if (self.atExpr) {
        XFExprContext *atCtx = [[XFExprContext alloc] initWithNode:ctxNode];
        atCtx.model = model;
        atCtx.nodeList = nodes;
        atCtx.size = nodes.count;
        atCtx.position = 1;
        double at = [self.atExpr evaluateInContext:atCtx error:NULL].numberValue;
        // Out-of-range and NaN CLAMP (XForms 1.1 10.4 / errata): at < 1
        // deletes the first node, at > size or NaN the last.
        NSInteger index;
        if (isnan(at)) {
            index = (NSInteger)nodes.count;
        } else {
            index = (NSInteger)lround(at);
            if (index < 1) {
                index = 1;
            }
            if ((NSUInteger)index > nodes.count) {
                index = (NSInteger)nodes.count;
            }
        }
        location = (NSUInteger)index;
        nodes = @[ nodes[location - 1] ];
    }

    // The instance ROOT cannot be deleted (nodeset="instance('x')"):
    // such nodes terminate with no effect.
    NSMutableArray<NSXMLNode *> *deletable = [NSMutableArray array];
    for (NSXMLNode *node in nodes) {
        if ([[node parent] kind] == NSXMLDocumentKind) {
            continue;
        }
        [deletable addObject:node];
    }
    nodes = deletable;
    if (nodes.count == 0) {
        return;
    }

    XFInstance *instance = [model instanceContainingNode:nodes.firstObject];
    NSMutableArray<NSXMLNode *> *deleted = [NSMutableArray array];
    NSMutableSet<NSString *> *repeatIDs = [NSMutableSet set];

    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"delete"];

    for (NSXMLNode *node in nodes) {
        [XFBind disposeNode:node model:model]; // XsltForms_mipbinding.nodedispose
        NSString *rid = [XFNodeState existingStateOnNode:node].repeatIdentifier;
        if (rid.length) {
            [repeatIDs addObject:rid];
        }
        NSXMLNode *parent = [node parent];
        if ([node kind] == NSXMLAttributeKind) {
            NSXMLElement *owner = (NSXMLElement *)parent;
            if ([owner isKindOfClass:[NSXMLElement class]]) {
                [owner removeAttributeForName:[node name]];
                [deleted addObject:node];
            }
        } else if (parent) {
            NSXMLElement *el = (NSXMLElement *)parent;
            if ([el isKindOfClass:[NSXMLElement class]] || [parent kind] == NSXMLDocumentKind) {
                NSUInteger idx = [node index];
                if ([parent kind] == NSXMLDocumentKind) {
                    [(NSXMLDocument *)parent removeChildAtIndex:idx];
                } else if ([parent kind] == NSXMLElementKind) {
                    [(NSXMLElement *)parent removeChildAtIndex:idx];
                } else {
                    NSLog(@"Unhandled parent kind: %lu", (unsigned long)[parent kind]);
                }
                [deleted addObject:node];
            }
        }
        if (parent) {
            [model addChange:parent];
        }
    }

    self.lastDeletedNodes = deleted;
    if (deleted.count) {
        // XFormsKit extension: XSLTForms' console does not log xf:delete,
        // but the designer console wants the mutation visible.
        XFTraceWrite(XFTraceKindAction, nil, self.element,
                     @"delete %lu node(s), first %@",
                     (unsigned long)deleted.count,
                     XFTraceDescribeNode(deleted.firstObject));
        [model setRebuilded:YES];
        [du addChangedModel:model];
        NSMutableDictionary *evctx = [@{ @"deleted-nodes": deleted } mutableCopy];
        if (location) {
            evctx[@"delete-location"] = @(location);
        }
        [XFXMLEvents dispatch:instance ?: model name:@"xforms-delete" context:evctx];
        for (NSString *rid in repeatIDs) {
            XFRepeat *repeat = [model repeatWithIdentifier:rid];
            XFExprContext *rctx = [[XFExprContext alloc] initWithNode:[[model defaultInstance] documentElement]];
            rctx.model = model;
            NSUInteger old = repeat.index;
            [repeat rebuildItemsWithContext:rctx error:NULL];
            if (repeat.nodes.count == 0) {
                [repeat setIndex:0];
            } else if (old > repeat.nodes.count) {
                [repeat setIndex:repeat.nodes.count];
            } else {
                [repeat setIndex:old];
                // the index kept its NUMBER but now names the next node —
                // a different item, so its inner repeats start fresh
                [repeat resetNestedRepeatIndexes];
            }
        }
    }
    [du closeAction:@"delete"];
}

@end
