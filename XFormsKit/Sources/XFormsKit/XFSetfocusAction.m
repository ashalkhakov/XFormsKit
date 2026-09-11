#import "XFSetfocusAction.h"
#import "XFControl.h"
#import "XFXML.h"
#import "XFXMLEvents.h"
#import "XFXPath.h"
#import "XFExprContext.h"
#import "XFEvent.h"
#import "XFNamespaces.h"
#import "XFModel.h"
#import <XFormsKit/XFXMLTypes.h>

@interface XFSetfocusAction ()
@property (nonatomic, copy, readwrite) NSString *controlID;
@property (nonatomic, weak, readwrite) id lastFocused;
@property (nonatomic, strong) XFXPath *controlExpr;
@end

@implementation XFSetfocusAction

- (instancetype)initWithElement:(XFXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    self.controlID = [[element attributeForName:@"control"] stringValue];
    XFXMLElement *ctrlEl = [XFXML firstElementWithLocalName:@"control"
                                              namespaceURI:XFXFormsNamespaceURI
                                                    inNode:element];
    if (ctrlEl) {
        NSString *v = [[ctrlEl attributeForName:@"value"] stringValue];
        if (v.length) {
            self.controlExpr = [XFXPath xpathWithString:v element:element error:error];
            if (self.controlExpr == nil) {
                return nil;
            }
        } else {
            NSString *lit = [XFXML stringValueOfNode:ctrlEl];
            if (lit.length) {
                self.controlID = lit;
            }
        }
    }
    return self;
}

- (void)runWithContextNode:(XFXMLNode *)contextNode event:(XFEvent *)event
{
    (void)event;
    NSString *cid = self.controlID;
    if (self.controlExpr) {
        XFExprContext *ctx = [[XFExprContext alloc] initWithNode:contextNode];
        ctx.model = self.model;
        cid = [self.controlExpr stringValueInContext:ctx error:NULL];
    }
    if (cid.length == 0) {
        return;
    }
    if ([cid hasPrefix:@"#"]) {
        cid = [cid substringFromIndex:1];
    }
    XFXMLElement *el = [XFXML elementWithID:cid inNode:self.element.rootDocument];
    if (el == nil) {
        return;
    }
    id xf = [[XFXMLEvents sharedEvents] xfElementForElement:el] ?: el;
    self.lastFocused = xf;
    [XFXMLEvents dispatch:xf name:@"xforms-focus"];
}

@end
