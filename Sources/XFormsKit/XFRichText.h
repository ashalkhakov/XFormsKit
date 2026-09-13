#import <Foundation/Foundation.h>
#if __has_include(<AppKit/AppKit.h>)
#import <AppKit/AppKit.h>
#endif
#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/// Paragraph kind: "p" (default when absent), "h1"–"h3", "ul", "ol".
FOUNDATION_EXPORT NSString * const XFRichBlockAttributeName;
/// Inline markers (@YES). The converter reads and writes ONLY these, never
/// a font or an underline style: that keeps it identical on Apple and
/// GNUstep, independent of what NSFontManager can synthesise, and free of
/// AppKit — NSUnderlineStyleAttributeName and friends come from AppKit on
/// macOS and UIKit on iOS, neither of which the portable half may import.
/// Turning the markers into something a text view displays is the view
/// layer's job: see +decoratedString:baseFont: below.
FOUNDATION_EXPORT NSString * const XFRichBoldAttributeName;
FOUNDATION_EXPORT NSString * const XFRichItalicAttributeName;
FOUNDATION_EXPORT NSString * const XFRichUnderlineAttributeName;
FOUNDATION_EXPORT NSString * const XFRichStrikeAttributeName;

/// Two-way converter between NSAttributedString and the XHTML subset the
/// rich textarea stores in the instance (`xf:textarea` /
/// `xf:output mediatype="application/xhtml+xml"`, the TinyMCE sample):
///
///   block:  p (default), h1 h2 h3, ul/ol + li; div/blockquote read as p
///   inline: strong/b, em/i, u, s/strike/del, br
///
/// Neither Apple's `initWithHTML:` (WebKit; emits CSS spans on the way
/// out) nor GNUstep (no HTML text converter at all) can round-trip such a
/// fragment, so this is hand-rolled and deterministic: parse → edit →
/// serialize keeps the markup canonical (tags nested strong→em→u→s,
/// entities escaped, list items prefixed "• " / "1. " in the text and
/// stripped again on the way out; `<br/>` is U+2028 inside a paragraph,
/// "\n" separates paragraphs). A fragment that does not parse as XML is
/// treated as plain text.
@interface XFRichText : NSObject

/* The converter. Portable: markers in, markers out, no presentation. */

+ (NSAttributedString *)attributedStringFromHTML:(NSString *)html;
+ (NSString *)htmlFromAttributedString:(NSAttributedString *)text;

@end

#if __has_include(<AppKit/AppKit.h>)

/* Presentation. AppKit-only, because the attribute names it applies come
   from AppKit here and from UIKit on iOS; a UIKit twin of this category is
   what an iOS text widget will want. The converter above needs none of it. */

@interface XFRichText (XFRichTextPresentation)

/// The converter's output made displayable with `baseFont`.
+ (NSAttributedString *)decoratedString:(NSAttributedString *)text
                               baseFont:(nullable NSFont *)baseFont;

/// One run's attributes with their presentation recomputed from their
/// markers — the old presentation is dropped first, so a marker just
/// turned off stops showing. The editor uses this as it toggles.
+ (NSMutableDictionary *)attributesWithPresentation:(NSDictionary *)attrs
                                           baseFont:(nullable NSFont *)baseFont;

/// The display font for a paragraph of `blockKind` ("p", "h1"–"h3", "ul",
/// "ol") with the given inline markers, derived from `baseFont`.
+ (NSFont *)fontForBlock:(nullable NSString *)blockKind
                    bold:(BOOL)bold
                  italic:(BOOL)italic
                baseFont:(nullable NSFont *)baseFont;

/// A read-only text view showing `markup`, already sized to the height it
/// needs at `width` (its frame is the fitting size, origin zero). Not
/// editable and not selectable: it is a label that happens to draw bold,
/// italics and headings, so it takes no clicks and no focus and can be
/// dropped wherever a wrapped NSTextField would have gone — an NSAlert
/// accessory view, a hint popup.
///
/// Nil for empty markup, so a caller can fall back to its plain-text path
/// with one test.
+ (nullable NSTextView *)displayViewWithMarkup:(nullable NSString *)markup
                                          font:(nullable NSFont *)font
                                      maxWidth:(CGFloat)maxWidth
                                     textColor:(nullable NSColor *)textColor;

@end

#endif

#if __has_include(<UIKit/UIKit.h>)

/* The same presentation on iOS. Same selector, same meaning; only the
   font class and the attribute names differ, and those come from UIKit
   here and AppKit there. The converter above is shared. */

@interface XFRichText (XFRichTextUIKitPresentation)

+ (NSAttributedString *)decoratedString:(NSAttributedString *)text
                               baseFont:(nullable UIFont *)baseFont;

/// Markup straight to something a label can show: convert, then decorate.
/// Plain text in, plain text out — nothing here needs the caller to know
/// whether the form wrote markup.
+ (NSAttributedString *)attributedStringFromMarkup:(nullable NSString *)markup
                                         plainText:(nullable NSString *)plain
                                          baseFont:(nullable UIFont *)baseFont
                                         textColor:(nullable UIColor *)textColor;

@end

#endif

NS_ASSUME_NONNULL_END
