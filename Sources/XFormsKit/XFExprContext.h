#import <Foundation/Foundation.h>

@class NSXMLNode;
@class XFModel;
@class XFNSResolver;
@class XFXPathValue;

NS_ASSUME_NONNULL_BEGIN

@interface XFExprContext : NSObject <NSCopying>

@property (nonatomic, strong, nullable) NSXMLNode *contextNode;
@property (nonatomic, strong, nullable) NSXMLNode *currentNode;
@property (nonatomic, copy, nullable) NSArray<NSXMLNode *> *nodeList;
@property (nonatomic, assign) NSUInteger position; // 1-based
@property (nonatomic, assign) NSUInteger size;
@property (nonatomic, weak, nullable) XFModel *model;
@property (nonatomic, strong, nullable) XFNSResolver *nsResolver;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, XFXPathValue *> *variables;
@property (nonatomic, strong, readonly) NSHashTable *dependencies;
@property (nonatomic, strong, readonly) NSHashTable *depElements;

- (instancetype)initWithNode:(nullable NSXMLNode *)node;

- (instancetype)cloneWithNode:(nullable NSXMLNode *)node
                     position:(NSUInteger)position
                     nodeList:(nullable NSArray<NSXMLNode *> *)nodeList;

- (void)addDependency:(NSXMLNode *)node;
- (void)addDepElement:(id)element;
- (NSArray<NSXMLNode *> *)dependencyNodes;

@end

NS_ASSUME_NONNULL_END
