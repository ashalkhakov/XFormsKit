#import "XFRangeControl.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFXMLEvents.h"

@implementation XFRangeControl {
    BOOL _hasRangeState;
    BOOL _outOfRange;
}

- (BOOL)outOfRange
{
    return _outOfRange;
}

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
    // XForms 1.1 8.1.7 data binding restriction: only duration, the
    // date/time family and the numeric types may bind a range
    static NSSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSSet setWithArray:@[
            @"duration", @"yearMonthDuration", @"dayTimeDuration",
            @"date", @"time", @"dateTime", @"gYearMonth",
            @"gYear", @"gMonthDay", @"gDay", @"gMonth", @"float",
            @"decimal", @"double", @"integer", @"nonPositiveInteger",
            @"negativeInteger", @"long", @"int", @"short", @"byte",
            @"nonNegativeInteger", @"unsignedLong", @"unsignedInt",
            @"unsignedShort", @"unsignedByte", @"positiveInteger" ]];
    });
    [self enforceDatatypeRestriction:allowed];
    self.numericValue = [self.stringValue doubleValue];
    // XForms 1.1 4.4.16/17: entering or leaving [start, end] notifies
    // the control; the FIRST refresh establishes and announces the
    // state too (the CSS :out-of-range styling of g.1.e needs it at
    // load).
    BOOL out = self.stringValue.length > 0
        && (self.numericValue < self.start || self.numericValue > self.end);
    if (!_hasRangeState || out != _outOfRange) {
        _hasRangeState = YES;
        _outOfRange = out;
        [XFXMLEvents dispatch:self
                         name:out ? @"xforms-out-of-range" : @"xforms-in-range"];
    }
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
