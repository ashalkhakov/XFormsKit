/* XFAVT.m — attribute value templates (see the header for the design).
   Scanning rules follow XSLTForms' avtparser.xsl: `{{` → literal "{",
   `}}` → literal "}", `{expr}` → compiled XPath whose end brace is the
   first `}` outside a string literal, and a `{` with no closing `}`
   degrades to literal text.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFAVT.h"
#import "XFXPath.h"
#import "XFXPathValue.h"

@interface XFAVT ()
@property (nonatomic, copy, readwrite) NSString *sourceString;
/// NSString literals and XFXPath expressions, in order.
@property (nonatomic, copy) NSArray *pieces;
@end

@implementation XFAVT

/// Splits `value` into literal NSStrings and expression-source NSStrings
/// (tagged by wrapping in a single-key dictionary to avoid a piece
/// class). Returns nil when no complete expression was found.
static NSArray *XFAVTSegments(NSString *value)
{
    NSUInteger n = value.length;
    NSMutableArray *out = [NSMutableArray array];
    NSMutableString *literal = [NSMutableString string];
    BOOL sawExpression = NO;
    NSUInteger i = 0;
    while (i < n) {
        unichar c = [value characterAtIndex:i];
        if (c == '{' && i + 1 < n && [value characterAtIndex:i + 1] == '{') {
            [literal appendString:@"{"];
            i += 2;
            continue;
        }
        if (c == '}' && i + 1 < n && [value characterAtIndex:i + 1] == '}') {
            [literal appendString:@"}"];
            i += 2;
            continue;
        }
        if (c == '{') {
            // find the closing brace outside string literals
            NSUInteger j = i + 1;
            unichar quote = 0;
            NSUInteger end = NSNotFound;
            while (j < n) {
                unichar d = [value characterAtIndex:j];
                if (quote != 0) {
                    if (d == quote) {
                        quote = 0;
                    }
                } else if (d == '\'' || d == '"') {
                    quote = d;
                } else if (d == '}') {
                    end = j;
                    break;
                }
                j++;
            }
            if (end == NSNotFound) {
                // unmatched — the rest is literal, brace included
                [literal appendString:[value substringFromIndex:i]];
                i = n;
                break;
            }
            NSString *expr = [value substringWithRange:
                NSMakeRange(i + 1, end - i - 1)];
            if (expr.length) {
                if (literal.length) {
                    [out addObject:[literal copy]];
                    [literal setString:@""];
                }
                [out addObject:@{ @"expr": expr }];
                sawExpression = YES;
            }
            i = end + 1;
            continue;
        }
        [literal appendFormat:@"%C", c];
        i++;
    }
    if (literal.length) {
        [out addObject:[literal copy]];
    }
    return sawExpression ? out : nil;
}

+ (BOOL)stringIsTemplate:(NSString *)value
{
    if ([value rangeOfString:@"{"].location == NSNotFound) {
        return NO;
    }
    return XFAVTSegments(value) != nil;
}

+ (instancetype)avtWithString:(NSString *)value
                      element:(XFXMLElement *)element
                        error:(NSError **)error
{
    NSArray *segments = XFAVTSegments(value ?: @"");
    if (segments == nil) {
        return nil;
    }
    NSMutableArray *pieces = [NSMutableArray array];
    for (id segment in segments) {
        if ([segment isKindOfClass:[NSDictionary class]]) {
            NSError *inner = nil;
            XFXPath *xpath = [XFXPath xpathWithString:segment[@"expr"]
                                              element:element
                                                error:&inner];
            if (xpath == nil) {
                if (error) {
                    *error = inner;
                }
                return nil;
            }
            [pieces addObject:xpath];
        } else {
            [pieces addObject:segment];
        }
    }
    XFAVT *avt = [[XFAVT alloc] init];
    avt.sourceString = value;
    avt.pieces = pieces;
    return avt;
}

- (NSString *)evaluateInContext:(XFExprContext *)context error:(NSError **)error
{
    NSMutableString *out = [NSMutableString string];
    for (id piece in self.pieces) {
        if ([piece isKindOfClass:[XFXPath class]]) {
            NSError *inner = nil;
            NSString *value = [(XFXPath *)piece stringValueInContext:context
                                                               error:&inner];
            if (value == nil && inner != nil && error && *error == nil) {
                *error = inner;
            }
            [out appendString:value ?: @""];
        } else {
            [out appendString:piece];
        }
    }
    return out;
}

+ (NSString *)resolveString:(NSString *)value
                    element:(XFXMLElement *)element
                  inContext:(XFExprContext *)context
{
    if ([value rangeOfString:@"{"].location == NSNotFound) {
        return value;
    }
    XFAVT *avt = [self avtWithString:value element:element error:NULL];
    if (avt == nil) {
        return value;
    }
    return [avt evaluateInContext:context error:NULL];
}

@end
