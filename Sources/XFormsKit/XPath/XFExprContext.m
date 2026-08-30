#import "XFExprContext.h"
#import "XFXPathPriv.h"
#import "XFModel.h"
#import <Foundation/NSXMLNode.h>
#import <Foundation/NSXMLDocument.h>

@implementation XFNSResolver {
    NSMutableDictionary<NSString *, NSString *> *_map;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _map = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)registerPrefix:(NSString *)prefix uri:(NSString *)uri
{
    if (prefix == nil) {
        return;
    }
    _map[prefix] = uri ?: @"";
    if ([uri isEqualToString:@"notfound"]) {
        self.notfound = YES;
    }
}

- (void)registerAll:(XFNSResolver *)other
{
    [_map addEntriesFromDictionary:other->_map];
}

- (NSString *)lookupNamespaceURI:(NSString *)prefix
{
    return prefix ? _map[prefix] : nil;
}

@end

@implementation XFExprContext

- (instancetype)init
{
    return [self initWithNode:nil];
}

- (instancetype)initWithNode:(NSXMLNode *)node
{
    self = [super init];
    if (self) {
        _contextNode = node;
        _currentNode = node;
        _nodeList = node ? @[ node ] : @[];
        _position = 1;
        _size = _nodeList.count;
        _dependencies = [NSHashTable weakObjectsHashTable];
        _depElements = [NSHashTable weakObjectsHashTable];
        _nsResolver = [[XFNSResolver alloc] init];
    }
    return self;
}

- (instancetype)cloneWithNode:(NSXMLNode *)node
                     position:(NSUInteger)position
                     nodeList:(NSArray<NSXMLNode *> *)nodeList
{
    XFExprContext *copy = [[[self class] alloc] init];
    copy.contextNode = node ?: self.contextNode;
    copy.currentNode = self.currentNode ?: copy.contextNode;
    copy.nodeList = nodeList ?: self.nodeList;
    copy.position = position > 0 ? position : self.position;
    copy.size = copy.nodeList.count;
    copy.model = self.model;
    copy.nsResolver = self.nsResolver;
    copy.variables = self.variables;
    copy->_dependencies = self.dependencies;
    copy->_depElements = self.depElements;
    return copy;
}

- (void)addDependency:(NSXMLNode *)node
{
    if (node && [node kind] != NSXMLDocumentKind) {
        [self.dependencies addObject:node];
    }
}

- (void)addDepElement:(id)element
{
    if (element) {
        [self.depElements addObject:element];
    }
}

- (NSArray<NSXMLNode *> *)dependencyNodes
{
    return [self.dependencies allObjects];
}

- (id)copyWithZone:(NSZone *)zone
{
    (void)zone;
    return [self cloneWithNode:self.contextNode position:self.position nodeList:self.nodeList];
}

@end

NSString * const XFAxisAncestorOrSelf = @"ancestor-or-self";
NSString * const XFAxisAncestor = @"ancestor";
NSString * const XFAxisAttribute = @"attribute";
NSString * const XFAxisChild = @"child";
NSString * const XFAxisDescendantOrSelf = @"descendant-or-self";
NSString * const XFAxisDescendant = @"descendant";
NSString * const XFAxisFollowingSibling = @"following-sibling";
NSString * const XFAxisFollowing = @"following";
NSString * const XFAxisNamespace = @"namespace";
NSString * const XFAxisParent = @"parent";
NSString * const XFAxisPrecedingSibling = @"preceding-sibling";
NSString * const XFAxisPreceding = @"preceding";
NSString * const XFAxisSelf = @"self";

NSXMLNode *XFRootNode(NSXMLNode *node)
{
    if (node == nil) {
        return nil;
    }
    if ([node kind] == NSXMLDocumentKind) {
        return node;
    }
    NSXMLNode *n = node;
    while (n.parent) {
        n = n.parent;
    }
    return n;
}

BOOL XFNodeInArray(NSXMLNode *node, NSArray<NSXMLNode *> *array)
{
    for (NSXMLNode *n in array) {
        if (n == node) {
            return YES;
        }
    }
    return NO;
}
