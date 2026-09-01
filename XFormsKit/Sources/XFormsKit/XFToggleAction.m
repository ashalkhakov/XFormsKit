#import "XFToggleAction.h"
#import "XFSwitch.h"
#import "XFModel.h"
#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFXML.h"
#import "XFXMLEvents.h"
#import "XFNamespaces.h"
#import "XFEvent.h"
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLDocument.h>

@interface XFToggleAction ()
@property (nonatomic, copy, readwrite) NSString *caseID;
@property (nonatomic, copy, readwrite) NSString *lastCaseID;
@property (nonatomic, strong) XFXPath *caseExpr;
@end

@implementation XFToggleAction

- (instancetype)initWithElement:(NSXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    self.caseID = [[element attributeForName:@"case"] stringValue];
    NSXMLElement *caseEl = [XFXML firstElementWithLocalName:@"case"
                                              namespaceURI:XFXFormsNamespaceURI
                                                    inNode:element];
    if (caseEl) {
        NSString *v = [[caseEl attributeForName:@"value"] stringValue];
        if (v.length) {
            self.caseExpr = [XFXPath xpathWithString:v element:element error:error];
            if (self.caseExpr == nil) {
                return nil;
            }
        } else {
            NSString *lit = [XFXML stringValueOfNode:caseEl];
            if (lit.length) {
                self.caseID = lit;
            }
        }
    }
    return self;
}

- (XFSwitch *)switchContainingCaseID:(NSString *)caseID event:(XFEvent *)event
{
    NSXMLDocument *doc = self.element.rootDocument;
    NSXMLElement *caseEl = [XFXML elementWithID:caseID inNode:doc];
    if (caseEl == nil) {
        return nil;
    }
    // XsltForms_toggle.run: IdManager.find resolves the case CLONE in the
    // repeat item the event came from. Repeat items here share the template
    // elements (no clones), so resolve the live per-item switch through the
    // event target's control chain instead: the activated trigger's
    // parentControl chain reaches ITS OWN item's switch (9.3.1.f, 9.3.4.a).
    NSXMLElement *swEl = nil;
    for (NSXMLNode *n = [caseEl parent]; n; n = [n parent]) {
        if ([n kind] == NSXMLElementKind
            && [XFXML element:(NSXMLElement *)n hasLocalName:@"switch"
                 namespaceURI:XFXFormsNamespaceURI]) {
            swEl = (NSXMLElement *)n;
            break;
        }
    }
    id origin = event.xfElement;
    if (swEl && [origin isKindOfClass:[XFControl class]]) {
        for (XFControl *c = origin; c; c = c.parentControl) {
            if ([c isKindOfClass:[XFSwitch class]] && c.element == swEl) {
                return (XFSwitch *)c;
            }
        }
    }
    id xf = [[XFXMLEvents sharedEvents] xfElementForElement:caseEl];
    if ([xf isKindOfClass:[XFCase class]]) {
        XFControl *parent = [(XFCase *)xf parentControl];
        if ([parent isKindOfClass:[XFSwitch class]]) {
            return (XFSwitch *)parent;
        }
    }
    // Walk up to xf:switch and use its xfElement.
    NSXMLNode *n = [caseEl parent];
    while (n) {
        if ([n kind] == NSXMLElementKind) {
            NSXMLElement *el = (NSXMLElement *)n;
            if ([XFXML element:el hasLocalName:@"switch" namespaceURI:XFXFormsNamespaceURI]) {
                id sw = [[XFXMLEvents sharedEvents] xfElementForElement:el];
                if ([sw isKindOfClass:[XFSwitch class]]) {
                    return sw;
                }
            }
        }
        n = [n parent];
    }
    return nil;
}

- (void)runWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    NSString *cid = self.caseID;
    if (self.caseExpr) {
        XFExprContext *ctx = [[XFExprContext alloc] initWithNode:contextNode];
        ctx.model = self.model;
        cid = [self.caseExpr stringValueInContext:ctx error:NULL];
    }
    if (cid.length == 0) {
        return;
    }
    if ([cid hasPrefix:@"#"]) {
        cid = [cid substringFromIndex:1];
    }
    self.lastCaseID = cid;
    XFSwitch *sw = [self switchContainingCaseID:cid event:event];
    XFCase *caze = [sw caseWithIdentifier:cid];
    if (caze) {
        [sw selectCase:caze];
    }
}

@end
