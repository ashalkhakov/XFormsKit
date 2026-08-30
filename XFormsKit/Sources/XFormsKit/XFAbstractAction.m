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
#import "XFControl.h"
#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFNamespaces.h"
#import "XFXML.h"
#import "XFErrors.h"
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLNode.h>

@interface XFAbstractAction ()
@property (nonatomic, strong, readwrite) NSXMLElement *element;
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
                     nil];
        }
    }
    return names;
}

+ (BOOL)isActionElement:(NSXMLElement *)element
{
    return [XFXML element:element hasLocalName:[element localName] namespaceURI:XFXFormsNamespaceURI]
        && [[self actionNames] containsObject:[element localName]];
}

+ (instancetype)actionWithElement:(NSXMLElement *)element
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
    } else if ([name isEqualToString:@"message"]) {
        cls = [XFMessageAction class];
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
    }
    return [[cls alloc] initWithElement:element model:model error:error];
}

- (instancetype)initWithElement:(NSXMLElement *)element
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

- (XFExprContext *)contextWithNode:(NSXMLNode *)node
{
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:node];
    ctx.model = self.model;
    return ctx;
}

- (BOOL)booleanExpr:(XFXPath *)expr contextNode:(NSXMLNode *)node
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

- (void)handleXMLEvent:(XFEvent *)event contextNode:(NSXMLNode *)contextNode
{
    // XsltForms_abstractAction.execute: ctx = element.node || default root
    NSXMLNode *ctx = contextNode;
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

- (void)executeWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    if (event.stopped) {
        return;
    }
    [self recordEvent:event];
    NSXMLNode *ctx = contextNode;
    if (ctx == nil) {
        ctx = [[self.model defaultInstance] documentElement];
    }
    if (self.iterateExpr) {
        XFXPathValue *nodes = [self.iterateExpr evaluateInContext:[self contextWithNode:ctx] error:NULL];
        for (NSXMLNode *item in nodes.nodes) {
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

- (BOOL)execWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    if (self.ifExpr) {
        if (![self booleanExpr:self.ifExpr contextNode:contextNode]) {
            return NO;
        }
    }
    [self runWithContextNode:contextNode event:event];
    return YES;
}

- (void)runWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    (void)contextNode;
    (void)event;
}

@end
