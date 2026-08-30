#import <Foundation/Foundation.h>

@class XFModel;
@class XFBinding;
@class XFMIPBinding;
@class XFXPath;
@class NSXMLElement;
@class NSXMLNode;

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_bind.
@interface XFBind : NSObject

@property (nonatomic, copy, nullable) NSString *identifier;
@property (nonatomic, strong, readonly) NSXMLElement *element;
@property (nonatomic, weak, nullable) XFModel *model;
@property (nonatomic, weak, nullable) XFBind *parent;
@property (nonatomic, strong, readonly, nullable) XFBinding *nodesetBinding;
@property (nonatomic, copy, nullable) NSString *typeName;
@property (nonatomic, strong, nullable) XFXPath *calculate;
@property (nonatomic, strong, nullable) XFMIPBinding *relevant;
@property (nonatomic, strong, nullable) XFMIPBinding *required;
@property (nonatomic, strong, nullable) XFMIPBinding *readonly;
@property (nonatomic, strong, nullable) XFMIPBinding *constraint;
@property (nonatomic, strong, readonly) NSMutableArray<NSXMLNode *> *nodes;
@property (nonatomic, strong, readonly) NSMutableArray<NSXMLNode *> *depsNodes;
@property (nonatomic, strong, readonly) NSMutableArray *depsElements;
@property (nonatomic, strong, readonly) NSMutableArray<XFBind *> *binds;
@property (nonatomic, assign) NSInteger depsId;

+ (nullable instancetype)bindWithElement:(NSXMLElement *)element
                                   model:(XFModel *)model
                                  parent:(nullable XFBind *)parent
                                   error:(NSError **)error;

- (void)addBind:(XFBind *)bind;
- (void)clear;
- (void)refresh;
- (void)refreshWithContextNode:(nullable NSXMLNode *)ctx index:(NSUInteger)index;
- (void)recalculate;

@end

NS_ASSUME_NONNULL_END
