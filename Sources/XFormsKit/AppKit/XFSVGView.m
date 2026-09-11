/* XFSVGView.m — SVG Tiny rendering over the host DOM (G-20 phase 3).
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

/// One elliptical-arc segment as cubics (SVG 1.1 F.6.5: endpoint to
/// center parameterization, then ≤90° slices with the 4/3·tan(δ/4)
/// control-point rule).
static void XFSVGAppendArc(NSBezierPath *path, NSPoint cur,
                           CGFloat rx, CGFloat ry, CGFloat rotDeg,
                           BOOL largeArc, BOOL sweep, NSPoint end)
{
    if (rx == 0 || ry == 0 || (cur.x == end.x && cur.y == end.y)) {
        [path lineToPoint:end];
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
    NSPoint (^pointAt)(CGFloat) = ^NSPoint(CGFloat theta) {
        CGFloat px = rx * cos(theta), py = ry * sin(theta);
        return NSMakePoint(cx + cosPhi * px - sinPhi * py,
                           cy + sinPhi * px + cosPhi * py);
    };
    NSPoint (^derivativeAt)(CGFloat) = ^NSPoint(CGFloat theta) {
        CGFloat px = -rx * sin(theta), py = ry * cos(theta);
        return NSMakePoint(cosPhi * px - sinPhi * py,
                           sinPhi * px + cosPhi * py);
    };
    CGFloat theta = theta1;
    for (NSInteger i = 0; i < segments; i++) {
        CGFloat next = theta + delta;
        NSPoint p0 = pointAt(theta), p1 = pointAt(next);
        NSPoint d0 = derivativeAt(theta), d1 = derivativeAt(next);
        [path curveToPoint:(i == segments - 1 ? end : p1)
             controlPoint1:NSMakePoint(p0.x + t * d0.x, p0.y + t * d0.y)
             controlPoint2:NSMakePoint(p1.x - t * d1.x, p1.y - t * d1.y)];
        theta = next;
    }
}

@implementation XFSVGDocument {
    XFSVGNode *_root;
    NSSize _size;
    NSMutableDictionary<NSString *, XFSVGNode *> *_ids;
}

+ (NSBezierPath *)bezierPathWithSVGPathData:(NSString *)d
{
    if (d.length == 0) {
        return nil;
    }
    XFSVGScan s = { [d UTF8String] };
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSPoint cur = NSZeroPoint, start = NSZeroPoint;
    NSPoint lastCubic = NSZeroPoint, lastQuad = NSZeroPoint;
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
                cur = rel ? NSMakePoint(cur.x + a, cur.y + b) : NSMakePoint(a, b);
                [path moveToPoint:cur];
                start = cur;
                break;
            }
            case 'L': {
                if (!XFSVGNumber(&s, &a) || !XFSVGNumber(&s, &b)) return path;
                cur = rel ? NSMakePoint(cur.x + a, cur.y + b) : NSMakePoint(a, b);
                [path lineToPoint:cur];
                break;
            }
            case 'H': {
                if (!XFSVGNumber(&s, &a)) return path;
                cur = NSMakePoint(rel ? cur.x + a : a, cur.y);
                [path lineToPoint:cur];
                break;
            }
            case 'V': {
                if (!XFSVGNumber(&s, &a)) return path;
                cur = NSMakePoint(cur.x, rel ? cur.y + a : a);
                [path lineToPoint:cur];
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
                [path curveToPoint:NSMakePoint(a, b)
                     controlPoint1:NSMakePoint(c1x, c1y)
                     controlPoint2:NSMakePoint(c2x, c2y)];
                lastCubic = NSMakePoint(c2x, c2y);
                cur = NSMakePoint(a, b);
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
                [path curveToPoint:NSMakePoint(a, b)
                     controlPoint1:NSMakePoint(c1x, c1y)
                     controlPoint2:NSMakePoint(c2x, c2y)];
                lastCubic = NSMakePoint(c2x, c2y);
                cur = NSMakePoint(a, b);
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
                [path curveToPoint:NSMakePoint(a, b)
                     controlPoint1:NSMakePoint(cur.x + 2.0 / 3.0 * (qx - cur.x),
                                               cur.y + 2.0 / 3.0 * (qy - cur.y))
                     controlPoint2:NSMakePoint(a + 2.0 / 3.0 * (qx - a),
                                               b + 2.0 / 3.0 * (qy - b))];
                lastQuad = NSMakePoint(qx, qy);
                cur = NSMakePoint(a, b);
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
                XFSVGAppendArc(path, cur, rx, ry, rot, large, sweep, NSMakePoint(a, b));
                cur = NSMakePoint(a, b);
                break;
            }
            case 'Z': {
                [path closePath];
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
static NSAffineTransformStruct XFSVGCompose(NSAffineTransformStruct op,
                                            NSAffineTransformStruct outer)
{
    NSAffineTransformStruct r;
    r.m11 = op.m11 * outer.m11 + op.m12 * outer.m21;
    r.m12 = op.m11 * outer.m12 + op.m12 * outer.m22;
    r.m21 = op.m21 * outer.m11 + op.m22 * outer.m21;
    r.m22 = op.m21 * outer.m12 + op.m22 * outer.m22;
    r.tX = op.tX * outer.m11 + op.tY * outer.m21 + outer.tX;
    r.tY = op.tX * outer.m12 + op.tY * outer.m22 + outer.tY;
    return r;
}

+ (NSAffineTransform *)transformWithSVGString:(NSString *)string
{
    NSAffineTransform *identity = [NSAffineTransform transform];
    if (string.length == 0) {
        return identity;
    }
    NSAffineTransformStruct total = [identity transformStruct];
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
        NSAffineTransformStruct op = { 1, 0, 0, 1, 0, 0 };
        name = [name lowercaseString];
        if ([name isEqualToString:@"translate"]) {
            op.tX = args[0];
            op.tY = count > 1 ? args[1] : 0;
        } else if ([name isEqualToString:@"scale"]) {
            op.m11 = args[0];
            op.m22 = count > 1 ? args[1] : args[0];
        } else if ([name isEqualToString:@"rotate"]) {
            CGFloat rad = args[0] * M_PI / 180.0;
            NSAffineTransformStruct rot = { cos(rad), sin(rad), -sin(rad), cos(rad), 0, 0 };
            if (count >= 3) {
                // rotate about (cx, cy): translate(-c) · rotate · translate(c)
                NSAffineTransformStruct toOrigin = { 1, 0, 0, 1, -args[1], -args[2] };
                NSAffineTransformStruct back = { 1, 0, 0, 1, args[1], args[2] };
                op = XFSVGCompose(toOrigin, XFSVGCompose(rot, back));
            } else {
                op = rot;
            }
        } else if ([name isEqualToString:@"matrix"] && count >= 6) {
            op.m11 = args[0]; op.m12 = args[1];
            op.m21 = args[2]; op.m22 = args[3];
            op.tX = args[4]; op.tY = args[5];
        } else if ([name isEqualToString:@"skewx"]) {
            op.m21 = tan(args[0] * M_PI / 180.0);
        } else if ([name isEqualToString:@"skewy"]) {
            op.m12 = tan(args[0] * M_PI / 180.0);
        }
        // list applies left to right with the RIGHTMOST hitting the point
        // first: fold each op inside the accumulated outer transform
        total = XFSVGCompose(op, total);
    }
    NSAffineTransform *result = [NSAffineTransform transform];
    [result setTransformStruct:total];
    return result;
}

#pragma mark - Colors, styles, lengths

+ (NSColor *)colorWithSVGString:(NSString *)string
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
        return [NSColor colorWithCalibratedWhite:0.87 alpha:1.0];
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
        return [NSColor colorWithCalibratedRed:((value >> 16) & 0xFF) / 255.0
                                         green:((value >> 8) & 0xFF) / 255.0
                                          blue:(value & 0xFF) / 255.0
                                         alpha:1.0];
    }
    if ([s hasPrefix:@"rgb("]) {
        XFSVGScan scan = { [s UTF8String] + 4 };
        CGFloat r = 0, g = 0, b = 0;
        if (XFSVGNumber(&scan, &r) && XFSVGNumber(&scan, &g) && XFSVGNumber(&scan, &b)) {
            BOOL percent = strchr([s UTF8String], '%') != NULL;
            CGFloat max = percent ? 100.0 : 255.0;
            return [NSColor colorWithCalibratedRed:MIN(r, max) / max
                                             green:MIN(g, max) / max
                                              blue:MIN(b, max) / max
                                             alpha:1.0];
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
    return [NSColor colorWithCalibratedRed:((value >> 16) & 0xFF) / 255.0
                                     green:((value >> 8) & 0xFF) / 255.0
                                      blue:(value & 0xFF) / 255.0
                                     alpha:1.0];
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
    doc->_size = NSMakeSize(MAX(width, 1), MAX(height, 1));
    return doc;
}

- (XFSVGNode *)root
{
    return _root;
}

- (NSSize)size
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
static NSBezierPath *XFSVGShapePath(XFSVGNode *node)
{
    NSString *tag = node.tag;
    if ([tag isEqualToString:@"path"]) {
        return [XFSVGDocument bezierPathWithSVGPathData:node.attributes[@"d"]];
    }
    if ([tag isEqualToString:@"rect"]) {
        NSRect r = NSMakeRect(XFSVGAttrLength(node, @"x", 0), XFSVGAttrLength(node, @"y", 0),
                              XFSVGAttrLength(node, @"width", 0), XFSVGAttrLength(node, @"height", 0));
        return (r.size.width > 0 && r.size.height > 0)
            ? [NSBezierPath bezierPathWithRect:r] : nil;
    }
    if ([tag isEqualToString:@"circle"]) {
        CGFloat r = XFSVGAttrLength(node, @"r", 0);
        return r > 0 ? [NSBezierPath bezierPathWithOvalInRect:
            NSMakeRect(XFSVGAttrLength(node, @"cx", 0) - r,
                       XFSVGAttrLength(node, @"cy", 0) - r, 2 * r, 2 * r)] : nil;
    }
    if ([tag isEqualToString:@"ellipse"]) {
        CGFloat rx = XFSVGAttrLength(node, @"rx", 0), ry = XFSVGAttrLength(node, @"ry", 0);
        return (rx > 0 && ry > 0) ? [NSBezierPath bezierPathWithOvalInRect:
            NSMakeRect(XFSVGAttrLength(node, @"cx", 0) - rx,
                       XFSVGAttrLength(node, @"cy", 0) - ry, 2 * rx, 2 * ry)] : nil;
    }
    if ([tag isEqualToString:@"line"]) {
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(XFSVGAttrLength(node, @"x1", 0), XFSVGAttrLength(node, @"y1", 0))];
        [path lineToPoint:NSMakePoint(XFSVGAttrLength(node, @"x2", 0), XFSVGAttrLength(node, @"y2", 0))];
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
        NSBezierPath *path = [NSBezierPath bezierPath];
        while (XFSVGNumber(&s, &x) && XFSVGNumber(&s, &y)) {
            if (first) {
                [path moveToPoint:NSMakePoint(x, y)];
                first = NO;
            } else {
                [path lineToPoint:NSMakePoint(x, y)];
            }
        }
        if ([tag isEqualToString:@"polygon"]) {
            [path closePath];
        }
        return first ? nil : path;
    }
    return nil;
}

/// YES for shapes whose fill never paints (open strokes by nature).
static BOOL XFSVGStrokeOnlyTag(NSString *tag)
{
    return [tag isEqualToString:@"line"];
}

/// Text metrics shared by drawing and hit testing: the drawn rectangle
/// (local coordinates, top-left origin in the flipped context) plus the
/// string attributes.
static NSRect XFSVGTextRect(XFSVGNode *node, NSDictionary *style,
                            NSDictionary **outAttrs)
{
    NSString *text = node.text;
    if (text.length == 0) {
        return NSZeroRect;
    }
    CGFloat size = [XFSVGDocument lengthWithSVGString:style[@"font-size"] fallback:16];
    NSString *weight = style[@"font-weight"];
    BOOL bold = [weight isEqualToString:@"bold"] || [weight isEqualToString:@"bolder"]
        || [weight doubleValue] >= 600;
    NSFont *font = bold ? [NSFont boldSystemFontOfSize:size]
                        : [NSFont systemFontOfSize:size];
    NSColor *color = [XFSVGDocument colorWithSVGString:style[@"fill"] ?: @"black"]
        ?: [NSColor blackColor];
    NSDictionary *attrs = @{ NSFontAttributeName: font,
                             NSForegroundColorAttributeName: color };
    if (outAttrs != NULL) {
        *outAttrs = attrs;
    }
    CGFloat x = XFSVGAttrLength(node, @"x", 0);
    CGFloat y = XFSVGAttrLength(node, @"y", 0);
    NSSize extent = [text sizeWithAttributes:attrs];
    NSString *anchor = style[@"text-anchor"];
    if ([anchor isEqualToString:@"middle"]) {
        x -= extent.width / 2;
    } else if ([anchor isEqualToString:@"end"]) {
        x -= extent.width;
    }
    // SVG's y is the BASELINE; the rect's top is a font-ascender above
    return NSMakeRect(x, y - [font ascender], extent.width, extent.height);
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
static NSGradient *XFSVGGradientFromNode(XFSVGNode *server, CGFloat alpha,
                                         NSColor **outFirst)
{
    NSMutableArray *colors = [NSMutableArray array];
    NSMutableArray *locations = [NSMutableArray array];
    CGFloat last = 0;
    for (XFSVGNode *stop in server.children) {
        if (![stop.tag isEqualToString:@"stop"]) {
            continue;
        }
        NSDictionary *decl = [XFSVGDocument declarationsWithSVGStyle:stop.attributes[@"style"]];
        NSString *colorSpec = decl[@"stop-color"] ?: stop.attributes[@"stop-color"] ?: @"black";
        NSString *opacity = decl[@"stop-opacity"] ?: stop.attributes[@"stop-opacity"];
        NSColor *color = [XFSVGDocument colorWithSVGString:colorSpec] ?: [NSColor blackColor];
        CGFloat a = alpha * (opacity.length ? MAX(0.0, MIN(1.0, [opacity doubleValue])) : 1.0);
        color = [color colorWithAlphaComponent:a];
        CGFloat offset = XFSVGCoordinate(stop.attributes[@"offset"], YES, 0);
        offset = MAX(MAX((CGFloat)0, MIN((CGFloat)1, offset)), last);   // ascending
        last = offset;
        [colors addObject:color];
        [locations addObject:@(offset)];
    }
    if (colors.count == 0) {
        return nil;
    }
    if (outFirst != NULL) {
        *outFirst = colors.firstObject;
    }
    if (colors.count == 1) {
        [colors addObject:colors.firstObject];
        [locations addObject:@(1.0)];
    }
    CGFloat locs[colors.count];
    for (NSUInteger i = 0; i < colors.count; i++) {
        locs[i] = [locations[i] doubleValue];
    }
    return [[NSGradient alloc] initWithColors:colors
                                  atLocations:locs
                                   colorSpace:[NSColorSpace genericRGBColorSpace]];
}

static void XFSVGDrawNode(XFSVGNode *node, NSDictionary *parentStyle,
                          XFSVGDocument *doc, NSInteger depth);

/// Fills `path` with the paint server `server` (gradient or pattern),
/// clipped to the path. Returns NO when the server cannot paint (the
/// caller falls back to a flat wash).
static BOOL XFSVGFillWithServer(NSBezierPath *path, XFSVGNode *server,
                                CGFloat alpha, XFSVGDocument *doc,
                                NSInteger depth)
{
    NSRect bounds = [path bounds];
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
        NSGradient *gradient = XFSVGGradientFromNode(server, alpha, NULL);
        if (gradient == nil) {
            return NO;
        }
        NSPoint from = NSMakePoint(resolveX(server.attributes[@"x1"], 0),
                                   resolveY(server.attributes[@"y1"], 0));
        NSPoint to = NSMakePoint(resolveX(server.attributes[@"x2"], 1),
                                 resolveY(server.attributes[@"y2"], 0));
        [NSGraphicsContext saveGraphicsState];
        [path addClip];
        NSString *gt = server.attributes[@"gradientTransform"]
            ?: server.attributes[@"gradienttransform"];
        if (gt.length) {
            [[XFSVGDocument transformWithSVGString:gt] concat];
        }
        [gradient drawFromPoint:from toPoint:to
                        options:NSGradientDrawsBeforeStartingLocation
                                | NSGradientDrawsAfterEndingLocation];
        [NSGraphicsContext restoreGraphicsState];
        return YES;
    }
    if ([tag isEqualToString:@"radialgradient"]) {
        NSGradient *gradient = XFSVGGradientFromNode(server, alpha, NULL);
        if (gradient == nil) {
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
        [NSGraphicsContext saveGraphicsState];
        [path addClip];
        NSString *gt = server.attributes[@"gradientTransform"]
            ?: server.attributes[@"gradienttransform"];
        if (gt.length) {
            [[XFSVGDocument transformWithSVGString:gt] concat];
        }
        [gradient drawFromCenter:NSMakePoint(fx, fy) radius:0
                        toCenter:NSMakePoint(cx, cy) radius:MAX(r, (CGFloat)0.01)
                         options:NSGradientDrawsBeforeStartingLocation
                                 | NSGradientDrawsAfterEndingLocation];
        [NSGraphicsContext restoreGraphicsState];
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
        NSInteger columns = (NSInteger)ceil((NSMaxX(bounds) - startX) / tileW);
        NSInteger rows = (NSInteger)ceil((NSMaxY(bounds) - startY) / tileH);
        if (columns < 1 || rows < 1 || columns * rows > kXFSVGMaxTiles) {
            return NO;
        }
        [NSGraphicsContext saveGraphicsState];
        [path addClip];
        for (NSInteger row = 0; row < rows; row++) {
            for (NSInteger column = 0; column < columns; column++) {
                [NSGraphicsContext saveGraphicsState];
                NSAffineTransform *shift = [NSAffineTransform transform];
                [shift translateXBy:startX + column * tileW
                                yBy:startY + row * tileH];
                [shift concat];
                for (XFSVGNode *child in server.children) {
                    XFSVGDrawNode(child, @{}, doc, depth + 1);
                }
                [NSGraphicsContext restoreGraphicsState];
            }
        }
        [NSGraphicsContext restoreGraphicsState];
        return YES;
    }
    return NO;
}

#pragma mark - Drawing

static void XFSVGPaintPath(NSBezierPath *path, NSDictionary *style,
                           BOOL strokeOnly, XFSVGDocument *doc, NSInteger depth)
{
    NSString *fillSpec = strokeOnly ? @"none" : (style[@"fill"] ?: @"black");
    NSString *serverID = XFSVGPaintServerID(fillSpec);
    CGFloat fillAlpha = XFSVGOpacity(style, @"fill-opacity");
    [path setWindingRule:[style[@"fill-rule"] isEqualToString:@"evenodd"]
        ? NSEvenOddWindingRule : NSNonZeroWindingRule];
    if (serverID != nil) {
        XFSVGNode *server = [doc nodeForIdentifier:serverID];
        if (server == nil || depth > kXFSVGMaxDepth
            || !XFSVGFillWithServer(path, server, fillAlpha, doc, depth)) {
            // unknown or unpaintable server: the neutral wash
            [[[NSColor colorWithCalibratedWhite:0.87 alpha:1.0]
                colorWithAlphaComponent:fillAlpha] setFill];
            [path fill];
        }
    } else {
        NSColor *fill = [XFSVGDocument colorWithSVGString:fillSpec];
        if (fill != nil) {
            [[fill colorWithAlphaComponent:fillAlpha] setFill];
            [path fill];
        }
    }

    NSString *strokeSpec = style[@"stroke"];
    NSString *strokeServerID = XFSVGPaintServerID(strokeSpec ?: @"");
    NSColor *stroke = nil;
    if (strokeServerID != nil) {
        // gradient / pattern strokes degrade to the first stop's color
        NSColor *first = nil;
        XFSVGNode *server = [doc nodeForIdentifier:strokeServerID];
        if (server != nil) {
            XFSVGGradientFromNode(server, 1.0, &first);
        }
        stroke = first ?: [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
    } else {
        stroke = [XFSVGDocument colorWithSVGString:strokeSpec];
    }
    if (stroke != nil) {
        [[stroke colorWithAlphaComponent:XFSVGOpacity(style, @"stroke-opacity")] setStroke];
        [path setLineWidth:[XFSVGDocument lengthWithSVGString:style[@"stroke-width"] fallback:1]];
        NSString *join = style[@"stroke-linejoin"];
        [path setLineJoinStyle:[join isEqualToString:@"round"] ? NSRoundLineJoinStyle
            : ([join isEqualToString:@"bevel"] ? NSBevelLineJoinStyle : NSMiterLineJoinStyle)];
        NSString *cap = style[@"stroke-linecap"];
        [path setLineCapStyle:[cap isEqualToString:@"round"] ? NSRoundLineCapStyle
            : ([cap isEqualToString:@"square"] ? NSSquareLineCapStyle : NSButtLineCapStyle)];
        [path stroke];
    }
}

static void XFSVGDrawNode(XFSVGNode *node, NSDictionary *parentStyle,
                          XFSVGDocument *doc, NSInteger depth)
{
    if (depth > kXFSVGMaxDepth) {
        return;
    }
    NSDictionary *style = XFSVGEffectiveStyle(node, parentStyle);
    NSString *transform = node.attributes[@"transform"];
    [NSGraphicsContext saveGraphicsState];
    if (transform.length) {
        [[XFSVGDocument transformWithSVGString:transform] concat];
    }
    NSString *tag = node.tag;
    if ([tag isEqualToString:@"use"]) {
        NSString *href = node.attributes[@"href"] ?: @"";
        XFSVGNode *target = [doc nodeForIdentifier:
            [href hasPrefix:@"#"] ? [href substringFromIndex:1] : href];
        if (target != nil) {
            NSAffineTransform *place = [NSAffineTransform transform];
            [place translateXBy:XFSVGAttrLength(node, @"x", 0)
                            yBy:XFSVGAttrLength(node, @"y", 0)];
            [place concat];
            if ([target.tag isEqualToString:@"symbol"]
                || [target.tag isEqualToString:@"svg"]) {
                for (XFSVGNode *child in target.children) {
                    XFSVGDrawNode(child, style, doc, depth + 1);
                }
            } else {
                XFSVGDrawNode(target, style, doc, depth + 1);
            }
        }
        [NSGraphicsContext restoreGraphicsState];
        return;
    }
    NSBezierPath *path = XFSVGShapePath(node);
    if (path != nil) {
        XFSVGPaintPath(path, style, XFSVGStrokeOnlyTag(tag), doc, depth);
    } else if ([tag isEqualToString:@"text"]) {
        NSDictionary *attrs = nil;
        NSRect rect = XFSVGTextRect(node, style, &attrs);
        if (!NSIsEmptyRect(rect)) {
            [node.text drawAtPoint:rect.origin withAttributes:attrs];
        }
    }
    for (XFSVGNode *child in node.children) {
        XFSVGDrawNode(child, style, doc, depth + 1);
    }
    [NSGraphicsContext restoreGraphicsState];
}

/// The viewport mapping drawInRect / hit tests use: rect placement,
/// viewport scale, then viewBox scale.
- (NSAffineTransform *)viewportTransformForRect:(NSRect)rect
{
    NSAffineTransform *viewport = [NSAffineTransform transform];
    [viewport translateXBy:rect.origin.x yBy:rect.origin.y];
    [viewport scaleXBy:rect.size.width / _size.width
                   yBy:rect.size.height / _size.height];
    NSString *viewBox = _root.attributes[@"viewBox"] ?: _root.attributes[@"viewbox"];
    if (viewBox.length) {
        XFSVGScan s = { [viewBox UTF8String] };
        CGFloat vx, vy, vw, vh;
        if (XFSVGNumber(&s, &vx) && XFSVGNumber(&s, &vy)
            && XFSVGNumber(&s, &vw) && XFSVGNumber(&s, &vh) && vw > 0 && vh > 0) {
            [viewport scaleXBy:_size.width / vw yBy:_size.height / vh];
            [viewport translateXBy:-vx yBy:-vy];
        }
    }
    return viewport;
}

- (void)drawInRect:(NSRect)rect
{
    XFSVGNode *root = _root;
    if (root == nil || NSIsEmptyRect(rect)) {
        return;
    }
    [NSGraphicsContext saveGraphicsState];
    [NSBezierPath clipRect:rect];
    [[self viewportTransformForRect:rect] concat];
    NSDictionary *rootStyle = XFSVGEffectiveStyle(root, @{});
    for (XFSVGNode *child in root.children) {
        XFSVGDrawNode(child, rootStyle, self, 0);
    }
    [NSGraphicsContext restoreGraphicsState];
}

#pragma mark - Hit testing

/// The walk mirrors XFSVGDrawNode, carrying the accumulated transform
/// (as a struct) instead of a CTM. `owner` is the reported node when the
/// content was reached through a <use>.
static void XFSVGHitNode(XFSVGNode *node, NSDictionary *parentStyle,
                         NSAffineTransformStruct outer, NSPoint point,
                         XFSVGDocument *doc, XFSVGNode *owner,
                         NSInteger depth, XFSVGNode *__strong *hit)
{
    if (depth > kXFSVGMaxDepth) {
        return;
    }
    NSDictionary *style = XFSVGEffectiveStyle(node, parentStyle);
    NSAffineTransformStruct total = outer;
    NSString *transform = node.attributes[@"transform"];
    if (transform.length) {
        total = XFSVGCompose(
            [[XFSVGDocument transformWithSVGString:transform] transformStruct], total);
    }
    NSString *tag = node.tag;
    if ([tag isEqualToString:@"use"]) {
        NSString *href = node.attributes[@"href"] ?: @"";
        XFSVGNode *target = [doc nodeForIdentifier:
            [href hasPrefix:@"#"] ? [href substringFromIndex:1] : href];
        if (target != nil) {
            NSAffineTransformStruct place = { 1, 0, 0, 1,
                XFSVGAttrLength(node, @"x", 0), XFSVGAttrLength(node, @"y", 0) };
            NSAffineTransformStruct inner = XFSVGCompose(place, total);
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
    CGFloat det = total.m11 * total.m22 - total.m12 * total.m21;
    if (fabs(det) > 1e-9) {
        NSAffineTransform *inverse = [NSAffineTransform transform];
        [inverse setTransformStruct:total];
        [inverse invert];
        NSPoint local = [inverse transformPoint:point];
        NSBezierPath *path = XFSVGShapePath(node);
        if (path != nil) {
            BOOL fillable = !XFSVGStrokeOnlyTag(tag)
                && ![style[@"fill"] isEqualToString:@"none"];
            BOOL inside = NO;
            if (fillable) {
                inside = [path containsPoint:local];
            }
            NSString *strokeSpec = style[@"stroke"];
            if (!inside && strokeSpec.length
                && ![strokeSpec isEqualToString:@"none"]) {
                CGFloat w = [XFSVGDocument lengthWithSVGString:style[@"stroke-width"]
                                                      fallback:1];
                inside = NSPointInRect(local,
                    NSInsetRect([path bounds], -(w / 2 + 2), -(w / 2 + 2)));
            }
            if (inside) {
                *hit = owner ?: node;   // later (topmost) hits overwrite
            }
        } else if ([tag isEqualToString:@"text"]) {
            NSRect rect = XFSVGTextRect(node, style, NULL);
            if (!NSIsEmptyRect(rect) && NSPointInRect(local, rect)) {
                *hit = owner ?: node;
            }
        }
    }
    for (XFSVGNode *child in node.children) {
        XFSVGHitNode(child, style, total, point, doc, owner, depth + 1, hit);
    }
}

- (XFSVGNode *)nodeAtPoint:(NSPoint)point
{
    if (_root == nil) {
        return nil;
    }
    NSAffineTransformStruct outer =
        [[self viewportTransformForRect:NSMakeRect(0, 0, _size.width, _size.height)]
            transformStruct];
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
                           NSAffineTransformStruct outer, XFXMLElement *target,
                           BOOL inside, XFSVGDocument *doc, NSInteger depth,
                           NSRect *unionRect)
{
    if (depth > kXFSVGMaxDepth) {
        return;
    }
    NSDictionary *style = XFSVGEffectiveStyle(node, parentStyle);
    NSAffineTransformStruct total = outer;
    NSString *transform = node.attributes[@"transform"];
    if (transform.length) {
        total = XFSVGCompose(
            [[XFSVGDocument transformWithSVGString:transform] transformStruct], total);
    }
    BOOL nowInside = inside || (target != nil && node.element == target);
    if (nowInside) {
        NSBezierPath *path = XFSVGShapePath(node);
        NSRect local = NSZeroRect;
        if (path != nil && ![path isEmpty]) {
            local = [path bounds];
        } else if ([node.tag isEqualToString:@"text"]) {
            local = XFSVGTextRect(node, style, NULL);
        }
        if (!NSIsEmptyRect(local)) {
            NSAffineTransform *t = [NSAffineTransform transform];
            [t setTransformStruct:total];
            // transform the rect through its corners (rotations tilt it)
            NSPoint corners[4] = {
                local.origin,
                NSMakePoint(NSMaxX(local), NSMinY(local)),
                NSMakePoint(NSMinX(local), NSMaxY(local)),
                NSMakePoint(NSMaxX(local), NSMaxY(local)),
            };
            NSRect mapped = NSZeroRect;
            for (int i = 0; i < 4; i++) {
                NSPoint p = [t transformPoint:corners[i]];
                NSRect dot = NSMakeRect(p.x, p.y, 0.01, 0.01);
                mapped = NSIsEmptyRect(mapped) ? dot : NSUnionRect(mapped, dot);
            }
            *unionRect = NSIsEmptyRect(*unionRect) ? mapped
                                                   : NSUnionRect(*unionRect, mapped);
        }
    }
    if ([node.tag isEqualToString:@"use"]) {
        NSString *href = node.attributes[@"href"] ?: @"";
        XFSVGNode *resolved = [doc nodeForIdentifier:
            [href hasPrefix:@"#"] ? [href substringFromIndex:1] : href];
        if (resolved != nil) {
            NSAffineTransformStruct place = { 1, 0, 0, 1,
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

- (NSRect)frameOfElement:(XFXMLElement *)element
{
    if (_root == nil || element == nil) {
        return NSZeroRect;
    }
    NSAffineTransformStruct outer =
        [[self viewportTransformForRect:NSMakeRect(0, 0, _size.width, _size.height)]
            transformStruct];
    NSRect result = NSZeroRect;
    NSDictionary *rootStyle = XFSVGEffectiveStyle(_root, @{});
    for (XFSVGNode *child in _root.children) {
        XFSVGFrameWalk(child, rootStyle, outer, element, NO, self, 0, &result);
    }
    return result;
}

@end

/* ---------------------------------------------------------------- */
#pragma mark - The widget

