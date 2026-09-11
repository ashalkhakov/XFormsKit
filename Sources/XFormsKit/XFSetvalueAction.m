#import "XFSetvalueAction.h"
#import "XFBinding.h"
#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFModel.h"
#import "XFXML.h"
#import "XFDeferredUpdates.h"
#import "XFEvent.h"
#import "XFXMLEvents.h"
#import "XFProcessor.h"

@interface XFSetvalueAction ()
@property (nonatomic, strong, readwrite) XFBinding *binding;
@property (nonatomic, strong, readwrite) XFXPath *valueExpr;
@property (nonatomic, copy, readwrite) NSString *literal;
@property (nonatomic, strong) XFXPath *contextExpr;
@end

@implementation XFSetvalueAction

- (instancetype)initWithElement:(XFXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    NSError *bindError = nil;
    self.binding = [XFBinding bindingForElement:element attribute:@"ref" error:&bindError];
    if (bindError) {
        if (error) {
            *error = bindError;
        }
        return nil;
    }
    NSString *value = [[element attributeForName:@"value"] stringValue];
    if (value.length) {
        self.valueExpr = [XFXPath xpathWithString:value element:element error:error];
        if (self.valueExpr == nil) {
            return nil;
        }
    } else {
        // setvalue.xsl: normalize-space(text()) (G-49)
        NSMutableString *text = [NSMutableString string];
        for (XFXMLNode *c in [element children]) {
            if ([c kind] == XFXMLTextKind) {
                [text appendString:[c stringValue] ?: @""];
            }
        }
        self.literal = [XFXML normalizeSpace:text];
    }
    NSString *context = [[element attributeForName:@"context"] stringValue];
    if (context.length) {
        self.contextExpr = [XFXPath xpathWithString:context element:element error:error];
        if (self.contextExpr == nil) {
            return nil;
        }
    }
    return self;
}

- (void)runWithContextNode:(XFXMLNode *)contextNode event:(XFEvent *)event
{
    (void)event;
    if (self.binding == nil || contextNode == nil) {
        return;
    }
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:contextNode];
    ctx.model = self.model;
    XFXMLNode *node = [self.binding boundNodeInContext:ctx error:NULL];
    if (node == nil) {
        return;
    }
    NSString *value = self.literal ?: @"";
    if (self.valueExpr) {
        // XFSetvalue.js: @value evaluates against the bound node, or against
        // the @context node when there is one (G-49)
        XFXMLNode *valueNode = node;
        if (self.contextExpr) {
            valueNode = [self.contextExpr evaluateInContext:ctx error:NULL].firstNode ?: node;
        }
        XFExprContext *valueCtx = [[XFExprContext alloc] initWithNode:valueNode];
        valueCtx.model = self.model;
        // the XForms context() function reads the ACTION's in-scope
        // context node — inside a repeat item that is the item's node,
        // not the setvalue target (7.10.4.a)
        valueCtx.currentNode = contextNode;
        value = [self.valueExpr stringValueInContext:valueCtx error:NULL] ?: @"";
    }
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"setvalue"];
    // debugConsole: "Setvalue name2string(node) = value"
    XFTraceWrite(XFTraceKindAction, nil, self.element,
                 @"Setvalue %@ = %@", XFTraceDescribeNode(node), value);
    [XFXML setStringValue:value ofNode:node];
    [self.model addChange:node];
    [du addChangedModel:self.model];
    [du closeAction:@"setvalue"];
}

@end

@interface XFSetvarAction ()
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, strong) XFBinding *valueBinding;
@end

@implementation XFSetvarAction

- (instancetype)initWithElement:(XFXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    self.name = [[element attributeForName:@"name"] stringValue] ?: @"";
    NSError *inner = nil;
    self.valueBinding = [XFBinding bindingForElement:element attribute:@"value" error:&inner];
    if (inner) {
        if (error) {
            *error = inner;
        }
        return nil;
    }
    return self;
}

- (void)runWithContextNode:(XFXMLNode *)contextNode event:(XFEvent *)event
{
    (void)event;
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:contextNode];
    ctx.model = self.model;
    XFXPathValue *v = self.valueBinding ? [self.valueBinding evaluateInContext:ctx error:NULL] : nil;
    [[XFDeferredUpdates sharedUpdates] setVariable:v ?: [XFXPathValue string:@""] named:self.name];
}

