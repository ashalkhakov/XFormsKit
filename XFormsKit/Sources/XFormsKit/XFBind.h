#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFModel;
@class XFBinding;
@class XFMIPBinding;
@class XFXPath;

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_bind.
///
/// `refresh` re-evaluates the nodeset, records XPath dependencies, tags
/// each selected node with this bind, applies `@type`, and walks child
/// binds. `recalculate` writes `@calculate`. Boolean MIPs are applied
/// during instance `revalidate` (XsltForms_instance.validate_).
@interface XFBind : NSObject

@property (nonatomic, copy, nullable) NSString *identifier;
@property (nonatomic, strong, readonly) XFXMLElement *element;
@property (nonatomic, weak, nullable) XFModel *model;
@property (nonatomic, weak, nullable) XFBind *parent;
@property (nonatomic, strong, readonly, nullable) XFBinding *nodesetBinding;
@property (nonatomic, copy, nullable) NSString *typeName;
@property (nonatomic, strong, nullable) XFXPath *calculate;
@property (nonatomic, strong, nullable) XFMIPBinding *relevant;
@property (nonatomic, strong, nullable) XFMIPBinding *required;
@property (nonatomic, strong, nullable) XFMIPBinding *readonly;
@property (nonatomic, strong, nullable) XFMIPBinding *constraint;
@property (nonatomic, strong, readonly) NSMutableArray<XFXMLNode *> *nodes;
@property (nonatomic, strong, readonly) NSMutableArray<XFXMLNode *> *depsNodes;
@property (nonatomic, strong, readonly) NSMutableArray *depsElements;
@property (nonatomic, strong, readonly) NSMutableArray<XFBind *> *binds;
@property (nonatomic, assign) NSInteger depsId;

/// XsltForms_mipbinding.nodedispose: drop the MIP caches of every bind that
/// selected `node` (and its subtree) before the node is deleted.
+ (void)disposeNode:(XFXMLNode *)node model:(XFModel *)model;

+ (nullable instancetype)bindWithElement:(XFXMLElement *)element
                                   model:(XFModel *)model
                                  parent:(nullable XFBind *)parent
                                   error:(NSError **)error;

- (void)addBind:(XFBind *)bind;
- (void)clear;
- (void)refresh;
- (void)refreshWithContextNode:(nullable XFXMLNode *)ctx index:(NSUInteger)index;
- (void)recalculate;

@end

NS_ASSUME_NONNULL_END
