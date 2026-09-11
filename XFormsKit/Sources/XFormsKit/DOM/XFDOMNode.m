#import "XFDOMPriv.h"

NSString *const XFDOMErrorDomain = @"XFDOMErrorDomain";

@interface XFDOMNode (XFDOMPrivateHelpers)
- (nullable NSArray<XFDOMNode *> *)siblingArray;
@end

@interface XFDOMDocument (XFDOMRootSlot)
/// Clears the root slot without touching the child list, for -detach.
- (void)setRootElementSlot:(nullable XFDOMElement *)root;
@end

#pragma mark - Escaping

/// Text content: NSXML escapes the three markup-significant characters
/// and leaves everything else (including quotes and non-ASCII) alone.
NSString *XFDOMEscapedText(NSString *text)
{
    if (text.length == 0) {
        return @"";
    }
    NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
    NSUInteger n = text.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [text characterAtIndex:i];
        switch (c) {
            case '&': [out appendString:@"&amp;"]; break;
            case '<': [out appendString:@"&lt;"]; break;
            case '>': [out appendString:@"&gt;"]; break;
            default:  [out appendFormat:@"%C", c]; break;
        }
    }
    return out;
}

/// Attribute values additionally escape the delimiter and the whitespace
/// an XML parser would otherwise normalise away.
NSString *XFDOMEscapedAttributeValue(NSString *value)
{
    if (value.length == 0) {
        return @"";
    }
    NSMutableString *out = [NSMutableString stringWithCapacity:value.length];
    NSUInteger n = value.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [value characterAtIndex:i];
        switch (c) {
            case '&':  [out appendString:@"&amp;"]; break;
            case '<':  [out appendString:@"&lt;"]; break;
            case '>':  [out appendString:@"&gt;"]; break;
            case '"':  [out appendString:@"&quot;"]; break;
            case '\n': [out appendString:@"&#10;"]; break;
            case '\r': [out appendString:@"&#13;"]; break;
            case '\t': [out appendString:@"&#9;"]; break;
            default:   [out appendFormat:@"%C", c]; break;
        }
    }
    return out;
}

#pragma mark - XFDOMNode

@implementation XFDOMNode

@synthesize kind = _kind;
@synthesize parent = _parent;

- (instancetype)initWithKind:(XFDOMNodeKind)kind
{
    self = [super init];
    if (self) {
        _kind = kind;
    }
    return self;
}

- (instancetype)init
{
    return [self initWithKind:XFDOMInvalidKind];
}

+ (XFDOMNode *)nodeOfKind:(XFDOMNodeKind)kind name:(NSString *)name value:(NSString *)value
{
    XFDOMNode *node = [[XFDOMNode alloc] initWithKind:kind];
    node.name = name;
    node.leafValue = value ?: @"";
    return node;
}

+ (XFDOMNode *)attributeWithName:(NSString *)name stringValue:(NSString *)stringValue
{
    return [self nodeOfKind:XFDOMAttributeKind name:name value:stringValue];
}

+ (XFDOMNode *)namespaceWithName:(NSString *)name stringValue:(NSString *)stringValue
{
    return [self nodeOfKind:XFDOMNamespaceKind name:name ?: @"" value:stringValue];
}

+ (XFDOMNode *)textWithStringValue:(NSString *)stringValue
{
    return [self nodeOfKind:XFDOMTextKind name:nil value:stringValue];
}

+ (XFDOMNode *)commentWithStringValue:(NSString *)stringValue
{
    return [self nodeOfKind:XFDOMCommentKind name:nil value:stringValue];
}

+ (XFDOMNode *)processingInstructionWithName:(NSString *)name stringValue:(NSString *)stringValue
{
    return [self nodeOfKind:XFDOMProcessingInstructionKind name:name value:stringValue];
}

#pragma mark Names

- (NSString *)localName
{
    NSString *name = self.name;
    if (name == nil) {
        return nil;
    }
    NSRange colon = [name rangeOfString:@":"];
    return colon.location == NSNotFound ? name : [name substringFromIndex:NSMaxRange(colon)];
}

- (NSString *)prefix
{
    NSString *name = self.name;
    if (name == nil) {
        return nil;
    }
    NSRange colon = [name rangeOfString:@":"];
    // NSXML reports an empty prefix, not nil, for an unprefixed name
    return colon.location == NSNotFound ? @"" : [name substringToIndex:colon.location];
}

#pragma mark Value

- (NSString *)stringValue
{
    switch (self.kind) {
        case XFDOMElementKind:
        case XFDOMDocumentKind: {
            NSMutableString *out = [NSMutableString string];
            for (XFDOMNode *child in self.mutableChildren) {
                if (child.kind == XFDOMTextKind) {
                    [out appendString:child.leafValue ?: @""];
                } else if (child.kind == XFDOMElementKind) {
                    [out appendString:child.stringValue ?: @""];
                }
            }
            return out;
        }
        default:
            return self.leafValue ?: @"";
    }
}

- (void)setStringValue:(NSString *)stringValue
{
    if (self.kind == XFDOMElementKind || self.kind == XFDOMDocumentKind) {
        // NSXML replaces the content wholesale with one text node
        for (XFDOMNode *child in [self.mutableChildren copy]) {
            child.parent = nil;
        }
        [self.mutableChildren removeAllObjects];
        if (stringValue.length > 0) {
            XFDOMNode *text = [XFDOMNode textWithStringValue:stringValue];
            text.parent = self;
            [self.mutableChildren addObject:text];
        }
        return;
    }
    self.leafValue = stringValue ?: @"";
}

#pragma mark Tree

- (NSArray<XFDOMNode *> *)children
{
    return self.mutableChildren ? [self.mutableChildren copy] : nil;
}

