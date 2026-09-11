// XPath functions beyond the XPath 1.0 / XForms 1.1 core: the XPath 2 style
// string and aggregate helpers, format-number, EXSLT math and the XSLTForms
// extensions the samples use. Translated from XSLTForms
// xpathexpr/XPathCoreFunctions.js (LGPL 2.1).

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "XFXPathPriv.h"
#import "XFXML.h"
#import "XFModel.h"
#import "XFControl.h"
#import "XFProcessor.h"
#import "XFSubform.h"
#import "XFInstance.h"
#import <XFormsKit/XFXMLTypes.h>
#import <math.h>
#import <objc/runtime.h>

/// XsltForms_exprContext carries the subform of the evaluating element;
/// resolve it from ctx.sourceElement (set by XFBinding around each
/// evaluation), falling back to the context model's own subform (model
/// event handlers run with the subform model's context).
static XFSubform *XFSubformOfContext(XFExprContext *ctx)
{
    id owner = ctx.model.owner;
    if (ctx.sourceElement && [owner isKindOfClass:[XFProcessor class]]) {
        XFSubform *sf = [(XFProcessor *)owner subformContainingElement:ctx.sourceElement];
        if (sf) {
            return sf;
        }
    }
    return ctx.model.subform;
}

static XFXPathValue *XFArg(NSArray<XFXPathValue *> *args, NSUInteger i)
{
    return i < args.count ? args[i] : nil;
}

static NSString *XFStr(NSArray<XFXPathValue *> *args, NSUInteger i)
{
    return [XFArg(args, i) stringValue] ?: @"";
}

static double XFNodeNumber(XFXMLNode *n)
{
    return [XFXPathValue string:XFXPathNodeValue(n)].numberValue;
}

