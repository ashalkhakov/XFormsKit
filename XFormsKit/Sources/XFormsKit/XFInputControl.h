#import "XFControl.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, XFDateType) {
    XFDateTypeNone = 0,
    XFDateTypeDate,
    XFDateTypeTime,
    XFDateTypeDateTime
};

@interface XFInputControl : XFControl

@property (nonatomic, assign) XFDateType dateType;

- (BOOL)commitStringValue:(NSString *)value error:(NSError **)error;
- (XFDateType)resolvedDateType;
- (nullable NSDate *)dateValue;
- (BOOL)commitDateValue:(NSDate *)date error:(NSError **)error;

+ (XFDateType)dateTypeFromTypeName:(nullable NSString *)typeName;
+ (nullable NSDate *)parseDateString:(NSString *)string type:(XFDateType)type;
+ (NSString *)formatDate:(NSDate *)date type:(XFDateType)type;

@end

NS_ASSUME_NONNULL_END
