#import "XFRangeControl.h"
#import "XFBinding.h"
#import "XFExprContext.h"

@implementation XFRangeControl

+ (double)doubleAttr:(NSXMLElement *)element name:(NSString *)name fallback:(double)fallback
{
    NSString *v = [[element attributeForName:name] stringValue];
    if (v.length == 0) {
        return fallback;
    }
    return [v doubleValue];
}

+ (instancetype)rangeWithElement:(NSXMLElement *)element
                           model:(id)model
                           error:(NSError **)error
{
    XFBinding *binding = [XFControl bindingOnElement:element preferredAttribute:@"ref" error:error];
    XFRangeControl *range = [[self alloc] initWithElement:element
                                                  binding:binding
                                                    label:[XFControl labelForElement:element]];
    range.owner = model;
    range.start = [self doubleAttr:element name:@"start" fallback:0];
    range.end = [self doubleAttr:element name:@"end" fallback:100];
    range.step = [self doubleAttr:element name:@"step" fallback:1];
    if (range.step <= 0) {
        range.step = 1;
    }
    return range;
}

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    [super refreshWithContext:context error:error];
    self.numericValue = [self.stringValue doubleValue];
}

- (BOOL)commitNumericValue:(double)value error:(NSError **)error
{
    if (value < self.start) {
        value = self.start;
    }
    if (value > self.end) {
        value = self.end;
    }
    self.numericValue = value;
    NSString *text = [NSString stringWithFormat:@"%g", value];
    return [self commitStringValue:text error:error];
}

@end