/// Detached text-like nodes returned by tokenize() / fromtostep(), kept
/// alive by their owning document.
static XFXPathValue *XFSyntheticNodeSet(NSString *elementName, NSArray<NSString *> *values)
{
    XFXMLElement *root = [XFXMLElement elementWithName:@"items"];
    XFXMLDocument *doc = [[XFXMLDocument alloc] initWithRootElement:root];
    NSMutableArray *nodes = [NSMutableArray array];
    for (NSString *v in values) {
        XFXMLElement *e = [XFXMLElement elementWithName:elementName stringValue:v];
        [root addChild:e];
        [nodes addObject:e];
    }
    objc_setAssociatedObject(root, "XFSyntheticDocument", doc, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return [XFXPathValue nodeSet:nodes];
}

#pragma mark - format-number (XSLTForms port)

typedef struct {
    NSString *decimalSeparator;
    NSString *groupingSeparator;
    NSString *minusSign;
    NSString *percent;
    NSString *perMille;
    NSString *infinity;
    NSString *nan;
    NSString *exponentSeparator;
    NSString *patternSeparator;
} XFNumberFormatSymbols;

static XFNumberFormatSymbols XFDefaultSymbols(void)
{
    // XSLTForms reads these from the i18n config (config.xsl); the defaults
    // are the XSLT 1.0 decimal-format defaults.
    XFNumberFormatSymbols s = { @".", @",", @"-", @"%", @"‰", @"Infinity", @"NaN", @"e", @";" };
    return s;
}

static NSString *XFFormatNumber(double value, NSString *picture)
{
    XFNumberFormatSymbols sym = XFDefaultSymbols();
    if (isnan(value)) {
        return sym.nan;
    }
    NSArray<NSString *> *pictures = [picture componentsSeparatedByString:sym.patternSeparator];
    picture = (value < 0 && pictures.count > 1) ? pictures[1] : pictures[0];
    NSString *signs = @".,-%‰#0123456789";
    NSString *esigns = @".,e-%‰#0123456789";
    __block NSUInteger i = 0;
    NSUInteger l = picture.length;
    while (i < l && [signs rangeOfString:[picture substringWithRange:NSMakeRange(i, 1)]].location == NSNotFound) {
        i++;
    }
    NSString *prefix = [picture substringToIndex:i];
    BOOL dss = NO, ess = NO, ms = NO, ps = NO, pms = NO;
    BOOL msbefore = NO, psafter = NO, pmsafter = NO;
    NSUInteger mips = 0, minfps = 0, maxfps = 0, mes = 0;
    NSMutableArray<NSNumber *> *iipgp = [NSMutableArray array];
    NSMutableArray<NSNumber *> *ipgp = [NSMutableArray array];
    NSMutableArray<NSNumber *> *fpgp = [NSMutableArray array];
    NSUInteger fstart = 0;
    void (^closeIntegerGroups)(void) = ^{
        NSUInteger l2 = iipgp.count;
        while (ipgp.count < l2) [ipgp addObject:@0];
        for (NSUInteger j = 0; j < l2; j++) {
            ipgp[l2 - j - 1] = @((NSInteger)i - [iipgp[j] integerValue] - 1);
        }
    };
    (void)msbefore;
    while (i < l && [esigns rangeOfString:[picture substringWithRange:NSMakeRange(i, 1)]].location != NSNotFound) {
        unichar c = [picture characterAtIndex:i];
        switch (c) {
            case '.':
                dss = YES;
                fstart = i + 1;
                closeIntegerGroups();
                break;
            case ',':
                if (dss) {
                    [fpgp addObject:@(i - fstart)];
                } else {
                    [iipgp addObject:@(i)];
                }
                break;
            case 'e':
                ess = YES;
                if (!dss) closeIntegerGroups();
                break;
            case '-':
                ms = YES;
                msbefore = mips == 0;
                break;
            case '%':
                ps = YES;
                psafter = mips != 0;
                value *= 100;
                if (!dss) closeIntegerGroups();
                break;
            case 0x2030:
                pms = YES;
                pmsafter = mips != 0;
                value *= 1000;
                if (!dss) closeIntegerGroups();
                break;
            case '#':
                if (dss) maxfps++;
                break;
            default: // digit
                if (ess) {
                    mes++;
                } else if (dss) {
                    minfps++;
                    maxfps++;
                } else {
                    mips++;
                }
                break;
        }
        i++;
    }
    (void)ms;
    if (!dss) {
        if (iipgp.count != ipgp.count) {
            closeIntegerGroups();
        }
        if (mips == 0) {
            mips = 1;
        }
    }
    if (ipgp.count > 1) {
        NSUInteger j = 1;
        while (j < ipgp.count && [ipgp[0] integerValue] != 0
               && [ipgp[j] integerValue] % [ipgp[0] integerValue] == 0) {
            j++;
        }
        if (j == ipgp.count) {
            ipgp = [NSMutableArray arrayWithObject:ipgp[0]];
        }
    }
    if (ipgp.count == 1 && [ipgp[0] integerValue] > 0) {
        for (NSUInteger j = 1; j < 30; j++) {
            [ipgp addObject:@([ipgp[j - 1] integerValue] + [ipgp[0] integerValue])];
        }
    }
    NSString *suffix = [picture substringFromIndex:i];
    if (isinf(value)) {
        return value > 0 ? [NSString stringWithFormat:@"%@%@%@", prefix, sym.infinity, suffix]
                         : [NSString stringWithFormat:@"%@%@%@%@", sym.minusSign, prefix, sym.infinity, suffix];
    }
    if (value < 0 && pictures.count == 1) {
        prefix = [sym.minusSign stringByAppendingString:prefix];
    }
    NSString *evalue = @"";
    if (ess) {
        double e = value == 0 ? 0 : floor(log10(fabs(value))) + 1 - (double)mips;
        value /= pow(10, e);
        NSString *esign = e < 0 ? sym.minusSign : @"";
        NSString *digits = [NSString stringWithFormat:@"%.0f", fabs(e)];
        while (digits.length < mes) {
            digits = [@"0" stringByAppendingString:digits];
        }
        evalue = [esign stringByAppendingString:digits];
    }
    NSString *s0 = [NSString stringWithFormat:@"%.*f", (int)maxfps, fabs(value)];
    // optional (#) fraction digits are omitted when zero (XSLT 1.0 12.3)
    if (maxfps > minfps && [s0 rangeOfString:@"."].location != NSNotFound) {
        NSUInteger keep = (NSUInteger)[s0 rangeOfString:@"."].location + 1 + minfps;
        while (s0.length > keep && [s0 hasSuffix:@"0"]) {
            s0 = [s0 substringToIndex:s0.length - 1];
        }
        if ([s0 hasSuffix:@"."]) {
            s0 = [s0 substringToIndex:s0.length - 1];
        }
    }
    if (maxfps == 0 && dss) {
        s0 = [s0 stringByAppendingString:@"."];
    }
    NSRange dot = [s0 rangeOfString:@"."];
    NSInteger dsspos = dot.location == NSNotFound ? (NSInteger)s0.length : (NSInteger)dot.location;
    if (dsspos < (NSInteger)mips) {
        NSMutableString *pad = [NSMutableString string];
        for (NSInteger k = 0; k < (NSInteger)mips - dsspos; k++) [pad appendString:@"0"];
        s0 = [pad stringByAppendingString:s0];
        dsspos = (NSInteger)mips;
    }
    NSMutableString *s = [NSMutableString string];
    NSInteger j = dsspos - 1;
    NSUInteger gi = 0;
    NSInteger l2 = (NSInteger)s0.length;
    while (j >= 0) {
        [s insertString:[s0 substringWithRange:NSMakeRange((NSUInteger)j, 1)] atIndex:0];
        if (j != 0 && gi < ipgp.count && [ipgp[gi] integerValue] == dsspos - j) {
            [s insertString:sym.groupingSeparator atIndex:0];
            gi++;
        }
        j--;
    }
    if (dss) {
        [s appendString:sym.decimalSeparator];
        j = dsspos + 1;
        gi = 0;
        while (j < l2) {
            [s appendString:[s0 substringWithRange:NSMakeRange((NSUInteger)j, 1)]];
            if (j != l2 - 1 && gi < fpgp.count && [fpgp[gi] integerValue] == j - dsspos) {
                [s appendString:sym.groupingSeparator];
                gi++;
            }
            j++;
        }
    }
    if (ps) {
        if (psafter) [s appendString:sym.percent]; else [s insertString:sym.percent atIndex:0];
    }
    if (pms) {
        if (pmsafter) [s appendString:sym.perMille]; else [s insertString:sym.perMille atIndex:0];
    }
    if (ess) {
        [s appendString:sym.exponentSeparator];
        [s appendString:evalue];
    }
    return [NSString stringWithFormat:@"%@%@%@", prefix, s, suffix];
}

#pragma mark - Date helpers

/// adjust-dateTime-to-timezone(): a dateTime with explicit zone is converted
/// to local time; without a zone it is taken as local time already.
static NSString *XFAdjustToLocal(NSString *s)
{
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
              @"^([12][0-9]{3})-(0[1-9]|1[012])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):([0-5][0-9]):([0-5][0-9])(\\.[0-9]+)?(Z|[+\\-])?([01][0-9]|2[0-3])?:?([0-5][0-9])?"
                                                       options:0 error:NULL];
    });
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (m == nil) {
        return @"";
    }
    NSInteger (^num)(NSUInteger) = ^NSInteger(NSUInteger k) {
        NSRange r = [m rangeAtIndex:k];
        return r.location == NSNotFound ? 0 : [[s substringWithRange:r] integerValue];
    };
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = num(1); c.month = num(2); c.day = num(3);
    c.hour = num(4); c.minute = num(5); c.second = num(6);
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSRange zr = [m rangeAtIndex:8];
    if (zr.location != NSNotFound) {
        cal.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        NSDate *d = [cal dateFromComponents:c];
        NSString *z = [s substringWithRange:zr];
        if (![z isEqualToString:@"Z"]) {
            NSInteger offset = (num(9) * 60 + num(10)) * 60;
            d = [d dateByAddingTimeInterval:[z isEqualToString:@"+"] ? -offset : offset];
        }
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.timeZone = [NSTimeZone localTimeZone];
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssxxx";
        return [fmt stringFromDate:d];
    }
    cal.timeZone = [NSTimeZone localTimeZone];
    NSDate *d = [cal dateFromComponents:c];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.timeZone = [NSTimeZone localTimeZone];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssxxx";
    return [fmt stringFromDate:d];
}

