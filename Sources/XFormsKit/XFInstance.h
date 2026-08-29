#import <Foundation/Foundation.h>

@class NSXMLDocument;
@class NSXMLElement;
@class NSXMLNode;

NS_ASSUME_NONNULL_BEGIN

@interface XFInstance : NSObject

@property (nonatomic, copy, nullable) NSString *identifier;
@property (nonatomic, strong, readonly) NSXMLDocument *document;
@property (nonatomic, strong, readonly) NSXMLDocument *originalDocument;

+ (nullable instancetype)instanceWithElement:(NSXMLElement *)instanceElement
                                       error:(NSError **)error;

- (NSXMLElement *)documentElement;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
