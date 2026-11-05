/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDRichFragment.h"
#import <XFormsKit/XFormsKit.h>

#pragma mark - Fragment helpers

/// Parse `fragment` with the label vocabulary bound (XHTML as the default
/// namespace, xf: for XForms — XFHostEdit rebinds to the document's real
/// prefix at commit time). nil when it does not parse.
XFXMLElement *XFDParseFragment(NSString *fragment, NSError **error)
{
    NSString *wrapped = [NSString stringWithFormat:
        @"<xfd-wrap xmlns=\"%@\" xmlns:xf=\"%@\">%@</xfd-wrap>",
        XFXHTMLNamespaceURI, XFXFormsNamespaceURI, fragment ?: @""];
    XFXMLDocument *doc = [[XFXMLDocument alloc] initWithXMLString:wrapped
                                                          options:0 error:error];
    return [doc rootElement];
}

NSString *XFDEscapeXML(NSString *text)
{
    NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        switch (c) {
            case '&': [out appendString:@"&amp;"]; break;
            case '<': [out appendString:@"&lt;"]; break;
            case '>': [out appendString:@"&gt;"]; break;
            default: [out appendFormat:@"%C", c]; break;
        }
    }
    return out;
}

NSString * const XFDTokenOpen = @"⟦";
NSString * const XFDTokenClose = @"⟧";

/// A dynamic output simple enough to ride through the rich editor as a
/// `⟦expr⟧` token: `<xf:output value="…"/>` — exactly that attribute, no
/// children, and an expression free of the bracket characters.
static BOOL XFDOutputElementIsToken(XFXMLElement *e)
{
    if (![[e localName] isEqualToString:@"output"]) {
        return NO;
    }
    NSString *uri = [e URI] ?: @"";
    if (![uri isEqualToString:XFXFormsNamespaceURI]
        && !(uri.length == 0 && [[e prefix] isEqualToString:@"xf"])) {
        return NO;
    }
    if ([e children].count || [e attributes].count != 1) {
        return NO;
    }
    NSString *value = [[e attributeForName:@"value"] stringValue];
    return value.length > 0
        && [value rangeOfString:XFDTokenOpen].location == NSNotFound
        && [value rangeOfString:XFDTokenClose].location == NSNotFound;
}

/// YES when the fragment stays inside what the rich view can show and
/// give back losslessly: the XFRichText subset, attribute-free, nothing
/// namespaced — except simple xf:output values, which become ⟦expr⟧
/// tokens. NO also for a fragment that does not parse.
static BOOL XFDFragmentSubtreeIsRichEditable(XFXMLElement *el)
{
    static NSSet *allowed;
    if (allowed == nil) {
        allowed = [NSSet setWithArray:@[ @"p", @"div", @"blockquote",
            @"h1", @"h2", @"h3", @"ul", @"ol", @"li",
            @"strong", @"b", @"em", @"i", @"u", @"s", @"strike", @"del", @"br" ]];
    }
    for (XFXMLNode *c in [el children]) {
        if ([c kind] == XFXMLTextKind) {
            continue;
        }
        if ([c kind] != XFXMLElementKind) {
            return NO;   // comments / PIs would be dropped
        }
        XFXMLElement *e = (XFXMLElement *)c;
        if (XFDOutputElementIsToken(e)) {
            continue;
        }
        if ([e prefix].length || ![allowed containsObject:[e localName] ?: @""]
            || [e attributes].count) {
            return NO;
        }
        if (!XFDFragmentSubtreeIsRichEditable(e)) {
            return NO;
        }
    }
    return YES;
}

#pragma mark - Output tokens (⟦expr⟧ ↔ xf:output)

static void XFDTokenizeIn(XFXMLElement *el)
{
    NSArray *kids = [[el children] copy];
    for (XFXMLNode *c in kids) {
        if ([c kind] != XFXMLElementKind) {
            continue;
        }
        XFXMLElement *e = (XFXMLElement *)c;
        if (XFDOutputElementIsToken(e)) {
            NSUInteger i = [e index];
            NSString *expr = [[e attributeForName:@"value"] stringValue];
            [e detach];
            [el insertChild:[XFXMLNode textWithStringValue:
                [NSString stringWithFormat:@"%@%@%@", XFDTokenOpen, expr, XFDTokenClose]]
                    atIndex:i];
        } else {
            XFDTokenizeIn(e);
        }
    }
}

