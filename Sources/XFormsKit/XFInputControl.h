#import "XFControl.h"

NS_ASSUME_NONNULL_BEGIN

@interface XFInputControl : XFControl

- (BOOL)commitStringValue:(NSString *)value error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
