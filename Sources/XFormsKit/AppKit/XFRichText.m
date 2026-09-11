#import "XFRichText.h"
#import <XFormsKit/XFXMLTypes.h>

void XFAppKitHasRichTextFile(void) {}

NSString * const XFRichBlockAttributeName = @"XFRichBlock";
NSString * const XFRichBoldAttributeName = @"XFRichBold";
NSString * const XFRichItalicAttributeName = @"XFRichItalic";

/// U+2028 LINE SEPARATOR: `<br/>` inside a paragraph (NSTextView renders
/// it as a line break; "\n" is reserved for paragraph boundaries).
static NSString * const XFRichLineBreak = @" ";

@implementation XFRichText

#pragma mark - Fonts

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

typedef struct {
    BOOL bold;
    BOOL italic;
    BOOL underline;
    BOOL strike;
} XFRichInline;

+ (NSDictionary *)attributesForBlock:(NSString *)block
                              inline:(XFRichInline)st
                            baseFont:(NSFont *)baseFont
{
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    NSFont *font = [self fontForBlock:block bold:st.bold italic:st.italic baseFont:baseFont];
    if (font) {
        attrs[NSFontAttributeName] = font;
    }
    if (block.length && ![block isEqualToString:@"p"]) {
        attrs[XFRichBlockAttributeName] = block;
    }
    if (st.bold) {
        attrs[XFRichBoldAttributeName] = @YES;
    }
    if (st.italic) {
        attrs[XFRichItalicAttributeName] = @YES;
    }
    if (st.underline) {
        attrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
    }
    if (st.strike) {
        attrs[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
    }
    return attrs;
}

/// HTML whitespace: runs collapse to one space; edge whitespace stays a
/// single space (a text node " and " after `</b>` keeps its separator —
/// duplicates across nodes are removed at append time, and paragraph
/// edges are trimmed by appendParagraph).
+ (NSString *)collapse:(NSString *)text
{
    NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
    BOOL space = NO;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            space = YES;
            continue;
        }
        if (space) {
            [out appendString:@" "];
        }
        space = NO;
        [out appendFormat:@"%C", c];
    }
    if (space) {
        [out appendString:@" "];
    }
    return out;
}

+ (void)appendInlineNodes:(NSArray<XFXMLNode *> *)nodes
                    block:(NSString *)block
                   style:(XFRichInline)style
                 baseFont:(NSFont *)baseFont
                     into:(NSMutableAttributedString *)out
{
    for (XFXMLNode *node in nodes) {
        if ([node kind] == XFXMLTextKind) {
            NSString *text = [self collapse:[node stringValue] ?: @""];
            // no doubled separators across node boundaries
            if ([text hasPrefix:@" "] && out.length) {
                unichar last = [[out string] characterAtIndex:out.length - 1];
                if (last == ' ' || last == 0x2028 || last == '\n') {
                    text = [text substringFromIndex:1];
                }
            }
            if (text.length) {
                [out appendAttributedString:
                    [[NSAttributedString alloc] initWithString:text
                                                    attributes:[self attributesForBlock:block inline:style baseFont:baseFont]]];
            }
            continue;
        }
        if ([node kind] != XFXMLElementKind) {
            continue;
        }
        NSString *tag = [[node localName] lowercaseString] ?: @"";
        if ([tag isEqualToString:@"br"]) {
            [out appendAttributedString:
                [[NSAttributedString alloc] initWithString:XFRichLineBreak
                                                attributes:[self attributesForBlock:block inline:style baseFont:baseFont]]];
            continue;
        }
        XFRichInline st = style;
        if ([tag isEqualToString:@"b"] || [tag isEqualToString:@"strong"]) {
            st.bold = YES;
        } else if ([tag isEqualToString:@"i"] || [tag isEqualToString:@"em"]) {
            st.italic = YES;
        } else if ([tag isEqualToString:@"u"]) {
            st.underline = YES;
        } else if ([tag isEqualToString:@"s"] || [tag isEqualToString:@"strike"] || [tag isEqualToString:@"del"]) {
            st.strike = YES;
        }
        // every other element (span, a, font, …) is transparent: children only
        [self appendInlineNodes:[node children] block:block style:st baseFont:baseFont into:out];
    }
}

