/* XFRichTextUIKit.m — XFRichText's markers turned into something UIKit
   shows. The AppKit twin is Sources/XFormsKit/AppKit/XFRichTextPresentation.m;
   the converter both decorate is shared and platform-independent.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#import <XFormsKit/XFRichText.h>

#if __has_include(<UIKit/UIKit.h>)

@implementation XFRichText (XFRichTextUIKitPresentation)

+ (UIFont *)uiFontForBlock:(NSString *)blockKind
                      bold:(BOOL)bold
                    italic:(BOOL)italic
                  baseFont:(UIFont *)baseFont
{
    UIFont *font = baseFont ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    if ([blockKind isEqualToString:@"h1"]) {
        font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
    } else if ([blockKind isEqualToString:@"h2"]) {
        font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    } else if ([blockKind isEqualToString:@"h3"]) {
        font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
    }
    UIFontDescriptorSymbolicTraits traits = font.fontDescriptor.symbolicTraits;
    if (bold) {
        traits |= UIFontDescriptorTraitBold;
    }
    if (italic) {
        traits |= UIFontDescriptorTraitItalic;
    }
    if (traits == font.fontDescriptor.symbolicTraits) {
        return font;
    }
    UIFontDescriptor *descriptor =
        [font.fontDescriptor fontDescriptorWithSymbolicTraits:traits];
    // a face without the trait answers nil rather than a substitute
    return descriptor ? [UIFont fontWithDescriptor:descriptor size:0] : font;
}

+ (NSAttributedString *)decoratedString:(NSAttributedString *)text
                               baseFont:(UIFont *)baseFont
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
        NSMutableDictionary *applied = [attrs mutableCopy];
        applied[NSFontAttributeName] =
            [self uiFontForBlock:attrs[XFRichBlockAttributeName]
                            bold:[attrs[XFRichBoldAttributeName] boolValue]
                          italic:[attrs[XFRichItalicAttributeName] boolValue]
                        baseFont:baseFont];
        if ([attrs[XFRichUnderlineAttributeName] boolValue]) {
            applied[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
        }
        if ([attrs[XFRichStrikeAttributeName] boolValue]) {
            applied[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
        }
        [out setAttributes:applied range:range];
        i = NSMaxRange(range);
    }
    [out endEditing];
    return out;
}

+ (NSAttributedString *)attributedStringFromMarkup:(NSString *)markup
                                         plainText:(NSString *)plain
                                          baseFont:(UIFont *)baseFont
                                         textColor:(UIColor *)textColor
{
    UIFont *font = baseFont ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    NSMutableDictionary *plainAttrs = [@{ NSFontAttributeName: font } mutableCopy];
    if (textColor) {
        plainAttrs[NSForegroundColorAttributeName] = textColor;
    }
    if (markup.length == 0) {
        return [[NSAttributedString alloc] initWithString:plain ?: @""
                                               attributes:plainAttrs];
    }
    NSAttributedString *rich =
        [self decoratedString:[self attributedStringFromHTML:markup] baseFont:font];
    if (textColor == nil || rich.length == 0) {
        return rich;
    }
    // over the whole run: a UILabel's textColor does not reach ranges of
    // an attributed string, so an uncoloured run would draw black on a
    // dark background
    NSMutableAttributedString *coloured = [rich mutableCopy];
    [coloured addAttribute:NSForegroundColorAttributeName
                     value:textColor
                     range:NSMakeRange(0, coloured.length)];
    return coloured;
}

@end

#endif
