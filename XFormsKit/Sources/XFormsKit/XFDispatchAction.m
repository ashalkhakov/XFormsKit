#import "XFDispatchAction.h"
#import "XFXMLEvents.h"
#import "XFModel.h"
#import "XFXML.h"
#import "XFEvent.h"
#import "XFXPath.h"
#import "XFExprContext.h"
#import "XFNamespaces.h"
#import "XFProcessor.h"
#import "XFSubmission.h"
#import <dispatch/dispatch.h>

@interface XFDispatchAction ()
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite) NSString *targetID;
@property (nonatomic, strong) XFXPath *nameExpr;
@property (nonatomic, strong) XFXPath *targetExpr;
@property (nonatomic, strong) XFXPath *delayExpr;
@property (nonatomic, copy) NSArray<NSDictionary *> *properties;
@property (nonatomic, assign) NSTimeInterval delay;
@end

@implementation XFDispatchAction

- (instancetype)initWithElement:(NSXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    // XFDispatch.js: name / targetid / delay as attributes or as child
    // elements (literal or @value expression); xf:property children give
    // the event context (G-48)
    self.name = [[element attributeForName:@"name"] stringValue];
    NSString *target = [[element attributeForName:@"targetid"] stringValue];
    if (target.length == 0) {
        target = [[element attributeForName:@"target"] stringValue];
    }
    self.targetID = target;
    NSString *delay = [[element attributeForName:@"delay"] stringValue];
    NSMutableArray *props = [NSMutableArray array];
    for (NSXMLNode *child in [element children]) {
        if ([child kind] != NSXMLElementKind) {
            continue;
        }
        NSXMLElement *c = (NSXMLElement *)child;
        if (![[c URI] isEqualToString:XFXFormsNamespaceURI]) {
            continue;
        }
        NSString *local = [c localName];
        NSString *value = [[c attributeForName:@"value"] stringValue];
        NSString *literal = [XFXML stringValueOfNode:c];
        XFXPath *expr = nil;
        if (value.length) {
            expr = [XFXPath xpathWithString:value element:c error:error];
            if (expr == nil) {
                return nil;
            }
        }
        if ([local isEqualToString:@"name"]) {
            self.nameExpr = expr;
            if (!expr) self.name = literal;
        } else if ([local isEqualToString:@"targetid"] || [local isEqualToString:@"target"]) {
            self.targetExpr = expr;
            if (!expr) self.targetID = literal;
        } else if ([local isEqualToString:@"delay"]) {
            self.delayExpr = expr;
            if (!expr) delay = literal;
        } else if ([local isEqualToString:@"property"]) {
            NSString *pname = [[c attributeForName:@"name"] stringValue];
            if (pname.length) {
                [props addObject:@{ @"name": pname, @"value": expr ?: (id)literal }];
            }
        }
    }
    self.properties = props;
    self.delay = delay.length ? [delay doubleValue] / 1000.0 : 0;
    return self;
}

- (NSString *)string:(XFXPath *)expr orLiteral:(NSString *)literal context:(NSXMLNode *)contextNode
{
    if (expr == nil) {
        return literal;
    }
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:contextNode];
    ctx.model = self.model;
    return [expr stringValueInContext:ctx error:NULL];
}

- (void)runWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    (void)event;
    NSString *name = [self string:self.nameExpr orLiteral:self.name context:contextNode];
    if (name.length == 0) {
        return;
    }
    NSString *targetID = [self string:self.targetExpr orLiteral:self.targetID context:contextNode];
    id target = nil;
    if (targetID.length) {
        NSString *tid = targetID;
        if ([tid hasPrefix:@"#"]) {
            tid = [tid substringFromIndex:1];
        }
        NSXMLElement *el = [XFXML elementWithID:tid inNode:self.element.rootDocument];
        if (el) {
            target = [[XFXMLEvents sharedEvents] xfElementForElement:el] ?: el;
        }
    }
    if (target == nil) {
        // XFDispatch.js: default targets for model events and xforms-submit
        XFModel *model = self.model;
        if ([self.model.owner isKindOfClass:[XFProcessor class]]) {
            model = [(XFProcessor *)self.model.owner modelContainingNode:contextNode] ?: self.model;
        }
        if ([name isEqualToString:@"xforms-submit"]) {
            target = model.defaultSubmission;
        } else if ([name isEqualToString:@"xforms-rebuild"] ||
                   [name isEqualToString:@"xforms-recalculate"] ||
                   [name isEqualToString:@"xforms-revalidate"] ||
                   [name isEqualToString:@"xforms-refresh"] ||
                   [name isEqualToString:@"xforms-reset"]) {
            target = model;
        }
    }
    if (target == nil) {
        return;
    }
    NSMutableDictionary *evcontext = [NSMutableDictionary dictionary];
    for (NSDictionary *prop in self.properties) {
        id v = prop[@"value"];
        NSString *sv = [v isKindOfClass:[XFXPath class]] ? [self string:v orLiteral:@"" context:contextNode] : v;
        evcontext[prop[@"name"]] = sv ?: @"";
    }
    NSTimeInterval delay = self.delay;
    if (self.delayExpr) {
        delay = [[self string:self.delayExpr orLiteral:@"0" context:contextNode] doubleValue] / 1000.0;
    }
    if (delay > 0) {
        // window.setTimeout(dispatch): the event context is not carried
        __weak id weakTarget = target;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            id t = weakTarget;
            if (t) {
                [XFXMLEvents dispatch:t name:name];
            }
        });
        return;
    }
    [XFXMLEvents dispatch:target name:name context:evcontext.count ? evcontext : nil];
}

@end
