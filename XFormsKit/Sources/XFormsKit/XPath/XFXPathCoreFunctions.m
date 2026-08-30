#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "XFXPathPriv.h"
#import "XFModel.h"
#import "XFProcessor.h"
#import "XFInstance.h"
#import "XFRepeat.h"
#import "XFXML.h"
#import "XFXMLEvents.h"
#import "XFNodeState.h"
#import "XFType.h"
#import <Foundation/NSXMLNode.h>
#import <Foundation/NSXMLDocument.h>
#import <Foundation/NSXMLElement.h>
#import <math.h>
#import <objc/runtime.h>
#if __has_include(<CommonCrypto/CommonDigest.h>)
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#define XF_HAS_COMMONCRYPTO 1
#elif __has_include(<openssl/evp.h>)
#include <openssl/evp.h>
#include <openssl/hmac.h>
#define XF_HAS_OPENSSL 1
#endif

static NSString *XFLocalName(NSString *qname)
{
    NSRange c = [qname rangeOfString:@":"];
    if (c.location == NSNotFound) {
        return qname;
    }
    return [qname substringFromIndex:c.location + 1];
}

static XFXPathValue *XFArg(NSArray<XFXPathValue *> *args, NSUInteger i)
{
    return i < args.count ? args[i] : nil;
}

static NSString *XFFormatDate(NSDate *date, BOOL utc)
{
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.timeZone = utc ? [NSTimeZone timeZoneForSecondsFromGMT:0] : [NSTimeZone localTimeZone];
    fmt.dateFormat = @"yyyy-MM-dd";
    return [fmt stringFromDate:date];
}

static NSString *XFFormatDateTime(NSDate *date, BOOL utc)
{
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.timeZone = utc ? [NSTimeZone timeZoneForSecondsFromGMT:0] : [NSTimeZone localTimeZone];
    fmt.dateFormat = utc ? @"yyyy-MM-dd'T'HH:mm:ss'Z'" : @"yyyy-MM-dd'T'HH:mm:ssxxx";
    return [fmt stringFromDate:date];
}

/// xsd:date / xsd:dateTime parser (XSLTForms XPathCoreFunctions.js
/// pattern): YYYY-MM-DD[THH:MM:SS[.fff]][Z|(+|-)HH:MM]. A trailing timezone
/// on a date is accepted and ignored (the day is taken as UTC, like
/// `Date.UTC(y, m, d)` in XSLTForms).
static NSRegularExpression *XFDateTimeRegex(void)
{
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
              @"^(-?[0-9]{4,})-(0[1-9]|1[012])-(0[1-9]|[12][0-9]|3[01])"
              @"(?:T([01][0-9]|2[0-3]):([0-5][0-9]):([0-5][0-9])(\\.[0-9]+)?)?"
              @"(Z|[+\\-][01][0-9]:[0-5][0-9])?$"
                                                       options:0 error:NULL];
    });
    return re;
}

/// Parses into (secondsSince1970, fraction) honouring the offset. Returns NO
/// when the string is not a lexical date/dateTime. `hasTime` reports whether
/// a time part was present.
static BOOL XFParseXSDDateTime(NSString *s, double *outSeconds, BOOL *hasTime)
{
    if (s == nil) {
        return NO;
    }
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSTextCheckingResult *m = [XFDateTimeRegex() firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (m == nil) {
        return NO;
    }
    NSString *(^grp)(NSUInteger) = ^NSString *(NSUInteger i) {
        NSRange r = [m rangeAtIndex:i];
        return r.location == NSNotFound ? nil : [s substringWithRange:r];
    };
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = [grp(1) integerValue];
    c.month = [grp(2) integerValue];
    c.day = [grp(3) integerValue];
    BOOL time = grp(4) != nil;
    c.hour = time ? [grp(4) integerValue] : 0;
    c.minute = time ? [grp(5) integerValue] : 0;
    c.second = time ? [grp(6) integerValue] : 0;
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDate *d = [cal dateFromComponents:c];
    if (d == nil) {
        return NO;
    }
    // reject invalid calendar dates (2020-02-30) that NSCalendar would roll over
    NSDateComponents *back = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:d];
    if (back.year != c.year || back.month != c.month || back.day != c.day) {
        return NO;
    }
    double secs = [d timeIntervalSince1970];
    NSString *frac = grp(7);
    if (frac.length) {
        secs += [frac doubleValue];
    }
    NSString *tz = grp(8);
    if (time && tz.length && ![tz isEqualToString:@"Z"]) {
        NSInteger hh = [[tz substringWithRange:NSMakeRange(1, 2)] integerValue];
        NSInteger mm = [[tz substringWithRange:NSMakeRange(4, 2)] integerValue];
        NSInteger offset = (hh * 60 + mm) * 60;
        secs += [tz hasPrefix:@"+"] ? -offset : offset;
    }
    if (outSeconds) *outSeconds = secs;
    if (hasTime) *hasTime = time;
    return YES;
}