@end

@interface XFSetnodeAction ()
@property (nonatomic, strong, readwrite) XFBinding *binding;
@property (nonatomic, assign, readwrite) BOOL inner;
@property (nonatomic, strong) XFXPath *valueExpr;
@property (nonatomic, strong) XFXPath *contextExpr;
@end

@implementation XFSetnodeAction

- (instancetype)initWithElement:(XFXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    NSError *inner = nil;
    self.binding = [XFBinding bindingForElement:element attribute:@"ref" error:&inner];
    if (inner) {
        if (error) *error = inner;
        return nil;
    }
    NSString *outer = [[element attributeForName:@"outer"] stringValue];
    NSString *innerExpr = [[element attributeForName:@"inner"] stringValue];
    self.inner = outer.length == 0;
    NSString *expr = outer.length ? outer : innerExpr;
    if (expr.length) {
        self.valueExpr = [XFXPath xpathWithString:expr element:element error:error];
        if (self.valueExpr == nil) {
            return nil;
        }
    }
    NSString *context = [[element attributeForName:@"context"] stringValue];
    if (context.length) {
        self.contextExpr = [XFXPath xpathWithString:context element:element error:error];
        if (self.contextExpr == nil) {
            return nil;
        }
    }
    return self;
}

- (void)runWithContextNode:(XFXMLNode *)contextNode event:(XFEvent *)event
{
    (void)event;
    if (self.binding == nil || contextNode == nil) {
        return;
    }
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:contextNode];
    ctx.model = self.model;
    XFXMLNode *node = [self.binding boundNodeInContext:ctx error:NULL];
    if ([node kind] != XFXMLElementKind) {
        return;
    }
    XFXMLNode *valueNode = node;
    if (self.contextExpr) {
        valueNode = [self.contextExpr evaluateInContext:ctx error:NULL].firstNode ?: node;
    }
    XFExprContext *valueCtx = [[XFExprContext alloc] initWithNode:valueNode];
    valueCtx.model = self.model;
    NSString *value = self.valueExpr ? ([self.valueExpr stringValueInContext:valueCtx error:NULL] ?: @"") : @"";
    // parse as a fragment (several elements / text allowed); the inserted
    // nodes are standalone copies — on Apple, insertChild:atIndex: with a
    // node detached from another document loses that node's content
    XFXMLDocument *doc = [[XFXMLDocument alloc] initWithXMLString:[NSString stringWithFormat:@"<x>%@</x>", value]
                                                          options:0 error:NULL];
    NSMutableArray<XFXMLNode *> *parsed = [NSMutableArray array];
    for (XFXMLNode *n in [[doc rootElement] children]) {
        [parsed addObject:[n copy]];
    }
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"XsltForms_setnode.prototype.run"];
    // debugConsole: "Setnode name2string(node) inner|outer = value"
    XFTraceWrite(XFTraceKindAction, nil, self.element,
                 @"Setnode %@%@ = %@", XFTraceDescribeNode(node),
                 self.inner ? @" inner" : @" outer", value);
    XFXMLElement *element = (XFXMLElement *)node;
    XFXMLNode *changed = node;
    if (self.inner) {
        for (XFXMLNode *c in [[element children] copy]) {
            [c detach];
        }
        for (XFXMLNode *n in parsed) {
            [element addChild:n];
        }
    } else {
        XFXMLElement *parent = (XFXMLElement *)[element parent];
        if ([parent kind] == XFXMLElementKind) {
            NSUInteger at = [element index];
            [element detach];
            for (XFXMLNode *n in parsed) {
                [parent insertChild:n atIndex:at++];
            }
            changed = parent;
        } else {
            // the document element: keep it, replace its content
            for (XFXMLNode *c in [[element children] copy]) {
                [c detach];
            }
            for (XFXMLNode *n in parsed) {
                [element addChild:n];
            }
        }
    }
    XFModel *model = self.model;
    if ([model.owner isKindOfClass:[XFProcessor class]]) {
        model = [(XFProcessor *)model.owner modelContainingNode:changed] ?: model;
    }
    [model addChange:changed];
    [model setRebuilded:YES];
    [du addChangedModel:model];
    [XFXMLEvents dispatch:model name:@"xforms-rebuild"];
    [du closeAction:@"XsltForms_setnode.prototype.run"];
}

@end
