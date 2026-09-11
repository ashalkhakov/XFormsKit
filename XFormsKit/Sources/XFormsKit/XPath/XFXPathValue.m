#import "XFXPathValue.h"
#import "XFXML.h"
#import "XFNodeState.h"
#import "XFType.h"
#import <XFormsKit/XFXMLTypes.h>
#import <math.h>

@interface XFXPathValue ()
@property (nonatomic, assign, readwrite) XFXPathValueType type;
@property (nonatomic, copy, readwrite) NSArray<XFXMLNode *> *nodes;
@property (nonatomic, copy, readwrite) NSString *string;
@property (nonatomic, assign, readwrite) double number;
@property (nonatomic, assign, readwrite) BOOL boolean;
@end

#pragma mark - Eval-typed node values (XsltForms_globals.xmlValue)

/// Tiny arithmetic evaluator for the XSLTForms eval types: decimal
/// literals, + - * / and parentheses with the usual precedence (what the
/// JS `eval` in xmlValue computes for values matching xsltforms:decimal's
/// pattern). Returns NO when the text is not such an expression.
typedef struct { const char *p; BOOL ok; } XFArith;

static double XFArithExpr(XFArith *a);

static void XFArithSpace(XFArith *a)
{
    while (*a->p == ' ' || *a->p == '\t' || *a->p == '\n' || *a->p == '\r') {
        a->p++;
    }
}

static double XFArithFactor(XFArith *a)
{
    XFArithSpace(a);
    double sign = 1;
    while (*a->p == '+' || *a->p == '-') {
        if (*a->p == '-') {
            sign = -sign;
        }
        a->p++;
        XFArithSpace(a);
    }
    if (*a->p == '(') {
        a->p++;
        double v = XFArithExpr(a);
        XFArithSpace(a);
        if (*a->p != ')') {
            a->ok = NO;
            return NAN;
        }
        a->p++;
        return sign * v;
    }
    const char *start = a->p;
    char *end = NULL;
    double v = strtod(start, &end);
    if (end == start) {
        a->ok = NO;
        return NAN;
    }
    a->p = end;
    return sign * v;
}

static double XFArithTerm(XFArith *a)
{
    double v = XFArithFactor(a);
    for (;;) {
        XFArithSpace(a);
        if (*a->p == '*') {
            a->p++;
            v *= XFArithFactor(a);
        } else if (*a->p == '/') {
            a->p++;
            v /= XFArithFactor(a);
        } else {
            return v;
        }
    }
}

static double XFArithExpr(XFArith *a)
{
    double v = XFArithTerm(a);
    for (;;) {
        XFArithSpace(a);
        if (*a->p == '+') {
            a->p++;
            v += XFArithTerm(a);
        } else if (*a->p == '-') {
            a->p++;
            v -= XFArithTerm(a);
        } else {
            return v;
        }
    }
}

static BOOL XFEvalArithmetic(NSString *text, double *out)
{
    XFArith a = { [text UTF8String] ?: "", YES };
    double v = XFArithExpr(&a);
    XFArithSpace(&a);
    if (!a.ok || *a.p != '\0') {
        return NO;
    }
    *out = v;
    return YES;
}

/// The node's type name: the bind's (node state), else its own xsi:type.
static XFType *XFNodeValueType(XFXMLNode *node)
{
    NSString *name = [XFNodeState existingStateOnNode:node].typeName;
    if (name.length == 0 && [node kind] == XFXMLElementKind) {
        NSString *qname = [[(XFXMLElement *)node attributeForLocalName:@"type"
                                                                   URI:@"http://www.w3.org/2001/XMLSchema-instance"] stringValue];
        if (qname.length) {
            return [XFType typeForQName:qname inElement:(XFXMLElement *)node targetNamespace:nil];
        }
        return nil;
    }
    return name.length ? [XFType typeNamed:name] : nil;
}

NSString *XFXPathNodeValue(XFXMLNode *node)
{
    NSString *raw = [XFXML stringValueOfNode:node] ?: @"";
    XFType *type = XFNodeValueType(node);
    if (type.evalTypeName == nil) {
        return raw;
    }
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return @"0";   // xmlValue: ret === "" ? 0 : eval(ret)
    }
    double v = 0;
    if (!XFEvalArithmetic(trimmed, &v)) {
        return raw;
    }
    return XFNumberToString(v);
}

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

+ (instancetype)nodeSet:(NSArray<XFXMLNode *> *)nodes
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

- (NSArray<XFXMLNode *> *)nodes
{
    return _nodes ?: @[];
}

- (NSString *)string
{
    return _string ?: @"";
}

- (XFXMLNode *)firstNode
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
            XFXMLNode *first = self.nodes.firstObject;
            return first ? XFXPathNodeValue(first) : @"";
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
