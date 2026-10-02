/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#import "XFDXPathTextStorage.h"
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFXPath.h>

/// Semantic colour, cross-SDK: try the named system colour (which keeps
/// contrast in dark themes where it exists), fall back to a fixed
/// calibrated one.
static NSColor *XFDSystemColor(NSString *selectorName, CGFloat r, CGFloat g, CGFloat b)
{
    SEL sel = NSSelectorFromString(selectorName);
    if ([NSColor respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSColor *color = [NSColor performSelector:sel];
#pragma clang diagnostic pop
        if (color != nil) {
            return color;
        }
    }
    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1];
}

NSColor *XFDXPathTokenColor(NSString *kind)
{
    if ([kind isEqualToString:@"string"]) {
        return XFDSystemColor(@"systemRedColor", 0.77, 0.10, 0.09);
    }
    if ([kind isEqualToString:@"number"]) {
        return XFDSystemColor(@"systemBlueColor", 0.11, 0.00, 0.81);
    }
    if ([kind isEqualToString:@"function"]) {
        return XFDSystemColor(@"systemPurpleColor", 0.42, 0.13, 0.66);
    }
    if ([kind isEqualToString:@"axis"]) {
        return XFDSystemColor(@"systemBrownColor", 0.42, 0.30, 0.16);
    }
    if ([kind isEqualToString:@"variable"]) {
        return XFDSystemColor(@"systemTealColor", 0.00, 0.46, 0.54);
    }
    if ([kind isEqualToString:@"operator"]) {
        return XFDSystemColor(@"systemOrangeColor", 0.64, 0.35, 0.00);
    }
    if ([kind isEqualToString:@"punct"]) {
        return [NSColor disabledControlTextColor];
    }
    return [NSColor controlTextColor];   // name
}

NSAttributedString *XFDXPathAttributedString(NSString *expression, NSFont *font)
{
    NSString *text = expression ?: @"";
    NSMutableDictionary *base = [NSMutableDictionary dictionary];
    if (font != nil) {
        base[NSFontAttributeName] = font;
    }
    base[NSForegroundColorAttributeName] = [NSColor controlTextColor];
    NSMutableAttributedString *out =
        [[NSMutableAttributedString alloc] initWithString:text attributes:base];
    for (NSDictionary *token in [XFXPath highlightTokensForString:text]) {
        NSRange range = [token[@"range"] rangeValue];
        if (NSMaxRange(range) <= text.length) {
            [out addAttribute:NSForegroundColorAttributeName
                        value:XFDXPathTokenColor(token[@"kind"])
                        range:range];
        }
    }
    return out;
}

@implementation XFDXPathTextStorage {
    // NSTextStorage is semi-abstract: a subclass supplies the storage and
    // the four primitives below, and inherits everything else.
    NSMutableAttributedString *_backing;
    BOOL _colouring;
}

+ (instancetype)installedInTextView:(NSTextView *)view
{
    NSLayoutManager *layout = [view layoutManager];
    if (layout == nil) {
        return nil;
    }
    XFDXPathTextStorage *storage = [[self alloc] init];
    [storage replaceCharactersInRange:NSMakeRange(0, 0)
                           withString:[[view textStorage] string] ?: @""];
    // -replaceTextStorage: moves every layout manager over, which is the
    // whole of what installing means; doing it by hand risks leaving the
    // view pointing at the storage it came with.
    [layout replaceTextStorage:storage];
    return [view textStorage] == storage ? storage : nil;
}

- (instancetype)init
{
    // super's designated initialiser, not -initWithAttributedString:, so
    // that _backing is the one place the text lives.
    if ((self = [super init])) {
        _backing = [[NSMutableAttributedString alloc] init];
        _baseAttributes = @{
            NSFontAttributeName:
                [NSFont systemFontOfSize:[NSFont smallSystemFontSize]],
            NSForegroundColorAttributeName: [NSColor controlTextColor],
        };
    }
    return self;
}

#pragma mark NSTextStorage primitives

- (NSString *)string
{
    return [_backing string];
}

- (NSDictionary<NSString *, id> *)attributesAtIndex:(NSUInteger)location
                                     effectiveRange:(NSRangePointer)range
{
    return [_backing attributesAtIndex:location effectiveRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str
{
    [_backing replaceCharactersInRange:range withString:str];
    [self edited:NSTextStorageEditedCharacters
               range:range
      changeInLength:(NSInteger)[str length] - (NSInteger)range.length];
}

- (void)setAttributes:(NSDictionary<NSString *, id> *)attrs range:(NSRange)range
{
    [_backing setAttributes:attrs range:range];
    [self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
}

#pragma mark Colouring

- (void)setInvalid:(BOOL)invalid
{
    if (_invalid == invalid) {
        return;
    }
    _invalid = invalid;
    [self recolour];
}

- (void)setBaseAttributes:(NSDictionary<NSString *, id> *)baseAttributes
{
    _baseAttributes = [baseAttributes copy];
    [self recolour];
}

/// The whole text, every time. An expression is a line or two long, and
/// recolouring only the edited range would be wrong anyway: typing a
/// quote or a bracket changes what the text after it is.
- (void)recolour
{
    if (_colouring || _backing.length == 0) {
        return;
    }
    _colouring = YES;
    NSRange all = NSMakeRange(0, _backing.length);
    NSMutableDictionary *base = [_baseAttributes mutableCopy] ?: [NSMutableDictionary dictionary];
    if (_invalid) {
        base[NSForegroundColorAttributeName] = [NSColor redColor];
    }
    [self setAttributes:base range:all];
    if (!_invalid) {
        for (NSDictionary *token in [XFXPath highlightTokensForString:[_backing string]]) {
            NSRange range = [token[@"range"] rangeValue];
            if (NSMaxRange(range) <= _backing.length) {
                [self addAttribute:NSForegroundColorAttributeName
                             value:XFDXPathTokenColor(token[@"kind"])
                             range:range];
            }
        }
    }
    _colouring = NO;
}

/// The mask is read before -[super processEditing], which clears it, and
/// the flag inside -recolour is there because setting attributes is
/// itself an edit: it comes back round through -edited: for a second
/// pass, which must not colour again.
- (void)processEditing
{
    NSUInteger mask = [self editedMask];
    [super processEditing];
    if ((mask & NSTextStorageEditedCharacters) == 0) {
        return;
    }
    [self recolour];
}

@end
