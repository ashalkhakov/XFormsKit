#import <Foundation/Foundation.h>

@class NSXMLNode;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, XFXPathValueType) {
    XFXPathValueTypeNodeSet = 0,
    XFXPathValueTypeString,
    XFXPathValueTypeNumber,
    XFXPathValueTypeBoolean
};

/// XPath 1.0 number-to-string conversion (shortest round-trip decimal).
FOUNDATION_EXPORT NSString *XFNumberToString(double n);

@interface XFXPathValue : NSObject

@property (nonatomic, readonly) XFXPathValueType type;
@property (nonatomic, copy, readonly) NSArray<NSXMLNode *> *nodes;
@property (nonatomic, copy, readonly) NSString *string;
@property (nonatomic, readonly) double number;
@property (nonatomic, readonly) BOOL boolean;

+ (instancetype)nodeSet:(NSArray<NSXMLNode *> *)nodes;
+ (instancetype)string:(NSString *)string;
+ (instancetype)number:(double)number;
+ (instancetype)boolean:(BOOL)flag;

- (NSString *)stringValue;
- (double)numberValue;
- (BOOL)booleanValue;
- (nullable NSXMLNode *)firstNode;

@end

NS_ASSUME_NONNULL_END
