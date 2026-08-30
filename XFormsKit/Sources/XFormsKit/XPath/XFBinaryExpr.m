#import "XFXPathPriv.h"
#import <math.h>

@implementation XFBinaryExpr

+ (instancetype)expr1:(XFExpr *)e1 op:(NSString *)op expr2:(XFExpr *)e2
{
    XFBinaryExpr *e = [[self alloc] init];
    e.expr1 = e1;
    e.op = op;
    e.expr2 = e2;
    return e;
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

    BOOL cmp = [self.op isEqualToString:@"="] || [self.op isEqualToString:@"!="] ||
               [self.op isEqualToString:@"<"] || [self.op isEqualToString:@"<="] ||
               [self.op isEqualToString:@">"] || [self.op isEqualToString:@">="];

    if (cmp && ((v1.type == XFXPathValueTypeNodeSet && v1.nodes.count > 1) ||
                (v2.type == XFXPathValueTypeNodeSet && v2.nodes.count > 1))) {
        NSArray *left = v1.type == XFXPathValueTypeNodeSet ? v1.nodes : @[ (id)v1 ];
        NSArray *right = v2.type == XFXPathValueTypeNodeSet ? v2.nodes : @[ (id)v2 ];
        for (id a in left) {
            XFXPathValue *va = [a isKindOfClass:[NSXMLNode class]] ? [XFXPathValue nodeSet:@[ a ]] : a;
            for (id b in right) {
                XFXPathValue *vb = [b isKindOfClass:[NSXMLNode class]] ? [XFXPathValue nodeSet:@[ b ]] : b;
                if ([self compare:va with:vb]) {
                    return [XFXPathValue boolean:YES];
                }
            }
        }
        return [XFXPathValue boolean:NO];
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
    double n1 = v1.numberValue;
    double n2 = v2.numberValue;
    NSString *s1 = nil;
    NSString *s2 = nil;
    if (isnan(n1) || isnan(n2) ||
        v1.type == XFXPathValueTypeString || v2.type == XFXPathValueTypeString ||
        ([self.op isEqualToString:@"="] || [self.op isEqualToString:@"!="])) {
        if (isnan(n1) || isnan(n2) ||
            v1.type == XFXPathValueTypeString || v2.type == XFXPathValueTypeString ||
            v1.type == XFXPathValueTypeNodeSet || v2.type == XFXPathValueTypeNodeSet) {
            s1 = [v1 stringValue];
            s2 = [v2 stringValue];
        }
    }
    if ([self.op isEqualToString:@"="]) {
        if (s1) {
            return [s1 isEqualToString:s2];
        }
        return n1 == n2;
    }
    if ([self.op isEqualToString:@"!="]) {
        if (s1) {
            return ![s1 isEqualToString:s2];
        }
        return n1 != n2;
    }
    if (s1 && (isnan(n1) || isnan(n2))) {
        n1 = v1.numberValue;
        n2 = v2.numberValue;
    }
    if ([self.op isEqualToString:@"<"])  return n1 < n2;
    if ([self.op isEqualToString:@"<="]) return n1 <= n2;
    if ([self.op isEqualToString:@">"])  return n1 > n2;
    if ([self.op isEqualToString:@">="]) return n1 >= n2;
    return NO;
}

@end
