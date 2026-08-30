#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "XFType.h"
#import "XFNamespaces.h"
#include <limits.h>

@interface XFType ()
@property (nonatomic, copy) NSString *patternSource;
@end

@implementation XFType

static NSMutableDictionary<NSString *, XFType *> *XFTypeTable(void)
{
    static NSMutableDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = [NSMutableDictionary dictionary];
    });
    return table;
}

static NSString *XFTypeKey(NSString *ns, NSString *name)
{
    return [NSString stringWithFormat:@"{%@}%@", ns ?: @"", name ?: @""];
}

+ (XFType *)define:(NSString *)name
                ns:(NSString *)ns
            base:(XFType *)base
        patterns:(NSArray<NSString *> *)patterns
     whitespace:(XFWhitespace)ws
{
    XFType *t = [[XFType alloc] init];
    t.localName = name;
    t.namespaceURI = ns;
    t.baseType = base;
    t.whitespace = ws;
    NSMutableArray *pats = [NSMutableArray array];
    if (base.patterns.count) {
        [pats addObjectsFromArray:base.patterns];
    }
    if (patterns.count) {
        [pats addObjectsFromArray:patterns];
    }
    t.patterns = pats;
    if (base) {
        t.fractionDigits = base.fractionDigits;
        t.totalDigits = base.totalDigits;
        t.minInclusive = base.minInclusive;
        t.maxInclusive = base.maxInclusive;
    }
    XFTypeTable()[XFTypeKey(ns, name)] = t;
    return t;
}

