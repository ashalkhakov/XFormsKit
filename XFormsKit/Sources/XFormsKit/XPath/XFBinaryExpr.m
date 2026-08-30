#import "XFXPathPriv.h"
#import "XFXML.h"
#import <math.h>

// XSLTForms BinaryExpr.js, with XPath 1.0 §3.4 comparison rules (XSLTForms
// compares node-set vs number as strings and lets strings fall back to
// lexical order; both are deviations from the spec that real forms do not
// rely on, so the spec rules are used here).

@implementation XFBinaryExpr

+ (instancetype)expr1:(XFExpr *)e1 op:(NSString *)op expr2:(XFExpr *)e2
{
    XFBinaryExpr *e = [[self alloc] init];
    e.expr1 = e1;
    e.op = op;
    e.expr2 = e2;
    return e;
}

static BOOL XFIsRelational(NSString *op)
{
    return [op isEqualToString:@"<"] || [op isEqualToString:@"<="] ||
           [op isEqualToString:@">"] || [op isEqualToString:@">="];
}

static BOOL XFCompareNumbers(NSString *op, double a, double b)
{
    if ([op isEqualToString:@"="])  return a == b;
    if ([op isEqualToString:@"!="]) return a != b;
    if ([op isEqualToString:@"<"])  return a < b;
    if ([op isEqualToString:@"<="]) return a <= b;
    if ([op isEqualToString:@">"])  return a > b;
    if ([op isEqualToString:@">="]) return a >= b;
    return NO;
}

/// Compare two non-node-set values.
static BOOL XFCompareAtomic(NSString *op, XFXPathValue *a, XFXPathValue *b)
{
    if (XFIsRelational(op)) {
        return XFCompareNumbers(op, a.numberValue, b.numberValue);
    }
    BOOL eq;
    if (a.type == XFXPathValueTypeBoolean || b.type == XFXPathValueTypeBoolean) {
        eq = a.booleanValue == b.booleanValue;
    } else if (a.type == XFXPathValueTypeNumber || b.type == XFXPathValueTypeNumber) {
        eq = a.numberValue == b.numberValue;
    } else {
        eq = [[a stringValue] isEqualToString:[b stringValue]];
    }
    return [op isEqualToString:@"="] ? eq : !eq;
}

/// Compare a node-set with a single non-node-set value: true if some node
/// satisfies the comparison after converting the node's string value to the
/// other operand's type (§3.4). `reversed` means the node-set is the right operand.
static BOOL XFCompareNodeSet(NSString *op, NSArray<NSXMLNode *> *nodes, XFXPathValue *other, BOOL reversed)
{
    if (other.type == XFXPathValueTypeBoolean) {
        XFXPathValue *b = [XFXPathValue boolean:nodes.count > 0];
        return reversed ? XFCompareAtomic(op, other, b) : XFCompareAtomic(op, b, other);
    }
    for (NSXMLNode *n in nodes) {
        NSString *s = XFXPathNodeValue(n);
        XFXPathValue *v = (other.type == XFXPathValueTypeNumber || XFIsRelational(op))
            ? [XFXPathValue number:[XFXPathValue string:s].numberValue]
            : [XFXPathValue string:s];
        XFXPathValue *o = XFIsRelational(op) ? [XFXPathValue number:other.numberValue] : other;
        if (reversed ? XFCompareAtomic(op, o, v) : XFCompareAtomic(op, v, o)) {
            return YES;
        }
    }
    return NO;
}

- (XFXPathValue *)evaluate:(XFExprContext *)ctx error:(NSError **)error
{
    XFXPathValue *v1 = [self.expr1 evaluate:ctx error:error];
    if (v1 == nil) {
        return nil;
    }
    if ([self.op isEqualToString:@"or"]) {
        if (v1.booleanValue) {
            return [XFXPathValue boolean:YES];
        }
        XFXPathValue *v2 = [self.expr2 evaluate:ctx error:error];
        return v2 ? [XFXPathValue boolean:v2.booleanValue] : nil;
    }
    if ([self.op isEqualToString:@"and"]) {
        if (!v1.booleanValue) {
            return [XFXPathValue boolean:NO];
        }
        XFXPathValue *v2 = [self.expr2 evaluate:ctx error:error];
        return v2 ? [XFXPathValue boolean:v2.booleanValue] : nil;
    }

    XFXPathValue *v2 = [self.expr2 evaluate:ctx error:error];
    if (v2 == nil) {
        return nil;
    }

    if ([self.op isEqualToString:@"+"]) {
        return [XFXPathValue number:v1.numberValue + v2.numberValue];
    }
    if ([self.op isEqualToString:@"-"]) {
        return [XFXPathValue number:v1.numberValue - v2.numberValue];
    }
    if ([self.op isEqualToString:@"*"]) {
        return [XFXPathValue number:v1.numberValue * v2.numberValue];
    }
    if ([self.op isEqualToString:@"div"]) {
        return [XFXPathValue number:v1.numberValue / v2.numberValue];
    }
    if ([self.op isEqualToString:@"mod"]) {
        return [XFXPathValue number:fmod(v1.numberValue, v2.numberValue)];
    }
    return [XFXPathValue boolean:[self compare:v1 with:v2]];
}

- (BOOL)compare:(XFXPathValue *)v1 with:(XFXPathValue *)v2
{
    BOOL ns1 = v1.type == XFXPathValueTypeNodeSet;
    BOOL ns2 = v2.type == XFXPathValueTypeNodeSet;
    if (ns1 && ns2) {
        for (NSXMLNode *a in v1.nodes) {
            NSString *sa = XFXPathNodeValue(a);
            for (NSXMLNode *b in v2.nodes) {
                NSString *sb = XFXPathNodeValue(b);
                BOOL hit = XFIsRelational(self.op)
                    ? XFCompareNumbers(self.op, [XFXPathValue string:sa].numberValue,
                                                [XFXPathValue string:sb].numberValue)
                    : ([self.op isEqualToString:@"="] ? [sa isEqualToString:sb] : ![sa isEqualToString:sb]);
                if (hit) {
                    return YES;
                }
            }
        }
        return NO;
    }
    if (ns1) {
        return XFCompareNodeSet(self.op, v1.nodes, v2, NO);
    }
    if (ns2) {
        return XFCompareNodeSet(self.op, v2.nodes, v1, YES);
    }
    return XFCompareAtomic(self.op, v1, v2);
}

@end