@implementation XFSVGView {
    XFHostNode *_hostNode;
    __weak XFProcessor *_processor;
    XFXMLNode *_contextNode;
    XFSVGDocument *_svgDocument;
}

- (instancetype)initWithHostNode:(XFHostNode *)hostNode
                       processor:(XFProcessor *)processor
                     contextNode:(XFXMLNode *)contextNode
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _hostNode = hostNode;
        _processor = processor;
        _contextNode = contextNode;
        [self rebuild];
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;   // SVG's y axis grows downward
}

- (XFSVGDocument *)svgDocument
{
    return _svgDocument;
}

- (void)rebuild
{
    XFProcessor *processor = _processor;
    if (processor == nil) {
        return;
    }
    _svgDocument = [XFSVGDocument documentWithHostNode:_hostNode
                                             processor:processor
                                           contextNode:_contextNode];
    [self setFrameSize:_svgDocument.size];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirty
{
    (void)dirty;
    [_svgDocument drawInRect:[self bounds]];
}

- (XFXMLElement *)hostElementAtPoint:(NSPoint)point
{
    // the view draws the document across its whole (flipped) bounds, so
    // view coordinates ARE document coordinates
    return [[_svgDocument nodeAtPoint:point] element];
}

- (NSRect)frameOfHostElement:(XFXMLElement *)element
{
    return [_svgDocument frameOfElement:element];
}

@end
