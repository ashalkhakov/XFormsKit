/* XFSVGDocument.m — SVG Tiny rendering over the host DOM (G-20 phase 3).
   See XFSVG.h for the supported subset. The render tree resolves AVTs
   (XFAVT) and repeat/group contexts at build time; elements with ids
   (defs content, paint servers) land in a registry that url(#…) and
   <use> resolve against. Drawing walks the tree with NSBezierPath /
   NSAffineTransform / NSGradient, the primitives GNUstep libs-gui
   implements Apple-compatibly; hit testing walks the same tree with the
   inverse transforms, so the designer's overlay can pick shapes. The
   path-data scanner and the arc-to-bezier conversion implement the SVG
   1.1 grammar and appendix F.6.5 (NanoSVG, zlib license, consulted as
   the reference implementation shape).
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import <CoreText/CoreText.h>
#import "XFSVG.h"
#import "XFAVT.h"
#import "XFHostNode.h"
#import "XFControl.h"
#import "XFGroup.h"
#import "XFRepeat.h"
#import "XFSwitch.h"
#import "XFProcessor.h"
#import "XFModel.h"
#import "XFInstance.h"
#import "XFExprContext.h"
#import <math.h>
#import <ctype.h>

void XFAppKitHasSVGFile(void) {}

/// use / pattern recursion guard.
static const NSInteger kXFSVGMaxDepth = 12;
/// Pattern tiling cap — a degenerate tile must not hang the draw.
static const NSInteger kXFSVGMaxTiles = 4096;

@implementation XFSVGNode
@end

/* ---------------------------------------------------------------- */
/// NSPointInRect takes the point first, CGRectContainsPoint the rect.
/// Keeping the old argument order in one helper means the hit-testing
/// code below reads exactly as it did before.
static inline BOOL XFSVGRectContainsPoint(CGPoint point, CGRect rect)
{
    return CGRectContainsPoint(rect, point);
}

#pragma mark - Scanning

typedef struct { const char *p; } XFSVGScan;

static BOOL XFSVGSkipSep(XFSVGScan *s)
{
    while (*s->p == ' ' || *s->p == '\t' || *s->p == '\n'
           || *s->p == '\r' || *s->p == ',') {
        s->p++;
    }
    return *s->p != 0;
}

static BOOL XFSVGNumber(XFSVGScan *s, CGFloat *out)
{
    XFSVGSkipSep(s);
    char *end = NULL;
    double v = strtod(s->p, &end);
    if (end == s->p) {
        return NO;
    }
    s->p = end;
    *out = (CGFloat)v;
    return YES;
}

/// Arc flags are single characters — "0140 20" is flag 0, flag 1, x 40:
/// a plain number scan would eat "0140" whole.
static BOOL XFSVGFlagNumber(XFSVGScan *s, BOOL *out)
{
    XFSVGSkipSep(s);
    if (*s->p == '0' || *s->p == '1') {
        *out = (*s->p == '1');
        s->p++;
        return YES;
    }
    return NO;
}

/* ---------------------------------------------------------------- */
#pragma mark - Path data

/* CGPath takes loose coordinates where NSBezierPath took points; these
   keep the path-building code below reading in points, as it did. */

static inline void XFSVGPathMove(CGMutablePathRef path, CGPoint p)
{
    CGPathMoveToPoint(path, NULL, p.x, p.y);
}

static inline void XFSVGPathAddLine(CGMutablePathRef path, CGPoint p)
{
    CGPathAddLineToPoint(path, NULL, p.x, p.y);
}

/// CGPathCreateWithEllipseInRect is missing from Opal, which GNUstep
/// draws through; CGPathAddEllipseInRect is there, so build it that way.
static CGPathRef XFSVGCreateEllipsePath(CGRect rect)
{
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddEllipseInRect(path, NULL, rect);
    return path;
}

static inline void XFSVGPathAddCurve(CGMutablePathRef path,
                                     CGPoint control1, CGPoint control2, CGPoint end)
{
    CGPathAddCurveToPoint(path, NULL, control1.x, control1.y,
                          control2.x, control2.y, end.x, end.y);
}


/// One elliptical-arc segment as cubics (SVG 1.1 F.6.5: endpoint to
/// center parameterization, then ≤90° slices with the 4/3·tan(δ/4)
/// control-point rule).
static void XFSVGAppendArc(CGMutablePathRef path, CGPoint cur,
                           CGFloat rx, CGFloat ry, CGFloat rotDeg,
                           BOOL largeArc, BOOL sweep, CGPoint end)
{
    if (rx == 0 || ry == 0 || (cur.x == end.x && cur.y == end.y)) {
        XFSVGPathAddLine(path, end);
        return;
    }
    rx = fabs(rx);
    ry = fabs(ry);
    CGFloat phi = rotDeg * M_PI / 180.0;
    CGFloat cosPhi = cos(phi), sinPhi = sin(phi);
    CGFloat dx2 = (cur.x - end.x) / 2.0, dy2 = (cur.y - end.y) / 2.0;
    CGFloat x1p = cosPhi * dx2 + sinPhi * dy2;
    CGFloat y1p = -sinPhi * dx2 + cosPhi * dy2;
    CGFloat lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if (lambda > 1) {
        CGFloat scale = sqrt(lambda);
        rx *= scale;
        ry *= scale;
    }
    CGFloat num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
    CGFloat den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
    CGFloat coef = den == 0 ? 0 : sqrt(MAX((CGFloat)0, num / den));
    if (largeArc == sweep) {
        coef = -coef;
    }
    CGFloat cxp = coef * rx * y1p / ry;
    CGFloat cyp = -coef * ry * x1p / rx;
    CGFloat cx = cosPhi * cxp - sinPhi * cyp + (cur.x + end.x) / 2.0;
    CGFloat cy = sinPhi * cxp + cosPhi * cyp + (cur.y + end.y) / 2.0;

    CGFloat ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry;
    CGFloat vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry;
    CGFloat (^angle)(CGFloat, CGFloat, CGFloat, CGFloat) =
        ^CGFloat(CGFloat ax, CGFloat ay, CGFloat bx, CGFloat by) {
        CGFloat dot = ax * bx + ay * by;
        CGFloat len = sqrt((ax * ax + ay * ay) * (bx * bx + by * by));
        CGFloat a = acos(MAX((CGFloat)-1, MIN((CGFloat)1, len == 0 ? 0 : dot / len)));
        return (ax * by - ay * bx) < 0 ? -a : a;
    };
    CGFloat theta1 = angle(1, 0, ux, uy);
    CGFloat dtheta = angle(ux, uy, vx, vy);
    if (!sweep && dtheta > 0) {
        dtheta -= 2 * M_PI;
    } else if (sweep && dtheta < 0) {
        dtheta += 2 * M_PI;
    }

    NSInteger segments = (NSInteger)ceil(fabs(dtheta) / (M_PI / 2.0));
    if (segments < 1) {
        segments = 1;
    }
    CGFloat delta = dtheta / segments;
    CGFloat t = 4.0 / 3.0 * tan(delta / 4.0);
    CGPoint (^pointAt)(CGFloat) = ^CGPoint(CGFloat theta) {
        CGFloat px = rx * cos(theta), py = ry * sin(theta);
        return CGPointMake(cx + cosPhi * px - sinPhi * py,
                           cy + sinPhi * px + cosPhi * py);
    };
    CGPoint (^derivativeAt)(CGFloat) = ^CGPoint(CGFloat theta) {
        CGFloat px = -rx * sin(theta), py = ry * cos(theta);
        return CGPointMake(cosPhi * px - sinPhi * py,
                           sinPhi * px + cosPhi * py);
    };
    CGFloat theta = theta1;
    for (NSInteger i = 0; i < segments; i++) {
        CGFloat next = theta + delta;
        CGPoint p0 = pointAt(theta), p1 = pointAt(next);
        CGPoint d0 = derivativeAt(theta), d1 = derivativeAt(next);
        XFSVGPathAddCurve(path, CGPointMake(p0.x + t * d0.x, p0.y + t * d0.y),
                       CGPointMake(p1.x - t * d1.x, p1.y - t * d1.y),
                       (i == segments - 1 ? end : p1));
        theta = next;
    }
}

@implementation XFSVGDocument {
    XFSVGNode *_root;
    CGSize _size;
    NSMutableDictionary<NSString *, XFSVGNode *> *_ids;
}

