#import "XFXPathValue.h"
#import "XFXML.h"
#import <Foundation/NSXMLNode.h>
#import <math.h>

@interface XFXPathValue ()
@property (nonatomic, assign, readwrite) XFXPathValueType type;
@property (nonatomic, copy, readwrite) NSArray<NSXMLNode *> *nodes;
@property (nonatomic, copy, readwrite) NSString *string;
@property (nonatomic, assign, readwrite) double number;
@property (nonatomic, assign, readwrite) BOOL boolean;
@end

/// XPath 1.0 number → string: shortest decimal that round-trips (what JS
/// `"" + n` gives XSLTForms), never in exponent notation, no trailing zeros.
NSString *XFNumberToString(double n)
{
    if (isnan(n)) {
        return @"NaN";
    }
    if (isinf(n)) {
        return n > 0 ? @"Infinity" : @"-Infinity";
    }
    if (n == 0) {
        return @"0";
    }
    if (n == trunc(n) && fabs(n) < 1e21) {
        return [NSString stringWithFormat:@"%.0f", n];
    }
    char buf[64];
    for (int prec = 15; prec <= 17; prec++) {
        snprintf(buf, sizeof buf, "%.*e", prec - 1, n);
        if (strtod(buf, NULL) == n) {
            break;
        }
    }
    // buf is d.ddddde[+-]xx: expand to plain decimal notation.
    NSString *sci = [NSString stringWithUTF8String:buf];
    BOOL negative = [sci hasPrefix:@"-"];
    if (negative) {
        sci = [sci substringFromIndex:1];
    }
    NSRange e = [sci rangeOfString:@"e"];
    NSString *mantissa = [sci substringToIndex:e.location];
    NSInteger exponent = [[sci substringFromIndex:e.location + 1] integerValue];
    NSString *digits = [mantissa stringByReplacingOccurrencesOfString:@"." withString:@""];
    while (digits.length > 1 && [digits hasSuffix:@"0"]) {
        digits = [digits substringToIndex:digits.length - 1];
    }
    NSInteger pointPos = exponent + 1; // digits before the decimal point
    NSMutableString *out = [NSMutableString string];
    if (pointPos <= 0) {
        [out appendString:@"0."];
        for (NSInteger i = 0; i < -pointPos; i++) {
            [out appendString:@"0"];
        }
        [out appendString:digits];
    } else if ((NSUInteger)pointPos >= digits.length) {
        [out appendString:digits];
        for (NSInteger i = (NSInteger)digits.length; i < pointPos; i++) {
            [out appendString:@"0"];
        }
    } else {
        [out appendString:[digits substringToIndex:(NSUInteger)pointPos]];
        [out appendString:@"."];
        [out appendString:[digits substringFromIndex:(NSUInteger)pointPos]];
    }
    return negative ? [@"-" stringByAppendingString:out] : out;
}

@implementation XFXPathValue

+ (instancetype)nodeSet:(NSArray<NSXMLNode *> *)nodes
{
    XFXPathValue *v = [[self alloc] init];
    v.type = XFXPathValueTypeNodeSet;
    v.nodes = nodes ?: @[];
    return v;
}

+ (instancetype)string:(NSString *)string
{
    XFXPathValue *v = [[self alloc] init];
    v.type = XFXPathValueTypeString;
    v.string = string ?: @"";
    return v;
}

+ (instancetype)number:(double)number
{
    XFXPathValue *v = [[self alloc] init];
    v.type = XFXPathValueTypeNumber;
    v.number = number;
    return v;
}

+ (instancetype)boolean:(BOOL)flag
{
    XFXPathValue *v = [[self alloc] init];
    v.type = XFXPathValueTypeBoolean;
    v.boolean = flag;
    return v;
}

- (NSArray<NSXMLNode *> *)nodes
{
    return _nodes ?: @[];
}

- (NSString *)string
{
    return _string ?: @"";
}

- (NSXMLNode *)firstNode
{
    return self.nodes.firstObject;
}

- (NSString *)stringValue
{
    switch (self.type) {
        case XFXPathValueTypeString:
            return self.string;
        case XFXPathValueTypeNumber: {
            if (isnan(self.number)) {
                return @"NaN";
            }
            if (isinf(self.number)) {
                return self.number > 0 ? @"Infinity" : @"-Infinity";
            }
            return XFNumberToString(self.number);
        }
        case XFXPathValueTypeBoolean:
            return self.boolean ? @"true" : @"false";
        case XFXPathValueTypeNodeSet: {
            NSXMLNode *first = self.nodes.firstObject;
            return first ? [XFXML stringValueOfNode:first] : @"";
        }
    }
    return @"";
}

- (double)numberValue
{
    switch (self.type) {
        case XFXPathValueTypeNumber:
            return self.number;
        case XFXPathValueTypeBoolean:
            return self.boolean ? 1.0 : 0.0;
        case XFXPathValueTypeNodeSet:
        case XFXPathValueTypeString: {
            NSString *s = [[self stringValue]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (s.length == 0) {
                return NAN;
            }
            const char *bytes = [s UTF8String];
            char *end = NULL;
            double d = strtod(bytes, &end);
            if (end == bytes) {
                return NAN;
            }
            while (*end == ' ' || *end == '\t' || *end == '\n' || *end == '\r') {
                end++;
            }
            if (*end != '\0') {
                return NAN;
            }
            return d;
        }
    }
    return NAN;
}

- (BOOL)booleanValue
{
    switch (self.type) {
        case XFXPathValueTypeBoolean:
            return self.boolean;
        case XFXPathValueTypeNumber:
            return self.number != 0.0 && !isnan(self.number);
        case XFXPathValueTypeString:
            return self.string.length > 0;
        case XFXPathValueTypeNodeSet:
            return self.nodes.count > 0;
    }
    return NO;
}

- (NSString *)description
{
    switch (self.type) {
        case XFXPathValueTypeString:
            return [NSString stringWithFormat:@"string(%@)", self.string];
        case XFXPathValueTypeNumber:
            return [NSString stringWithFormat:@"number(%g)", self.number];
        case XFXPathValueTypeBoolean:
            return [NSString stringWithFormat:@"boolean(%@)", self.boolean ? @"true" : @"false"];
        case XFXPathValueTypeNodeSet:
            return [NSString stringWithFormat:@"nodeset(%lu)", (unsigned long)self.nodes.count];
    }
    return @"xpath-value";
}

@end
