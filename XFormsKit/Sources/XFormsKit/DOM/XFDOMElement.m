#import "XFDOMPriv.h"

@implementation XFDOMElement

@synthesize mutableAttributes = _mutableAttributes;
@synthesize mutableNamespaces = _mutableNamespaces;

+ (instancetype)elementWithName:(NSString *)name
{
    return [[self alloc] initWithName:name URI:nil];
}

+ (instancetype)elementWithName:(NSString *)name URI:(NSString *)URI
{
    return [[self alloc] initWithName:name URI:URI];
}

- (instancetype)initWithName:(NSString *)name
{
    return [self initWithName:name URI:nil];
}

- (instancetype)initWithName:(NSString *)name URI:(NSString *)URI
{
    self = [super initWithKind:XFDOMElementKind];
    if (self) {
        self.name = name;
        self.URI = URI;
        self.mutableChildren = [NSMutableArray array];
        _mutableAttributes = [NSMutableArray array];
        _mutableNamespaces = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithKind:(XFDOMNodeKind)kind
{
    // an element is always element-kind, whatever a copy asks for
    return [self initWithName:nil URI:nil];
}

#pragma mark Attributes

- (NSArray<XFDOMNode *> *)attributes
{
    return [_mutableAttributes copy];
}

- (XFDOMNode *)attributeForName:(NSString *)name
{
    for (XFDOMNode *attribute in _mutableAttributes) {
        if ([attribute.name isEqualToString:name]) {
            return attribute;
        }
    }
    return nil;
}

- (XFDOMNode *)attributeForLocalName:(NSString *)localName URI:(NSString *)URI
{
    for (XFDOMNode *attribute in _mutableAttributes) {
        if (![attribute.localName isEqualToString:localName]) {
            continue;
        }
        NSString *attributeURI = attribute.URI;
        if (URI.length == 0 ? attributeURI.length == 0 : [attributeURI isEqualToString:URI]) {
            return attribute;
        }
    }
    return nil;
}

- (void)addAttribute:(XFDOMNode *)attribute
{
    if (attribute == nil) {
        return;
    }
    XFDOMNode *existing = [self attributeForName:attribute.name ?: @""];
    if (existing != nil) {
        [existing detach];
    }
    [self adoptNode:attribute];
    [_mutableAttributes addObject:attribute];
}

- (void)removeAttributeForName:(NSString *)name
{
    [[self attributeForName:name] detach];
}

#pragma mark Namespaces

- (NSArray<XFDOMNode *> *)namespaces
{
    return [_mutableNamespaces copy];
}

- (void)addNamespace:(XFDOMNode *)namespaceNode
{
    if (namespaceNode == nil) {
        return;
    }
    XFDOMNode *existing = [self namespaceForPrefix:namespaceNode.name ?: @""];
    if (existing != nil) {
        [existing detach];
    }
    [self adoptNode:namespaceNode];
    [_mutableNamespaces addObject:namespaceNode];
}

- (XFDOMNode *)namespaceForPrefix:(NSString *)prefix
{
    NSString *wanted = prefix ?: @"";
    for (XFDOMNode *namespaceNode in _mutableNamespaces) {
        if ([(namespaceNode.name ?: @"") isEqualToString:wanted]) {
            return namespaceNode;
        }
    }
    return nil;
}

- (XFDOMNode *)resolveNamespaceForName:(NSString *)name
{
    NSString *prefix = @"";
    NSRange colon = [name rangeOfString:@":"];
    if (colon.location != NSNotFound) {
        prefix = [name substringToIndex:colon.location];
    }
    XFDOMNode *walk = self;
    while (walk != nil) {
        if ([walk isKindOfClass:[XFDOMElement class]]) {
            XFDOMNode *found = [(XFDOMElement *)walk namespaceForPrefix:prefix];
            if (found != nil) {
                return found;
            }
        }
        walk = walk.parent;
    }
    return nil;
}

#pragma mark Children

- (void)addChild:(XFDOMNode *)child
{
    if (child == nil) {
        return;
    }
    [self adoptNode:child];
    [self.mutableChildren addObject:child];
}

- (void)insertChild:(XFDOMNode *)child atIndex:(NSUInteger)index
{
    if (child == nil) {
        return;
    }
    [self adoptNode:child];
    NSUInteger at = MIN(index, self.mutableChildren.count);
    [self.mutableChildren insertObject:child atIndex:at];
}

- (void)removeChildAtIndex:(NSUInteger)index
{
    if (index >= self.mutableChildren.count) {
        return;
    }
    XFDOMNode *child = self.mutableChildren[index];
    child.parent = nil;
    [self.mutableChildren removeObjectAtIndex:index];
}

#pragma mark Copying

- (id)copyWithZone:(NSZone *)zone
{
    XFDOMElement *copy = [[XFDOMElement allocWithZone:zone] initWithName:self.name URI:self.URI];
    [copy copyContentsOf:self];
    for (XFDOMNode *namespaceNode in _mutableNamespaces) {
        [copy addNamespace:[namespaceNode copy]];
    }
    for (XFDOMNode *attribute in _mutableAttributes) {
        [copy addAttribute:[attribute copy]];
    }
    return copy;
}

#pragma mark Serialisation

- (void)appendXMLStringWithOptions:(XFDOMNodeOptions)options into:(NSMutableString *)out
{
    NSString *name = self.name ?: @"";
    [out appendFormat:@"<%@", name];
    for (XFDOMNode *namespaceNode in _mutableNamespaces) {
        [out appendString:@" "];
        [namespaceNode appendXMLStringWithOptions:options into:out];
    }
    for (XFDOMNode *attribute in _mutableAttributes) {
        [out appendString:@" "];
        [attribute appendXMLStringWithOptions:options into:out];
    }
    // NSXML always writes the long form, even for an empty element
    [out appendString:@">"];
    for (XFDOMNode *child in self.mutableChildren) {
        [child appendXMLStringWithOptions:options into:out];
    }
    [out appendFormat:@"</%@>", name];
}

@end
