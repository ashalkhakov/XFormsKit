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