+ (CGPathRef)createPathWithSVGPathData:(NSString *)d
{
    if (d.length == 0) {
        return NULL;
    }
    XFSVGScan s = { [d UTF8String] };
    CGMutablePathRef path = CGPathCreateMutable();
    CGPoint cur = CGPointZero, start = CGPointZero;
    CGPoint lastCubic = CGPointZero, lastQuad = CGPointZero;
    char cmd = 0, prev = 0;
    while (XFSVGSkipSep(&s)) {
        char c = *s.p;
        if (isalpha((unsigned char)c)) {
            cmd = c;
            s.p++;
        } else if (cmd == 0 || toupper(cmd) == 'Z') {
            break;   // junk, or numbers after a close
        } else if (toupper(cmd) == 'M') {
            // extra coordinate pairs after moveto are implicit linetos
            cmd = (cmd == 'M') ? 'L' : 'l';
        }
        // islower returns a glibc bitmask (512) that a signed-char BOOL
        // truncates to 0 — compare, never assign
        BOOL rel = islower((unsigned char)cmd) != 0;
        CGFloat a = 0, b = 0, c1x = 0, c1y = 0, c2x = 0, c2y = 0;
        switch (toupper((unsigned char)cmd)) {
            case 'M': {
                if (!XFSVGNumber(&s, &a) || !XFSVGNumber(&s, &b)) return path;
                cur = rel ? CGPointMake(cur.x + a, cur.y + b) : CGPointMake(a, b);
                XFSVGPathMove(path, cur);
                start = cur;
                break;
            }
            case 'L': {
                if (!XFSVGNumber(&s, &a) || !XFSVGNumber(&s, &b)) return path;
                cur = rel ? CGPointMake(cur.x + a, cur.y + b) : CGPointMake(a, b);
                XFSVGPathAddLine(path, cur);
                break;
            }
            case 'H': {
                if (!XFSVGNumber(&s, &a)) return path;
                cur = CGPointMake(rel ? cur.x + a : a, cur.y);
                XFSVGPathAddLine(path, cur);
                break;
            }
            case 'V': {
                if (!XFSVGNumber(&s, &a)) return path;
                cur = CGPointMake(cur.x, rel ? cur.y + a : a);
                XFSVGPathAddLine(path, cur);
                break;
            }
            case 'C': {
                if (!XFSVGNumber(&s, &c1x) || !XFSVGNumber(&s, &c1y)
                    || !XFSVGNumber(&s, &c2x) || !XFSVGNumber(&s, &c2y)
                    || !XFSVGNumber(&s, &a) || !XFSVGNumber(&s, &b)) return path;
                if (rel) {
                    c1x += cur.x; c1y += cur.y; c2x += cur.x; c2y += cur.y;
                    a += cur.x; b += cur.y;
                }
                XFSVGPathAddCurve(path, CGPointMake(c1x, c1y),
                       CGPointMake(c2x, c2y),
                       CGPointMake(a, b));
                lastCubic = CGPointMake(c2x, c2y);
                cur = CGPointMake(a, b);
                break;
            }
            case 'S': {
                if (!XFSVGNumber(&s, &c2x) || !XFSVGNumber(&s, &c2y)
                    || !XFSVGNumber(&s, &a) || !XFSVGNumber(&s, &b)) return path;
                if (rel) {
                    c2x += cur.x; c2y += cur.y; a += cur.x; b += cur.y;
                }
                BOOL reflect = (toupper((unsigned char)prev) == 'C'
                                || toupper((unsigned char)prev) == 'S');
                c1x = reflect ? 2 * cur.x - lastCubic.x : cur.x;
                c1y = reflect ? 2 * cur.y - lastCubic.y : cur.y;
                XFSVGPathAddCurve(path, CGPointMake(c1x, c1y),
                       CGPointMake(c2x, c2y),
                       CGPointMake(a, b));
                lastCubic = CGPointMake(c2x, c2y);
                cur = CGPointMake(a, b);
                break;
            }
            case 'Q': case 'T': {
                CGFloat qx, qy;
                if (toupper((unsigned char)cmd) == 'Q') {
                    if (!XFSVGNumber(&s, &qx) || !XFSVGNumber(&s, &qy)
                        || !XFSVGNumber(&s, &a) || !XFSVGNumber(&s, &b)) return path;
                    if (rel) {
                        qx += cur.x; qy += cur.y; a += cur.x; b += cur.y;
                    }
                } else {
                    if (!XFSVGNumber(&s, &a) || !XFSVGNumber(&s, &b)) return path;
                    if (rel) {
                        a += cur.x; b += cur.y;
                    }
                    BOOL reflect = (toupper((unsigned char)prev) == 'Q'
                                    || toupper((unsigned char)prev) == 'T');
                    qx = reflect ? 2 * cur.x - lastQuad.x : cur.x;
                    qy = reflect ? 2 * cur.y - lastQuad.y : cur.y;
                }
                // quadratic as cubic: c = p + 2/3 (q − p)
                XFSVGPathAddCurve(path, CGPointMake(cur.x + 2.0 / 3.0 * (qx - cur.x),
                                               cur.y + 2.0 / 3.0 * (qy - cur.y)),
                       CGPointMake(a + 2.0 / 3.0 * (qx - a),
                                               b + 2.0 / 3.0 * (qy - b)),
                       CGPointMake(a, b));
                lastQuad = CGPointMake(qx, qy);
                cur = CGPointMake(a, b);
                break;
            }
            case 'A': {
                CGFloat rx, ry, rot;
                BOOL large = NO, sweep = NO;
                if (!XFSVGNumber(&s, &rx) || !XFSVGNumber(&s, &ry)
                    || !XFSVGNumber(&s, &rot)
                    || !XFSVGFlagNumber(&s, &large) || !XFSVGFlagNumber(&s, &sweep)
                    || !XFSVGNumber(&s, &a) || !XFSVGNumber(&s, &b)) return path;
                if (rel) {
                    a += cur.x; b += cur.y;
                }
                XFSVGAppendArc(path, cur, rx, ry, rot, large, sweep, CGPointMake(a, b));
                cur = CGPointMake(a, b);
                break;
            }
            case 'Z': {
                CGPathCloseSubpath(path);
                cur = start;
                break;
            }
            default:
                return path;   // unknown command: keep what parsed
        }
        prev = cmd;
    }
    return path;
}

#pragma mark - Transforms

/// Row-vector composition: apply `op` to the point first, then `outer`.
/// That is precisely CGAffineTransformConcat's contract, so the hand-rolled
/// matrix multiply this used to carry is gone.
static inline CGAffineTransform XFSVGCompose(CGAffineTransform op,
                                             CGAffineTransform outer)
{
    return CGAffineTransformConcat(op, outer);
}

+ (CGAffineTransform)transformWithSVGString:(NSString *)string
{
    if (string.length == 0) {
        return CGAffineTransformIdentity;
    }
    CGAffineTransform total = CGAffineTransformIdentity;
    NSScanner *scanner = [NSScanner scannerWithString:string];
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    NSMutableCharacterSet *seps = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
    [seps addCharactersInString:@",()"];
    [scanner setCharactersToBeSkipped:seps];
    while (![scanner isAtEnd]) {
        NSString *name = nil;
        if (![scanner scanCharactersFromSet:letters intoString:&name]) {
            break;
        }
        double args[6] = { 0 };
        NSInteger count = 0;
        while (count < 6 && [scanner scanDouble:&args[count]]) {
            count++;
        }
        CGAffineTransform op = { 1, 0, 0, 1, 0, 0 };
        name = [name lowercaseString];
        if ([name isEqualToString:@"translate"]) {
            op.tx = args[0];
            op.ty = count > 1 ? args[1] : 0;
        } else if ([name isEqualToString:@"scale"]) {
            op.a = args[0];
            op.d = count > 1 ? args[1] : args[0];
        } else if ([name isEqualToString:@"rotate"]) {
            CGFloat rad = args[0] * M_PI / 180.0;
            CGAffineTransform rot = { cos(rad), sin(rad), -sin(rad), cos(rad), 0, 0 };
            if (count >= 3) {
                // rotate about (cx, cy): translate(-c) · rotate · translate(c)
                CGAffineTransform toOrigin = { 1, 0, 0, 1, -args[1], -args[2] };
                CGAffineTransform back = { 1, 0, 0, 1, args[1], args[2] };
                op = XFSVGCompose(toOrigin, XFSVGCompose(rot, back));
            } else {
                op = rot;
            }
        } else if ([name isEqualToString:@"matrix"] && count >= 6) {
            op.a = args[0]; op.b = args[1];
            op.c = args[2]; op.d = args[3];
            op.tx = args[4]; op.ty = args[5];
        } else if ([name isEqualToString:@"skewx"]) {
            op.c = tan(args[0] * M_PI / 180.0);
        } else if ([name isEqualToString:@"skewy"]) {
            op.b = tan(args[0] * M_PI / 180.0);
        }
        // list applies left to right with the RIGHTMOST hitting the point
        // first: fold each op inside the accumulated outer transform
        total = XFSVGCompose(op, total);
    }
    return total;
}

