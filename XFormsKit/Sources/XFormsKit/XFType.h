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
/// Facets of user schema types (G-56): xs:restriction children.
@property (nonatomic, strong, nullable) NSNumber *minExclusive;
@property (nonatomic, strong, nullable) NSNumber *maxExclusive;
@property (nonatomic, strong, nullable) NSNumber *length;
@property (nonatomic, strong, nullable) NSNumber *minLength;
@property (nonatomic, strong, nullable) NSNumber *maxLength;
@property (nonatomic, copy, nullable) NSArray<NSString *> *enumeration;
/// xs:list itemType: the value is a whitespace-separated list of items.
@property (nonatomic, weak, nullable) XFType *itemType;
/// xs:union memberTypes: valid when any member accepts the value.
@property (nonatomic, copy, nullable) NSArray<XFType *> *memberTypes;

/// Register the simple types of an `xs:schema` element (XsltForms_schema /
/// jsgen/simpleType.xsl: restrictions with facets, lists, unions) under its
/// targetNamespace (G-56). Returns the number of types defined.
+ (NSUInteger)registerSchemaElement:(NSXMLElement *)schema;
/// Resolve a `prefix:local` type name in the namespace context of
/// `element` (unprefixed names fall back to `targetNamespace`, then to the
/// xsd:/xf: conventions of `typeNamed:`).
+ (nullable XFType *)typeForQName:(NSString *)qname inElement:(NSXMLElement *)element targetNamespace:(nullable NSString *)targetNamespace;
/// XsltForms_atomicType.normalize: numbers rounded to `fractionDigits`.
- (NSString *)normalizeValue:(NSString *)value;

+ (nullable XFType *)typeNamed:(nullable NSString *)name;
+ (nullable XFType *)typeWithLocalName:(NSString *)localName
                         namespaceURI:(nullable NSString *)namespaceURI;

- (NSString *)canonicalValue:(NSString *)value;
- (BOOL)validateValue:(nullable NSString *)value;

/// Empty nodes are type-valid in XForms unless `@required` (handled by revalidate).
+ (BOOL)value:(nullable NSString *)value conformsToTypeNamed:(nullable NSString *)typeName;

@end

NS_ASSUME_NONNULL_END
