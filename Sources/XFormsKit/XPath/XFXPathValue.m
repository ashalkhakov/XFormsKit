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
            if (self.number == trunc(self.number) &&
                fabs(self.number) < 1e15) {
                return [NSString stringWithFormat:@"%.0f", self.number];
            }
            return [NSString stringWithFormat:@"%g", self.number];
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