#pragma mark - Colors, styles, lengths

/// One device RGB space for every colour the renderer makes. Created once:
/// CGColorSpaceCreateDeviceRGB is not free, and the drawing path builds
/// colours per shape.
static CGColorSpaceRef XFSVGColorSpace(void)
{
    static CGColorSpaceRef space;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ space = CGColorSpaceCreateDeviceRGB(); });
    return space;
}

/// Autoreleased, so call sites read like the NSColor ones they replaced.
static CGColorRef XFSVGColor(CGFloat r, CGFloat g, CGFloat b, CGFloat a)
{
    CGFloat components[4] = { r, g, b, a };
    return CGColorCreate(XFSVGColorSpace(), components);
}

static CGColorRef XFSVGColorWithAlpha(CGColorRef color, CGFloat alpha)
{
    if (color == NULL) {
        return NULL;
    }
    return CGColorCreateCopyWithAlpha(color, alpha);
}


+ (CGColorRef)createColorWithSVGString:(NSString *)string
{
    NSString *s = [[string stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (s.length == 0 || [s isEqualToString:@"none"] || [s isEqualToString:@"transparent"]) {
        return nil;
    }
    if ([s hasPrefix:@"url("]) {
        // resolved against the paint-server registry at draw time; as a
        // bare color (an unknown reference) a neutral wash keeps the
        // shape visible
        return XFSVGColor(0.87, 0.87, 0.87, 1.0);
    }
    if ([s hasPrefix:@"#"]) {
        NSString *hex = [s substringFromIndex:1];
        if (hex.length == 3) {
            hex = [NSString stringWithFormat:@"%C%C%C%C%C%C",
                [hex characterAtIndex:0], [hex characterAtIndex:0],
                [hex characterAtIndex:1], [hex characterAtIndex:1],
                [hex characterAtIndex:2], [hex characterAtIndex:2]];
        }
        if (hex.length != 6) {
            return nil;
        }
        unsigned value = 0;
        if (![[NSScanner scannerWithString:hex] scanHexInt:&value]) {
            return nil;
        }
        return XFSVGColor(((value >> 16) & 0xFF) / 255.0,
                          ((value >> 8) & 0xFF) / 255.0,
                          (value & 0xFF) / 255.0, 1.0);
    }
    if ([s hasPrefix:@"rgb("]) {
        XFSVGScan scan = { [s UTF8String] + 4 };
        CGFloat r = 0, g = 0, b = 0;
        if (XFSVGNumber(&scan, &r) && XFSVGNumber(&scan, &g) && XFSVGNumber(&scan, &b)) {
            BOOL percent = strchr([s UTF8String], '%') != NULL;
            CGFloat max = percent ? 100.0 : 255.0;
            return XFSVGColor(MIN(r, max) / max, MIN(g, max) / max,
                              MIN(b, max) / max, 1.0);
        }
        return nil;
    }
    static NSDictionary *named;
    if (named == nil) {
        named = @{ @"black": @0x000000, @"white": @0xFFFFFF, @"red": @0xFF0000,
                   @"green": @0x008000, @"blue": @0x0000FF, @"yellow": @0xFFFF00,
                   @"orange": @0xFFA500, @"purple": @0x800080, @"gray": @0x808080,
                   @"grey": @0x808080, @"silver": @0xC0C0C0, @"maroon": @0x800000,
                   @"navy": @0x000080, @"olive": @0x808000, @"teal": @0x008080,
                   @"lime": @0x00FF00, @"aqua": @0x00FFFF, @"fuchsia": @0xFF00FF,
                   @"cyan": @0x00FFFF, @"magenta": @0xFF00FF, @"brown": @0xA52A2A,
                   @"pink": @0xFFC0CB, @"gold": @0xFFD700, @"darkgray": @0xA9A9A9,
                   @"lightgray": @0xD3D3D3, @"darkgreen": @0x006400 };
    }
    NSNumber *hex = named[s];
    if (hex == nil) {
        return nil;
    }
    unsigned value = [hex unsignedIntValue];
    return XFSVGColor(((value >> 16) & 0xFF) / 255.0,
                      ((value >> 8) & 0xFF) / 255.0,
                      (value & 0xFF) / 255.0, 1.0);
}

+ (NSDictionary *)declarationsWithSVGStyle:(NSString *)css
{
    if (css.length == 0) {
        return @{};
    }
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSString *declaration in [css componentsSeparatedByString:@";"]) {
        NSRange colon = [declaration rangeOfString:@":"];
        if (colon.location == NSNotFound) {
            continue;
        }
        NSString *key = [[[declaration substringToIndex:colon.location]
            stringByTrimmingCharactersInSet:ws] lowercaseString];
        NSString *value = [[declaration substringFromIndex:NSMaxRange(colon)]
            stringByTrimmingCharactersInSet:ws];
        if (key.length && value.length) {
            out[key] = value;
        }
    }
    return out;
}

+ (CGFloat)lengthWithSVGString:(NSString *)string fallback:(CGFloat)fallback
{
    NSString *s = [string stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length == 0) {
        return fallback;
    }
    char *end = NULL;
    const char *c = [s UTF8String];
    double v = strtod(c, &end);
    if (end == c || !isfinite(v)) {
        // strtod parses "NaN" — an AVT over missing data must not
        // poison the layout
        return fallback;
    }
    // CSS absolute units at the SVG 96 dpi reference pixel
    if (strncmp(end, "mm", 2) == 0) return v * 96.0 / 25.4;
    if (strncmp(end, "cm", 2) == 0) return v * 96.0 / 2.54;
    if (strncmp(end, "in", 2) == 0) return v * 96.0;
    if (strncmp(end, "pt", 2) == 0) return v * 96.0 / 72.0;
    if (strncmp(end, "pc", 2) == 0) return v * 16.0;
    if (strncmp(end, "%", 1) == 0) return fallback;
    return v;   // px and unitless are user units
}

/// A gradient coordinate: "35%" → 0.35 when fractions are expected
/// (objectBoundingBox), else a plain user-space length.
static CGFloat XFSVGCoordinate(NSString *value, BOOL fractional, CGFloat fallback)
{
    if (value.length == 0) {
        return fallback;
    }
    if ([value hasSuffix:@"%"]) {
        return [value doubleValue] / 100.0;
    }
    CGFloat v = [XFSVGDocument lengthWithSVGString:value fallback:fallback];
    (void)fractional;
    return v;
}

#pragma mark - Render tree

static NSString *XFSVGCollapse(NSString *text)
{
    NSArray *parts = [text componentsSeparatedByCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length) {
            [kept addObject:part];
        }
    }
    return [kept componentsJoinedByString:@" "];
}

static BOOL XFSVGSkippedTag(NSString *tag)
{
    static NSSet *skipped;
    if (skipped == nil) {
        skipped = [NSSet setWithArray:@[ @"title", @"desc", @"metadata",
            @"clippath", @"mask", @"marker", @"style", @"script" ]];
    }
    return [skipped containsObject:tag];
}

/// Registered but never painted in place: url(#…) / use targets.
static BOOL XFSVGDefinitionTag(NSString *tag)
{
    static NSSet *defs;
    if (defs == nil) {
        defs = [NSSet setWithArray:@[ @"defs", @"symbol", @"pattern",
            @"lineargradient", @"radialgradient" ]];
    }
    return [defs containsObject:tag];
}

static XFSVGNode *XFSVGBuildElement(XFHostNode *hn, XFExprContext *ctx,
                                    NSMutableDictionary *ids);
static void XFSVGBuildChildren(NSArray<XFHostNode *> *hostChildren,
                               XFExprContext *ctx, NSMutableDictionary *ids,
                               NSMutableArray *out);

static XFSVGNode *XFSVGBuildElement(XFHostNode *hn, XFExprContext *ctx,
                                    NSMutableDictionary *ids)
{
    NSString *tag = hn.tag ?: @"";
    if (XFSVGSkippedTag(tag)) {
        return nil;
    }
    XFSVGNode *node = [[XFSVGNode alloc] init];
    node.tag = tag;
    node.element = hn.element;
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    for (XFXMLNode *attr in [hn.element attributes]) {
        NSString *name = [attr localName] ?: [attr name];
        if (name.length == 0 || [[attr name] hasPrefix:@"xmlns"]) {
            continue;
        }
        NSString *value = [attr stringValue] ?: @"";
        if ([value rangeOfString:@"{"].location != NSNotFound) {
            value = [XFAVT resolveString:value element:hn.element inContext:ctx];
        }
        attributes[name] = value;
    }
    node.attributes = attributes;
    NSString *identifier = attributes[@"id"];
    if (identifier.length && ids[identifier] == nil) {
        ids[identifier] = node;   // url(#…) / use target registry
    }
    if ([tag isEqualToString:@"text"] || [tag isEqualToString:@"tspan"]) {
        // gathered content: host text plus xf:output values, tspans
        // flattened (the Tiny slice draws one run per <text>)
        node.text = XFSVGCollapse([hn textContent] ?: @"");
        node.children = @[];
        return node;
    }
    NSMutableArray *children = [NSMutableArray array];
    XFSVGBuildChildren(hn.children, ctx, ids, children);
    node.children = children;
    if (XFSVGDefinitionTag(tag)) {
        return nil;   // built + registered (subtree ids included), not painted
    }
    return node;
}

