#import <XFormsKit/XFControl.h>

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

+ (nullable instancetype)groupWithElement:(NSXMLElement *)element
                                    model:(nullable id)model
                                    error:(NSError **)error;

- (void)addChild:(XFControl *)child;
- (void)removeChild:(XFControl *)child;
/// Rebuild `hostNodes` from the live element, reusing existing children
/// and instantiating controls for new elements.
- (BOOL)rebuildHostNodesWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
