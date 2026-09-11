#import "XFControl.h"

NS_ASSUME_NONNULL_BEGIN

@interface XFOutputControl : XFControl
@property (nonatomic, copy, nullable) NSString *mediaType;
@property (nonatomic, assign, readonly) BOOL displaysImage;
@property (nonatomic, assign, readonly) BOOL displaysHTML;
- (nullable NSData *)imageData;
@end

NS_ASSUME_NONNULL_END