static double XFDaysFromDateString(NSString *s)
{
    double secs = 0;
    if (!XFParseXSDDateTime(s, &secs, NULL)) {
        return NAN;
    }
    // XSLTForms: Date.UTC(year, month, day) of the date part only.
    (void)secs;
    NSTextCheckingResult *m = [XFDateTimeRegex() firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    NSDateComponents *dc = [[NSDateComponents alloc] init];
    dc.year = [[s substringWithRange:[m rangeAtIndex:1]] integerValue];
    dc.month = [[s substringWithRange:[m rangeAtIndex:2]] integerValue];
    dc.day = [[s substringWithRange:[m rangeAtIndex:3]] integerValue];
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    return floor([[cal dateFromComponents:dc] timeIntervalSince1970] / 86400.0 + 0.000001);
}

/// XSLTForms `seconds()` / `months()`: any lexical xsd:duration; seconds()
/// ignores the Y/M fields and months() ignores D/T (XForms 1.1 7.10.4/5).
static NSArray<NSString *> *XFDurationParts(NSString *s)
{
    if (s.length == 0) return nil;
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
              @"^(-)?P(?!$)(?:([0-9]+)Y)?(?:([0-9]+)M)?(?:([0-9]+)D)?(?:T(?!$)(?:([0-9]+)H)?(?:([0-9]+)M)?(?:([0-9]+(?:\\.[0-9]+)?)S)?)?$"
                                                       options:0 error:NULL];
    });
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (m == nil) return nil;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSUInteger i = 1; i <= 7; i++) {
        NSRange r = [m rangeAtIndex:i];
        [parts addObject:r.location == NSNotFound ? @"" : [s substringWithRange:r]];
    }
    return parts;
}

static double XFDurationSeconds(NSString *s)
{
    NSArray *p = XFDurationParts(s);
    if (p == nil) return NAN;
    double sign = [p[0] length] ? -1.0 : 1.0;
    return sign * ((([p[3] doubleValue] * 24 + [p[4] doubleValue]) * 60 + [p[5] doubleValue]) * 60 + [p[6] doubleValue]);
}

static double XFDurationMonths(NSString *s)
{
    NSArray *p = XFDurationParts(s);
    if (p == nil) return NAN;
    double sign = [p[0] length] ? -1.0 : 1.0;
    return sign * ([p[1] doubleValue] * 12 + [p[2] doubleValue]);
}

static BOOL XFLuhn(NSString *s)
{
    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= '0' && c <= '9') {
            [digits appendFormat:@"%C", c];
        } else if (c != ' ' && c != '-') {
            return NO;
        }
    }
    if (digits.length == 0) {
        return NO;
    }
    NSInteger sum = 0;
    BOOL alt = NO;
    for (NSInteger i = (NSInteger)digits.length - 1; i >= 0; i--) {
        NSInteger d = [digits characterAtIndex:(NSUInteger)i] - '0';
        if (alt) {
            d *= 2;
            if (d > 9) d -= 9;
        }
        sum += d;
        alt = !alt;
    }
    return (sum % 10) == 0;
}

static NSString *XFHexFromData(NSData *data)
{
    static const char *hex = "0123456789abcdef";
    const unsigned char *b = data.bytes;
    NSMutableString *out = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) {
        [out appendFormat:@"%c%c", hex[(b[i] >> 4) & 0xF], hex[b[i] & 0xF]];
    }
    return out;
}

