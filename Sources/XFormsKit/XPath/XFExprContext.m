#import "XFExprContext.h"
#import "XFModel.h"
#import <Foundation/NSXMLNode.h>

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
        _position = 1;
        _size = 1;
        _dependencies = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

- (void)addDependency:(NSXMLNode *)node
{
    if (node) {
        [self.dependencies addObject:node];
    }
}

- (NSArray<NSXMLNode *> *)dependencyNodes
{
    return [self.dependencies allObjects];
}

- (id)copyWithZone:(NSZone *)zone
{
    XFExprContext *copy = [[[self class] allocWithZone:zone] init];
    copy.contextNode = self.contextNode;
    copy.position = self.position;
    copy.size = self.size;
    copy.model = self.model;
    // Share the dependency table so nested evaluations record on the same set.
    copy->_dependencies = self.dependencies;
    return copy;
}

@end
