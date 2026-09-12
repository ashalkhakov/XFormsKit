#import <XFormsKit/XFDOM.h>
#import <XFormsKit/XFDOMNode.h>
#import <XFormsKit/XFDOMElement.h>
#import <XFormsKit/XFDOMDocument.h>

NS_ASSUME_NONNULL_BEGIN

/// Internals shared between the DOM classes and the parser. Not public:
/// the engine only ever sees the NSXML-shaped API.
@interface XFDOMNode ()

@property (nonatomic, assign) XFDOMNodeKind kind;
/// The raw value of a leaf node (text, comment, attribute, namespace, PI).
@property (nonatomic, copy, nullable) NSString *leafValue;
@property (nonatomic, weak, nullable) XFDOMNode *parent;
/// Element and document children; nil for leaves.
@property (nonatomic, strong, nullable) NSMutableArray<XFDOMNode *> *mutableChildren;
/// Set on a text node parsed from (or destined for) a CDATA section.
@property (nonatomic, assign) BOOL CDATA;

- (instancetype)initWithKind:(XFDOMNodeKind)kind;
/// Take ownership of `child`, detaching it from any previous parent.
- (void)adoptNode:(XFDOMNode *)node;
/// Deep-copy names, value and children from `other`, leaving the receiver
/// detached — the shared half of every -copyWithZone:.
- (void)copyContentsOf:(XFDOMNode *)other;
/// Append the node's serialisation, used by the recursive writer.
- (void)appendXMLStringWithOptions:(XFDOMNodeOptions)options into:(NSMutableString *)out;
/// The same, carrying the nesting level that XFDOMNodePrettyPrint indents
/// by. The depthless version above is this one at level 0.
- (void)appendXMLStringWithOptions:(XFDOMNodeOptions)options
                             depth:(NSUInteger)depth
                              into:(NSMutableString *)out;

@end

@interface XFDOMElement ()
@property (nonatomic, strong) NSMutableArray<XFDOMNode *> *mutableAttributes;
@property (nonatomic, strong) NSMutableArray<XFDOMNode *> *mutableNamespaces;
@end

/// Builds a tree from XML data with NSXMLParser. Namespace processing is
/// deliberately left off so that xmlns declarations arrive as attributes
/// and the scope can be tracked here — NSXMLParser would otherwise hide
/// the declarations that the DOM has to keep.
@interface XFDOMParser : NSObject
+ (nullable XFDOMDocument *)documentWithData:(NSData *)data
                                     options:(XFDOMNodeOptions)options
                                       error:(NSError **)error;
@end

/// Shared escaping, exposed for the tests.
FOUNDATION_EXPORT NSString *XFDOMEscapedText(NSString *text);
FOUNDATION_EXPORT NSString *XFDOMEscapedAttributeValue(NSString *value);

NS_ASSUME_NONNULL_END