+ (void)installBuiltins
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *xsd = XFXMLSchemaNamespaceURI;
        NSString *xf = XFXFormsNamespaceURI;

        XFType *xsdString = [self define:@"string" ns:xsd base:nil patterns:nil whitespace:XFWhitespacePreserve];
        XFType *norm = [self define:@"normalizedString" ns:xsd base:xsdString patterns:nil whitespace:XFWhitespaceReplace];
        XFType *token = [self define:@"token" ns:xsd base:norm patterns:nil whitespace:XFWhitespaceCollapse];

        [self define:@"boolean" ns:xsd base:nil
            patterns:@[@"^(true|false|0|1)$"] whitespace:XFWhitespaceCollapse];

        XFType *decimal = [self define:@"decimal" ns:xsd base:nil
            patterns:@[@"^[\\-+]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)$"]
         whitespace:XFWhitespaceCollapse];

        XFType *integer = [self define:@"integer" ns:xsd base:decimal
            patterns:@[@"^[\\-+]?[0-9]+$"] whitespace:XFWhitespaceCollapse];
        integer.fractionDigits = @0;

        XFType *(^intRange)(NSString *, long long, long long) = ^(NSString *n, long long lo, long long hi) {
            XFType *t = [self define:n ns:xsd base:integer patterns:nil whitespace:XFWhitespaceCollapse];
            t.minInclusive = @(lo);
            t.maxInclusive = @(hi);
            return t;
        };
        intRange(@"long", LLONG_MIN, LLONG_MAX);
        intRange(@"int", INT_MIN, INT_MAX);
        intRange(@"short", SHRT_MIN, SHRT_MAX);
        intRange(@"byte", SCHAR_MIN, SCHAR_MAX);
        XFType *nni = [self define:@"nonNegativeInteger" ns:xsd base:integer patterns:nil whitespace:XFWhitespaceCollapse];
        nni.minInclusive = @0;
        XFType *pos = [self define:@"positiveInteger" ns:xsd base:nni patterns:nil whitespace:XFWhitespaceCollapse];
        pos.minInclusive = @1;
        XFType *npi = [self define:@"nonPositiveInteger" ns:xsd base:integer patterns:nil whitespace:XFWhitespaceCollapse];
        npi.maxInclusive = @0;
        XFType *neg = [self define:@"negativeInteger" ns:xsd base:npi patterns:nil whitespace:XFWhitespaceCollapse];
        neg.maxInclusive = @-1;
        XFType *ulong = [self define:@"unsignedLong" ns:xsd base:nni patterns:nil whitespace:XFWhitespaceCollapse];
        ulong.minInclusive = @0;
        intRange(@"unsignedInt", 0, UINT_MAX);
        intRange(@"unsignedShort", 0, USHRT_MAX);
        intRange(@"unsignedByte", 0, UCHAR_MAX);

        NSString *floatPat = @"^(([\\-+]?([0-9]+(\\.[0-9]*)?)|(\\.[0-9]+))([eE][\\-+]?[0-9]+)?|-?INF|NaN)$";
        [self define:@"float" ns:xsd base:nil patterns:@[ floatPat ] whitespace:XFWhitespaceCollapse];
        [self define:@"double" ns:xsd base:nil patterns:@[ floatPat ] whitespace:XFWhitespaceCollapse];

        [self define:@"date" ns:xsd base:nil
            patterns:@[@"^([0-9]{4})-(0[1-9]|1[012])-(0[1-9]|[12][0-9]|3[01])(Z|[+\\-]([01][0-9]|2[0-3]):[0-5][0-9])?$"]
         whitespace:XFWhitespaceCollapse];
        [self define:@"time" ns:xsd base:nil
            patterns:@[@"^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\\.[0-9]+)?(Z|[+\\-]([01][0-9]|2[0-3]):[0-5][0-9])?$"]
         whitespace:XFWhitespaceCollapse];
        [self define:@"dateTime" ns:xsd base:nil
            patterns:@[@"^([0-9]{4})-(0[1-9]|1[012])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\\.[0-9]+)?(Z|[+\\-]([01][0-9]|2[0-3]):[0-5][0-9])?$"]
         whitespace:XFWhitespaceCollapse];
        [self define:@"duration" ns:xsd base:nil
            patterns:@[@"^-?P(?!$)([0-9]+Y)?([0-9]+M)?([0-9]+D)?(T(?!$)([0-9]+H)?([0-9]+M)?([0-9]+(\\.[0-9]+)?S)?)?$"]
         whitespace:XFWhitespaceCollapse];
        [self define:@"gYear" ns:xsd base:nil patterns:@[@"^-?[0-9]{4,}$"] whitespace:XFWhitespaceCollapse];
        [self define:@"gYearMonth" ns:xsd base:nil patterns:@[@"^-?[0-9]{4,}-(0[1-9]|1[012])$"] whitespace:XFWhitespaceCollapse];
        [self define:@"gMonthDay" ns:xsd base:nil patterns:@[@"^--(0[1-9]|1[012])-(0[1-9]|[12][0-9]|3[01])$"] whitespace:XFWhitespaceCollapse];
        [self define:@"gDay" ns:xsd base:nil patterns:@[@"^---(0[1-9]|[12][0-9]|3[01])$"] whitespace:XFWhitespaceCollapse];
        [self define:@"gMonth" ns:xsd base:nil patterns:@[@"^--(0[1-9]|1[012])$"] whitespace:XFWhitespaceCollapse];

        [self define:@"anyURI" ns:xsd base:token patterns:nil whitespace:XFWhitespaceCollapse];
        [self define:@"base64Binary" ns:xsd base:nil
            patterns:@[@"^[A-Za-z0-9+/=\r\n ]+$"] whitespace:XFWhitespaceCollapse];
        [self define:@"hexBinary" ns:xsd base:nil
            patterns:@[@"^([0-9A-Fa-f]{2})+$"] whitespace:XFWhitespaceCollapse];
        [self define:@"language" ns:xsd base:token
            patterns:@[@"^[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*$"] whitespace:XFWhitespaceCollapse];
        [self define:@"Name" ns:xsd base:token
            patterns:@[@"^[A-Za-z_:][A-Za-z0-9_.:-]*$"] whitespace:XFWhitespaceCollapse];
        [self define:@"NCName" ns:xsd base:token
            patterns:@[@"^[A-Za-z_][A-Za-z0-9_.-]*$"] whitespace:XFWhitespaceCollapse];
        [self define:@"ID" ns:xsd base:token patterns:@[@"^[A-Za-z_][A-Za-z0-9_.-]*$"] whitespace:XFWhitespaceCollapse];
        [self define:@"IDREF" ns:xsd base:token patterns:@[@"^[A-Za-z_][A-Za-z0-9_.-]*$"] whitespace:XFWhitespaceCollapse];
        [self define:@"NMTOKEN" ns:xsd base:token patterns:@[@"^[A-Za-z0-9._:-]+$"] whitespace:XFWhitespaceCollapse];
        [self define:@"QName" ns:xsd base:token patterns:@[@"^([A-Za-z_][A-Za-z0-9_.-]*:)?[A-Za-z_][A-Za-z0-9_.-]*$"] whitespace:XFWhitespaceCollapse];

        // XForms library mirrors the XSD primitives plus extras.
        NSArray *copy = @[ @"string", @"boolean", @"decimal", @"float", @"double",
                           @"date", @"time", @"dateTime", @"duration", @"integer",
                           @"nonPositiveInteger", @"nonNegativeInteger",
                           @"negativeInteger", @"positiveInteger",
                           @"byte", @"short", @"int", @"long",
                           @"unsignedByte", @"unsignedShort", @"unsignedInt", @"unsignedLong",
                           @"normalizedString", @"token", @"language", @"anyURI",
                           @"Name", @"NCName", @"QName", @"ID", @"IDREF", @"NMTOKEN",
                           @"base64Binary", @"hexBinary", @"gDay", @"gMonth",
                           @"gMonthDay", @"gYear", @"gYearMonth" ];
        for (NSString *n in copy) {
            XFType *src = XFTypeTable()[XFTypeKey(xsd, n)];
            if (src) {
                XFType *dst = [self define:n ns:xf base:src patterns:nil whitespace:src.whitespace];
                dst.fractionDigits = src.fractionDigits;
                dst.minInclusive = src.minInclusive;
                dst.maxInclusive = src.maxInclusive;
            }
        }
        [self define:@"email" ns:xf base:xsdString
            patterns:@[@"^([A-Za-z0-9!#-'\\*\\+\\-/=\\?\\^_`\\{-~]+(\\.[A-Za-z0-9!#-'\\*\\+\\-/=\\?\\^_`\\{-~]+)*@[A-Za-z0-9!#-'\\*\\+\\-/=\\?\\^_`\\{-~]+(\\.[A-Za-z0-9!#-'\\*\\+\\-/=\\?\\^_`\\{-~]+)*)?$"]
         whitespace:XFWhitespaceCollapse];
        [self define:@"card-number" ns:xf base:xsdString
            patterns:@[@"^[0-9]*$"] whitespace:XFWhitespaceCollapse];
        [self define:@"url" ns:xf base:token patterns:nil whitespace:XFWhitespaceCollapse];
        [self define:@"dayTimeDuration" ns:xf base:nil
            patterns:@[@"^-?P((([0-9]+D)?(T(?!$)(([0-9]+H)|([0-9]+H)?[0-9]+M|[0-9]+H?([0-9]+M)?[0-9]+(\\.[0-9]+)?S))?)|T(?!$)(([0-9]+H)|([0-9]+H)?[0-9]+M|[0-9]+H?([0-9]+M)?[0-9]+(\\.[0-9]+)?S)))$"]
         whitespace:XFWhitespaceCollapse];
        [self define:@"yearMonthDuration" ns:xf base:nil
            patterns:@[@"^-?P([0-9]+Y)?([0-9]+M)?$"] whitespace:XFWhitespaceCollapse];
    });
}

