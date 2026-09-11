#import <XFormsKit/XFControl.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFModel;
@class XFHostNode;

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_group: optional single-node binding, relevance,
/// child controls refreshed against the bound node.
@interface XFGroup : XFControl

@property (nonatomic, copy, readonly) NSArray<XFControl *> *children;
/// Host-markup tree of the group's content (G-20); `children` are the
/// controls found in it, document order.
@property (nonatomic, copy, readonly) NSArray<XFHostNode *> *hostNodes;

+ (nullable instancetype)groupWithElement:(XFXMLElement *)element
                                    model:(nullable id)model
                                    error:(NSError **)error;

- (void)addChild:(XFControl *)child;
- (void)removeChild:(XFControl *)child;
/// Rebuild `hostNodes` from the live element, reusing existing children
/// and instantiating controls for new elements.
- (BOOL)rebuildHostNodesWithError:(NSError **)error;

@end

/// `xf:component/@resource` (XFComponent.js, G-95): a bound group whose
/// content is the XForms document at `resource`, embedded as a subform
/// (G-90) once the main form is ready; `subform-context()` inside it is the
/// component's bound node.
@interface XFComponentControl : XFGroup
@property (nonatomic, copy, readonly, nullable) NSString *resource;
+ (nullable instancetype)componentWithElement:(XFXMLElement *)element
                                        model:(nullable id)model
                                        error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
