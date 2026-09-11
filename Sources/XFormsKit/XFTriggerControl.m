#import "XFTriggerControl.h"
#import "XFXMLEvents.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFNodeState.h"

@implementation XFTriggerControl

- (BOOL)isValueControl
{
    return NO;
}

+ (instancetype)triggerWithElement:(XFXMLElement *)element
                             model:(id)model
                             error:(NSError **)error
{
    XFBinding *binding = [XFControl bindingOnElement:element preferredAttribute:@"ref" error:error];
    XFTriggerControl *trigger = [[self alloc] initWithElement:element
                                                      binding:binding
                                                        label:[XFControl labelForElement:element]];
    trigger.owner = model;
    return trigger;
}

- (BOOL)isTrigger
{
    return YES;
}

- (void)activate
{
    [XFXMLEvents dispatch:self name:@"DOMActivate"];
}

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    if (self.binding == nil) {
        self.relevant = YES;
        return;
    }
    [super refreshWithContext:context error:error];
}

@end