static BOOL XFDigestAlgorithmKnown(NSString *alg)
{
    NSString *a = [alg uppercaseString];
    return [@[ @"MD5", @"SHA-1", @"SHA1", @"SHA-256", @"SHA256", @"SHA-384", @"SHA384", @"SHA-512", @"SHA512" ] containsObject:a];
}

static BOOL XFDigestEncodingKnown(NSString *enc)
{
    NSString *e = [enc lowercaseString];
    return [e isEqualToString:@"base64"] || [e isEqualToString:@"hex"];
}

static NSString *XFDigestString(NSString *data, NSString *alg, NSString *enc, NSString *key)
{
    NSData *inData = [data dataUsingEncoding:NSUTF8StringEncoding];
    NSData *out = nil;
#ifdef XF_HAS_COMMONCRYPTO
    NSString *a = [alg uppercaseString];
    if (key) {
        NSData *k = [key dataUsingEncoding:NSUTF8StringEncoding];
        CCHmacAlgorithm ha = kCCHmacAlgMD5;
        NSUInteger len = CC_MD5_DIGEST_LENGTH;
        if ([a isEqualToString:@"SHA-1"] || [a isEqualToString:@"SHA1"]) {
            ha = kCCHmacAlgSHA1; len = CC_SHA1_DIGEST_LENGTH;
        } else if ([a isEqualToString:@"SHA-256"] || [a isEqualToString:@"SHA256"]) {
            ha = kCCHmacAlgSHA256; len = CC_SHA256_DIGEST_LENGTH;
        } else if ([a isEqualToString:@"SHA-384"] || [a isEqualToString:@"SHA384"]) {
            ha = kCCHmacAlgSHA384; len = CC_SHA384_DIGEST_LENGTH;
        } else if ([a isEqualToString:@"SHA-512"] || [a isEqualToString:@"SHA512"]) {
            ha = kCCHmacAlgSHA512; len = CC_SHA512_DIGEST_LENGTH;
        }
        unsigned char buf[64];
        CCHmac(ha, k.bytes, k.length, inData.bytes, inData.length, buf);
        out = [NSData dataWithBytes:buf length:len];
    } else {
        unsigned char buf[64];
        NSUInteger len = CC_MD5_DIGEST_LENGTH;
        if ([a isEqualToString:@"SHA-1"] || [a isEqualToString:@"SHA1"]) {
            CC_SHA1(inData.bytes, (CC_LONG)inData.length, buf);
            len = CC_SHA1_DIGEST_LENGTH;
        } else if ([a isEqualToString:@"SHA-256"] || [a isEqualToString:@"SHA256"]) {
            CC_SHA256(inData.bytes, (CC_LONG)inData.length, buf);
            len = CC_SHA256_DIGEST_LENGTH;
        } else if ([a isEqualToString:@"SHA-384"] || [a isEqualToString:@"SHA384"]) {
            CC_SHA384(inData.bytes, (CC_LONG)inData.length, buf);
            len = CC_SHA384_DIGEST_LENGTH;
        } else if ([a isEqualToString:@"SHA-512"] || [a isEqualToString:@"SHA512"]) {
            CC_SHA512(inData.bytes, (CC_LONG)inData.length, buf);
            len = CC_SHA512_DIGEST_LENGTH;
        } else {
            CC_MD5(inData.bytes, (CC_LONG)inData.length, buf);
        }
        out = [NSData dataWithBytes:buf length:len];
    }
#elif defined(XF_HAS_OPENSSL)
    NSString *a = [[alg uppercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    const EVP_MD *md = EVP_md5();
    if ([a isEqualToString:@"SHA1"]) md = EVP_sha1();
    else if ([a isEqualToString:@"SHA256"]) md = EVP_sha256();
    else if ([a isEqualToString:@"SHA384"]) md = EVP_sha384();
    else if ([a isEqualToString:@"SHA512"]) md = EVP_sha512();
    unsigned char buf[EVP_MAX_MD_SIZE];
    unsigned int len = 0;
    if (key) {
        NSData *k = [key dataUsingEncoding:NSUTF8StringEncoding];
        if (HMAC(md, k.bytes, (int)k.length, inData.bytes, inData.length, buf, &len) == NULL) {
            return @"";
        }
    } else if (!EVP_Digest(inData.bytes, inData.length, buf, &len, md, NULL)) {
        return @"";
    }
    out = [NSData dataWithBytes:buf length:len];
#else
    (void)alg; (void)key; (void)inData;
    return @"";
#endif
    if (out == nil) {
        return @"";
    }
    if ([[enc lowercaseString] isEqualToString:@"hex"]) {
        return XFHexFromData(out);
    }
    return [out base64EncodedStringWithOptions:0];
}

static BOOL XFSubtreeIsValid(NSXMLNode *n)
{
    XFNodeState *st = [XFNodeState existingStateOnNode:n];
    if (st && !st.valid) {
        return NO;
    }
    if ([n kind] == NSXMLElementKind) {
        for (NSXMLNode *a in [(NSXMLElement *)n attributes]) {
            if (!XFSubtreeIsValid(a)) return NO;
        }
    }
    for (NSXMLNode *c in [n children]) {
        if ([c kind] == NSXMLElementKind && !XFSubtreeIsValid(c)) return NO;
    }
    return YES;
}

/// event() values: strings/numbers → string, nodes → node-set, arrays of
/// nodes → node-set, dictionaries (response-headers) → <header><name/>
/// <value/></header> nodes, XML text bodies → parsed root element.
static XFXPathValue *XFEventValue(NSString *key, id v)
{
    if ([v isKindOfClass:[NSString class]]) {
        if ([key isEqualToString:@"response-body"]) {
            NSString *t = [v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([t hasPrefix:@"<"]) {
                NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:t options:0 error:NULL];
                if (doc.rootElement) {
                    XFXPathValue *nodes = [XFXPathValue nodeSet:@[ doc.rootElement ]];
                    // keep the document alive as long as the node-set
                    objc_setAssociatedObject(doc.rootElement, "XFEventDocument", doc, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    return nodes;
                }
            }
        }
        return [XFXPathValue string:v];
    }
    if ([v isKindOfClass:[NSNumber class]]) {
        return [XFXPathValue number:[v doubleValue]];
    }
    if ([v isKindOfClass:[NSXMLNode class]]) {
        return [XFXPathValue nodeSet:@[ v ]];
    }
    if ([v isKindOfClass:[NSArray class]]) {
        NSMutableArray *nodes = [NSMutableArray array];
        for (id item in v) {
            if ([item isKindOfClass:[NSXMLNode class]]) {
                [nodes addObject:item];
            }
        }
        if (nodes.count == [v count]) {
            return [XFXPathValue nodeSet:nodes];
        }
        return [XFXPathValue string:[v componentsJoinedByString:@" "]];
    }
    if ([v isKindOfClass:[NSDictionary class]]) {
        NSXMLElement *root = [NSXMLElement elementWithName:@"headers"];
        NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];
        NSMutableArray *nodes = [NSMutableArray array];
        for (NSString *name in [[v allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            NSXMLElement *h = [NSXMLElement elementWithName:@"header"];
            [h addChild:[NSXMLElement elementWithName:@"name" stringValue:name]];
            [h addChild:[NSXMLElement elementWithName:@"value" stringValue:[v[name] description]]];
            [root addChild:h];
            [nodes addObject:h];
        }
        objc_setAssociatedObject(root, "XFEventDocument", doc, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return [XFXPathValue nodeSet:nodes];
    }
    return [XFXPathValue string:[v description]];
}

@implementation XFXPathCoreFunctions

+ (NSDictionary<NSString *, XFXPathFunction *> *)table
{
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @"last": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)args; (void)err;
                return [XFXPathValue number:(double)(ctx.nodeList.count ? ctx.nodeList.count : ctx.size)];
            }],
            @"position": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)args; (void)err;
                return [XFXPathValue number:(double)ctx.position];
            }],
            @"count": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue number:(double)XFArg(args, 0).nodes.count];
            }],
            @"local-name": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNodeSet body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSXMLNode *n = XFArg(args, 0).firstNode;
                if (n == nil) return [XFXPathValue string:@""];
                return [XFXPathValue string:([n localName] ?: [n name]) ?: @""];
            }],
            @"namespace-uri": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNodeSet body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSXMLNode *n = XFArg(args, 0).firstNode;
                return [XFXPathValue string:n.URI ?: @""];
            }],
            @"name": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNodeSet body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSXMLNode *n = XFArg(args, 0).firstNode;
                return [XFXPathValue string:[n name] ?: @""];
            }],
            @"string": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNodeSet body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                XFXPathValue *a = XFArg(args, 0);
                return [XFXPathValue string:a ? [a stringValue] : @""];
            }],
            @"concat": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSMutableString *s = [NSMutableString string];
                for (XFXPathValue *v in args) {
                    [s appendString:[v stringValue]];
                }
                return [XFXPathValue string:s];
            }],
            @"starts-with": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *a = [XFArg(args, 0) stringValue] ?: @"";
                NSString *b = [XFArg(args, 1) stringValue] ?: @"";
                return [XFXPathValue boolean:[a hasPrefix:b]];
            }],
            @"contains": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *a = [XFArg(args, 0) stringValue] ?: @"";
                NSString *b = [XFArg(args, 1) stringValue] ?: @"";
                return [XFXPathValue boolean:b.length == 0 || [a rangeOfString:b].location != NSNotFound];
            }],
            @"substring-before": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *a = [XFArg(args, 0) stringValue] ?: @"";
                NSString *b = [XFArg(args, 1) stringValue] ?: @"";
                NSRange r = [a rangeOfString:b];
                if (b.length == 0 || r.location == NSNotFound) return [XFXPathValue string:@""];
                return [XFXPathValue string:[a substringToIndex:r.location]];
            }],
            @"substring-after": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *a = [XFArg(args, 0) stringValue] ?: @"";
                NSString *b = [XFArg(args, 1) stringValue] ?: @"";
                NSRange r = [a rangeOfString:b];
                if (b.length == 0) return [XFXPathValue string:a];
                if (r.location == NSNotFound) return [XFXPathValue string:@""];
                return [XFXPathValue string:[a substringFromIndex:NSMaxRange(r)]];
            }],
            @"substring": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *s = [XFArg(args, 0) stringValue] ?: @"";
                double start = round([XFArg(args, 1) numberValue]);
                double len = args.count > 2 ? round([XFArg(args, 2) numberValue]) : (double)s.length;
                if (isnan(start) || isinf(start) || isnan(len)) return [XFXPathValue string:@""];
                NSInteger from = (NSInteger)start - 1;
                if (from < 0) {
                    len += from;
                    from = 0;
                }
                if (from >= (NSInteger)s.length || len <= 0) return [XFXPathValue string:@""];
                NSInteger end = from + (NSInteger)len;
                if (end > (NSInteger)s.length) end = (NSInteger)s.length;
                return [XFXPathValue string:[s substringWithRange:NSMakeRange((NSUInteger)from, (NSUInteger)(end - from))]];
            }],
            @"string-length": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultString body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue number:(double)([XFArg(args, 0) stringValue] ?: @"").length];
            }],
            @"normalize-space": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultString body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *s = [XFArg(args, 0) stringValue] ?: @"";
                NSArray *parts = [s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSMutableArray *nz = [NSMutableArray array];
                for (NSString *p in parts) {
                    if (p.length) [nz addObject:p];
                }
                return [XFXPathValue string:[nz componentsJoinedByString:@" "]];
            }],
            @"translate": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *s = [XFArg(args, 0) stringValue] ?: @"";
                NSString *from = [XFArg(args, 1) stringValue] ?: @"";
                NSString *to = [XFArg(args, 2) stringValue] ?: @"";
                NSMutableString *out = [NSMutableString string];
                for (NSUInteger i = 0; i < s.length; i++) {
                    unichar c = [s characterAtIndex:i];
                    NSRange r = [from rangeOfString:[NSString stringWithCharacters:&c length:1]];
                    if (r.location == NSNotFound) {
                        [out appendFormat:@"%C", c];
                    } else if (r.location < to.length) {
                        [out appendFormat:@"%C", [to characterAtIndex:r.location]];
                    }
                }
                return [XFXPathValue string:out];
            }],
            @"boolean": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue boolean:XFArg(args, 0).booleanValue];
            }],
            @"not": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue boolean:!XFArg(args, 0).booleanValue];
            }],
            @"true": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)args; (void)err;
                return [XFXPathValue boolean:YES];
            }],
            @"false": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)args; (void)err;
                return [XFXPathValue boolean:NO];
            }],
            @"number": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNodeSet body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue number:XFArg(args, 0).numberValue];
            }],
            @"sum": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                double sum = 0;
                for (NSXMLNode *n in XFArg(args, 0).nodes) {
                    sum += [XFXPathValue nodeSet:@[ n ]].numberValue;
                }
                return [XFXPathValue number:sum];
            }],
            @"floor": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue number:floor(XFArg(args, 0).numberValue)];
            }],
            @"ceiling": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue number:ceil(XFArg(args, 0).numberValue)];
            }],
            @"round": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                // XPath 1.0: round half towards +infinity (round(-2.5) = -2)
                double x = XFArg(args, 0).numberValue;
                return [XFXPathValue number:(isnan(x) || isinf(x)) ? x : floor(x + 0.5)];
            }],
            @"instance": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                XFModel *model = ctx.model;
                if (model == nil) {
                    if (err) {
                        *err = [NSError errorWithDomain:XFErrorDomain
                                                   code:XFErrorXPathEvaluation
                                               userInfo:@{ NSLocalizedDescriptionKey:
                                                               @"instance() requires a model on the evaluation context" }];
                    }
                    return nil;
                }
                NSString *ident = args.count > 0 ? [args[0] stringValue] : nil;
                XFInstance *inst = nil;
                if (ident.length) {
                    inst = [model instanceWithIdentifier:ident];
                    if (inst == nil && [model.owner isKindOfClass:[XFProcessor class]]) {
                        // instance('id') resolves across all models (XSLTForms uses the DOM id)
                        for (XFModel *m in [(XFProcessor *)model.owner models]) {
                            inst = [m instanceWithIdentifier:ident];
                            if (inst) break;
                        }
                    }
                } else {
                    // instance() with no argument: the instance holding the context node
                    inst = ctx.contextNode ? [model instanceContainingNode:ctx.contextNode] : nil;
                    inst = inst ?: [model defaultInstance];
                }
                NSXMLElement *root = [inst documentElement];
                if (root) {
                    [ctx addDependency:root];
                    [ctx addDepElement:model];
                }
                return [XFXPathValue nodeSet:root ? @[ root ] : @[]];
            }],
            @"index": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)err;
                XFModel *model = ctx.model;
                NSString *ident = args.count > 0 ? [args[0] stringValue] : nil;
                XFRepeat *repeat = [model repeatWithIdentifier:ident];
                if (repeat == nil) {
                    return [XFXPathValue number:NAN];
                }
                [ctx addDepElement:repeat];
                return [XFXPathValue number:(double)repeat.index];
            }],
            @"context": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)args; (void)err;
                NSXMLNode *n = ctx.currentNode ?: ctx.contextNode;
                return [XFXPathValue nodeSet:n ? @[ n ] : @[]];
            }],
            @"current": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)args; (void)err;
                NSXMLNode *n = ctx.currentNode ?: ctx.contextNode;
                if (n) {
                    [ctx addDependency:n];
                    if (ctx.model) [ctx addDepElement:ctx.model];
                }
                return [XFXPathValue nodeSet:n ? @[ n ] : @[]];
            }],
            @"if": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                BOOL cond = XFArg(args, 0).booleanValue;
                XFXPathValue *chosen = cond ? XFArg(args, 1) : XFArg(args, 2);
                return chosen ?: [XFXPathValue string:@""];
            }],
            @"choose": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                BOOL cond = XFArg(args, 0).booleanValue;
                XFXPathValue *chosen = cond ? XFArg(args, 1) : XFArg(args, 2);
                return chosen ?: [XFXPathValue string:@""];
            }],
            @"boolean-from-string": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultString body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *s = [[XFArg(args, 0) stringValue] lowercaseString];
                return [XFXPathValue boolean:[s isEqualToString:@"true"] || [s isEqualToString:@"1"]];
            }],
            @"count-non-empty": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSUInteger n = 0;
                for (NSXMLNode *node in XFArg(args, 0).nodes) {
                    if ([XFXML stringValueOfNode:node].length) {
                        n++;
                    }
                }
                return [XFXPathValue number:(double)n];
            }],
            @"power": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue number:pow(XFArg(args, 0).numberValue, XFArg(args, 1).numberValue)];
            }],
            @"random": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)args; (void)err;
                return [XFXPathValue number:(double)arc4random() / (double)UINT32_MAX];
            }],
            @"property": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)err;
                NSString *name = [XFArg(args, 0) stringValue];
                if ([name isEqualToString:@"version"]) {
                    return [XFXPathValue string:@"1.1"];
                }
                if ([name isEqualToString:@"conformance-level"]) {
                    return [XFXPathValue string:@"full"];
                }
                // XSLTForms extras (G-75); xsl:* vendor properties have no
                // XSLT engine behind them here
                if ([name isEqualToString:@"xsltforms:debug-mode"]) {
                    return [XFXPathValue string:@"off"];
                }
                if ([name isEqualToString:@"xsltforms:version"]) {
                    return [XFXPathValue string:@"XFormsKit"];
                }
                if ([name isEqualToString:@"xsltforms:version-number"]) {
                    return [XFXPathValue string:@"1"];
                }
                if ([name hasPrefix:@"xsl:"]) {
                    if ([name isEqualToString:@"xsl:vendor"]) {
                        return [XFXPathValue string:@"XFormsKit"];
                    }
                    return [XFXPathValue string:@""];
                }
                if (name.length && [name rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:
                        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.:"] invertedSet]].location != NSNotFound) {
                    [XFXMLEvents raise:@"xforms-binding-exception" on:ctx.model message:@"Invalid NCNAME"];
                }
                return [XFXPathValue string:@""];
            }],
            @"event": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *key = [XFArg(args, 0) stringValue];
                if (key.length == 0) {
                    return [XFXPathValue string:@""];
                }
                // XSLTForms walks the EventContexts stack innermost first.
                NSArray *stack = [XFXMLEvents eventContexts];
                for (NSInteger i = (NSInteger)stack.count - 1; i >= 0; i--) {
                    id v = stack[(NSUInteger)i][key];
                    if (v == nil || v == [NSNull null]) {
                        continue;
                    }
                    return XFEventValue(key, v);
                }
                return [XFXPathValue string:@""];
            }],
            @"id": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)err;
                NSMutableArray *ids = [NSMutableArray array];
                XFXPathValue *arg = XFArg(args, 0);
                if (arg.nodes.count) {
                    for (NSXMLNode *n in arg.nodes) {
                        NSString *s = [XFXML stringValueOfNode:n];
                        for (NSString *tok in [s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
                            if (tok.length) [ids addObject:tok];
                        }
                    }
                } else {
                    for (NSString *tok in [[arg stringValue] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
                        if (tok.length) [ids addObject:tok];
                    }
                }
                // optional second argument: a node whose document is searched
                NSXMLNode *scope = args.count > 1 ? XFArg(args, 1).firstNode : nil;
                NSXMLNode *root = XFRootNode(scope ?: ctx.contextNode);
                NSMutableArray *found = [NSMutableArray array];
                for (NSString *ident in ids) {
                    NSXMLElement *el = [XFXML elementWithID:ident inNode:root];
                    if (el) [found addObject:el];
                }
                return [XFXPathValue nodeSet:found];
            }],
            @"lang": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)err;
                NSString *want = [[XFArg(args, 0) stringValue] lowercaseString];
                NSString *have = nil;
                for (NSXMLNode *n = ctx.contextNode; n; n = [n parent]) {
                    if ([n kind] != NSXMLElementKind) continue;
                    NSXMLNode *attr = [(NSXMLElement *)n attributeForName:@"xml:lang"];
                    if (attr == nil) {
                        attr = [(NSXMLElement *)n attributeForName:@"lang"];
                    }
                    if (attr) {
                        have = [[attr stringValue] lowercaseString];
                        break;
                    }
                }
                if (have.length == 0) {
                    return [XFXPathValue boolean:NO];
                }
                BOOL ok = [have isEqualToString:want] || [have hasPrefix:[want stringByAppendingString:@"-"]];
                return [XFXPathValue boolean:ok];
            }],
            @"now": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)args; (void)err;
                return [XFXPathValue string:XFFormatDateTime([NSDate date], YES)];
            }],
            @"local-date": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)args; (void)err;
                return [XFXPathValue string:XFFormatDate([NSDate date], NO)];
            }],
            @"local-dateTime": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)args; (void)err;
                return [XFXPathValue string:XFFormatDateTime([NSDate date], NO)];
            }],
            @"days-from-date": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                double d = XFDaysFromDateString([XFArg(args, 0) stringValue]);
                return [XFXPathValue number:d];
            }],
            @"days-to-date": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                double days = XFArg(args, 0).numberValue;
                if (isnan(days)) return [XFXPathValue string:@""];
                NSDate *date = [NSDate dateWithTimeIntervalSince1970:days * 86400.0];
                return [XFXPathValue string:XFFormatDate(date, YES)];
            }],
            @"seconds-from-dateTime": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                double secs = 0; BOOL hasTime = NO;
                if (!XFParseXSDDateTime([XFArg(args, 0) stringValue], &secs, &hasTime) || !hasTime) {
                    return [XFXPathValue number:NAN];
                }
                return [XFXPathValue number:secs];
            }],
            @"seconds-to-dateTime": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                double s = XFArg(args, 0).numberValue;
                if (isnan(s)) return [XFXPathValue string:@""];
                return [XFXPathValue string:XFFormatDateTime([NSDate dateWithTimeIntervalSince1970:s], YES)];
            }],
            @"seconds": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue number:XFDurationSeconds([XFArg(args, 0) stringValue])];
            }],
            @"months": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue number:XFDurationMonths([XFArg(args, 0) stringValue])];
            }],
            @"is-valid": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNodeSet body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                BOOL ok = YES;
                NSArray *nodes = XFArg(args, 0).nodes;
                if (nodes.count == 0 && ctx.contextNode) {
                    nodes = @[ ctx.contextNode ];
                }
                // XSLTForms validate_(): the node, its attributes and descendants
                for (NSXMLNode *n in nodes) {
                    if (!XFSubtreeIsValid(n)) {
                        ok = NO;
                        break;
                    }
                }
                return [XFXPathValue boolean:ok];
            }],
            @"is-card-number": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultString body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue boolean:XFLuhn([XFArg(args, 0) stringValue])];
            }],
            @"digest": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *data = [XFArg(args, 0) stringValue] ?: @"";
                NSString *alg = args.count > 1 ? [XFArg(args, 1) stringValue] : @"MD5";
                NSString *enc = args.count > 2 ? [XFArg(args, 2) stringValue] : @"base64";
                if (!XFDigestAlgorithmKnown(alg)) {
                    [XFXMLEvents raise:@"xforms-binding-exception" on:ctx.model message:@"Invalid crypting method"];
                    return [XFXPathValue string:@""];
                }
                if (!XFDigestEncodingKnown(enc)) {
                    [XFXMLEvents raise:@"xforms-binding-exception" on:ctx.model message:@"Invalid encoding method"];
                    return [XFXPathValue string:@""];
                }
                NSString *out = XFDigestString(data, alg, enc, nil);
                return [XFXPathValue string:out ?: @""];
            }],
            @"hmac": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *key = [XFArg(args, 0) stringValue] ?: @"";
                NSString *data = [XFArg(args, 1) stringValue] ?: @"";
                NSString *alg = args.count > 2 ? [XFArg(args, 2) stringValue] : @"MD5";
                NSString *enc = args.count > 3 ? [XFArg(args, 3) stringValue] : @"base64";
                if (!XFDigestAlgorithmKnown(alg)) {
                    [XFXMLEvents raise:@"xforms-binding-exception" on:ctx.model message:@"Invalid crypting method"];
                    return [XFXPathValue string:@""];
                }
                if (!XFDigestEncodingKnown(enc)) {
                    [XFXMLEvents raise:@"xforms-binding-exception" on:ctx.model message:@"Invalid encoding method"];
                    return [XFXPathValue string:@""];
                }
                NSString *out = XFDigestString(data, alg, enc, key);
                return [XFXPathValue string:out ?: @""];
            }],
        };
    });
    return table;
}

+ (XFXPathFunction *)functionNamed:(NSString *)name
{
    NSString *local = XFLocalName(name);
    XFXPathFunction *fn = [self table][local] ?: [self table][name];
    if (fn == nil) {
        NSDictionary *extra = XFXPathExtraFunctionTable();
        fn = extra[local] ?: extra[name];
    }
    return fn;
}

@end
