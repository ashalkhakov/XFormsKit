#import <Foundation/Foundation.h>

@class NSXMLNode;
@class XFModel;

NS_ASSUME_NONNULL_BEGIN

@interface XFExprContext : NSObject <NSCopying>

@property (nonatomic, strong, nullable) NSXMLNode *contextNode;
@property (nonatomic, assign) NSUInteger position; // 1-based
@property (nonatomic, assign) NSUInteger size;
@property (nonatomic, weak, nullable) XFModel *model;
@property (nonatomic, strong, readonly) NSHashTable *dependencies;

- (instancetype)initWithNode:(nullable NSXMLNode *)node;
- (void)addDependency:(NSXMLNode *)node;
- (NSArray<NSXMLNode *> *)dependencyNodes;

@end

NS_ASSUME_NONNULL_END