#pragma mark - Table

#define XF_FN(ctxflag, dflt, ...) [XFXPathFunction acceptContext:ctxflag defaultTo:dflt body:__VA_ARGS__]
#define XF_MATH1(fn) XF_FN(NO, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) { \
        (void)ctx; (void)err; return [XFXPathValue number:fn(XFArg(args, 0).numberValue)]; })

NSDictionary<NSString *, XFXPathFunction *> *XFXPathExtraFunctionTable(void)
{
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            // ---- XPath 2 style string functions (fn namespace in XSLTForms)
            @"ends-with": XF_FN(NO, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue boolean:[XFStr(args, 0) hasSuffix:XFStr(args, 1)]];
            }),
            @"compare": XF_FN(NO, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSComparisonResult r = [XFStr(args, 0) compare:XFStr(args, 1)];
                return [XFXPathValue number:r == NSOrderedSame ? 0 : (r == NSOrderedDescending ? 1 : -1)];
            }),
            @"replace": XF_FN(NO, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx;
                NSString *s = XFStr(args, 0);
                NSError *inner = nil;
                NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:XFStr(args, 1) options:0 error:&inner];
                if (re == nil) {
                    if (err) *err = inner;
                    return nil;
                }
                return [XFXPathValue string:[re stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length)
                                                                     withTemplate:XFStr(args, 2)]];
            }),
            @"upper-case": XF_FN(NO, XFXPathFnDefaultNodeSet, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue string:[XFStr(args, 0) uppercaseString]];
            }),
            @"lower-case": XF_FN(NO, XFXPathFnDefaultNodeSet, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue string:[XFStr(args, 0) lowercaseString]];
            }),
            @"string-join": XF_FN(NO, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSMutableArray *parts = [NSMutableArray array];
                XFXPathValue *v = XFArg(args, 0);
                if (v.type == XFXPathValueTypeNodeSet) {
                    for (XFXMLNode *n in v.nodes) {
                        [parts addObject:XFXPathNodeValue(n)];
                    }
                } else if (v) {
                    [parts addObject:[v stringValue]];
                }
                return [XFXPathValue string:[parts componentsJoinedByString:args.count > 1 ? XFStr(args, 1) : @""]];
            }),
            @"tokenize": XF_FN(NO, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx;
                NSString *s = XFStr(args, 0);
                NSError *inner = nil;
                NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:XFStr(args, 1) options:0 error:&inner];
                if (re == nil) {
                    if (err) *err = inner;
                    return nil;
                }
                NSMutableArray *tokens = [NSMutableArray array];
                NSUInteger last = 0;
                for (NSTextCheckingResult *m in [re matchesInString:s options:0 range:NSMakeRange(0, s.length)]) {
                    if (m.range.length == 0) continue;
                    [tokens addObject:[s substringWithRange:NSMakeRange(last, m.range.location - last)]];
                    last = NSMaxRange(m.range);
                }
                [tokens addObject:[s substringFromIndex:last]];
                return XFSyntheticNodeSet(@"token", tokens);
            }),
            @"encode-for-uri": XF_FN(NO, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                // encodeURIComponent: unreserved = A-Z a-z 0-9 - _ . ! ~ * ' ( )
                NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                                           @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"];
                return [XFXPathValue string:[XFStr(args, 0) stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @""];
            }),
            @"distinct-values": XF_FN(NO, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSMutableArray *out = [NSMutableArray array];
                NSMutableSet *seen = [NSMutableSet set];
                for (XFXMLNode *n in XFArg(args, 0).nodes) {
                    NSString *v = XFXPathNodeValue(n);
                    if (![seen containsObject:v]) {
                        [seen addObject:v];
                        [out addObject:n];
                    }
                }
                return [XFXPathValue nodeSet:out];
            }),

            // ---- aggregates
            @"avg": XF_FN(NO, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSArray *nodes = XFArg(args, 0).nodes;
                double sum = 0;
                for (XFXMLNode *n in nodes) sum += XFNodeNumber(n);
                return [XFXPathValue number:sum / (double)nodes.count];
            }),
            @"min": XF_FN(NO, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSArray *nodes = XFArg(args, 0).nodes;
                if (nodes.count == 0) return [XFXPathValue number:NAN];
                double m = XFNodeNumber(nodes[0]);
                for (NSUInteger i = 1; i < nodes.count; i++) {
                    double v = XFNodeNumber(nodes[i]);
                    if (isnan(v)) return [XFXPathValue number:NAN];
                    if (v < m) m = v;
                }
                return [XFXPathValue number:m];
            }),
            @"max": XF_FN(NO, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSArray *nodes = XFArg(args, 0).nodes;
                if (nodes.count == 0) return [XFXPathValue number:NAN];
                double m = XFNodeNumber(nodes[0]);
                for (NSUInteger i = 1; i < nodes.count; i++) {
                    double v = XFNodeNumber(nodes[i]);
                    if (isnan(v)) return [XFXPathValue number:NAN];
                    if (v > m) m = v;
                }
                return [XFXPathValue number:m];
            }),
            @"format-number": XF_FN(NO, XFXPathFnDefaultNodeSet, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue string:XFFormatNumber(XFArg(args, 0).numberValue, XFStr(args, 1))];
            }),

            // ---- XForms extras
            @"adjust-dateTime-to-timezone": XF_FN(NO, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                if (args.count == 0) return [XFXPathValue string:@""];
                return [XFXPathValue string:XFAdjustToLocal(XFStr(args, 0))];
            }),
            @"subform-instance": XF_FN(YES, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)err; (void)args;
                // the root of the first instance of the subform's first model;
                // the main form is its own subform (G-90). The subform is
                // the one holding the EVALUATING element (ctx.sourceElement,
                // XsltForms_exprContext's subform) — the inherited context
                // node usually belongs to the parent form
                XFSubform *sf = XFSubformOfContext(ctx);
                XFModel *model = sf ? [sf defaultModel] : nil;
                if (model == nil && [ctx.model.owner isKindOfClass:[XFProcessor class]]) {
                    model = [(XFProcessor *)ctx.model.owner model];
                }
                XFXMLElement *root = [[model defaultInstance] documentElement];
                if (root) [ctx addDependency:root];
                return [XFXPathValue nodeSet:root ? @[ root ] : @[]];
            }),
            @"subform-context": XF_FN(YES, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)err; (void)args;
                // the bound node of the control the subform was loaded into
                XFSubform *sf = XFSubformOfContext(ctx);
                id owner = ctx.model.owner;
                XFControl *control = (sf && [owner isKindOfClass:[XFProcessor class]])
                    ? [(XFProcessor *)owner controlForElement:sf.targetElement] : nil;
                XFXMLNode *node = control.boundNode;
                if (control) [ctx addDepElement:control];
                if (node) [ctx addDependency:node];
                return [XFXPathValue nodeSet:node ? @[ node ] : @[]];
            }),
            @"itext": XF_FN(YES, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                // itext(id): the translation of the model's xf:itext for the
                // current language (G-94)
                if (args.count != 1) {
                    if (err) *err = [NSError errorWithDomain:XFErrorDomain code:XFErrorXPathEvaluation
                                                    userInfo:@{ NSLocalizedDescriptionKey: @"itext() function must have one argument" }];
                    return nil;
                }
                XFModel *model = ctx.model;
                id owner = model.owner;
                NSString *language = [owner isKindOfClass:[XFProcessor class]] ? [(XFProcessor *)owner effectiveLanguage] : nil;
                if (model == nil && [owner isKindOfClass:[XFProcessor class]]) {
                    model = [(XFProcessor *)owner model];
                }
                if (model) [ctx addDepElement:model];
                return [XFXPathValue string:[model itextForIdentifier:XFStr(args, 0) language:language] ?: @""];
            }),
            @"nodeindex": XF_FN(YES, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)err;
                // bound node of the control with the given id (XSLTForms nodeindex())
                id owner = ctx.model.owner;
                if (![owner isKindOfClass:[XFProcessor class]]) {
                    return [XFXPathValue nodeSet:@[]];
                }
                XFProcessor *processor = owner;
                XFXMLElement *el = [XFXML elementWithID:XFStr(args, 0) inNode:processor.hostDocument.rootElement];
                XFControl *control = el ? [processor controlForElement:el] : nil;
                if (control) [ctx addDepElement:control];
                XFXMLNode *node = control.boundNode;
                if (node) {
                    [ctx addDependency:node];
                    if (ctx.model) [ctx addDepElement:ctx.model];
                }
                return [XFXPathValue nodeSet:node ? @[ node ] : @[]];
            }),
            @"fromtostep": XF_FN(NO, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                double from = XFArg(args, 0).numberValue, to = XFArg(args, 1).numberValue;
                double step = args.count > 2 ? XFArg(args, 2).numberValue : 1;
                NSMutableArray *values = [NSMutableArray array];
                if (!isnan(from) && !isnan(to) && !isnan(step) && step > 0) {
                    for (double i = from; i <= to && values.count < 100000; i += step) {
                        [values addObject:XFNumberToString(i)];
                    }
                }
                return XFSyntheticNodeSet(@"repeatitem", values);
            }),

            // ---- EXSLT math (http://exslt.org/math); looked up by local name
            @"abs": XF_MATH1(fabs),
            @"acos": XF_MATH1(acos),
            @"asin": XF_MATH1(asin),
            @"atan": XF_MATH1(atan),
            @"cos": XF_MATH1(cos),
            @"exp": XF_MATH1(exp),
            @"log": XF_MATH1(log),
            @"sin": XF_MATH1(sin),
            @"sqrt": XF_MATH1(sqrt),
            @"tan": XF_MATH1(tan),
            @"atan2": XF_FN(NO, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                return [XFXPathValue number:atan2(XFArg(args, 0).numberValue, XFArg(args, 1).numberValue)];
            }),
            @"constant": XF_FN(NO, XFXPathFnDefaultNone, ^XFXPathValue *(XFExprContext *ctx, NSArray *args, NSError **err) {
                (void)ctx; (void)err;
                NSString *name = XFStr(args, 0);
                NSDictionary *consts = @{ @"PI": @M_PI, @"E": @M_E, @"SQRRT2": @M_SQRT2, @"SQRT2": @M_SQRT2,
                                          @"SQRT1_2": @M_SQRT1_2, @"LN2": @M_LN2, @"LN10": @M_LN10,
                                          @"LOG2E": @M_LOG2E, @"LOG10E": @M_LOG10E };
                NSNumber *v = consts[name];
                return [XFXPathValue number:v ? [v doubleValue] : NAN];
            }),
        };
    });
    return table;
}