static void XFSVGBuildChildren(NSArray<XFHostNode *> *hostChildren,
                               XFExprContext *ctx, NSMutableDictionary *ids,
                               NSMutableArray *out)
{
    for (XFHostNode *hn in hostChildren) {
        if (hn.kind == XFHostNodeKindControl) {
            XFControl *control = hn.control;
            if ([control isKindOfClass:[XFRepeat class]]) {
                XFRepeat *repeat = (XFRepeat *)control;
                for (XFRepeatItem *item in repeat.items) {
                    XFExprContext *itemCtx = [ctx cloneWithNode:item.node
                                                       position:item.position
                                                       nodeList:repeat.nodes];
                    XFSVGBuildChildren(item.hostNodes, itemCtx, ids, out);
                }
            } else if ([control isKindOfClass:[XFSwitch class]]) {
                XFCase *selected = [(XFSwitch *)control selectedCase];
                if (selected != nil) {
                    XFSVGBuildChildren([selected hostNodes], ctx, ids, out);
                }
            } else if ([control isKindOfClass:[XFGroup class]]) {
                if (!control.relevant) {
                    continue;
                }
                XFExprContext *childCtx = ctx;
                if (control.boundNode != nil) {
                    childCtx = [ctx cloneWithNode:control.boundNode
                                         position:1
                                         nodeList:@[ control.boundNode ]];
                }
                XFSVGBuildChildren([(XFGroup *)control hostNodes], childCtx, ids, out);
            }
            // other controls inside svg contribute nothing here — outputs
            // are gathered by their enclosing <text>'s textContent
            continue;
        }
        if (hn.element != nil) {
            XFSVGNode *node = XFSVGBuildElement(hn, ctx, ids);
            if (node != nil) {
                [out addObject:node];
            }
        }
    }
}

+ (instancetype)documentWithHostNode:(XFHostNode *)hostNode
                           processor:(XFProcessor *)processor
                         contextNode:(XFXMLNode *)contextNode
{
    XFSVGDocument *doc = [[XFSVGDocument alloc] init];
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:
        contextNode ?: [[processor defaultInstance] documentElement]];
    ctx.model = processor.model;
    doc->_ids = [NSMutableDictionary dictionary];
    doc->_root = XFSVGBuildElement(hostNode, ctx, doc->_ids);

    NSDictionary *attrs = doc->_root.attributes;
    CGFloat vb[4] = { 0, 0, 0, 0 };
    BOOL hasViewBox = NO;
    NSString *viewBox = attrs[@"viewBox"] ?: attrs[@"viewbox"];
    if (viewBox.length) {
        XFSVGScan s = { [viewBox UTF8String] };
        hasViewBox = XFSVGNumber(&s, &vb[0]) && XFSVGNumber(&s, &vb[1])
            && XFSVGNumber(&s, &vb[2]) && XFSVGNumber(&s, &vb[3]);
    }
    CGFloat width = [self lengthWithSVGString:attrs[@"width"]
                                     fallback:hasViewBox ? vb[2] : 300];
    CGFloat height = [self lengthWithSVGString:attrs[@"height"]
                                      fallback:hasViewBox ? vb[3] : 150];
    doc->_size = CGSizeMake(MAX(width, 1), MAX(height, 1));
    return doc;
}

- (XFSVGNode *)root
{
    return _root;
}

- (CGSize)size
{
    return _size;
}

- (XFSVGNode *)nodeForIdentifier:(NSString *)identifier
{
    return identifier.length ? _ids[identifier] : nil;
}

#pragma mark - Styles and shapes

static NSSet *XFSVGStyleKeys(void)
{
    static NSSet *keys;
    if (keys == nil) {
        keys = [NSSet setWithArray:@[ @"fill", @"stroke", @"stroke-width",
            @"stroke-linecap", @"stroke-linejoin", @"fill-rule", @"opacity",
            @"fill-opacity", @"stroke-opacity", @"font-size", @"font-weight",
            @"text-anchor" ]];
    }
    return keys;
}

/// Parent style + presentation attributes + style="" (style wins, CSS).
static NSDictionary *XFSVGEffectiveStyle(XFSVGNode *node, NSDictionary *parent)
{
    NSMutableDictionary *style = [parent mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *key in XFSVGStyleKeys()) {
        NSString *value = node.attributes[key];
        if (value.length && ![value isEqualToString:@"inherit"]) {
            style[key] = value;
        }
    }
    NSDictionary *declarations = [XFSVGDocument declarationsWithSVGStyle:node.attributes[@"style"]];
    for (NSString *key in declarations) {
        if ([XFSVGStyleKeys() containsObject:key]) {
            style[key] = declarations[key];
        }
    }
    return style;
}

static CGFloat XFSVGOpacity(NSDictionary *style, NSString *key)
{
    NSString *value = style[key];
    CGFloat alpha = value.length ? [value doubleValue] : 1.0;
    NSString *group = style[@"opacity"];
    if (group.length) {
        alpha *= [group doubleValue];
    }
    return MAX((CGFloat)0, MIN((CGFloat)1, alpha));
}

static CGFloat XFSVGAttrLength(XFSVGNode *node, NSString *name, CGFloat fallback)
{
    return [XFSVGDocument lengthWithSVGString:node.attributes[name] fallback:fallback];
}

/// The outline geometry of a shape element, nil for non-shapes. Shared
/// by drawing and hit testing.
static CGPathRef XFSVGCreateShapePath(XFSVGNode *node)
{
    NSString *tag = node.tag;
    if ([tag isEqualToString:@"path"]) {
        return [XFSVGDocument createPathWithSVGPathData:node.attributes[@"d"]];
    }
    if ([tag isEqualToString:@"rect"]) {
        CGRect r = CGRectMake(XFSVGAttrLength(node, @"x", 0), XFSVGAttrLength(node, @"y", 0),
                              XFSVGAttrLength(node, @"width", 0), XFSVGAttrLength(node, @"height", 0));
        return (r.size.width > 0 && r.size.height > 0)
            ? CGPathCreateWithRect(r, NULL) : NULL;
    }
    if ([tag isEqualToString:@"circle"]) {
        CGFloat r = XFSVGAttrLength(node, @"r", 0);
        return r > 0 ? XFSVGCreateEllipsePath(
            CGRectMake(XFSVGAttrLength(node, @"cx", 0) - r,
                       XFSVGAttrLength(node, @"cy", 0) - r, 2 * r, 2 * r)) : NULL;
    }
    if ([tag isEqualToString:@"ellipse"]) {
        CGFloat rx = XFSVGAttrLength(node, @"rx", 0), ry = XFSVGAttrLength(node, @"ry", 0);
        return (rx > 0 && ry > 0) ? XFSVGCreateEllipsePath(
            CGRectMake(XFSVGAttrLength(node, @"cx", 0) - rx,
                       XFSVGAttrLength(node, @"cy", 0) - ry, 2 * rx, 2 * ry)) : NULL;
    }
    if ([tag isEqualToString:@"line"]) {
        CGMutablePathRef path = CGPathCreateMutable();
        XFSVGPathMove(path, CGPointMake(XFSVGAttrLength(node, @"x1", 0), XFSVGAttrLength(node, @"y1", 0)));
        XFSVGPathAddLine(path, CGPointMake(XFSVGAttrLength(node, @"x2", 0), XFSVGAttrLength(node, @"y2", 0)));
        return path;
    }
    if ([tag isEqualToString:@"polyline"] || [tag isEqualToString:@"polygon"]) {
        NSString *points = node.attributes[@"points"];
        if (points.length == 0) {
            return nil;
        }
        XFSVGScan s = { [points UTF8String] };
        CGFloat x, y;
        BOOL first = YES;
        CGMutablePathRef path = CGPathCreateMutable();
        while (XFSVGNumber(&s, &x) && XFSVGNumber(&s, &y)) {
            if (first) {
                XFSVGPathMove(path, CGPointMake(x, y));
                first = NO;
            } else {
                XFSVGPathAddLine(path, CGPointMake(x, y));
            }
        }
        if ([tag isEqualToString:@"polygon"]) {
            CGPathCloseSubpath(path);
        }
        if (first) {
            CGPathRelease(path);
            return NULL;
        }
        return path;
    }
    return NULL;
}

