#import "XFMessageAction.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFXML.h"
#import "XFDeferredUpdates.h"
#import "XFModel.h"
#import "XFEvent.h"

@interface XFMessageAction ()
@property (nonatomic, strong) XFBinding *binding;
@property (nonatomic, copy, readwrite) NSString *level;
@property (nonatomic, copy, readwrite) NSString *lastText;
@end

@implementation XFMessageAction

- (instancetype)initWithElement:(NSXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    self.level = [[element attributeForName:@"level"] stringValue] ?: @"modal";
    NSString *ref = [[element attributeForName:@"ref"] stringValue];
    if (ref.length) {
        self.binding = [XFBinding bindingWithExpression:ref element:element error:error];
        if (self.binding == nil) {
            return nil;
        }
    }
    return self;
}

- (void)runWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    (void)event;
    NSString *text = nil;
    if (self.binding && contextNode) {
        XFExprContext *ctx = [[XFExprContext alloc] initWithNode:contextNode];
        ctx.model = self.model;
        text = [self.binding stringValueInContext:ctx error:NULL];
    } else {
        text = [XFXML stringValueOfNode:self.element];
    }
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.lastText = text;
    if (text.length) {
        [[XFDeferredUpdates sharedUpdates].messages addObject:text];
    }
}

@end
