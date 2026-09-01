#import "XFXML.h"
#import <Foundation/NSXMLNode.h>
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLDocument.h>

@implementation XFXML

+ (void)collectElementsWithLocalName:(NSString *)localName
                       namespaceURI:(NSString *)namespaceURI
                             inNode:(NSXMLNode *)node
                             into:(NSMutableArray<NSXMLElement *> *)out
{
    if ([node kind] == NSXMLElementKind) {
        NSXMLElement *element = (NSXMLElement *)node;
        if ([self element:element hasLocalName:localName namespaceURI:namespaceURI]) {
            [out addObject:element];
        }
    }
    for (NSXMLNode *child in [node children]) {
        [self collectElementsWithLocalName:localName
                             namespaceURI:namespaceURI
                                   inNode:child
                                   into:out];
    }
}

+ (NSArray<NSXMLElement *> *)elementsWithLocalName:(NSString *)localName
                                     namespaceURI:(NSString *)namespaceURI
                                           inNode:(NSXMLNode *)node
{
    NSMutableArray<NSXMLElement *> *out = [NSMutableArray array];
    [self collectElementsWithLocalName:localName
                         namespaceURI:namespaceURI
                               inNode:node
                               into:out];
    return out;
}

+ (NSXMLElement *)childElementWithLocalName:(NSString *)localName
                               namespaceURI:(NSString *)namespaceURI
                                  ofElement:(NSXMLElement *)element
{
    for (NSXMLNode *c in [element children]) {
        if ([c kind] == NSXMLElementKind
            && [self element:(NSXMLElement *)c hasLocalName:localName namespaceURI:namespaceURI]) {
            return (NSXMLElement *)c;
        }
    }
    return nil;
}

+ (NSXMLElement *)firstElementWithLocalName:(NSString *)localName
                              namespaceURI:(NSString *)namespaceURI
                                    inNode:(NSXMLNode *)node
{
    NSArray *found = [self elementsWithLocalName:localName namespaceURI:namespaceURI inNode:node];
    return found.count > 0 ? found[0] : nil;
}

+ (BOOL)element:(NSXMLElement *)element
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

+ (NSString *)stringValueOfNode:(NSXMLNode *)node
{
    if (node == nil) {
        return @"";
    }
    switch ([node kind]) {
        case NSXMLAttributeKind:
        case NSXMLTextKind:
        case NSXMLCommentKind:
        case NSXMLProcessingInstructionKind:
            return [node stringValue] ?: @"";
        case NSXMLElementKind:
        case NSXMLDocumentKind: {
            NSMutableString *text = [NSMutableString string];
            for (NSXMLNode *child in [node children]) {
                NSXMLNodeKind kind = [child kind];
                if (kind == NSXMLTextKind || kind == NSXMLElementKind) {
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
                  onElement:(NSXMLElement *)element
{
    if (element == nil || localName.length == 0) {
        return nil;
    }
    for (NSXMLNode *attr in [element attributes]) {
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

+ (NSXMLElement *)elementWithID:(NSString *)identifier inNode:(NSXMLNode *)node
{
    if (identifier.length == 0 || node == nil) {
        return nil;
    }
    if ([node kind] == NSXMLElementKind) {
        NSXMLElement *element = (NSXMLElement *)node;
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
    for (NSXMLNode *child in [node children]) {
        NSXMLElement *found = [self elementWithID:identifier inNode:child];
        if (found) {
            return found;
        }
    }
    return nil;
}

+ (NSArray<NSXMLElement *> *)childElementsWithLocalName:(NSString *)localName
                                          namespaceURI:(NSString *)namespaceURI
                                             ofElement:(NSXMLElement *)element
{
    NSMutableArray<NSXMLElement *> *out = [NSMutableArray array];
    for (NSXMLNode *child in [element children]) {
        if ([child kind] != NSXMLElementKind) {
            continue;
        }
        NSXMLElement *el = (NSXMLElement *)child;
        if ([self element:el hasLocalName:localName namespaceURI:namespaceURI]) {
            [out addObject:el];
        }
    }
    return out;
}

+ (void)setStringValue:(NSString *)value ofNode:(NSXMLNode *)node
{
    if ([node kind] == NSXMLAttributeKind) {
        [node setStringValue:value ?: @""];
        return;
    }
    if ([node kind] != NSXMLElementKind) {
        [node setStringValue:value ?: @""];
        return;
    }
    NSXMLElement *element = (NSXMLElement *)node;
    NSArray *children = [[element children] copy];
    for (NSXMLNode *child in children) {
        if ([child kind] == NSXMLTextKind) {
            [element removeChildAtIndex:[child index]];
        }
    }
    if (value.length > 0) {
        NSXMLNode *text = [NSXMLNode textWithStringValue:value];
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
