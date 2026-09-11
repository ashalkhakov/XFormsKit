/* XFRichTextPresentation.m — turning XFRichText's markers into something
   AppKit shows. The converter itself is platform-independent and lives in
   Sources/XFormsKit/RichText/XFRichText.m; only this half knows about
   fonts and underline styles, whose attribute names come from AppKit here
   and from UIKit on iOS.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#import "XFAppKitPriv.h"

void XFAppKitHasRichTextFile(void) {}

@implementation XFRichText (XFRichTextPresentation)

+ (NSFont *)baseFontOrDefault:(NSFont *)baseFont
{
    return baseFont ?: [NSFont systemFontOfSize:13];
}

+ (NSFont *)fontForBlock:(NSString *)blockKind
                    bold:(BOOL)bold
                  italic:(BOOL)italic
                baseFont:(NSFont *)baseFont
{
    NSFont *font = [self baseFontOrDefault:baseFont];
    CGFloat size = [font pointSize];
    BOOL heading = NO;
    if ([blockKind isEqualToString:@"h1"]) {
        size = round(size * 1.6);
        heading = YES;
    } else if ([blockKind isEqualToString:@"h2"]) {
        size = round(size * 1.35);
        heading = YES;
    } else if ([blockKind isEqualToString:@"h3"]) {
        size = round(size * 1.15);
        heading = YES;
    }
    NSFontManager *fm = [NSFontManager sharedFontManager];
    font = [fm convertFont:font toSize:size] ?: font;
    if (bold || heading) {
        font = [fm convertFont:font toHaveTrait:NSBoldFontMask] ?: font;
    }
    if (italic) {
        font = [fm convertFont:font toHaveTrait:NSItalicFontMask] ?: font;
    }
    return font;
}

#pragma mark - HTML → attributed string


#pragma mark - Presentation (AppKit)

/// What the markers should LOOK like: the font for the block and its
/// bold/italic traits, plus underline and strikethrough. Separate from the
/// converter because these attribute names come from AppKit on macOS and
/// UIKit on iOS, and the converter may name neither.
+ (NSDictionary *)presentationForMarkers:(NSDictionary *)attrs baseFont:(NSFont *)baseFont
{
    NSMutableDictionary *presentation = [NSMutableDictionary dictionary];
    NSFont *font = [self fontForBlock:attrs[XFRichBlockAttributeName]
                                 bold:[attrs[XFRichBoldAttributeName] boolValue]
                               italic:[attrs[XFRichItalicAttributeName] boolValue]
                             baseFont:baseFont];
    if (font != nil) {
        presentation[NSFontAttributeName] = font;
    }
    if ([attrs[XFRichUnderlineAttributeName] boolValue]) {
        presentation[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
    }
    if ([attrs[XFRichStrikeAttributeName] boolValue]) {
        presentation[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
    }
    return presentation;
}

/// `attrs` with its presentation recomputed from its markers. The old
/// presentation is dropped first, so a marker that was just turned OFF
/// stops showing.
+ (NSMutableDictionary *)attributesWithPresentation:(NSDictionary *)attrs
                                           baseFont:(NSFont *)baseFont
{
    NSMutableDictionary *out = [attrs mutableCopy];
    [out removeObjectForKey:NSFontAttributeName];
    [out removeObjectForKey:NSUnderlineStyleAttributeName];
    [out removeObjectForKey:NSStrikethroughStyleAttributeName];
    [out addEntriesFromDictionary:[self presentationForMarkers:attrs baseFont:baseFont]];
    return out;
}

/// The converter's output made displayable. Runs are walked by hand:
/// GNUstep's NSAttributedString has no enumerateAttributesInRange:.
+ (NSAttributedString *)decoratedString:(NSAttributedString *)text baseFont:(NSFont *)baseFont
{
    if (text.length == 0) {
        return text;
    }
    NSMutableAttributedString *out = [text mutableCopy];
    [out beginEditing];
    NSUInteger i = 0;
    while (i < out.length) {
        NSRange range;
        NSDictionary *attrs = [out attributesAtIndex:i effectiveRange:&range];
        [out setAttributes:[self attributesWithPresentation:attrs baseFont:baseFont] range:range];
        i = NSMaxRange(range);
    }
    [out endEditing];
    return out;
}

@end
