#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>


NS_ASSUME_NONNULL_BEGIN

@interface XFXML : NSObject

+ (NSArray<XFXMLElement *> *)elementsWithLocalName:(NSString *)localName
                                     namespaceURI:(NSString *)namespaceURI
                                           inNode:(XFXMLNode *)node;

/// First DIRECT child element with the given name (label/hint/help/alert
/// belong to their parent control only, XForms 1.1 8.3).
+ (nullable XFXMLElement *)childElementWithLocalName:(NSString *)localName
                                        namespaceURI:(nullable NSString *)namespaceURI
                                           ofElement:(XFXMLElement *)element;
+ (nullable XFXMLElement *)firstElementWithLocalName:(NSString *)localName
                                       namespaceURI:(NSString *)namespaceURI
                                             inNode:(XFXMLNode *)node;

+ (NSString *)stringValueOfNode:(XFXMLNode *)node;

/// The element's children serialized as XHTML — its markup, not its text.
/// nil when the element holds no element children, so a caller can tell
/// "<xf:hint>plain</xf:hint>" from "<xf:hint>with <b>emphasis</b></xf:hint>"
/// and only pay for the second.
+ (nullable NSString *)innerMarkupOfElement:(nullable XFXMLElement *)element;

/// `text` with the five XML metacharacters escaped, for splicing a value
/// into markup.
+ (NSString *)escapedText:(nullable NSString *)text;

+ (void)setStringValue:(NSString *)value ofNode:(XFXMLNode *)node;
/// XPath normalize-space().
+ (NSString *)normalizeSpace:(NSString *)string;

+ (BOOL)element:(XFXMLElement *)element
   hasLocalName:(NSString *)localName
  namespaceURI:(NSString *)namespaceURI;

+ (nullable NSString *)attributeValue:(NSString *)localName
                        namespaceURI:(nullable NSString *)namespaceURI
                           onElement:(XFXMLElement *)element;

+ (nullable XFXMLElement *)elementWithID:(NSString *)identifier
                                  inNode:(XFXMLNode *)node;

/// Direct children only (nested `xf:bind` must be walked via the parent bind).
+ (NSArray<XFXMLElement *> *)childElementsWithLocalName:(NSString *)localName
                                          namespaceURI:(NSString *)namespaceURI
                                             ofElement:(XFXMLElement *)element;

@end

/// RFC 3986 unreserved percent-encoding (XsltForms_submission.toUrl_).
NSString *XFPercentEncode(NSString *string);

NS_ASSUME_NONNULL_END