+ (void)appendParagraph:(NSArray<XFXMLNode *> *)content
                  block:(NSString *)block
                 prefix:(NSString *)prefix
               baseFont:(NSFont *)baseFont
                   into:(NSMutableAttributedString *)out
{
    if (out.length) {
        [out appendAttributedString:
            [[NSAttributedString alloc] initWithString:@"\n"
                                            attributes:[self attributesForBlock:block inline:(XFRichInline){0} baseFont:baseFont]]];
    }
    if (prefix.length) {
        [out appendAttributedString:
            [[NSAttributedString alloc] initWithString:prefix
                                            attributes:[self attributesForBlock:block inline:(XFRichInline){0} baseFont:baseFont]]];
    }
    NSUInteger start = out.length;
    [self appendInlineNodes:content block:block style:(XFRichInline){0} baseFont:baseFont into:out];
    // trim the leading/trailing space HTML collapsing leaves at the edges
    while (out.length > start && [[out string] characterAtIndex:start] == ' ') {
        [out deleteCharactersInRange:NSMakeRange(start, 1)];
    }
    while (out.length > start && [[out string] characterAtIndex:out.length - 1] == ' ') {
        [out deleteCharactersInRange:NSMakeRange(out.length - 1, 1)];
    }
}

+ (NSAttributedString *)attributedStringFromHTML:(NSString *)html baseFont:(NSFont *)baseFont
{
    baseFont = [self baseFontOrDefault:baseFont];
    NSString *source = html ?: @"";
    // tolerate the usual non-XML entity
    source = [source stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "];
    XFXMLDocument *doc = [[XFXMLDocument alloc]
        initWithXMLString:[NSString stringWithFormat:@"<x>%@</x>", source]
                  options:0 error:NULL];
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    if (doc == nil) {
        // not our subset: plain text with the base font
        return [[NSAttributedString alloc] initWithString:source
                                               attributes:@{ NSFontAttributeName: baseFont }];
    }

    NSMutableArray<XFXMLNode *> *pending = [NSMutableArray array];   // loose inline content
    void (^flushPending)(void) = ^{
        if (pending.count) {
            [self appendParagraph:pending block:@"p" prefix:nil baseFont:baseFont into:out];
            [pending removeAllObjects];
        }
    };
    for (XFXMLNode *node in [[doc rootElement] children]) {
        NSString *tag = [node kind] == XFXMLElementKind ? [[node localName] lowercaseString] : nil;
        if ([tag isEqualToString:@"p"] || [tag isEqualToString:@"div"] || [tag isEqualToString:@"blockquote"]
            || [tag isEqualToString:@"h1"] || [tag isEqualToString:@"h2"] || [tag isEqualToString:@"h3"]) {
            flushPending();
            NSString *block = [tag hasPrefix:@"h"] ? tag : @"p";
            [self appendParagraph:[node children] block:block prefix:nil baseFont:baseFont into:out];
        } else if ([tag isEqualToString:@"ul"] || [tag isEqualToString:@"ol"]) {
            flushPending();
            NSUInteger number = 1;
            for (XFXMLNode *item in [node children]) {
                if ([item kind] != XFXMLElementKind
                    || ![[[item localName] lowercaseString] isEqualToString:@"li"]) {
                    continue;
                }
                NSString *prefix = [tag isEqualToString:@"ol"]
                    ? [NSString stringWithFormat:@"%lu. ", (unsigned long)number++]
                    : @"• ";
                [self appendParagraph:[item children] block:tag prefix:prefix baseFont:baseFont into:out];
            }
        } else if ([node kind] == XFXMLTextKind
                   && [self collapse:[node stringValue] ?: @""].length == 0) {
            continue;   // whitespace between blocks
        } else {
            [pending addObject:node];
        }
    }
    flushPending();
    return out;
}

#pragma mark - Attributed string → HTML

static void XFRichEscape(NSString *text, NSMutableString *out)
{
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        switch (c) {
            case '&': [out appendString:@"&amp;"]; break;
            case '<': [out appendString:@"&lt;"]; break;
            case '>': [out appendString:@"&gt;"]; break;
            case 0x2028: [out appendString:@"<br/>"]; break;
            case 0x00a0: [out appendString:@"&#160;"]; break;
            default: [out appendFormat:@"%C", c]; break;
        }
    }
}

