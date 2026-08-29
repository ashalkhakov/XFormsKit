#import <Foundation/Foundation.h>

@class XFInstance;
@class NSXMLElement;

NS_ASSUME_NONNULL_BEGIN

@interface XFModel : NSObject

@property (nonatomic, copy, nullable) NSString *identifier;
@property (nonatomic, copy, readonly) NSArray<XFInstance *> *instances;

+ (nullable instancetype)modelWithElement:(NSXMLElement *)modelElement
                                    error:(NSError **)error;

- (nullable XFInstance *)instanceWithIdentifier:(nullable NSString *)identifier;
- (nullable XFInstance *)defaultInstance;

@end

NS_ASSUME_NONNULL_END
