#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Paragraph kind: "p" (default when absent), "h1"–"h3", "ul", "ol".
FOUNDATION_EXPORT NSString * const XFRichBlockAttributeName;
/// Inline markers (@YES). The serializer reads THESE, not the font — the
/// converter is then identical on Apple and GNUstep and independent of
/// what NSFontManager can synthesise; the font traits are applied too so
/// the text view shows the styling.
FOUNDATION_EXPORT NSString * const XFRichBoldAttributeName;
FOUNDATION_EXPORT NSString * const XFRichItalicAttributeName;

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

+ (NSAttributedString *)attributedStringFromHTML:(NSString *)html
                                        baseFont:(nullable NSFont *)baseFont;
+ (NSString *)htmlFromAttributedString:(NSAttributedString *)text;

/// The display font for a paragraph of `blockKind` ("p", "h1"–"h3", "ul",
/// "ol") with the given inline markers, derived from `baseFont`.
+ (NSFont *)fontForBlock:(nullable NSString *)blockKind
                    bold:(BOOL)bold
                  italic:(BOOL)italic
                baseFont:(nullable NSFont *)baseFont;

@end

NS_ASSUME_NONNULL_END
