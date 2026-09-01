#import "XFSetindexAction.h"
#import "XFXMLEvents.h"
#import "XFRepeat.h"
#import "XFModel.h"
#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFInstance.h"
#import "XFEvent.h"
#import <math.h>

@interface XFSetindexAction ()
@property (nonatomic, copy, readwrite) NSString *repeatID;
@property (nonatomic, copy, readwrite) NSString *indexExpression;
@property (nonatomic, strong) XFXPath *indexExpr;
@end

@implementation XFSetindexAction

- (instancetype)initWithElement:(NSXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    self.repeatID = [[element attributeForName:@"repeat"] stringValue];
    self.indexExpression = [[element attributeForName:@"index"] stringValue];
    if (self.indexExpression.length) {
        self.indexExpr = [XFXPath xpathWithString:self.indexExpression element:element error:error];
        if (self.indexExpr == nil) {
            return nil;
        }
    }
    return self;
}

- (void)runWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    (void)event;
    XFRepeat *repeat = [self.model repeatWithIdentifier:self.repeatID];
    if (repeat == nil || self.indexExpr == nil) {
        return;
    }
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:contextNode];
    ctx.model = self.model;
    XFXPathValue *value = [self.indexExpr evaluateInContext:ctx error:NULL];
    double n = value ? [value numberValue] : NAN;
    if (isnan(n)) {
        return;
    }
    // debugConsole: "setIndex index"
    XFTraceWrite(XFTraceKindAction, nil, self.element,
                 @"setIndex %lu", (unsigned long)(NSUInteger)n);
    [repeat setIndex:(NSUInteger)n];
}

@end
