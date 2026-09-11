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

/// One delayed xf:dispatch in flight: the timer retains this holder, the
/// holder holds its TARGET WEAKLY (the processor may be disposed before
/// the delay elapses; XSLTForms' setTimeout callback checks the same way).
@interface XFDelayedEvent : NSObject
@property (nonatomic, weak) id target;
@property (nonatomic, copy) NSString *name;
@end

@implementation XFDelayedEvent

- (void)fire:(NSTimer *)timer
{
    (void)timer;
    id target = self.target;
    if (target) {
        [XFXMLEvents dispatch:target name:self.name];
    }
}

@end

@implementation XFDispatchAction

- (instancetype)initWithElement:(XFXMLElement *)element
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
    for (XFXMLNode *child in [element children]) {
        if ([child kind] != XFXMLElementKind) {
            continue;
        }
        XFXMLElement *c = (XFXMLElement *)child;
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

- (NSString *)string:(XFXPath *)expr orLiteral:(NSString *)literal context:(XFXMLNode *)contextNode
{
    if (expr == nil) {
        return literal;
    }
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:contextNode];
    ctx.model = self.model;
    return [expr stringValueInContext:ctx error:NULL];
}

- (void)runWithContextNode:(XFXMLNode *)contextNode event:(XFEvent *)event
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
        XFXMLElement *el = [XFXML elementWithID:tid inNode:self.element.rootDocument];
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
        // window.setTimeout(dispatch): the event context is not carried.
        // An NSTimer on the main run loop, not dispatch_after on the main
        // queue — a gnustep-base built without GS_USE_LIBDISPATCH_RUNLOOP
        // never drains that queue from NSRunLoop, so the delayed event
        // would never fire there.
        XFDelayedEvent *delayed = [[XFDelayedEvent alloc] init];
        delayed.target = target;
        delayed.name = name;
        NSTimer *timer = [NSTimer timerWithTimeInterval:delay
                                                 target:delayed
                                               selector:@selector(fire:)
                                               userInfo:nil
                                                repeats:NO];
        // BOTH modes: GNUstep takes NSRunLoopCommonModes literally (a mode
        // that never spins), so the default mode carries the timer there;
        // on Apple the common-modes registration keeps it firing during
        // tracking and modal loops too.
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
        return;
    }
    [XFXMLEvents dispatch:target name:name context:evcontext.count ? evcontext : nil];
}

@end

@implementation XFShowHideAction

- (instancetype)initWithElement:(XFXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    self.name = [[element localName] isEqualToString:@"show"] ? @"xforms-dialog-open" : @"xforms-dialog-close";
    self.targetID = [[element attributeForName:@"dialog"] stringValue];
    return self;
}

@end