- (NSUInteger)childCount
{
    return self.mutableChildren.count;
}

- (XFDOMNode *)childAtIndex:(NSUInteger)index
{
    return index < self.mutableChildren.count ? self.mutableChildren[index] : nil;
}

- (XFDOMDocument *)rootDocument
{
    XFDOMNode *walk = self;
    while (walk != nil && walk.kind != XFDOMDocumentKind) {
        walk = walk.parent;
    }
    return (XFDOMDocument *)walk;
}

/// The array on the parent that holds a node of this kind.
- (NSArray<XFDOMNode *> *)siblingArray
{
    XFDOMNode *parent = self.parent;
    if (parent == nil) {
        return nil;
    }
    if (self.kind == XFDOMAttributeKind && [parent isKindOfClass:[XFDOMElement class]]) {
        return [(XFDOMElement *)parent attributes];
    }
    if (self.kind == XFDOMNamespaceKind && [parent isKindOfClass:[XFDOMElement class]]) {
        return [(XFDOMElement *)parent namespaces];
    }
    return parent.mutableChildren;
}

- (NSUInteger)index
{
    NSUInteger at = [[self siblingArray] indexOfObjectIdenticalTo:self];
    return at == NSNotFound ? 0 : at;
}

- (XFDOMNode *)nextSibling
{
    NSArray *siblings = [self siblingArray];
    NSUInteger at = [siblings indexOfObjectIdenticalTo:self];
    if (at == NSNotFound || at + 1 >= siblings.count) {
        return nil;
    }
    return siblings[at + 1];
}

- (XFDOMNode *)previousSibling
{
    NSArray *siblings = [self siblingArray];
    NSUInteger at = [siblings indexOfObjectIdenticalTo:self];
    if (at == NSNotFound || at == 0) {
        return nil;
    }
    return siblings[at - 1];
}

- (void)detach
{
    XFDOMNode *parent = self.parent;
    if (parent == nil) {
        return;
    }
    if (self.kind == XFDOMAttributeKind && [parent isKindOfClass:[XFDOMElement class]]) {
        [[(XFDOMElement *)parent mutableAttributes] removeObjectIdenticalTo:self];
    } else if (self.kind == XFDOMNamespaceKind && [parent isKindOfClass:[XFDOMElement class]]) {
        [[(XFDOMElement *)parent mutableNamespaces] removeObjectIdenticalTo:self];
    } else {
        if (parent.kind == XFDOMDocumentKind && [(XFDOMDocument *)parent rootElement] == self) {
            // clear the document's root slot as well as its child list
            [(XFDOMDocument *)parent setRootElementSlot:nil];
        }
        [parent.mutableChildren removeObjectIdenticalTo:self];
    }
    self.parent = nil;
}

- (void)adoptNode:(XFDOMNode *)node
{
    [node detach];
    node.parent = self;
}

#pragma mark Copying

- (id)copyWithZone:(NSZone *)zone
{
    // the cast matters: +allocWithZone: is typed id, and where NSXML also
    // exists the compiler would otherwise bind initWithKind: to
    // NSXMLNode's declaration of it
    XFDOMNode *fresh = (XFDOMNode *)[[self class] allocWithZone:zone];
    XFDOMNode *copy = [fresh initWithKind:self.kind];
    [copy copyContentsOf:self];
    return copy;
}

/// Deep copy, detached from any parent — NSXML's -copy contract.
- (void)copyContentsOf:(XFDOMNode *)other
{
    self.name = other.name;
    self.URI = other.URI;
    self.leafValue = other.leafValue;
    self.CDATA = other.CDATA;
    if (other.mutableChildren != nil) {
        self.mutableChildren = [NSMutableArray arrayWithCapacity:other.mutableChildren.count];
        for (XFDOMNode *child in other.mutableChildren) {
            XFDOMNode *childCopy = [child copy];
            childCopy.parent = self;
            [self.mutableChildren addObject:childCopy];
        }
    }
}

#pragma mark Serialisation

- (NSString *)XMLString
{
    return [self XMLStringWithOptions:XFDOMNodeOptionsNone];
}

- (NSString *)XMLStringWithOptions:(XFDOMNodeOptions)options
{
    NSMutableString *out = [NSMutableString string];
    [self appendXMLStringWithOptions:options into:out];
    return out;
}

- (void)appendXMLStringWithOptions:(XFDOMNodeOptions)options into:(NSMutableString *)out
{
    switch (self.kind) {
        case XFDOMTextKind:
            if (self.CDATA || (options & XFDOMNodeIsCDATA)) {
                [out appendFormat:@"<![CDATA[%@]]>", self.leafValue ?: @""];
            } else {
                [out appendString:XFDOMEscapedText(self.leafValue ?: @"")];
            }
            break;
        case XFDOMCommentKind:
            [out appendFormat:@"<!--%@-->", self.leafValue ?: @""];
            break;
        case XFDOMProcessingInstructionKind:
            [out appendFormat:@"<?%@ %@?>", self.name ?: @"", self.leafValue ?: @""];
            break;
        case XFDOMAttributeKind:
            [out appendFormat:@"%@=\"%@\"", self.name ?: @"",
                              XFDOMEscapedAttributeValue(self.leafValue ?: @"")];
            break;
        case XFDOMNamespaceKind: {
            NSString *prefix = self.name ?: @"";
            [out appendString:prefix.length ? [NSString stringWithFormat:@"xmlns:%@", prefix] : @"xmlns"];
            [out appendFormat:@"=\"%@\"", XFDOMEscapedAttributeValue(self.leafValue ?: @"")];
            break;
        }
        default:
            break;
    }
}

@end
