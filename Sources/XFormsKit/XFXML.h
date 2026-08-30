#import <Foundation/Foundation.h>

@class NSXMLNode;
@class NSXMLElement;
@class NSXMLDocument;

NS_ASSUME_NONNULL_BEGIN

@interface XFXML : NSObject

+ (NSArray<NSXMLElement *> *)elementsWithLocalName:(NSString *)localName
                                     namespaceURI:(NSString *)namespaceURI
                                           inNode:(NSXMLNode *)node;

+ (nullable NSXMLElement *)firstElementWithLocalName:(NSString *)localName
                                       namespaceURI:(NSString *)namespaceURI
                                             inNode:(NSXMLNode *)node;

+ (NSString *)stringValueOfNode:(NSXMLNode *)node;

+ (void)setStringValue:(NSString *)value ofNode:(NSXMLNode *)node;

+ (BOOL)element:(NSXMLElement *)element
   hasLocalName:(NSString *)localName
  namespaceURI:(NSString *)namespaceURI;

+ (nullable NSString *)attributeValue:(NSString *)localName
                        namespaceURI:(nullable NSString *)namespaceURI
                           onElement:(NSXMLElement *)element;

+ (nullable NSXMLElement *)elementWithID:(NSString *)identifier
                                  inNode:(NSXMLNode *)node;

@end

NS_ASSUME_NONNULL_END
