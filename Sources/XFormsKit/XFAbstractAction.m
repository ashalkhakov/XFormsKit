#import "XFAbstractAction.h"
#import "XFAction.h"
#import "XFSetvalueAction.h"
#import "XFDispatchAction.h"
#import "XFMessageAction.h"
#import "XFModelAction.h"
#import "XFSendAction.h"
#import "XFLoadAction.h"
#import "XFSetindexAction.h"
#import "XFInsertAction.h"
#import "XFDeleteAction.h"
#import "XFToggleAction.h"
#import "XFSetfocusAction.h"
#import "XFEvent.h"
#import "XFModel.h"
#import "XFInstance.h"
#import "XFProcessor.h"
#import "XFControl.h"
#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFNamespaces.h"
#import "XFXML.h"
#import "XFErrors.h"
#import <XFormsKit/XFXMLTypes.h>

@interface XFAbstractAction ()
@property (nonatomic, strong, readwrite) XFXMLElement *element;
@property (nonatomic, copy, readwrite) NSString *identifier;
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableInvokedEvents;
@property (nonatomic, assign, readwrite) NSInteger invocationCount;
@property (nonatomic, strong, readwrite) XFEvent *lastEvent;
@end

@implementation XFAbstractAction

+ (NSSet<NSString *> *)actionNames
{
    static NSSet *names;
    @synchronized(self) {
        if (names == nil) {
            names = [NSSet setWithObjects:
                     @"action", @"setvalue", @"dispatch", @"message",
                     @"rebuild", @"recalculate", @"revalidate", @"refresh", @"reset",
                     @"send", @"load", @"setindex",
                     @"insert", @"delete", @"toggle", @"setfocus",
                     @"setvar", @"var", @"show", @"hide", @"unload", @"setnode",
                     nil];
        }
    }
    return names;
}

+ (BOOL)isActionElement:(XFXMLElement *)element
{
    if ([XFXML element:element hasLocalName:@"confirm" namespaceURI:XFAJXNamespaceURI]) {
        return YES;   // ajx:confirm (message-confirm.xsl, G-95)
    }
    if (![XFXML element:element hasLocalName:[element localName] namespaceURI:XFXFormsNamespaceURI]
        || ![[self actionNames] containsObject:[element localName]]) {
        return NO;
    }
    if ([[element localName] isEqualToString:@"var"]) {
        // xf:var is an action only inside an action (XFVar.js otherwise:
        // a control published to the UI scope)
        XFXMLNode *parent = [element parent];
        return [parent kind] == XFXMLElementKind
            && [[(XFXMLElement *)parent URI] isEqualToString:XFXFormsNamespaceURI]
            && [[self actionNames] containsObject:[(XFXMLElement *)parent localName]]
            && ![[(XFXMLElement *)parent localName] isEqualToString:@"var"];
    }
    return YES;
}

+ (instancetype)actionWithElement:(XFXMLElement *)element
                            model:(XFModel *)model
                            error:(NSError **)error
{
    if (![self isActionElement:element]) {
        return nil;
    }
    NSString *name = [element localName];
    Class cls = [XFAction class];
    if ([name isEqualToString:@"setvalue"]) {
        cls = [XFSetvalueAction class];
    } else if ([name isEqualToString:@"dispatch"]) {
        cls = [XFDispatchAction class];
    } else if ([name isEqualToString:@"show"] || [name isEqualToString:@"hide"]) {
        cls = [XFShowHideAction class];
    } else if ([name isEqualToString:@"unload"]) {
        cls = [XFUnloadAction class];
    } else if ([name isEqualToString:@"setnode"]) {
        cls = [XFSetnodeAction class];
    } else if ([name isEqualToString:@"message"]) {
        cls = [XFMessageAction class];
    } else if ([name isEqualToString:@"confirm"] && [[element URI] isEqualToString:XFAJXNamespaceURI]) {
        cls = [XFConfirmAction class];
    } else if ([name isEqualToString:@"rebuild"] ||
               [name isEqualToString:@"recalculate"] ||
               [name isEqualToString:@"revalidate"] ||
               [name isEqualToString:@"refresh"] ||
               [name isEqualToString:@"reset"]) {
        cls = [XFModelAction class];
    } else if ([name isEqualToString:@"send"]) {
        cls = [XFSendAction class];
    } else if ([name isEqualToString:@"load"]) {
        cls = [XFLoadAction class];
    } else if ([name isEqualToString:@"setindex"]) {
        cls = [XFSetindexAction class];
    } else if ([name isEqualToString:@"insert"]) {
        cls = [XFInsertAction class];
    } else if ([name isEqualToString:@"delete"]) {
        cls = [XFDeleteAction class];
    } else if ([name isEqualToString:@"toggle"]) {
        cls = [XFToggleAction class];
    } else if ([name isEqualToString:@"setfocus"]) {
        cls = [XFSetfocusAction class];
    } else if ([name isEqualToString:@"setvar"] || [name isEqualToString:@"var"]) {
        cls = [XFSetvarAction class];
    }
    return [[cls alloc] initWithElement:element model:model error:error];
}

