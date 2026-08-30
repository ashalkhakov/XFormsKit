#import "XFSetvalueAction.h"
#import "XFBinding.h"
#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFModel.h"
#import "XFXML.h"
#import "XFDeferredUpdates.h"
#import "XFEvent.h"

@interface XFSetvalueAction ()
@property (nonatomic, strong, readwrite) XFBinding *binding;
@property (nonatomic, strong, readwrite) XFXPath *valueExpr;
@property (nonatomic, copy, readwrite) NSString *literal;
@property (nonatomic, strong) XFXPath *contextExpr;
@end

@implementation XFSetvalueAction

- (instancetype)initWithElement:(NSXMLElement *)element
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
        for (NSXMLNode *c in [element children]) {
            if ([c kind] == NSXMLTextKind) {
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

- (void)runWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    (void)event;
    if (self.binding == nil || contextNode == nil) {
        return;
    }
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:contextNode];
    ctx.model = self.model;
    NSXMLNode *node = [self.binding boundNodeInContext:ctx error:NULL];
    if (node == nil) {
        return;
    }
    NSString *value = self.literal ?: @"";
    if (self.valueExpr) {
        // XFSetvalue.js: @value evaluates against the bound node, or against
        // the @context node when there is one (G-49)
        NSXMLNode *valueNode = node;
        if (self.contextExpr) {
            valueNode = [self.contextExpr evaluateInContext:ctx error:NULL].firstNode ?: node;
        }
        XFExprContext *valueCtx = [[XFExprContext alloc] initWithNode:valueNode];
        valueCtx.model = self.model;
        value = [self.valueExpr stringValueInContext:valueCtx error:NULL] ?: @"";
    }
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"setvalue"];
    [XFXML setStringValue:value ofNode:node];
    [self.model addChange:node];
    [du addChangedModel:self.model];
    [du closeAction:@"setvalue"];
}

@end
