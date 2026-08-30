#import "XFLabelControl.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFXPathValue.h"
#import "XFXML.h"

@implementation XFLabelControl

+ (instancetype)labelWithElement:(NSXMLElement *)element
                           model:(id)model
                           error:(NSError **)error
{
    NSString *preferred = [element attributeForName:@"value"] ? @"value" : @"ref";
    XFBinding *binding = [XFControl bindingOnElement:element preferredAttribute:preferred error:error];
    XFLabelControl *label = [[self alloc] initWithElement:element binding:binding label:nil];
    label.owner = model;
    if (binding == nil) {
        label.stringValue = [XFXML stringValueOfNode:element] ?: @"";
    }
    return label;
}

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    if (self.binding == nil) {
        self.relevant = YES;
        if (self.stringValue.length == 0) {
            self.stringValue = [XFXML stringValueOfNode:self.element] ?: @"";
        }
        return;
    }
    NSError *inner = nil;
    XFXPathValue *value = [self.binding evaluateInContext:context error:&inner];
    if (inner) {
        if (error) {
            *error = inner;
        }
        return;
    }
    self.boundNode = value.firstNode;
    self.stringValue = [value stringValue] ?: @"";
    [self applyMIPsFromBoundNode];
}

@end
