#import "XFMIPBinding.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFXPathValue.h"
#import "XFModel.h"
#import <XFormsKit/XFXMLTypes.h>

@interface XFMIPNodeCache : NSObject
@property (nonatomic, weak) XFXMLNode *node;
@property (nonatomic, strong) XFXPathValue *result;
@property (nonatomic, strong) NSMutableArray<XFXMLNode *> *depsN;
@property (nonatomic, strong) NSMutableArray *deps;
@end

@implementation XFMIPNodeCache
@end

@interface XFMIPBinding ()
@property (nonatomic, strong, readwrite) XFBinding *binding;
@property (nonatomic, copy, readwrite) NSString *expression;
@property (nonatomic, strong) NSMutableArray<XFMIPNodeCache *> *nodes;
@end

@implementation XFMIPBinding

+ (instancetype)mipBindingWithExpression:(NSString *)expression error:(NSError **)error
{
    return [self mipBindingWithExpression:expression element:nil error:error];
}

+ (instancetype)mipBindingWithExpression:(NSString *)expression
                                 element:(XFXMLElement *)element
                                   error:(NSError **)error
{
    XFBinding *binding = [XFBinding bindingWithExpression:expression element:element error:error];
    if (binding == nil) {
        return nil;
    }
    XFMIPBinding *mip = [[self alloc] init];
    mip.binding = binding;
    mip.expression = expression;
    mip.nodes = [NSMutableArray array];
    return mip;
}

- (XFMIPNodeCache *)cacheForNode:(XFXMLNode *)node create:(BOOL)create
{
    for (XFMIPNodeCache *entry in self.nodes) {
        if (entry.node == node) {
            return entry;
        }
    }
    if (!create) {
        return nil;
    }
    XFMIPNodeCache *entry = [[XFMIPNodeCache alloc] init];
    entry.node = node;
    entry.depsN = [NSMutableArray array];
    entry.deps = [NSMutableArray array];
    [self.nodes addObject:entry];
    return entry;
}

- (BOOL)needsRebuild:(XFMIPNodeCache *)entry model:(XFModel *)model
{
    if (!model.ready || entry.depsN.count == 0) {
        return YES;
    }
    if (model.rebuilded || model.pendingRebuild) {
        return YES;
    }
    for (XFXMLNode *dep in entry.depsN) {
        // XsltForms_mipbinding.evaluate: a dependency that was deleted
        // (nodeName === "") forces a re-evaluation
        if ([dep kind] != XFXMLDocumentKind && [dep parent] == nil) {
            return YES;
        }
        if ([model.nodesChanged indexOfObjectIdenticalTo:dep] != NSNotFound) {
            return YES;
        }
        if ([model.pendingNodesChanged indexOfObjectIdenticalTo:dep] != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

- (XFXPathValue *)evaluateInContext:(XFExprContext *)context
                               node:(XFXMLNode *)node
                              model:(XFModel *)model
                              error:(NSError **)error
{
    XFMIPNodeCache *entry = [self cacheForNode:node create:YES];
    if (![self needsRebuild:entry model:model] && entry.result) {
        return entry.result;
    }

    XFExprContext *eval = [context cloneWithNode:node
                                        position:context.position
                                        nodeList:context.nodeList];
    [entry.depsN removeAllObjects];
    [entry.deps removeAllObjects];

    NSError *inner = nil;
    XFXPathValue *value = [self.binding evaluateInContext:eval error:&inner];
    if (inner && error) {
        *error = inner;
    }
    for (XFXMLNode *dep in eval.dependencyNodes) {
        if (![entry.depsN containsObject:dep]) {
            [entry.depsN addObject:dep];
        }
    }
    if (model && ![entry.deps containsObject:model]) {
        [entry.deps addObject:model];
    }
    entry.result = value;
    return value;
}

- (void)disposeNode:(XFXMLNode *)node
{
    NSUInteger i = 0;
    while (i < self.nodes.count) {
        if (self.nodes[i].node == node) {
            [self.nodes removeObjectAtIndex:i];
        } else {
            i++;
        }
    }
}

@end