+ (XFType *)typeWithLocalName:(NSString *)localName namespaceURI:(NSString *)namespaceURI
{
    [self installBuiltins];
    if (localName.length == 0) {
        return nil;
    }
    NSString *ns = namespaceURI.length ? namespaceURI : XFXMLSchemaNamespaceURI;
    XFType *t = XFTypeTable()[XFTypeKey(ns, localName)];
    if (t == nil && ![ns isEqualToString:XFXMLSchemaNamespaceURI]) {
        t = XFTypeTable()[XFTypeKey(XFXMLSchemaNamespaceURI, localName)];
    }
    return t;
}

+ (XFType *)typeNamed:(NSString *)name
{
    [self installBuiltins];
    if (name.length == 0) {
        return nil;
    }
    if ([name hasPrefix:@"{"]) {
        NSRange end = [name rangeOfString:@"}"];
        if (end.location != NSNotFound) {
            NSString *ns = [name substringWithRange:NSMakeRange(1, end.location - 1)];
            NSString *local = [name substringFromIndex:end.location + 1];
            return [self typeWithLocalName:local namespaceURI:ns];
        }
    }
    NSRange colon = [name rangeOfString:@":"];
    if (colon.location != NSNotFound) {
        NSString *prefix = [name substringToIndex:colon.location];
        NSString *local = [name substringFromIndex:colon.location + 1];
        NSString *ns = XFXMLSchemaNamespaceURI;
        if ([prefix isEqualToString:@"xf"] || [prefix isEqualToString:@"xforms"]) {
            ns = XFXFormsNamespaceURI;
        } else if ([prefix isEqualToString:@"xsd"] || [prefix isEqualToString:@"xs"]) {
            ns = XFXMLSchemaNamespaceURI;
        }
        return [self typeWithLocalName:local namespaceURI:ns];
    }
    return [self typeWithLocalName:name namespaceURI:XFXMLSchemaNamespaceURI]
        ?: [self typeWithLocalName:name namespaceURI:XFXFormsNamespaceURI];
}

