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
        t.evalTypeName = base.evalTypeName;
        t.fractionDigits = base.fractionDigits;
        t.totalDigits = base.totalDigits;
        t.minInclusive = base.minInclusive;
        t.maxInclusive = base.maxInclusive;
        t.minExclusive = base.minExclusive;
        t.maxExclusive = base.maxExclusive;
        t.length = base.length;
        t.minLength = base.minLength;
        t.maxLength = base.maxLength;
        t.enumeration = base.enumeration;
        t.itemType = base.itemType;
        t.memberTypes = base.memberTypes;
    }
    XFTypeTable()[XFTypeKey(ns, name)] = t;
    return t;
}

#pragma mark - user schemas (G-56)

static NSString * const XFXSDNS = @"http://www.w3.org/2001/XMLSchema";

+ (XFType *)typeForQName:(NSString *)qname inElement:(NSXMLElement *)element targetNamespace:(NSString *)tns
{
    if (qname.length == 0) {
        return nil;
    }
    NSRange colon = [qname rangeOfString:@":"];
    NSString *prefix = colon.location == NSNotFound ? @"" : [qname substringToIndex:colon.location];
    NSString *local = colon.location == NSNotFound ? qname : [qname substringFromIndex:colon.location + 1];
    NSString *ns = [[element resolveNamespaceForName:prefix.length ? [prefix stringByAppendingString:@":x"] : @"x"] stringValue];
    if (ns.length == 0) {
        ns = prefix.length ? nil : tns;
    }
    if (ns.length) {
        XFType *t = [self typeWithLocalName:local namespaceURI:ns];
        if (t) {
            return t;
        }
    }
    return [self typeNamed:qname];
}

+ (NSUInteger)registerSchemaElement:(NSXMLElement *)schema
{
    [self installBuiltins];
    NSString *tns = [[schema attributeForName:@"targetNamespace"] stringValue] ?: @"";
    NSUInteger count = 0;
    // two passes so a restriction can name a type defined later
    for (int pass = 0; pass < 2; pass++) {
        for (NSXMLNode *child in [schema children]) {
            if ([child kind] != NSXMLElementKind) {
                continue;
            }
            NSXMLElement *st = (NSXMLElement *)child;
            if (![[st localName] isEqualToString:@"simpleType"]) {
                continue;
            }
            NSString *name = [[st attributeForName:@"name"] stringValue];
            if (name.length == 0) {
                continue;
            }
            if ([self defineSimpleType:st name:name targetNamespace:tns]) {
                count++;
            }
        }
    }
    return count;
}

