#import "XFXML.h"
#import <XFormsKit/XFXMLTypes.h>

@implementation XFXML

+ (void)collectElementsWithLocalName:(NSString *)localName
                       namespaceURI:(NSString *)namespaceURI
                             inNode:(XFXMLNode *)node
                             into:(NSMutableArray<XFXMLElement *> *)out
{
    if ([node kind] == XFXMLElementKind) {
        XFXMLElement *element = (XFXMLElement *)node;
        if ([self element:element hasLocalName:localName namespaceURI:namespaceURI]) {
            [out addObject:element];
        }
    }
    for (XFXMLNode *child in [node children]) {
        [self collectElementsWithLocalName:localName
                             namespaceURI:namespaceURI
                                   inNode:child
                                   into:out];
    }
}

+ (NSArray<XFXMLElement *> *)elementsWithLocalName:(NSString *)localName
                                     namespaceURI:(NSString *)namespaceURI
                                           inNode:(XFXMLNode *)node
{
    NSMutableArray<XFXMLElement *> *out = [NSMutableArray array];
    [self collectElementsWithLocalName:localName
                         namespaceURI:namespaceURI
                               inNode:node
                               into:out];
    return out;
}

+ (XFXMLElement *)childElementWithLocalName:(NSString *)localName
                               namespaceURI:(NSString *)namespaceURI
                                  ofElement:(XFXMLElement *)element
{
    for (XFXMLNode *c in [element children]) {
        if ([c kind] == XFXMLElementKind
            && [self element:(XFXMLElement *)c hasLocalName:localName namespaceURI:namespaceURI]) {
            return (XFXMLElement *)c;
        }
    }
    return nil;
}

+ (XFXMLElement *)firstElementWithLocalName:(NSString *)localName
                              namespaceURI:(NSString *)namespaceURI
                                    inNode:(XFXMLNode *)node
{
    NSArray *found = [self elementsWithLocalName:localName namespaceURI:namespaceURI inNode:node];
    return found.count > 0 ? found[0] : nil;
}

+ (BOOL)element:(XFXMLElement *)element
   hasLocalName:(NSString *)localName
  namespaceURI:(NSString *)namespaceURI
{
    if (![[element localName] isEqualToString:localName]) {
        return NO;
    }
    NSString *uri = [element URI];
    if (uri == nil) {
        uri = @"";
    }
    return [uri isEqualToString:namespaceURI];
}

+ (NSString *)stringValueOfNode:(XFXMLNode *)node
{
    if (node == nil) {
        return @"";
    }
    switch ([node kind]) {
        case XFXMLAttributeKind:
        case XFXMLTextKind:
        case XFXMLCommentKind:
        case XFXMLProcessingInstructionKind:
            return [node stringValue] ?: @"";
        case XFXMLElementKind:
        case XFXMLDocumentKind: {
            NSMutableString *text = [NSMutableString string];
            for (XFXMLNode *child in [node children]) {
                XFXMLNodeKind kind = [child kind];
                if (kind == XFXMLTextKind || kind == XFXMLElementKind) {
                    [text appendString:[self stringValueOfNode:child]];
                }
            }
            return text;
        }
        default:
            return [node stringValue] ?: @"";
    }
}

+ (NSString *)attributeValue:(NSString *)localName
               namespaceURI:(NSString *)namespaceURI
                  onElement:(XFXMLElement *)element
{
    if (element == nil || localName.length == 0) {
        return nil;
    }
    for (XFXMLNode *attr in [element attributes]) {
        NSString *aLocal = [attr localName] ?: [attr name];
        if (![aLocal isEqualToString:localName]) {
            NSString *name = [attr name];
            NSRange colon = [name rangeOfString:@":"];
            if (colon.location != NSNotFound) {
                aLocal = [name substringFromIndex:colon.location + 1];
            }
            if (![aLocal isEqualToString:localName]) {
                continue;
            }
        }
        if (namespaceURI.length == 0) {
            return [attr stringValue];
        }
        NSString *uri = [attr URI];
        if ([uri isEqualToString:namespaceURI]) {
            return [attr stringValue];
        }
        // Accept ev:foo even when the parser dropped the attribute namespace.
        NSString *name = [attr name];
        if ([name hasPrefix:@"ev:"] && [namespaceURI isEqualToString:@"http://www.w3.org/2001/xml-events"]) {
            return [attr stringValue];
        }
    }
    if (namespaceURI.length == 0) {
        return [[element attributeForName:localName] stringValue];
    }
    return nil;
}