NSString *XFDTokenizeFragment(NSString *fragment)
{
    XFXMLElement *wrap = XFDParseFragment(fragment, NULL);
    if (wrap == nil) {
        return fragment;
    }
    XFDTokenizeIn(wrap);
    NSMutableString *out = [NSMutableString string];
    for (XFXMLNode *c in [wrap children]) {
        [out appendString:[c XMLString] ?: @""];
    }
    return out;
}

static void XFDDetokenizeIn(XFXMLElement *el)
{
    NSArray *kids = [[el children] copy];
    for (XFXMLNode *c in kids) {
        if ([c kind] == XFXMLElementKind) {
            XFDDetokenizeIn((XFXMLElement *)c);
            continue;
        }
        if ([c kind] != XFXMLTextKind) {
            continue;
        }
        NSString *text = [c stringValue] ?: @"";
        if ([text rangeOfString:XFDTokenOpen].location == NSNotFound) {
            continue;
        }
        NSMutableArray *replacement = [NSMutableArray array];
        NSUInteger pos = 0;
        while (pos < text.length) {
            NSRange open = [text rangeOfString:XFDTokenOpen options:0
                                         range:NSMakeRange(pos, text.length - pos)];
            if (open.location == NSNotFound) {
                break;
            }
            NSUInteger after = NSMaxRange(open);
            NSRange close = [text rangeOfString:XFDTokenClose options:0
                                          range:NSMakeRange(after, text.length - after)];
            if (close.location == NSNotFound) {
                break;   // unmatched bracket: stays literal text
            }
            if (open.location > pos) {
                [replacement addObject:[XFXMLNode textWithStringValue:
                    [text substringWithRange:NSMakeRange(pos, open.location - pos)]]];
            }
            NSString *expr = [text substringWithRange:
                NSMakeRange(after, close.location - after)];
            if (expr.length) {
                XFXMLElement *output = [XFXMLElement elementWithName:@"xf:output"];
                [output addAttribute:[XFXMLNode attributeWithName:@"value" stringValue:expr]];
                [replacement addObject:output];
            }
            pos = NSMaxRange(close);
        }
        if (replacement.count == 0 && pos == 0) {
            continue;   // only unmatched brackets
        }
        if (pos < text.length) {
            [replacement addObject:[XFXMLNode textWithStringValue:
                [text substringFromIndex:pos]]];
        }
        NSUInteger i = [c index];
        [c detach];
        for (XFXMLNode *node in replacement) {
            [el insertChild:node atIndex:i++];
        }
    }
}

NSString *XFDDetokenizeFragment(NSString *fragment)
{
    if ([fragment rangeOfString:XFDTokenOpen].location == NSNotFound) {
        return fragment;
    }
    XFXMLElement *wrap = XFDParseFragment(fragment, NULL);
    if (wrap == nil) {
        return fragment;
    }
    XFDDetokenizeIn(wrap);
    NSMutableString *out = [NSMutableString string];
    for (XFXMLNode *c in [wrap children]) {
        [out appendString:[c XMLString] ?: @""];
    }
    return out;
}

BOOL XFDFragmentIsRichEditable(NSString *fragment)
{
    XFXMLElement *wrap = XFDParseFragment(fragment, NULL);
    return wrap != nil && XFDFragmentSubtreeIsRichEditable(wrap);
}

/// XFRichText serializes a single plain paragraph as `<p>text</p>`; label
/// content is inline, so one lone paragraph sheds its wrapper.
NSString *XFDUnwrapSingleParagraph(NSString *html)
{
    if ([html hasPrefix:@"<p>"] && [html hasSuffix:@"</p>"]
        && [html rangeOfString:@"<p>" options:0
                         range:NSMakeRange(1, html.length - 1)].location == NSNotFound) {
        return [html substringWithRange:NSMakeRange(3, html.length - 7)];
    }
    return html;
}