- (NSString *)canonicalValue:(NSString *)value
{
    if (value == nil) {
        return @"";
    }
    if (self.whitespace == XFWhitespacePreserve) {
        return value;
    }
    NSMutableString *s = [value mutableCopy];
    [s replaceOccurrencesOfString:@"\t" withString:@" " options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\r" withString:@" " options:0 range:NSMakeRange(0, s.length)];
    if (self.whitespace == XFWhitespaceReplace) {
        return s;
    }
    NSArray *parts = [s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *nz = [NSMutableArray array];
    for (NSString *p in parts) {
        if (p.length) {
            [nz addObject:p];
        }
    }
    return [nz componentsJoinedByString:@" "];
}

- (BOOL)matchesPatterns:(NSString *)value
{
    if (self.patterns.count == 0 && self.baseType) {
        return [self.baseType matchesPatterns:value];
    }
    if (self.patterns.count == 0) {
        return YES;
    }
    for (NSString *pat in self.patterns) {
        NSRegularExpression *re =
            [NSRegularExpression regularExpressionWithPattern:pat options:0 error:NULL];
        if (re == nil) {
            continue;
        }
        NSRange full = NSMakeRange(0, value.length);
        if ([re numberOfMatchesInString:value options:0 range:full] == 0) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)validateValue:(NSString *)value
{
    if (value == nil) {
        return YES;
    }
    NSString *canon = [self canonicalValue:value];
    if (![self matchesPatterns:canon]) {
        return NO;
    }
    if (self.fractionDigits && [self.fractionDigits integerValue] == 0) {
        if ([canon rangeOfString:@"."].location != NSNotFound) {
            NSArray *bits = [canon componentsSeparatedByString:@"."];
            NSString *frac = bits.count > 1 ? bits[1] : @"";
            BOOL nonzero = NO;
            for (NSUInteger i = 0; i < frac.length; i++) {
                if ([frac characterAtIndex:i] != '0') {
                    nonzero = YES;
                    break;
                }
            }
            if (nonzero) {
                return NO;
            }
        }
    }
    if (self.minInclusive || self.maxInclusive) {
        double n = [canon doubleValue];
        if (self.minInclusive && n < [self.minInclusive doubleValue]) {
            return NO;
        }
        if (self.maxInclusive && n > [self.maxInclusive doubleValue]) {
            return NO;
        }
    }
    return YES;
}

+ (BOOL)value:(NSString *)value conformsToTypeNamed:(NSString *)typeName
{
    if (typeName.length == 0) {
        return YES;
    }
    XFType *type = [self typeNamed:typeName];
    if (type == nil) {
        return YES;
    }
    if (value.length == 0) {
        // XSLTForms TypeDefs: the xforms:* types have `(...)?` patterns and
        // accept the empty string; the xsd:* types only do when they have no
        // pattern (string family). XForms 1.1 says the same: use xf:date
        // rather than xsd:date for optional values (G-12).
        return [type.namespaceURI isEqualToString:XFXFormsNamespaceURI] || type.patterns.count == 0;
    }
    return [type validateValue:value];
}

@end