/// YES for shapes whose fill never paints (open strokes by nature).
static BOOL XFSVGStrokeOnlyTag(NSString *tag)
{
    return [tag isEqualToString:@"line"];
}

/// Text metrics shared by drawing and hit testing: the drawn rectangle
/// (local coordinates, top-left origin in the flipped context) plus the
/// string attributes.
/// The size a <text> node asks for, in user-space units.
static CGFloat XFSVGFontSize(NSDictionary *style)
{
    return [XFSVGDocument lengthWithSVGString:style[@"font-size"] fallback:16];
}

static BOOL XFSVGFontIsBold(NSDictionary *style)
{
    NSString *weight = style[@"font-weight"];
    return [weight isEqualToString:@"bold"] || [weight isEqualToString:@"bolder"]
        || [weight doubleValue] >= 600;
}

/// The face a <text> node is drawn in, by name. Only GNUstep needs this:
/// there the face has to be named twice, once to measure and once to
/// paint, because the two halves come from different font systems.
static NSString *XFSVGFontFaceName(NSDictionary *style)
{
    return XFSVGFontIsBold(style) ? @"Helvetica-Bold" : @"Helvetica";
}

/// The font a <text> node asks for. Core Text rather than NSFont: it is
/// the one text API present on all three targets — Opal ships CoreText
/// for GNUstep — and it draws through a CGContext like everything else
/// here.
static CTFontRef XFSVGCreateFont(NSDictionary *style)
{
    CGFloat size = XFSVGFontSize(style);
#if defined(GNUSTEP)
    // Opal's CTFontCreateUIFontForLanguage ignores the UI font type
    // altogether and wraps the language in an array without checking it,
    // so asking for a UI font with no language raises. Name a face.
    CTFontRef font = CTFontCreateWithName(
        (__bridge CFStringRef)XFSVGFontFaceName(style), size, NULL);
#else
    CTFontRef font = CTFontCreateUIFontForLanguage(
        XFSVGFontIsBold(style) ? kCTFontUIFontEmphasizedSystem : kCTFontUIFontSystem,
        size, NULL);
#endif
    if (font == NULL) {
        // a bridged literal rather than CFSTR: the same string, with
        // one less CoreFoundation feature to be present on GNUstep
        font = CTFontCreateWithName((__bridge CFStringRef)@"Helvetica", size, NULL);
    }
    return font;
}

/// Glyphs and advances for `text` in `font`. Returns the count, and fills
/// the caller's buffers (sized for text.length).
static CFIndex XFSVGGlyphs(CTFontRef font, NSString *text,
                           CGGlyph *glyphs, CGSize *advances, CGFloat *outWidth)
{
    CFIndex count = (CFIndex)text.length;
    if (count == 0) {
        return 0;
    }
    unichar characters[count];
    [text getCharacters:characters range:NSMakeRange(0, (NSUInteger)count)];
    if (!CTFontGetGlyphsForCharacters(font, characters, glyphs, count)) {
        // a missing glyph leaves a 0 in place; the run still measures and
        // draws, just with a gap, which beats refusing to render
    }
    CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, glyphs, advances, count);
    CGFloat width = 0;
    for (CFIndex i = 0; i < count; i++) {
        width += advances[i].width;
    }
    if (outWidth != NULL) {
        *outWidth = width;
    }
    return count;
}

/// The box a <text> node paints, in SVG user space. `x`/`y` place the
/// BASELINE, so the box starts an ascender above it.
static CGRect XFSVGTextRect(XFSVGNode *node, NSDictionary *style, CGFloat *outBaselineX)
{
    NSString *text = node.text;
    if (text.length == 0) {
        return CGRectZero;
    }
    CTFontRef font = XFSVGCreateFont(style);
    if (font == NULL) {
        return CGRectZero;   // no font, no text: draw nothing rather than raise
    }
    CGGlyph glyphs[text.length];
    CGSize advances[text.length];
    CGFloat width = 0;
    XFSVGGlyphs(font, text, glyphs, advances, &width);
    CGFloat ascent = CTFontGetAscent(font);
    CGFloat descent = CTFontGetDescent(font);
    CFRelease(font);

    CGFloat x = XFSVGAttrLength(node, @"x", 0);
    CGFloat y = XFSVGAttrLength(node, @"y", 0);
    NSString *anchor = style[@"text-anchor"];
    if ([anchor isEqualToString:@"middle"]) {
        x -= width / 2;
    } else if ([anchor isEqualToString:@"end"]) {
        x -= width;
    }
    if (outBaselineX != NULL) {
        *outBaselineX = x;
    }
    return CGRectMake(x, y - ascent, width, ascent + descent);
}

/// Draws a <text> node. The context is y-down (SVG's own orientation, and
/// what a flipped NSView or a UIView gives), so the text matrix flips back
/// or every glyph would come out mirrored.
static void XFSVGDrawText(CGContextRef ctx, XFSVGNode *node, NSDictionary *style)
{
    NSString *text = node.text;
    if (text.length == 0) {
        return;
    }
    CGFloat baselineX = 0;
    CGRect rect = XFSVGTextRect(node, style, &baselineX);
    if (CGRectIsEmpty(rect)) {
        return;
    }
    CTFontRef font = XFSVGCreateFont(style);
    if (font == NULL) {
        return;
    }
    CGGlyph glyphs[text.length];
    CGSize advances[text.length];
    CFIndex count = XFSVGGlyphs(font, text, glyphs, advances, NULL);

    CGColorRef color = [XFSVGDocument createColorWithSVGString:style[@"fill"] ?: @"black"];
    if (color == NULL) {
        color = XFSVGColor(0, 0, 0, 1);
    }
    CGContextSaveGState(ctx);
    CGContextSetFillColorWithColor(ctx, color);
    CGColorRelease(color);

    CGFloat baselineY = XFSVGAttrLength(node, @"y", 0);
    CGPoint positions[count > 0 ? count : 1];
    CGFloat pen = baselineX;
    for (CFIndex i = 0; i < count; i++) {
        // The y is NEGATED because the text matrix below is applied to
        // these positions as well as to the glyph outlines: without it a
        // baseline at y=110 is drawn at y=-110, off the top of the
        // viewport. Text inside a translate() then lands mirrored about
        // that origin instead of vanishing, which is why this looked
        // half-right — a label at the top of a group appeared at the
        // bottom of it.
        positions[i] = CGPointMake(pen, -baselineY);
        pen += advances[i].width;
    }
    // SVG's y axis grows downward and a glyph's does not, so the run is
    // flipped back; -baselineY above keeps the placement upright.
    CGContextSetTextMatrix(ctx, CGAffineTransformMakeScale(1, -1));
#if defined(GNUSTEP)
    // Opal's CTFontDrawGlyphs is an empty stub; the CoreGraphics glyph
    // call is the one that paints there, and it wants the face as a
    // CGFont rather than the CTFont measured with above. Both come from
    // the same family name, so the glyph ids agree.
    CGFontRef faceToPaintWith =
        CGFontCreateWithFontName((__bridge CFStringRef)XFSVGFontFaceName(style));
    if (faceToPaintWith != NULL) {
        CGContextSetFont(ctx, faceToPaintWith);
        CGContextSetFontSize(ctx, XFSVGFontSize(style));
        CGFontRelease(faceToPaintWith);
        CGContextShowGlyphsAtPositions(ctx, glyphs, positions, (size_t)count);
    }
#else
    CTFontDrawGlyphs(font, glyphs, positions, (size_t)count, ctx);
#endif
    CGContextRestoreGState(ctx);
    CFRelease(font);
}

#pragma mark - Paint servers

/// "url(#id)" → id, else nil.
static NSString *XFSVGPaintServerID(NSString *paint)
{
    NSString *s = [paint stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![s hasPrefix:@"url("]) {
        return nil;
    }
    NSRange close = [s rangeOfString:@")"];
    if (close.location == NSNotFound) {
        return nil;
    }
    NSString *ref = [[s substringWithRange:NSMakeRange(4, close.location - 4)]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    ref = [ref stringByTrimmingCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@"'\""]];
    return [ref hasPrefix:@"#"] ? [ref substringFromIndex:1] : nil;
}