- (instancetype)initWithElement:(XFXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _element = element;
    _model = model;
    _identifier = [[element attributeForName:@"id"] stringValue];
    _mutableInvokedEvents = [NSMutableArray array];

    NSError *inner = nil;
    NSString *ifattr = [[element attributeForName:@"if"] stringValue];
    if (ifattr.length) {
        _ifExpr = [XFXPath xpathWithString:ifattr element:element error:&inner];
        if (_ifExpr == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
    }
    NSString *whileattr = [[element attributeForName:@"while"] stringValue];
    if (whileattr.length) {
        _whileExpr = [XFXPath xpathWithString:whileattr element:element error:&inner];
        if (_whileExpr == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
    }
    NSString *iterate = [[element attributeForName:@"iterate"] stringValue];
    if (iterate.length) {
        _iterateExpr = [XFXPath xpathWithString:iterate element:element error:&inner];
        if (_iterateExpr == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
    }
    return self;
}

- (NSArray<NSString *> *)invokedEvents
{
    return [self.mutableInvokedEvents copy];
}

- (BOOL)wasInvokedForEvent:(NSString *)name
{
    return [self.mutableInvokedEvents containsObject:name];
}

- (void)recordEvent:(XFEvent *)event
{
    self.lastEvent = event;
    self.invocationCount += 1;
    if (event.type.length) {
        [self.mutableInvokedEvents addObject:event.type];
    }
}

- (XFExprContext *)contextWithNode:(XFXMLNode *)node
{
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:node];
    ctx.model = self.model;
    return ctx;
}

- (BOOL)booleanExpr:(XFXPath *)expr contextNode:(XFXMLNode *)node
{
    if (expr == nil || node == nil) {
        return YES;
    }
    XFXPathValue *value = [expr evaluateInContext:[self contextWithNode:node] error:NULL];
    return value ? [value booleanValue] : NO;
}

- (void)handleXMLEvent:(XFEvent *)event
{
    [self handleXMLEvent:event contextNode:nil];
}

- (void)handleXMLEvent:(XFEvent *)event contextNode:(XFXMLNode *)contextNode
{
    // XsltForms_abstractAction.execute: ctx = element.node || default root
    XFXMLNode *ctx = contextNode;
    if (ctx == nil) {
        id xf = event.xfElement;
        if ([xf isKindOfClass:[XFControl class]]) {
            ctx = [(XFControl *)xf boundNode] ?: [(XFControl *)xf inScopeContextNode];
        }
    }
    if (ctx == nil) {
        ctx = [[self.model defaultInstance] documentElement];
    }
    [self executeWithContextNode:ctx event:event];
}

/// A sequence's context node can belong to a DISCARDED document after an
/// earlier xf:reset or replace="instance" swapped the instance's DOM
/// (XSLTForms never sees this: it re-resolves element.node on every
/// execution). A node no model instance owns any more falls back to the
/// default instance root — what a fresh resolution would yield for a
/// model-less handler.
- (XFXMLNode *)liveContextNode:(XFXMLNode *)node
{
    if (node == nil) {
        return nil;
    }
    XFModel *model = self.model;
    if ([model instanceOwningNode:node]) {
        return node;
    }
    if ([model.owner isKindOfClass:[XFProcessor class]]) {
        for (XFModel *m in [(XFProcessor *)model.owner models]) {
            if ([m instanceOwningNode:node]) {
                return node;
            }
        }
    }
    return [[model defaultInstance] documentElement] ?: node;
}

/// The model this action's bindings evaluate in: @model="id" switches it
/// (and, per XsltForms_binding.bind_evaluate, the context node moves to
/// that model's default instance root unless it already belongs there).
- (XFModel *)actionTargetModel
{
    NSString *mid = [[self.element attributeForName:@"model"] stringValue];
    if (mid.length == 0 || [mid isEqualToString:self.model.identifier]) {
        return self.model;
    }
    if ([self.model.owner isKindOfClass:[XFProcessor class]]) {
        for (XFModel *m in [(XFProcessor *)self.model.owner models]) {
            if ([m.identifier isEqualToString:mid]) {
                return m;
            }
        }
    }
    return self.model;
}

- (void)executeWithContextNode:(XFXMLNode *)contextNode event:(XFEvent *)event
{
    if (event.stopped) {
        return;
    }
    [self recordEvent:event];
    XFXMLNode *ctx = [self liveContextNode:contextNode];
    if (ctx == nil) {
        ctx = [[self.model defaultInstance] documentElement];
    }
    if (self.iterateExpr) {
        XFXPathValue *nodes = [self.iterateExpr evaluateInContext:[self contextWithNode:ctx] error:NULL];
        for (XFXMLNode *item in nodes.nodes) {
            [self execWithContextNode:item event:event];
        }
        return;
    }
    if (self.whileExpr) {
        NSUInteger guard = 0;
        while ([self booleanExpr:self.whileExpr contextNode:ctx] && guard < 1000) {
            if (![self execWithContextNode:ctx event:event]) {
                break;
            }
            guard++;
        }
        return;
    }
    [self execWithContextNode:ctx event:event];
}

- (BOOL)execWithContextNode:(XFXMLNode *)contextNode event:(XFEvent *)event
{
    if (self.ifExpr) {
        if (![self booleanExpr:self.ifExpr contextNode:contextNode]) {
            return NO;
        }
    }
    [self runWithContextNode:contextNode event:event];
    return YES;
}

- (void)runWithContextNode:(XFXMLNode *)contextNode event:(XFEvent *)event
{
    (void)contextNode;
    (void)event;
}

@end
