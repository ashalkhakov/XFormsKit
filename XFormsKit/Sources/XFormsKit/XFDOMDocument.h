#import <XFormsKit/XFDOMNode.h>

NS_ASSUME_NONNULL_BEGIN

@class XFDOMElement;

@interface XFDOMDocument : XFDOMNode

- (nullable instancetype)initWithXMLString:(NSString *)string
                                   options:(XFDOMNodeOptions)options
                                     error:(NSError **)error;
- (nullable instancetype)initWithData:(NSData *)data
                              options:(XFDOMNodeOptions)options
                                error:(NSError **)error;
- (instancetype)initWithRootElement:(XFDOMElement *)element;

/// Setting a root detaches the previous one and adopts the new element.
@property (nonatomic, strong, nullable) XFDOMElement *rootElement;

@property (nonatomic, copy, nullable) NSString *version;
@property (nonatomic, copy, nullable) NSString *characterEncoding;

@end

NS_ASSUME_NONNULL_END