/// The gradient's stops as colors + locations. Returns nil without at
/// least one stop.
/// The stops as a CGGradient, plus (optionally) the first stop's colour,
/// which is what a gradient *stroke* degrades to.
static CGGradientRef XFSVGGradientFromNode(XFSVGNode *server, CGFloat alpha,
                                           CGColorRef *outFirst)
{
    // RGBA components rather than an array of CGColors: the array form
    // wants a CFArrayRef, and CoreFoundation is optional where GNUstep
    // draws through Opal.
    NSMutableArray<NSNumber *> *components = [NSMutableArray array];
    NSMutableArray<NSNumber *> *locations = [NSMutableArray array];
    CGFloat last = 0;
    if (outFirst != NULL) {
        *outFirst = NULL;
    }
    for (XFSVGNode *stop in server.children) {
        if (![stop.tag isEqualToString:@"stop"]) {
            continue;
        }
        NSDictionary *decl = [XFSVGDocument declarationsWithSVGStyle:stop.attributes[@"style"]];
        NSString *colorSpec = decl[@"stop-color"] ?: stop.attributes[@"stop-color"] ?: @"black";
        NSString *opacity = decl[@"stop-opacity"] ?: stop.attributes[@"stop-opacity"];
        CGColorRef base = [XFSVGDocument createColorWithSVGString:colorSpec];
        if (base == NULL) {
            base = XFSVGColor(0, 0, 0, 1);
        }
        CGFloat a = alpha * (opacity.length ? MAX(0.0, MIN(1.0, [opacity doubleValue])) : 1.0);
        CGColorRef color = XFSVGColorWithAlpha(base, a);
        CGColorRelease(base);
        CGFloat offset = XFSVGCoordinate(stop.attributes[@"offset"], YES, 0);
        offset = MAX(MAX((CGFloat)0, MIN((CGFloat)1, offset)), last);   // ascending
        last = offset;

        const CGFloat *rgba = CGColorGetComponents(color);
        size_t count = CGColorGetNumberOfComponents(color);
        [components addObject:@(count > 0 ? rgba[0] : 0)];
        [components addObject:@(count > 1 ? rgba[1] : 0)];
        [components addObject:@(count > 2 ? rgba[2] : 0)];
        [components addObject:@(CGColorGetAlpha(color))];
        [locations addObject:@(offset)];
        // a gradient STROKE degrades to the first stop's colour
        if (outFirst != NULL && *outFirst == NULL) {
            *outFirst = CGColorRetain(color);
        }
        CGColorRelease(color);
    }
    if (locations.count == 0) {
        return NULL;
    }
    if (locations.count == 1) {
        for (NSUInteger i = 0; i < 4; i++) {
            [components addObject:components[i]];
        }
        [locations addObject:@(1.0)];
    }
    CGFloat comps[components.count];
    for (NSUInteger i = 0; i < components.count; i++) {
        comps[i] = [components[i] doubleValue];
    }
    CGFloat locs[locations.count];
    for (NSUInteger i = 0; i < locations.count; i++) {
        locs[i] = [locations[i] doubleValue];
    }
    return CGGradientCreateWithColorComponents(XFSVGColorSpace(), comps, locs,
                                               locations.count);
}

static void XFSVGDrawNode(CGContextRef ctx, XFSVGNode *node,
                          NSDictionary *parentStyle,
                          XFSVGDocument *doc, NSInteger depth);

/// Fills `path` with the paint server `server` (gradient or pattern),
/// clipped to the path. Returns NO when the server cannot paint (the
/// caller falls back to a flat wash).
static BOOL XFSVGFillWithServer(CGContextRef ctx, CGPathRef path,
                                XFSVGNode *server, CGFloat alpha,
                                XFSVGDocument *doc, NSInteger depth)
{
    CGRect bounds = CGPathGetBoundingBox(path);
    NSString *tag = server.tag;
    BOOL objectUnits = YES;   // objectBoundingBox is the SVG default
    NSString *units = server.attributes[@"gradientUnits"]
        ?: server.attributes[@"gradientunits"]
        ?: server.attributes[@"patternUnits"]
        ?: server.attributes[@"patternunits"];
    if ([units isEqualToString:@"userSpaceOnUse"]) {
        objectUnits = NO;
    }
    CGFloat (^resolveX)(NSString *, CGFloat) = ^CGFloat(NSString *value, CGFloat fallback) {
        CGFloat v = XFSVGCoordinate(value, objectUnits, fallback);
        return objectUnits ? bounds.origin.x + v * bounds.size.width : v;
    };
    CGFloat (^resolveY)(NSString *, CGFloat) = ^CGFloat(NSString *value, CGFloat fallback) {
        CGFloat v = XFSVGCoordinate(value, objectUnits, fallback);
        return objectUnits ? bounds.origin.y + v * bounds.size.height : v;
    };

    if ([tag isEqualToString:@"lineargradient"]) {
        CGGradientRef gradient = XFSVGGradientFromNode(server, alpha, NULL);
        if (gradient == NULL) {
            return NO;
        }
        CGPoint from = CGPointMake(resolveX(server.attributes[@"x1"], 0),
                                   resolveY(server.attributes[@"y1"], 0));
        CGPoint to = CGPointMake(resolveX(server.attributes[@"x2"], 1),
                                 resolveY(server.attributes[@"y2"], 0));
        CGContextSaveGState(ctx);
        CGContextAddPath(ctx, path);
        CGContextClip(ctx);
        NSString *gt = server.attributes[@"gradientTransform"]
            ?: server.attributes[@"gradienttransform"];
        if (gt.length) {
            CGContextConcatCTM(ctx, [XFSVGDocument transformWithSVGString:gt]);
        }
        CGContextDrawLinearGradient(ctx, gradient, from, to,
                                    kCGGradientDrawsBeforeStartLocation
                                    | kCGGradientDrawsAfterEndLocation);
        CGContextRestoreGState(ctx);
        CGGradientRelease(gradient);
        return YES;
    }
    if ([tag isEqualToString:@"radialgradient"]) {
        CGGradientRef gradient = XFSVGGradientFromNode(server, alpha, NULL);
        if (gradient == NULL) {
            return NO;
        }
        CGFloat cx = resolveX(server.attributes[@"cx"], 0.5);
        CGFloat cy = resolveY(server.attributes[@"cy"], 0.5);
        CGFloat r = XFSVGCoordinate(server.attributes[@"r"], objectUnits, 0.5);
        if (objectUnits) {
            r *= MAX(bounds.size.width, bounds.size.height);
        }
        CGFloat fx = server.attributes[@"fx"].length
            ? resolveX(server.attributes[@"fx"], 0.5) : cx;
        CGFloat fy = server.attributes[@"fy"].length
            ? resolveY(server.attributes[@"fy"], 0.5) : cy;
        CGContextSaveGState(ctx);
        CGContextAddPath(ctx, path);
        CGContextClip(ctx);
        NSString *gt = server.attributes[@"gradientTransform"]
            ?: server.attributes[@"gradienttransform"];
        if (gt.length) {
            CGContextConcatCTM(ctx, [XFSVGDocument transformWithSVGString:gt]);
        }
        CGContextDrawRadialGradient(ctx, gradient, CGPointMake(fx, fy), 0,
                                    CGPointMake(cx, cy), MAX(r, (CGFloat)0.01),
                                    kCGGradientDrawsBeforeStartLocation
                                    | kCGGradientDrawsAfterEndLocation);
        CGContextRestoreGState(ctx);
        CGGradientRelease(gradient);
        return YES;
    }
    if ([tag isEqualToString:@"pattern"]) {
        CGFloat tileW = XFSVGCoordinate(server.attributes[@"width"], objectUnits, 0);
        CGFloat tileH = XFSVGCoordinate(server.attributes[@"height"], objectUnits, 0);
        CGFloat tileX = XFSVGCoordinate(server.attributes[@"x"], objectUnits, 0);
        CGFloat tileY = XFSVGCoordinate(server.attributes[@"y"], objectUnits, 0);
        if (objectUnits) {
            tileW *= bounds.size.width;
            tileH *= bounds.size.height;
            tileX = bounds.origin.x + tileX * bounds.size.width;
            tileY = bounds.origin.y + tileY * bounds.size.height;
        }
        if (!(tileW > 0.01) || !(tileH > 0.01) || server.children.count == 0) {
            return NO;
        }
        // anchor the tile grid so it covers the path bounds
        CGFloat startX = tileX + floor((bounds.origin.x - tileX) / tileW) * tileW;
        CGFloat startY = tileY + floor((bounds.origin.y - tileY) / tileH) * tileH;
        NSInteger columns = (NSInteger)ceil((CGRectGetMaxX(bounds) - startX) / tileW);
        NSInteger rows = (NSInteger)ceil((CGRectGetMaxY(bounds) - startY) / tileH);
        if (columns < 1 || rows < 1 || columns * rows > kXFSVGMaxTiles) {
            return NO;
        }
        CGContextSaveGState(ctx);
        CGContextAddPath(ctx, path);
        CGContextClip(ctx);
        for (NSInteger row = 0; row < rows; row++) {
            for (NSInteger column = 0; column < columns; column++) {
                CGContextSaveGState(ctx);
                CGContextConcatCTM(ctx, CGAffineTransformMakeTranslation(
                    startX + column * tileW, startY + row * tileH));
                for (XFSVGNode *child in server.children) {
                    XFSVGDrawNode(ctx, child, @{}, doc, depth + 1);
                }
                CGContextRestoreGState(ctx);
            }
        }
        CGContextRestoreGState(ctx);
        return YES;
    }
    return NO;
}

