/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFMarkupParts.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFXML.h"
#import "XFNamespaces.h"

@implementation XFMarkupOutput
@end

@implementation XFMarkupParts

+ (BOOL)isOutput:(XFXMLElement *)el
{
    return [XFXML element:el hasLocalName:@"output" namespaceURI:XFXFormsNamespaceURI];
}

/// Formatting markup means an element that is not an xf:output: a hint of
/// text and outputs renders identically as plain text, and taking the rich
/// path for it would only cost every host an XML parse.
+ (BOOL)hasFormattingMarkup:(XFXMLElement *)element
{
    for (XFXMLNode *child in [element children]) {
        if ([child kind] != XFXMLElementKind) {
            continue;
        }
        if (![self isOutput:(XFXMLElement *)child]) {
            return YES;
        }
    }
    return NO;
}

+ (XFMarkupOutput *)outputPartFor:(XFXMLElement *)el
{
    NSString *attr = [el attributeForName:@"value"] && ![el attributeForName:@"ref"]
        ? @"value" : @"ref";
    XFBinding *b = [XFBinding bindingForElement:el attribute:attr error:NULL];
    if (b == nil) {
        return nil;
    }
    XFMarkupOutput *part = [[XFMarkupOutput alloc] init];
    part.binding = b;
    NSString *mediatype = [[el attributeForName:@"mediatype"] stringValue];
    part.rawMarkup = [[mediatype lowercaseString] containsString:@"xhtml"]
                  || [[mediatype lowercaseString] containsString:@"text/html"];
    return part;
}

+ (void)appendStartTagOf:(XFXMLElement *)el
                selfClosing:(BOOL)selfClosing
                       into:(NSMutableString *)out
{
    [out appendFormat:@"<%@", [el localName] ?: @""];
    for (XFXMLNode *attr in [el attributes]) {
        [out appendFormat:@" %@=\"%@\"", [attr name] ?: @"",
                          [XFXML escapedText:[attr stringValue] ?: @""]];
    }
    [out appendString:selfClosing ? @"/>" : @">"];
}

+ (void)collectPartsOf:(XFXMLElement *)element
                markup:(BOOL)markup
                  into:(NSMutableArray *)parts
{
    NSMutableString *literal = [NSMutableString string];
    for (XFXMLNode *child in [element children]) {
        XFXMLNodeKind kind = [child kind];
        if (kind == XFXMLTextKind) {
            NSString *text = [child stringValue] ?: @"";
            [literal appendString:markup ? [XFXML escapedText:text] : text];
            continue;
        }
        if (kind != XFXMLElementKind) {
            continue;
        }
        XFXMLElement *el = (XFXMLElement *)child;
        if ([self isOutput:el]) {
            XFMarkupOutput *part = [self outputPartFor:el];
            if (part) {
                if (literal.length) {
                    [parts addObject:[literal copy]];
                    [literal setString:@""];
                }
                [parts addObject:part];
            }
            continue;
        }
        NSArray *kids = [el children];
        if (!markup) {
            // flush first: whatever the recursion adds belongs AFTER the
            // text already gathered here
            if (literal.length) {
                [parts addObject:[literal copy]];
                [literal setString:@""];
            }
            [self collectPartsOf:el markup:NO into:parts];
            // reopen the run on the trailing literal, so runs stay merged
            if (parts.count && [[parts lastObject] isKindOfClass:[NSString class]]) {
                [literal setString:[parts lastObject]];
                [parts removeLastObject];
            }
            continue;
        }
        if (kids.count == 0) {
            [self appendStartTagOf:el selfClosing:YES into:literal];
            continue;
        }
        [self appendStartTagOf:el selfClosing:NO into:literal];
        // the run breaks here only if a descendant output forces it
        [parts addObject:[literal copy]];
        [literal setString:@""];
        [self collectPartsOf:el markup:YES into:parts];
        // reopen the run on the last literal, so the end tag stays joined
        if (parts.count && [[parts lastObject] isKindOfClass:[NSString class]]) {
            [literal setString:[parts lastObject]];
            [parts removeLastObject];
        }
        [literal appendFormat:@"</%@>", [el localName] ?: @""];
    }
    if (literal.length) {
        [parts addObject:[literal copy]];
    }
}

+ (NSArray *)partsOfElement:(XFXMLElement *)element
{
    if (element == nil || ![self hasFormattingMarkup:element]) {
        return nil;
    }
    NSMutableArray *parts = [NSMutableArray array];
    [self collectPartsOf:element markup:YES into:parts];
    return parts.count ? parts : nil;
}

+ (NSArray *)textPartsOfElement:(XFXMLElement *)element
{
    if (element == nil) {
        return nil;
    }
    NSMutableArray *parts = [NSMutableArray array];
    [self collectPartsOf:element markup:NO into:parts];
    return parts;
}

+ (BOOL)partsAreDynamic:(NSArray *)parts
{
    for (id part in parts) {
        if ([part isKindOfClass:[XFMarkupOutput class]]) {
            return YES;
        }
    }
    return NO;
}

+ (NSString *)textFromParts:(NSArray *)parts context:(XFExprContext *)context
{
    if (parts == nil) {
        return nil;
    }
    NSMutableString *out = [NSMutableString string];
    for (id part in parts) {
        if ([part isKindOfClass:[XFMarkupOutput class]]) {
            XFMarkupOutput *hole = part;
            [out appendString:(context
                ? ([hole.binding stringValueInContext:context error:NULL] ?: @"") : @"")];
        } else {
            [out appendString:(NSString *)part];
        }
    }
    return out;
}

+ (NSString *)markupFromParts:(NSArray *)parts context:(XFExprContext *)context
{
    if (parts.count == 0) {
        return nil;
    }
    NSMutableString *out = [NSMutableString string];
    for (id part in parts) {
        if (![part isKindOfClass:[XFMarkupOutput class]]) {
            [out appendString:(NSString *)part];
            continue;
        }
        XFMarkupOutput *hole = part;
        NSString *value = context
            ? ([hole.binding stringValueInContext:context error:NULL] ?: @"") : @"";
        [out appendString:hole.rawMarkup ? value : [XFXML escapedText:value]];
    }
    return out.length ? out : nil;
}

@end
