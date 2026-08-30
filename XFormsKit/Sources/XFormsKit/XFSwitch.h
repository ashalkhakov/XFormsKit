#import <XFormsKit/XFControl.h>

@class XFHostNode;

NS_ASSUME_NONNULL_BEGIN

@interface XFCase : XFControl
@property (nonatomic, assign) BOOL selected;
@property (nonatomic, copy, readonly) NSArray<XFControl *> *children;
/// Host-markup tree of the case content (G-20).
@property (nonatomic, copy, readonly) NSArray<XFHostNode *> *hostNodes;
- (void)addChild:(XFControl *)child;
- (void)removeChild:(XFControl *)child;
- (BOOL)rebuildHostNodesWithError:(NSError **)error;
@end

/// XForms `xf:switch` / `xf:case`. Toggle selects a case by id.
@interface XFSwitch : XFControl

@property (nonatomic, copy, readonly) NSArray<XFCase *> *cases;
@property (nonatomic, weak, nullable, readonly) XFCase *selectedCase;

+ (nullable instancetype)switchWithElement:(NSXMLElement *)element
                                     model:(nullable id)model
                                     error:(NSError **)error;

- (nullable XFCase *)caseWithIdentifier:(NSString *)identifier;
- (void)selectCase:(XFCase *)caze;

@end

NS_ASSUME_NONNULL_END