+ (BOOL)defineSimpleType:(NSXMLElement *)st name:(NSString *)name targetNamespace:(NSString *)tns
{
    NSXMLElement *def = nil;
    for (NSXMLNode *c in [st children]) {
        if ([c kind] == NSXMLElementKind) {
            def = (NSXMLElement *)c;
            break;
        }
    }
    if (def == nil) {
        return NO;
    }
    NSString *kind = [def localName];
    if ([kind isEqualToString:@"restriction"]) {
        NSString *baseName = [[def attributeForName:@"base"] stringValue];
        XFType *base = [self typeForQName:baseName inElement:def targetNamespace:tns];
        if (base == nil) {
            base = [self typeWithLocalName:@"string" namespaceURI:XFXSDNS];
        }
        NSMutableArray *patterns = [NSMutableArray array];
        NSMutableArray *enumeration = [NSMutableArray array];
        XFType *t = [self define:name ns:tns base:base patterns:nil whitespace:base.whitespace];
        for (NSXMLNode *fc in [def children]) {
            if ([fc kind] != NSXMLElementKind) {
                continue;
            }
            NSString *facet = [fc localName];
            NSString *v = [[(NSXMLElement *)fc attributeForName:@"value"] stringValue] ?: @"";
            if ([facet isEqualToString:@"pattern"]) {
                [patterns addObject:[NSString stringWithFormat:@"^(?:%@)$", v]];
            } else if ([facet isEqualToString:@"enumeration"]) {
                [enumeration addObject:v];
            } else if ([facet isEqualToString:@"length"]) {
                t.length = @([v integerValue]);
            } else if ([facet isEqualToString:@"minLength"]) {
                t.minLength = @([v integerValue]);
            } else if ([facet isEqualToString:@"maxLength"]) {
                t.maxLength = @([v integerValue]);
            } else if ([facet isEqualToString:@"minInclusive"]) {
                t.minInclusive = @([v doubleValue]);
            } else if ([facet isEqualToString:@"maxInclusive"]) {
                t.maxInclusive = @([v doubleValue]);
            } else if ([facet isEqualToString:@"minExclusive"]) {
                t.minExclusive = @([v doubleValue]);
            } else if ([facet isEqualToString:@"maxExclusive"]) {
                t.maxExclusive = @([v doubleValue]);
            } else if ([facet isEqualToString:@"totalDigits"]) {
                t.totalDigits = @([v integerValue]);
            } else if ([facet isEqualToString:@"fractionDigits"]) {
                t.fractionDigits = @([v integerValue]);
            } else if ([facet isEqualToString:@"whiteSpace"]) {
                t.whitespace = [v isEqualToString:@"preserve"] ? XFWhitespacePreserve
                    : [v isEqualToString:@"replace"] ? XFWhitespaceReplace : XFWhitespaceCollapse;
            }
        }
        if (patterns.count) {
            t.patterns = [(t.patterns ?: @[]) arrayByAddingObjectsFromArray:patterns];
        }
        if (enumeration.count) {
            t.enumeration = enumeration;
        }
        return YES;
    }
    if ([kind isEqualToString:@"list"]) {
        XFType *item = [self typeForQName:[[def attributeForName:@"itemType"] stringValue] inElement:def targetNamespace:tns];
        XFType *t = [self define:name ns:tns base:nil patterns:nil whitespace:XFWhitespaceCollapse];
        t.itemType = item ?: [self typeWithLocalName:@"string" namespaceURI:XFXSDNS];
        return YES;
    }
    if ([kind isEqualToString:@"union"]) {
        NSMutableArray *members = [NSMutableArray array];
        for (NSString *m in [[[def attributeForName:@"memberTypes"] stringValue] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
            XFType *mt = m.length ? [self typeForQName:m inElement:def targetNamespace:tns] : nil;
            if (mt) {
                [members addObject:mt];
            }
        }
        XFType *t = [self define:name ns:tns base:nil patterns:nil whitespace:XFWhitespaceCollapse];
        t.memberTypes = members;
        return YES;
    }
    return NO;
}

- (NSString *)normalizeValue:(NSString *)value
{
    if (self.fractionDigits == nil || value == nil) {
        return value;
    }
    NSInteger digits = [self.fractionDigits integerValue];
    if (![[NSScanner scannerWithString:value] scanDouble:NULL]) {
        return @"NaN";
    }
    double number = [value doubleValue];
    return [NSString stringWithFormat:@"%.*f", (int)MAX(0, digits), number];
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

        // XSLTForms TypeDefs.js: anyURI pattern, and Name characters that
        // include the Latin-1 letters (ctes.i / ctes.c) — G-79
        [self define:@"anyURI" ns:xsd base:token
            patterns:@[@"^(([^ :\\/?#]+)://)?[^ /\\?#]+([^ \\?#]*)(\\?([^ #]*))?(#([^ :#\\[\\]@!$&\\\\'()*+,;=]*))?$"]
         whitespace:XFWhitespaceCollapse];
        NSString *nameStart = @"A-Za-z_\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u00FF";
        NSString *nameChar = @"A-Za-z_\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u00FF\\-.0-9\u00B7";
        [self define:@"base64Binary" ns:xsd base:nil
            patterns:@[@"^[A-Za-z0-9+/=\r\n ]+$"] whitespace:XFWhitespaceCollapse];
        [self define:@"hexBinary" ns:xsd base:nil
            patterns:@[@"^([0-9A-Fa-f]{2})+$"] whitespace:XFWhitespaceCollapse];
        [self define:@"language" ns:xsd base:token
            patterns:@[@"^[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*$"] whitespace:XFWhitespaceCollapse];
        [self define:@"Name" ns:xsd base:token
            patterns:@[[NSString stringWithFormat:@"^[%@:][%@:]*$", nameStart, nameChar]] whitespace:XFWhitespaceCollapse];
        XFType *ncname = [self define:@"NCName" ns:xsd base:token
            patterns:@[[NSString stringWithFormat:@"^[%@][%@]*$", nameStart, nameChar]] whitespace:XFWhitespaceCollapse];
        [self define:@"ID" ns:xsd base:ncname patterns:nil whitespace:XFWhitespaceCollapse];
        [self define:@"IDREF" ns:xsd base:ncname patterns:nil whitespace:XFWhitespaceCollapse];
        [self define:@"IDREFS" ns:xsd base:token
            patterns:@[[NSString stringWithFormat:@"^[%@][%@]*( +[%@][%@]*)*$", nameStart, nameChar, nameStart, nameChar]]
         whitespace:XFWhitespaceCollapse];
        [self define:@"NMTOKEN" ns:xsd base:token
            patterns:@[[NSString stringWithFormat:@"^[%@]+$", nameChar]] whitespace:XFWhitespaceCollapse];
        [self define:@"NMTOKENS" ns:xsd base:token
            patterns:@[[NSString stringWithFormat:@"^[%@]+( [%@]+)*$", nameChar, nameChar]] whitespace:XFWhitespaceCollapse];
        [self define:@"QName" ns:xsd base:token
            patterns:@[[NSString stringWithFormat:@"^([%@][%@]*:)?[%@][%@]*$", nameStart, nameChar, nameStart, nameChar]]
         whitespace:XFWhitespaceCollapse];

        // XForms library mirrors the XSD primitives plus extras.
        NSArray *copy = @[ @"string", @"boolean", @"decimal", @"float", @"double",
                           @"date", @"time", @"dateTime", @"duration", @"integer",
                           @"nonPositiveInteger", @"nonNegativeInteger",
                           @"negativeInteger", @"positiveInteger",
                           @"byte", @"short", @"int", @"long",
                           @"unsignedByte", @"unsignedShort", @"unsignedInt", @"unsignedLong",
                           @"normalizedString", @"token", @"language", @"anyURI",
                           @"Name", @"NCName", @"QName", @"ID", @"IDREF", @"IDREFS", @"NMTOKEN", @"NMTOKENS",
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
        // xf:amount (a decimal shown with 2 fraction digits in XSLTForms),
        // xf:HTMLFragment (a string), dcterms:W3CDTF (a dateTime) — G-79
        XFType *amount = [self define:@"amount" ns:xf base:decimal patterns:nil whitespace:XFWhitespaceCollapse];
        amount.fractionDigits = @2;
        [self define:@"HTMLFragment" ns:xf base:xsdString patterns:nil whitespace:XFWhitespacePreserve];
        [self define:@"W3CDTF" ns:@"http://purl.org/dc/terms/" base:XFTypeTable()[XFTypeKey(xsd, @"dateTime")]
            patterns:nil whitespace:XFWhitespaceCollapse];
        // XSLTForms eval types (TypeDefs.js XsltForms_typeDefs.XSLTForms):
        // the value is an arithmetic expression, evaluated by the XPath
        // layer (XFXPathNodeValue) — used by the spreadsheet sample (G-79)
        NSString *xsltforms = @"http://www.agencexml.com/xsltforms";
        XFType *evalDecimal = [self define:@"decimal" ns:xsltforms base:nil
            patterns:@[@"^[\\-+]?\\(*[\\-+]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)(([+\\-/]|\\*)\\(*([0-9]+(\\.[0-9]*)?|\\.[0-9]+)\\)*)*$"]
         whitespace:XFWhitespaceCollapse];
        evalDecimal.evalTypeName = @"xsd:decimal";
        for (NSString *n in @[ @"float", @"double", @"integer",
                               @"nonPositiveInteger", @"nonNegativeInteger",
                               @"negativeInteger", @"positiveInteger",
                               @"byte", @"short", @"int", @"long",
                               @"unsignedByte", @"unsignedShort", @"unsignedInt", @"unsignedLong" ]) {
            XFType *t = [self define:n ns:xsltforms base:evalDecimal patterns:nil whitespace:XFWhitespaceCollapse];
            t.evalTypeName = [@"xsd:" stringByAppendingString:n];
        }
        // xsltforms:shortDate (yyyyMMdd, locale format/parse) is a UI
        // formatting type; only its pattern is enforced
        [self define:@"shortDate" ns:xsltforms base:nil
            patterns:@[@"^(([12][0-9]{3})(0[1-9]|1[012])(0[1-9]|[12][0-9]|3[01]))?$"]
         whitespace:XFWhitespaceCollapse];

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
    if (self.minInclusive || self.maxInclusive || self.minExclusive || self.maxExclusive) {
        double n = [canon doubleValue];
        if (self.minInclusive && n < [self.minInclusive doubleValue]) {
            return NO;
        }
        if (self.maxInclusive && n > [self.maxInclusive doubleValue]) {
            return NO;
        }
        if (self.minExclusive && n <= [self.minExclusive doubleValue]) {
            return NO;
        }
        if (self.maxExclusive && n >= [self.maxExclusive doubleValue]) {
            return NO;
        }
    }
    if (self.length && (NSInteger)canon.length != [self.length integerValue]) {
        return NO;
    }
    if (self.minLength && (NSInteger)canon.length < [self.minLength integerValue]) {
        return NO;
    }
    if (self.maxLength && (NSInteger)canon.length > [self.maxLength integerValue]) {
        return NO;
    }
    if (self.enumeration.count && ![self.enumeration containsObject:canon]) {
        return NO;
    }
    if (self.itemType) {
        for (NSString *item in [canon componentsSeparatedByString:@" "]) {
            if (item.length && ![self.itemType validateValue:item]) {
                return NO;
            }
        }
    }
    if (self.memberTypes.count) {
        for (XFType *m in self.memberTypes) {
            if ([m validateValue:canon]) {
                return YES;
            }
        }
        return NO;
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