#pragma mark - Drawing

static void XFSVGPaintPath(CGContextRef ctx, CGPathRef path, NSDictionary *style,
                           BOOL strokeOnly, XFSVGDocument *doc, NSInteger depth)
{
    NSString *fillSpec = strokeOnly ? @"none" : (style[@"fill"] ?: @"black");
    NSString *serverID = XFSVGPaintServerID(fillSpec);
    CGFloat fillAlpha = XFSVGOpacity(style, @"fill-opacity");
    BOOL evenOdd = [style[@"fill-rule"] isEqualToString:@"evenodd"];
    if (serverID != nil) {
        XFSVGNode *server = [doc nodeForIdentifier:serverID];
        if (server == nil || depth > kXFSVGMaxDepth
            || !XFSVGFillWithServer(ctx, path, server, fillAlpha, doc, depth)) {
            // unknown or unpaintable server: the neutral wash
            CGColorRef wash = XFSVGColor(0.87, 0.87, 0.87, fillAlpha);
            CGContextSetFillColorWithColor(ctx, wash);
            CGColorRelease(wash);
            CGContextAddPath(ctx, path);
            CGContextDrawPath(ctx, evenOdd ? kCGPathEOFill : kCGPathFill);
        }
    } else {
        CGColorRef fill = [XFSVGDocument createColorWithSVGString:fillSpec];
        if (fill != NULL) {
            CGColorRef withAlpha = XFSVGColorWithAlpha(fill, fillAlpha);
            CGContextSetFillColorWithColor(ctx, withAlpha);
            CGColorRelease(withAlpha);
            CGColorRelease(fill);
            CGContextAddPath(ctx, path);
            CGContextDrawPath(ctx, evenOdd ? kCGPathEOFill : kCGPathFill);
        }
    }

    NSString *strokeSpec = style[@"stroke"];
    NSString *strokeServerID = XFSVGPaintServerID(strokeSpec ?: @"");
    CGColorRef stroke = NULL;
    if (strokeServerID != nil) {
        // gradient / pattern strokes degrade to the first stop's color
        CGColorRef first = NULL;
        XFSVGNode *server = [doc nodeForIdentifier:strokeServerID];
        if (server != nil) {
            XFSVGGradientFromNode(server, 1.0, &first);
        }
        stroke = first ?: XFSVGColor(0.6, 0.6, 0.6, 1.0);   // owned either way
    } else {
        stroke = [XFSVGDocument createColorWithSVGString:strokeSpec];
    }
    if (stroke != NULL) {
        CGColorRef withAlpha = XFSVGColorWithAlpha(stroke,
            XFSVGOpacity(style, @"stroke-opacity"));
        CGContextSetStrokeColorWithColor(ctx, withAlpha);
        CGColorRelease(withAlpha);
        CGContextSetLineWidth(ctx,
            [XFSVGDocument lengthWithSVGString:style[@"stroke-width"] fallback:1]);
        NSString *join = style[@"stroke-linejoin"];
        CGContextSetLineJoin(ctx, [join isEqualToString:@"round"] ? kCGLineJoinRound
            : ([join isEqualToString:@"bevel"] ? kCGLineJoinBevel : kCGLineJoinMiter));
        NSString *cap = style[@"stroke-linecap"];
        CGContextSetLineCap(ctx, [cap isEqualToString:@"round"] ? kCGLineCapRound
            : ([cap isEqualToString:@"square"] ? kCGLineCapSquare : kCGLineCapButt));
        CGContextAddPath(ctx, path);
        CGContextStrokePath(ctx);
    }
    CGColorRelease(stroke);
}

static void XFSVGDrawNode(CGContextRef ctx, XFSVGNode *node,
                          NSDictionary *parentStyle,
                          XFSVGDocument *doc, NSInteger depth)
{
    if (depth > kXFSVGMaxDepth) {
        return;
    }
    NSDictionary *style = XFSVGEffectiveStyle(node, parentStyle);
    NSString *transform = node.attributes[@"transform"];
    CGContextSaveGState(ctx);
    if (transform.length) {
        CGContextConcatCTM(ctx, [XFSVGDocument transformWithSVGString:transform]);
    }
    NSString *tag = node.tag;
    if ([tag isEqualToString:@"use"]) {
        NSString *href = node.attributes[@"href"] ?: @"";
        XFSVGNode *target = [doc nodeForIdentifier:
            [href hasPrefix:@"#"] ? [href substringFromIndex:1] : href];
        if (target != nil) {
            CGContextConcatCTM(ctx, CGAffineTransformMakeTranslation(
                XFSVGAttrLength(node, @"x", 0), XFSVGAttrLength(node, @"y", 0)));
            if ([target.tag isEqualToString:@"symbol"]
                || [target.tag isEqualToString:@"svg"]) {
                for (XFSVGNode *child in target.children) {
                    XFSVGDrawNode(ctx, child, style, doc, depth + 1);
                }
            } else {
                XFSVGDrawNode(ctx, target, style, doc, depth + 1);
            }
        }
        CGContextRestoreGState(ctx);
        return;
    }
    CGPathRef path = XFSVGCreateShapePath(node);
    if (path != NULL) {
        XFSVGPaintPath(ctx, path, style, XFSVGStrokeOnlyTag(tag), doc, depth);
        CGPathRelease(path);
    } else if ([tag isEqualToString:@"text"]) {
        XFSVGDrawText(ctx, node, style);
    }
    for (XFSVGNode *child in node.children) {
        XFSVGDrawNode(ctx, child, style, doc, depth + 1);
    }
    CGContextRestoreGState(ctx);
}

/// The viewport mapping drawing and hit tests use: rect placement,
/// viewport scale, then viewBox scale.
- (CGAffineTransform)viewportTransformForRect:(CGRect)rect
{
    // The user units the content is drawn in: the viewBox where there is
    // one, the declared width/height otherwise.
    CGFloat vx = 0, vy = 0, vw = _size.width, vh = _size.height;
    NSString *viewBox = _root.attributes[@"viewBox"] ?: _root.attributes[@"viewbox"];
    if (viewBox.length) {
        XFSVGScan scan = { [viewBox UTF8String] };
        CGFloat bx, by, bw, bh;
        if (XFSVGNumber(&scan, &bx) && XFSVGNumber(&scan, &by)
            && XFSVGNumber(&scan, &bw) && XFSVGNumber(&scan, &bh) && bw > 0 && bh > 0) {
            vx = bx; vy = by; vw = bw; vh = bh;
        }
    }
    if (vw <= 0 || vh <= 0) {
        return CGAffineTransformIdentity;
    }
    CGFloat sx = rect.size.width / vw;
    CGFloat sy = rect.size.height / vh;
    CGFloat tx = rect.origin.x;
    CGFloat ty = rect.origin.y;

    // preserveAspectRatio. The DEFAULT is "xMidYMid meet" — uniform scale,
    // centred — and only an explicit "none" stretches the drawing to fill
    // the rect. Scaling the axes independently (which is what this did
    // before) shows up wherever the host cannot give the view the
    // document's own proportions: on AppKit the view frame IS the document
    // size, so it never appeared there, while the iOS form, whose rows are
    // as wide as the table, drew every chart squashed.
    NSString *par = XFSVGCollapse(_root.attributes[@"preserveAspectRatio"] ?: @"");
    if (![par isEqualToString:@"none"]) {
        NSArray<NSString *> *words = [par componentsSeparatedByString:@" "];
        NSString *align = words.firstObject.length ? words.firstObject : @"xMidYMid";
        BOOL slice = [words containsObject:@"slice"];
        CGFloat scale = slice ? MAX(sx, sy) : MIN(sx, sy);
        CGFloat slack = rect.size.width - vw * scale;
        if ([align hasPrefix:@"xMid"]) {
            tx += slack / 2;
        } else if ([align hasPrefix:@"xMax"]) {
            tx += slack;
        }
        slack = rect.size.height - vh * scale;
        if ([align rangeOfString:@"YMid"].location != NSNotFound) {
            ty += slack / 2;
        } else if ([align rangeOfString:@"YMax"].location != NSNotFound) {
            ty += slack;
        }
        sx = sy = scale;
    }
    CGAffineTransform viewport = CGAffineTransformMakeTranslation(tx, ty);
    viewport = CGAffineTransformScale(viewport, sx, sy);
    viewport = CGAffineTransformTranslate(viewport, -vx, -vy);
    return viewport;
}

