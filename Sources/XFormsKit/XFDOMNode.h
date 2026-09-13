#import <XFormsKit/XFDOM.h>

NS_ASSUME_NONNULL_BEGIN

@class XFDOMDocument;

/// Base class for every node in the tree. Attributes, namespace
/// declarations, text, comments and processing instructions are all
/// XFDOMNode instances distinguished by `kind`; elements and documents
/// are the two subclasses, because only they carry children.
@interface XFDOMNode : NSObject <NSCopying>

/* Leaf-node factories (NSXMLNode's spelling). */

+ (XFDOMNode *)attributeWithName:(NSString *)name stringValue:(NSString *)stringValue;
/// `name` is the prefix; the empty string makes a default-namespace
/// declaration. `stringValue` is the URI.
+ (XFDOMNode *)namespaceWithName:(NSString *)name stringValue:(NSString *)stringValue;
+ (XFDOMNode *)textWithStringValue:(NSString *)stringValue;
/// A text node that serialises as `<![CDATA[...]]>`.
///
/// The content is the same text either way — CDATA is a choice about
/// how to write it, not a kind of node, which is why this answers a
/// text node and why a parsed section comes back as one. `xf:submission`
/// asks for it by name through @cdata-section-elements (XForms 1.1
/// 11.1, via xsl:output).
+ (XFDOMNode *)CDATAWithStringValue:(NSString *)stringValue;
+ (XFDOMNode *)commentWithStringValue:(NSString *)stringValue;
+ (XFDOMNode *)processingInstructionWithName:(NSString *)name stringValue:(NSString *)stringValue;

@property (nonatomic, readonly) XFDOMNodeKind kind;

/// The qualified name (`xf:input`), or for a namespace node its prefix.
@property (nonatomic, copy, nullable) NSString *name;
/// `name` with any prefix stripped.
@property (nonatomic, readonly, nullable) NSString *localName;
/// The prefix in `name`, or nil when unprefixed.
@property (nonatomic, readonly, nullable) NSString *prefix;
/// The namespace URI this node resolved to, nil when in no namespace.
@property (nonatomic, copy, nullable) NSString *URI;

/// For a leaf, its value. For an element or document, the concatenated
/// text of every descendant text node. Setting it on an element replaces
/// the children with a single text node.
@property (nonatomic, copy, null_resettable) NSString *stringValue;

@property (nonatomic, weak, readonly, nullable) XFDOMNode *parent;
@property (nonatomic, readonly, nullable) XFDOMDocument *rootDocument;

/// Element and text children — never attributes or namespaces. nil for
/// leaf kinds, matching NSXML.
@property (nonatomic, readonly, nullable) NSArray<XFDOMNode *> *children;
@property (nonatomic, readonly) NSUInteger childCount;
- (nullable XFDOMNode *)childAtIndex:(NSUInteger)index;

/// Position among the parent's children, or among its attributes or
/// namespaces for those kinds. 0 when unparented.
@property (nonatomic, readonly) NSUInteger index;
@property (nonatomic, readonly, nullable) XFDOMNode *nextSibling;
@property (nonatomic, readonly, nullable) XFDOMNode *previousSibling;

/// Unlink from the parent, leaving the node usable and re-insertable.
- (void)detach;

/* Child mutation. Meaningful on the two container kinds, element and
   document; a no-op on leaves. */

- (void)addChild:(XFDOMNode *)child;
- (void)insertChild:(XFDOMNode *)child atIndex:(NSUInteger)index;
- (void)removeChildAtIndex:(NSUInteger)index;

@property (nonatomic, readonly) NSString *XMLString;
- (NSString *)XMLStringWithOptions:(XFDOMNodeOptions)options;

@end

NS_ASSUME_NONNULL_END
