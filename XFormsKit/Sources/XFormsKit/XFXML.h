#import <Foundation/Foundation.h>

@class NSXMLNode;
@class NSXMLElement;
@class NSXMLDocument;

NS_ASSUME_NONNULL_BEGIN

@interface XFXML : NSObject

+ (NSArray<NSXMLElement *> *)elementsWithLocalName:(NSString *)localName
                                     namespaceURI:(NSString *)namespaceURI
                                           inNode:(NSXMLNode *)node;

/// First DIRECT child element with the given name (label/hint/help/alert
/// belong to their parent control only, XForms 1.1 8.3).
+ (nullable NSXMLElement *)childElementWithLocalName:(NSString *)localName
                                        namespaceURI:(nullable NSString *)namespaceURI
                                           ofElement:(NSXMLElement *)element;
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

/// Direct children only (nested `xf:bind` must be walked via the parent bind).
+ (NSArray<NSXMLElement *> *)childElementsWithLocalName:(NSString *)localName
                                          namespaceURI:(NSString *)namespaceURI
                                             ofElement:(NSXMLElement *)element;

@end

/// RFC 3986 unreserved percent-encoding (XsltForms_submission.toUrl_).
NSString *XFPercentEncode(NSString *string);

NS_ASSUME_NONNULL_END
