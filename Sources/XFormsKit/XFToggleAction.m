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
            self.caseExpr = [XFXPath xpathWithString:v error:error];
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

- (XFSwitch *)switchContainingCaseID:(NSString *)caseID
{
    NSXMLDocument *doc = self.element.rootDocument;
    NSXMLElement *caseEl = [XFXML elementWithID:caseID inNode:doc];
    if (caseEl == nil) {
        return nil;
    }
    id xf = [[XFXMLEvents sharedEvents] xfElementForElement:caseEl];
    if ([xf isKindOfClass:[XFCase class]]) {
        XFControl *parent = [(XFCase *)xf parentControl];
        if ([parent isKindOfClass:[XFSwitch class]]) {
            return (XFSwitch *)parent;
        }
    }
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
    (void)event;
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
    XFSwitch *sw = [self switchContainingCaseID:cid];
    XFCase *caze = [sw caseWithIdentifier:cid];
    if (caze) {
        [sw selectCase:caze];
    }
}

@end
