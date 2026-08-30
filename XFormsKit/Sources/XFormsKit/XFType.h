#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, XFWhitespace) {
    XFWhitespacePreserve = 0,
    XFWhitespaceReplace,
    XFWhitespaceCollapse
};

/// Atomic schema type (XsltForms_atomicType) used by `xf:bind/@type`
/// and instance revalidate. Built-in XSD + XForms libraries are
/// registered the first time a type is looked up.
@interface XFType : NSObject

@property (nonatomic, copy) NSString *localName;
@property (nonatomic, copy) NSString *namespaceURI;
@property (nonatomic, weak, nullable) XFType *baseType;
@property (nonatomic, copy) NSArray<NSString *> *patterns;
@property (nonatomic, assign) XFWhitespace whitespace;
@property (nonatomic, strong, nullable) NSNumber *fractionDigits;
@property (nonatomic, strong, nullable) NSNumber *totalDigits;
@property (nonatomic, strong, nullable) NSNumber *minInclusive;
@property (nonatomic, strong, nullable) NSNumber *maxInclusive;

+ (nullable XFType *)typeNamed:(nullable NSString *)name;
+ (nullable XFType *)typeWithLocalName:(NSString *)localName
                         namespaceURI:(nullable NSString *)namespaceURI;

- (NSString *)canonicalValue:(NSString *)value;
- (BOOL)validateValue:(nullable NSString *)value;

/// Empty nodes are type-valid in XForms unless `@required` (handled by revalidate).
+ (BOOL)value:(nullable NSString *)value conformsToTypeNamed:(nullable NSString *)typeName;

@end

NS_ASSUME_NONNULL_END
