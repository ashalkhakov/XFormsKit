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

@end
