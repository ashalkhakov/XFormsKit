#import "XFOutputControl.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFXPathValue.h"

@implementation XFOutputControl

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    if (self.binding == nil) {
        return;
    }
    // xf:output/@value is a computed string, not necessarily a node-set.
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
}

@end