/// Canonical inline nesting order.
static NSArray<NSString *> *XFRichTagsForAttributes(NSDictionary *attrs)
{
    NSMutableArray *tags = [NSMutableArray array];
    if ([attrs[XFRichBoldAttributeName] boolValue]) {
        [tags addObject:@"strong"];
    }
    if ([attrs[XFRichItalicAttributeName] boolValue]) {
        [tags addObject:@"em"];
    }
    if ([attrs[NSUnderlineStyleAttributeName] integerValue] != 0) {
        [tags addObject:@"u"];
    }
    if ([attrs[NSStrikethroughStyleAttributeName] integerValue] != 0) {
        [tags addObject:@"s"];
    }
    return tags;
}

+ (void)serializeParagraph:(NSAttributedString *)paragraph into:(NSMutableString *)out
{
    NSMutableArray<NSString *> *stack = [NSMutableArray array];
    NSUInteger i = 0;
    while (i < paragraph.length) {
        NSRange run;
        NSDictionary *attrs = [paragraph attributesAtIndex:i effectiveRange:&run];
        NSArray<NSString *> *want = XFRichTagsForAttributes(attrs);
        // pop to the common prefix, then push what is missing (the order is
        // canonical, so the stack is always a prefix of `want`)
        NSUInteger common = 0;
        while (common < stack.count && common < want.count
               && [stack[common] isEqualToString:want[common]]) {
            common++;
        }
        while (stack.count > common) {
            [out appendFormat:@"</%@>", stack.lastObject];
            [stack removeLastObject];
        }
        for (NSUInteger t = common; t < want.count; t++) {
            [out appendFormat:@"<%@>", want[t]];
            [stack addObject:want[t]];
        }
        XFRichEscape([[paragraph string] substringWithRange:run], out);
        i = NSMaxRange(run);
    }
    while (stack.count) {
        [out appendFormat:@"</%@>", stack.lastObject];
        [stack removeLastObject];
    }
}

+ (NSString *)htmlFromAttributedString:(NSAttributedString *)text
{
    if (text.length == 0) {
        return @"";
    }
    NSMutableString *out = [NSMutableString string];
    NSString *plain = [text string];
    NSString *openList = nil;   // "ul" / "ol" while inside one
    NSUInteger start = 0;
    while (start <= plain.length) {
        NSRange nl = [plain rangeOfString:@"\n"
                                  options:0
                                    range:NSMakeRange(start, plain.length - start)];
        NSUInteger end = nl.location == NSNotFound ? plain.length : nl.location;
        NSAttributedString *paragraph = [text attributedSubstringFromRange:NSMakeRange(start, end - start)];
        NSString *block = paragraph.length
            ? [paragraph attribute:XFRichBlockAttributeName atIndex:0 effectiveRange:NULL] : nil;
        BOOL list = [block isEqualToString:@"ul"] || [block isEqualToString:@"ol"];
        if (openList && (!list || ![block isEqualToString:openList])) {
            [out appendFormat:@"</%@>", openList];
            openList = nil;
        }
        BOOL last = (nl.location == NSNotFound);
        if (!(last && paragraph.length == 0 && out.length)) {   // trailing empty line
            if (list) {
                if (openList == nil) {
                    [out appendFormat:@"<%@>", block];
                    openList = block;
                }
                // the bullet / number prefix lives only in the display text
                NSUInteger skip = 0;
                NSString *s = [paragraph string];
                if ([s hasPrefix:@"• "]) {
                    skip = 2;
                } else {
                    NSUInteger d = 0;
                    while (d < s.length && [s characterAtIndex:d] >= '0' && [s characterAtIndex:d] <= '9') {
                        d++;
                    }
                    if (d > 0 && d + 1 < s.length && [s characterAtIndex:d] == '.' && [s characterAtIndex:d + 1] == ' ') {
                        skip = d + 2;
                    } else if (d > 0 && d + 1 == s.length && [s characterAtIndex:d] == '.') {
                        skip = d + 1;
                    }
                }
                [out appendString:@"<li>"];
                [self serializeParagraph:[paragraph attributedSubstringFromRange:
                                          NSMakeRange(skip, paragraph.length - skip)] into:out];
                [out appendString:@"</li>"];
            } else {
                NSString *tag = ([block isEqualToString:@"h1"] || [block isEqualToString:@"h2"]
                                 || [block isEqualToString:@"h3"]) ? block : @"p";
                [out appendFormat:@"<%@>", tag];
                [self serializeParagraph:paragraph into:out];
                [out appendFormat:@"</%@>", tag];
            }
        }
        if (last) {
            break;
        }
        start = NSMaxRange(nl);
    }
    if (openList) {
        [out appendFormat:@"</%@>", openList];
    }
    return out;
}

@end
