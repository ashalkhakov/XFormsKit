#import <Foundation/Foundation.h>

@class XFInstance;
@class NSXMLElement;

NS_ASSUME_NONNULL_BEGIN

@protocol XFModelOwner <NSObject>
- (void)refreshControls;
@end

@interface XFModel : NSObject

@property (nonatomic, copy, nullable) NSString *identifier;
@property (nonatomic, strong, nullable) NSXMLElement *element;
@property (nonatomic, weak, nullable) id<XFModelOwner> owner;
@property (nonatomic, copy, readonly) NSArray<XFInstance *> *instances;

+ (nullable instancetype)modelWithElement:(NSXMLElement *)modelElement
                                    error:(NSError **)error;

- (nullable XFInstance *)instanceWithIdentifier:(nullable NSString *)identifier;
- (nullable XFInstance *)defaultInstance;

- (void)construct;
- (void)rebuild;
- (void)recalculate;
- (void)revalidate;
- (void)refresh;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
