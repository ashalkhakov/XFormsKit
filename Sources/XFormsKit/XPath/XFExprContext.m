#import "XFExprContext.h"
#import "XFXPathPriv.h"
#import "XFModel.h"
#import "XFRepeat.h"
#import "XFNodeState.h"
#import <XFormsKit/XFXMLTypes.h>

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
    if (other == nil) {
        return;
    }
    for (NSString *prefix in other->_map) {
        if (_map[prefix] == nil) {
            _map[prefix] = other->_map[prefix];
        }
    }
}

- (NSString *)lookupNamespaceURI:(NSString *)prefix
{
    return prefix ? _map[prefix] : nil;
}

@end

@implementation XFExprContext {
    BOOL _autoPosition;
    NSUInteger _position;
}

@synthesize position = _position;

- (instancetype)init
{
    return [self initWithNode:nil];
}

- (instancetype)initWithNode:(XFXMLNode *)node
{
    self = [super init];
    if (self) {
        _contextNode = node;
        _currentNode = node;
        _nodeList = node ? @[ node ] : @[];
        _position = 1;
        _autoPosition = YES;
        _size = _nodeList.count;
        _dependencies = [NSHashTable weakObjectsHashTable];
        _depElements = [NSHashTable weakObjectsHashTable];
        _nsResolver = [[XFNSResolver alloc] init];
    }
    return self;
}

- (instancetype)cloneWithNode:(XFXMLNode *)node
                     position:(NSUInteger)position
                     nodeList:(NSArray<XFXMLNode *> *)nodeList
{
    XFExprContext *copy = [[[self class] alloc] init];
    copy.contextNode = node ?: self.contextNode;
    copy.currentNode = self.currentNode ?: copy.contextNode;
    copy.expressionStartNode = self.expressionStartNode;
    copy.nodeList = nodeList ?: self.nodeList;
    copy.position = position > 0 ? position : self.position;
    copy->_autoPosition = position > 0 ? NO : self->_autoPosition;
    copy.size = copy.nodeList.count;
    copy.model = self.model;
    copy.sourceElement = self.sourceElement;
    copy.nsResolver = self.nsResolver;
    copy.variables = self.variables;
    copy->_dependencies = self.dependencies;
    copy->_depElements = self.depElements;
    return copy;
}

- (void)addDependency:(XFXMLNode *)node
{
    if (node && [node kind] != XFXMLDocumentKind) {
        [self.dependencies addObject:node];
    }
}

- (void)addDepElement:(id)element
{
    if (element) {
        [self.depElements addObject:element];
    }
}

- (NSArray<XFXMLNode *> *)dependencyNodes
{
    return [self.dependencies allObjects];
}

- (id)copyWithZone:(NSZone *)zone
{
    (void)zone;
    return [self cloneWithNode:self.contextNode position:self.position nodeList:self.nodeList];
}

/// XsltForms_exprContext: with no explicit position, a node that belongs to
/// a repeat's nodeset takes its position in that repeat (G-76).
- (NSUInteger)position
{
    if (_autoPosition && _position == 1 && self.contextNode && self.model) {
        NSString *rid = [XFNodeState existingStateOnNode:self.contextNode].repeatIdentifier;
        if (rid.length) {
            XFRepeat *repeat = [self.model repeatWithIdentifier:rid];
            NSUInteger at = [repeat.nodes indexOfObjectIdenticalTo:self.contextNode];
            if (at != NSNotFound) {
                return at + 1;
            }
        }
    }
    return _position;
}

- (void)setPosition:(NSUInteger)position
{
    _position = position;
    _autoPosition = NO;
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

XFXMLNode *XFRootNode(XFXMLNode *node)
{
    if (node == nil) {
        return nil;
    }
    if ([node kind] == XFXMLDocumentKind) {
        return node;
    }
    XFXMLNode *n = node;
    while (n.parent) {
        n = n.parent;
    }
    return n;
}

BOOL XFNodeInArray(XFXMLNode *node, NSArray<XFXMLNode *> *array)
{
    for (XFXMLNode *n in array) {
        if (n == node) {
            return YES;
        }
    }
    return NO;
}

/// Path from the root to `node` as (ancestor..., node); attributes are
/// ordered before the children of their element (XPath 1.0 §5).
static NSArray<XFXMLNode *> *XFAncestryOf(XFXMLNode *node)
{
    NSMutableArray *path = [NSMutableArray array];
    for (XFXMLNode *n = node; n; n = [n parent]) {
        [path insertObject:n atIndex:0];
    }
    return path;
}

static NSInteger XFPositionOf(XFXMLNode *child, XFXMLNode *parent)
{
    if ([child kind] == XFXMLAttributeKind) {
        NSArray *attrs = [(XFXMLElement *)parent attributes];
        return -(NSInteger)attrs.count + (NSInteger)[attrs indexOfObjectIdenticalTo:child];
    }
    return (NSInteger)[child index];
}

NSComparisonResult XFCompareDocumentOrder(XFXMLNode *a, XFXMLNode *b)
{
    if (a == b) {
        return NSOrderedSame;
    }
    NSArray *pa = XFAncestryOf(a);
    NSArray *pb = XFAncestryOf(b);
    NSUInteger n = MIN(pa.count, pb.count);
    for (NSUInteger i = 0; i < n; i++) {
        if (pa[i] != pb[i]) {
            if (i == 0) {
                // different documents: keep a stable but arbitrary order
                return (uintptr_t)pa[0] < (uintptr_t)pb[0] ? NSOrderedAscending : NSOrderedDescending;
            }
            NSInteger ia = XFPositionOf(pa[i], pa[i - 1]);
            NSInteger ib = XFPositionOf(pb[i], pb[i - 1]);
            return ia < ib ? NSOrderedAscending : NSOrderedDescending;
        }
    }
    // one is an ancestor of the other: the ancestor comes first
    return pa.count < pb.count ? NSOrderedAscending : NSOrderedDescending;
}

NSArray<XFXMLNode *> *XFSortDocumentOrder(NSArray<XFXMLNode *> *nodes)
{
    if (nodes.count < 2) {
        return nodes;
    }
    return [nodes sortedArrayUsingComparator:^NSComparisonResult(XFXMLNode *a, XFXMLNode *b) {
        return XFCompareDocumentOrder(a, b);
    }];
}
