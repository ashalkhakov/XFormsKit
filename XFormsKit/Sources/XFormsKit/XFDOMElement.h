#import <XFormsKit/XFDOMNode.h>

NS_ASSUME_NONNULL_BEGIN

@interface XFDOMElement : XFDOMNode

+ (instancetype)elementWithName:(NSString *)name;
+ (instancetype)elementWithName:(NSString *)name URI:(NSString *)URI;
- (instancetype)initWithName:(NSString *)name;
- (instancetype)initWithName:(NSString *)name URI:(nullable NSString *)URI NS_DESIGNATED_INITIALIZER;

/* Attributes. Namespace declarations are NOT attributes here — they live
   in `namespaces`, as in NSXML, and the serialisation and submission code
   depends on that split. */

@property (nonatomic, readonly) NSArray<XFDOMNode *> *attributes;
- (nullable XFDOMNode *)attributeForName:(NSString *)name;
- (nullable XFDOMNode *)attributeForLocalName:(NSString *)localName URI:(nullable NSString *)URI;
/// Replaces any attribute of the same name, as NSXML does.
- (void)addAttribute:(XFDOMNode *)attribute;
- (void)removeAttributeForName:(NSString *)name;

/* Namespace declarations carried by this element. */

@property (nonatomic, readonly) NSArray<XFDOMNode *> *namespaces;
- (void)addNamespace:(XFDOMNode *)namespaceNode;
/// This element's own declaration for `prefix`; does not search ancestors.
- (nullable XFDOMNode *)namespaceForPrefix:(NSString *)prefix;
/// The declaration in scope for the prefix of a qualified name, searching
/// this element and then its ancestors.
- (nullable XFDOMNode *)resolveNamespaceForName:(NSString *)name;

/* Children. */

- (void)addChild:(XFDOMNode *)child;
- (void)insertChild:(XFDOMNode *)child atIndex:(NSUInteger)index;
- (void)removeChildAtIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