+ (XFXMLElement *)elementWithID:(NSString *)identifier inNode:(XFXMLNode *)node
{
    if (identifier.length == 0 || node == nil) {
        return nil;
    }
    if ([node kind] == XFXMLElementKind) {
        XFXMLElement *element = (XFXMLElement *)node;
        NSString *xmlid = [self attributeValue:@"id"
                                 namespaceURI:@"http://www.w3.org/XML/1998/namespace"
                                    onElement:element];
        if (xmlid == nil) {
            xmlid = [[element attributeForName:@"id"] stringValue];
        }
        if (xmlid == nil) {
            // xsi:type="xsd:ID" makes the element's CONTENT its ID
            // (7.10.3.c)
            NSString *xsi = [self attributeValue:@"type"
                                    namespaceURI:@"http://www.w3.org/2001/XMLSchema-instance"
                                       onElement:element]
                // XsltForms_browser.getType matches the literal
                // "xsi:type" name — suite forms bind xsi to variant URIs
                ?: [[element attributeForName:@"xsi:type"] stringValue];
            if (xsi != nil
                && [[[xsi componentsSeparatedByString:@":"] lastObject] isEqualToString:@"ID"]) {
                xmlid = [self stringValueOfNode:element];
            }
        }
        if ([xmlid isEqualToString:identifier]) {
            return element;
        }
    }
    for (XFXMLNode *child in [node children]) {
        XFXMLElement *found = [self elementWithID:identifier inNode:child];
        if (found) {
            return found;
        }
    }
    return nil;
}

+ (NSArray<XFXMLElement *> *)childElementsWithLocalName:(NSString *)localName
                                          namespaceURI:(NSString *)namespaceURI
                                             ofElement:(XFXMLElement *)element
{
    NSMutableArray<XFXMLElement *> *out = [NSMutableArray array];
    for (XFXMLNode *child in [element children]) {
        if ([child kind] != XFXMLElementKind) {
            continue;
        }
        XFXMLElement *el = (XFXMLElement *)child;
        if ([self element:el hasLocalName:localName namespaceURI:namespaceURI]) {
            [out addObject:el];
        }
    }
    return out;
}

+ (void)setStringValue:(NSString *)value ofNode:(XFXMLNode *)node
{
    if ([node kind] == XFXMLAttributeKind) {
        [node setStringValue:value ?: @""];
        return;
    }
    if ([node kind] != XFXMLElementKind) {
        [node setStringValue:value ?: @""];
        return;
    }
    XFXMLElement *element = (XFXMLElement *)node;
    NSArray *children = [[element children] copy];
    for (XFXMLNode *child in children) {
        if ([child kind] == XFXMLTextKind) {
            [element removeChildAtIndex:[child index]];
        }
    }
    if (value.length > 0) {
        XFXMLNode *text = [XFXMLNode textWithStringValue:value];
        [element addChild:text];
    }
}

+ (NSString *)normalizeSpace:(NSString *)string
{
    NSArray *parts = [string componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *words = [NSMutableArray array];
    for (NSString *w in parts) {
        if (w.length) {
            [words addObject:w];
        }
    }
    return [words componentsJoinedByString:@" "];
}

@end

NSString *XFPercentEncode(NSString *string)
{
    if (string.length == 0) {
        return @"";
    }
    const unsigned char *utf8 = (const unsigned char *)[string UTF8String];
    if (utf8 == NULL) {
        return @"";
    }
    NSMutableString *out = [NSMutableString string];
    for (const unsigned char *p = utf8; *p; p++) {
        unsigned char c = *p;
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
            (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~') {
            [out appendFormat:@"%c", c];
        } else {
            [out appendFormat:@"%%%02X", c];
        }
    }
    return out;
}
