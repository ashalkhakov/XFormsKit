#import "XFXPathPriv.h"
#import "XFModel.h"
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
#if __has_include(<CommonCrypto/CommonDigest.h>)
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#define XF_HAS_COMMONCRYPTO 1
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

static NSDate *XFParseDateTime(NSString *s)
{
    if (s.length < 10) {
        return nil;
    }
    NSString *core = s;
    if ([core hasSuffix:@"Z"]) {
        core = [core substringToIndex:core.length - 1];
    }
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    for (NSString *pat in @[ @"yyyy-MM-dd'T'HH:mm:ss", @"yyyy-MM-dd'T'HH:mm:ss.SSS", @"yyyy-MM-dd" ]) {
        fmt.dateFormat = pat;
        NSDate *d = [fmt dateFromString:[core substringToIndex:MIN(core.length, (NSUInteger)[pat length] + 4)]];
        if (d) {
            return d;
        }
        d = [fmt dateFromString:core];
        if (d) {
            return d;
        }
    }
    if (s.length >= 10) {
        fmt.dateFormat = @"yyyy-MM-dd";
        return [fmt dateFromString:[s substringToIndex:10]];
    }
    return nil;
}

static double XFDaysFromDateString(NSString *s)
{
    NSDate *d = XFParseDateTime(s);
    if (d == nil) {
        return NAN;
    }
    return floor([d timeIntervalSince1970] / 86400.0);
}

static double XFDurationSeconds(NSString *s)
{
    if (s.length == 0) return NAN;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:
                               @"^(-)?P(?:([0-9]+)D)?(?:T(?:([0-9]+)H)?(?:([0-9]+)M)?(?:([0-9]+(?:\\.[0-9]+)?)S)?)?$"
                                                                        options:0 error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (m == nil) return NAN;
    double sign = [m rangeAtIndex:1].location != NSNotFound ? -1.0 : 1.0;
    double days = ([m rangeAtIndex:2].location != NSNotFound) ? [[s substringWithRange:[m rangeAtIndex:2]] doubleValue] : 0;
    double hours = ([m rangeAtIndex:3].location != NSNotFound) ? [[s substringWithRange:[m rangeAtIndex:3]] doubleValue] : 0;
    double mins = ([m rangeAtIndex:4].location != NSNotFound) ? [[s substringWithRange:[m rangeAtIndex:4]] doubleValue] : 0;
    double secs = ([m rangeAtIndex:5].location != NSNotFound) ? [[s substringWithRange:[m rangeAtIndex:5]] doubleValue] : 0;
    return sign * (days * 86400.0 + hours * 3600.0 + mins * 60.0 + secs);
}

static double XFDurationMonths(NSString *s)
{
    if (s.length == 0) return NAN;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:
                               @"^(-)?P(?:([0-9]+)Y)?(?:([0-9]+)M)?$"
                                                                        options:0 error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (m == nil) return NAN;
    double sign = [m rangeAtIndex:1].location != NSNotFound ? -1.0 : 1.0;
    double years = ([m rangeAtIndex:2].location != NSNotFound) ? [[s substringWithRange:[m rangeAtIndex:2]] doubleValue] : 0;
    double months = ([m rangeAtIndex:3].location != NSNotFound) ? [[s substringWithRange:[m rangeAtIndex:3]] doubleValue] : 0;
    return sign * (years * 12.0 + months);
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
                return [XFXPathValue number:round(XFArg(args, 0).numberValue)];
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
                XFInstance *inst = ident.length ? [model instanceWithIdentifier:ident] : [model defaultInstance];
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
            @"property": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *name = [XFArg(args, 0) stringValue];
                if ([name isEqualToString:@"version"]) {
                    return [XFXPathValue string:@"1.1"];
                }
                if ([name isEqualToString:@"conformance-level"]) {
                    return [XFXPathValue string:@"full"];
                }
                return [XFXPathValue string:@""];
            }],
            @"event": [XFXPathFunction acceptContext:YES defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *key = [XFArg(args, 0) stringValue];
                NSDictionary *ev = [XFXMLEvents currentEventContext];
                id v = key.length ? ev[key] : nil;
                if ([v isKindOfClass:[NSString class]]) {
                    return [XFXPathValue string:v];
                }
                if ([v isKindOfClass:[NSNumber class]]) {
                    return [XFXPathValue string:[v stringValue]];
                }
                if ([v isKindOfClass:[NSXMLNode class]]) {
                    return [XFXPathValue nodeSet:@[ v ]];
                }
                return [XFXPathValue string:v ? [v description] : @""];
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
                NSXMLNode *root = XFRootNode(ctx.contextNode);
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
                NSDate *d = XFParseDateTime([XFArg(args, 0) stringValue]);
                return [XFXPathValue number:d ? [d timeIntervalSince1970] : NAN];
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
                for (NSXMLNode *n in nodes) {
                    XFNodeState *st = [XFNodeState existingStateOnNode:n];
                    if (st && !st.valid) {
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
            @"digest": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *data = [XFArg(args, 0) stringValue] ?: @"";
                NSString *alg = args.count > 1 ? [XFArg(args, 1) stringValue] : @"MD5";
                NSString *enc = args.count > 2 ? [XFArg(args, 2) stringValue] : @"base64";
                NSString *out = XFDigestString(data, alg, enc, nil);
                return [XFXPathValue string:out ?: @""];
            }],
            @"hmac": [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone body:^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *key = [XFArg(args, 0) stringValue] ?: @"";
                NSString *data = [XFArg(args, 1) stringValue] ?: @"";
                NSString *alg = args.count > 2 ? [XFArg(args, 2) stringValue] : @"MD5";
                NSString *enc = args.count > 3 ? [XFArg(args, 3) stringValue] : @"base64";
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
    XFXPathFunction *fn = [self table][local];
    if (fn == nil) {
        fn = [self table][name];
    }
    return fn;
}

@end
