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
    NSString *ref = [[element attributeForName:@"ref"] stringValue];
    if (ref.length == 0) {
        ref = [[element attributeForName:@"nodeset"] stringValue];
    }
    if (ref.length) {
        self.binding = [XFBinding bindingWithExpression:ref error:error];
        if (self.binding == nil) {
            return nil;
        }
    }
    NSString *value = [[element attributeForName:@"value"] stringValue];
    if (value.length) {
        self.valueExpr = [XFXPath xpathWithString:value error:error];
        if (self.valueExpr == nil) {
            return nil;
        }
    } else {
        self.literal = [XFXML stringValueOfNode:element];
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
        XFExprContext *valueCtx = [[XFExprContext alloc] initWithNode:node];
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
