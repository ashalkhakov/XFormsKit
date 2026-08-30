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
    NSString *nodeset = [[element attributeForName:@"nodeset"] stringValue];
    if (nodeset.length == 0) {
        nodeset = [[element attributeForName:@"ref"] stringValue];
    }
    NSString *bindID = [[element attributeForName:@"bind"] stringValue];
    if (bindID.length) {
        XFBind *bind = [model bindWithIdentifier:bindID];
        if (bind.nodesetBinding.expression.length) {
            nodeset = bind.nodesetBinding.expression;
        }
    }
    if (nodeset.length) {
        self.nodesetBinding = [XFBinding bindingWithExpression:nodeset error:error];
        if (self.nodesetBinding == nil) {
            return nil;
        }
    }
    NSString *at = [[element attributeForName:@"at"] stringValue];
    if (at.length) {
        self.atExpr = [XFXPath xpathWithString:at error:error];
        if (self.atExpr == nil) {
            return nil;
        }
    }
    NSString *ctx = [[element attributeForName:@"context"] stringValue];
    if (ctx.length) {
        self.contextExpr = [XFXPath xpathWithString:ctx error:error];
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
    NSXMLNode *ctxNode = contextNode;
    if (self.contextExpr) {
        XFExprContext *c = [[XFExprContext alloc] initWithNode:contextNode];
        c.model = self.model;
        ctxNode = [self.contextExpr evaluateInContext:c error:NULL].firstNode;
    }
    if (ctxNode == nil || self.nodesetBinding == nil) {
        return;
    }
    XFExprContext *listCtx = [[XFExprContext alloc] initWithNode:ctxNode];
    listCtx.model = self.model;
    NSArray<NSXMLNode *> *nodes = [self.nodesetBinding evaluateInContext:listCtx error:NULL].nodes ?: @[];
    NSUInteger location = 0;
    if (self.atExpr) {
        XFExprContext *atCtx = [[XFExprContext alloc] initWithNode:ctxNode];
        atCtx.model = self.model;
        atCtx.nodeList = nodes;
        atCtx.size = nodes.count;
        atCtx.position = 1;
        double at = [self.atExpr evaluateInContext:atCtx error:NULL].numberValue;
        if (isnan(at)) {
            return;
        }
        NSInteger index = (NSInteger)lround(at);
        if (index < 1 || (NSUInteger)index > nodes.count) {
            return;
        }
        location = (NSUInteger)index;
        nodes = @[ nodes[location - 1] ];
    }

    if (nodes.count == 0) {
        return;
    }

    XFInstance *instance = [self.model instanceContainingNode:nodes.firstObject];
    NSMutableArray<NSXMLNode *> *deleted = [NSMutableArray array];
    NSMutableSet<NSString *> *repeatIDs = [NSMutableSet set];

    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"delete"];

    for (NSXMLNode *node in nodes) {
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
                [parent removeChildAtIndex:idx];
                [deleted addObject:node];
            }
        }
        if (parent) {
            [self.model addChange:parent];
        }
    }

    self.lastDeletedNodes = deleted;
    if (deleted.count) {
        [self.model setRebuilded:YES];
        [du addChangedModel:self.model];
        NSMutableDictionary *evctx = [@{ @"deleted-nodes": deleted } mutableCopy];
        if (location) {
            evctx[@"delete-location"] = @(location);
        }
        [XFXMLEvents dispatch:instance ?: self.model name:@"xforms-delete" context:evctx];
        for (NSString *rid in repeatIDs) {
            XFRepeat *repeat = [self.model repeatWithIdentifier:rid];
            XFExprContext *rctx = [[XFExprContext alloc] initWithNode:[[self.model defaultInstance] documentElement]];
            rctx.model = self.model;
            NSUInteger old = repeat.index;
            [repeat rebuildItemsWithContext:rctx error:NULL];
            if (repeat.nodes.count == 0) {
                [repeat setIndex:0];
            } else if (old > repeat.nodes.count) {
                [repeat setIndex:repeat.nodes.count];
            } else {
                [repeat setIndex:old];
            }
        }
    }
    [du closeAction:@"delete"];
}

@end