- (void)drawInContext:(CGContextRef)ctx rect:(CGRect)rect
{
    XFSVGNode *root = _root;
    if (root == nil || ctx == NULL || CGRectIsEmpty(rect)) {
        return;
    }
    CGContextSaveGState(ctx);
    CGContextClipToRect(ctx, rect);
    CGContextConcatCTM(ctx, [self viewportTransformForRect:rect]);
    NSDictionary *rootStyle = XFSVGEffectiveStyle(root, @{});
    for (XFSVGNode *child in root.children) {
        XFSVGDrawNode(ctx, child, rootStyle, self, 0);
    }
    CGContextRestoreGState(ctx);
}

#pragma mark - Hit testing

/// The walk mirrors XFSVGDrawNode, carrying the accumulated transform
/// (as a struct) instead of a CTM. `owner` is the reported node when the
/// content was reached through a <use>.
static void XFSVGHitNode(XFSVGNode *node, NSDictionary *parentStyle,
                         CGAffineTransform outer, CGPoint point,
                         XFSVGDocument *doc, XFSVGNode *owner,
                         NSInteger depth, XFSVGNode *__strong *hit)
{
    if (depth > kXFSVGMaxDepth) {
        return;
    }
    NSDictionary *style = XFSVGEffectiveStyle(node, parentStyle);
    CGAffineTransform total = outer;
    NSString *transform = node.attributes[@"transform"];
    if (transform.length) {
        total = XFSVGCompose([XFSVGDocument transformWithSVGString:transform], total);
    }
    NSString *tag = node.tag;
    if ([tag isEqualToString:@"use"]) {
        NSString *href = node.attributes[@"href"] ?: @"";
        XFSVGNode *target = [doc nodeForIdentifier:
            [href hasPrefix:@"#"] ? [href substringFromIndex:1] : href];
        if (target != nil) {
            CGAffineTransform place = { 1, 0, 0, 1,
                XFSVGAttrLength(node, @"x", 0), XFSVGAttrLength(node, @"y", 0) };
            CGAffineTransform inner = XFSVGCompose(place, total);
            XFSVGNode *reported = owner ?: node;
            if ([target.tag isEqualToString:@"symbol"]
                || [target.tag isEqualToString:@"svg"]) {
                for (XFSVGNode *child in target.children) {
                    XFSVGHitNode(child, style, inner, point, doc, reported, depth + 1, hit);
                }
            } else {
                XFSVGHitNode(target, style, inner, point, doc, reported, depth + 1, hit);
            }
        }
        return;
    }
    // the local point: invert the accumulated transform (skip a
    // degenerate one — nothing it draws is hittable)
    CGFloat det = total.a * total.d - total.b * total.c;
    if (fabs(det) > 1e-9) {
        CGPoint local = CGPointApplyAffineTransform(point, CGAffineTransformInvert(total));
        CGPathRef path = XFSVGCreateShapePath(node);
        if (path != NULL) {
            BOOL fillable = !XFSVGStrokeOnlyTag(tag)
                && ![style[@"fill"] isEqualToString:@"none"];
            BOOL inside = NO;
            if (fillable) {
                inside = CGPathContainsPoint(path, NULL, local,
                    [style[@"fill-rule"] isEqualToString:@"evenodd"]);
            }
            NSString *strokeSpec = style[@"stroke"];
            if (!inside && strokeSpec.length
                && ![strokeSpec isEqualToString:@"none"]) {
                CGFloat w = [XFSVGDocument lengthWithSVGString:style[@"stroke-width"]
                                                      fallback:1];
                inside = XFSVGRectContainsPoint(local,
                    CGRectInset(CGPathGetBoundingBox(path), -(w / 2 + 2), -(w / 2 + 2)));
            }
            CGPathRelease(path);
            if (inside) {
                *hit = owner ?: node;   // later (topmost) hits overwrite
            }
        } else if ([tag isEqualToString:@"text"]) {
            CGRect rect = XFSVGTextRect(node, style, NULL);
            if (!CGRectIsEmpty(rect) && XFSVGRectContainsPoint(local, rect)) {
                *hit = owner ?: node;
            }
        }
    }
    for (XFSVGNode *child in node.children) {
        XFSVGHitNode(child, style, total, point, doc, owner, depth + 1, hit);
    }
}

- (XFSVGNode *)nodeAtPoint:(CGPoint)point
{
    if (_root == nil) {
        return nil;
    }
    CGAffineTransform outer =
        [self viewportTransformForRect:CGRectMake(0, 0, _size.width, _size.height)];
    NSDictionary *rootStyle = XFSVGEffectiveStyle(_root, @{});
    XFSVGNode *hit = nil;
    for (XFSVGNode *child in _root.children) {
        XFSVGHitNode(child, rootStyle, outer, point, self, nil, 0, &hit);
    }
    return hit;
}

/// Union of the painted rectangles of nodes whose host element is
/// `target` — subtrees rooted at a matching node contribute whole.
static void XFSVGFrameWalk(XFSVGNode *node, NSDictionary *parentStyle,
                           CGAffineTransform outer, XFXMLElement *target,
                           BOOL inside, XFSVGDocument *doc, NSInteger depth,
                           CGRect *unionRect)
{
    if (depth > kXFSVGMaxDepth) {
        return;
    }
    NSDictionary *style = XFSVGEffectiveStyle(node, parentStyle);
    CGAffineTransform total = outer;
    NSString *transform = node.attributes[@"transform"];
    if (transform.length) {
        total = XFSVGCompose([XFSVGDocument transformWithSVGString:transform], total);
    }
    BOOL nowInside = inside || (target != nil && node.element == target);
    if (nowInside) {
        CGPathRef path = XFSVGCreateShapePath(node);
        CGRect local = CGRectZero;
        if (path != NULL && !CGPathIsEmpty(path)) {
            local = CGPathGetBoundingBox(path);
        } else if ([node.tag isEqualToString:@"text"]) {
            local = XFSVGTextRect(node, style, NULL);
        }
        CGPathRelease(path);
        if (!CGRectIsEmpty(local)) {
            // transform the rect through its corners (rotations tilt it)
            CGPoint corners[4] = {
                local.origin,
                CGPointMake(CGRectGetMaxX(local), CGRectGetMinY(local)),
                CGPointMake(CGRectGetMinX(local), CGRectGetMaxY(local)),
                CGPointMake(CGRectGetMaxX(local), CGRectGetMaxY(local)),
            };
            CGRect mapped = CGRectZero;
            for (int i = 0; i < 4; i++) {
                CGPoint p = CGPointApplyAffineTransform(corners[i], total);
                CGRect dot = CGRectMake(p.x, p.y, 0.01, 0.01);
                mapped = CGRectIsEmpty(mapped) ? dot : CGRectUnion(mapped, dot);
            }
            *unionRect = CGRectIsEmpty(*unionRect) ? mapped
                                                   : CGRectUnion(*unionRect, mapped);
        }
    }
    if ([node.tag isEqualToString:@"use"]) {
        NSString *href = node.attributes[@"href"] ?: @"";
        XFSVGNode *resolved = [doc nodeForIdentifier:
            [href hasPrefix:@"#"] ? [href substringFromIndex:1] : href];
        if (resolved != nil) {
            CGAffineTransform place = { 1, 0, 0, 1,
                XFSVGAttrLength(node, @"x", 0), XFSVGAttrLength(node, @"y", 0) };
            XFSVGFrameWalk(resolved, style, XFSVGCompose(place, total), target,
                           nowInside, doc, depth + 1, unionRect);
        }
        return;
    }
    for (XFSVGNode *child in node.children) {
        XFSVGFrameWalk(child, style, total, target, nowInside, doc, depth + 1, unionRect);
    }
}

- (CGRect)frameOfElement:(XFXMLElement *)element
{
    if (_root == nil || element == nil) {
        return CGRectZero;
    }
    CGAffineTransform outer =
        [self viewportTransformForRect:CGRectMake(0, 0, _size.width, _size.height)];
    CGRect result = CGRectZero;
    NSDictionary *rootStyle = XFSVGEffectiveStyle(_root, @{});
    for (XFSVGNode *child in _root.children) {
        XFSVGFrameWalk(child, rootStyle, outer, element, NO, self, 0, &result);
    }
    return result;
}

@end

/* ---------------------------------------------------------------- */
