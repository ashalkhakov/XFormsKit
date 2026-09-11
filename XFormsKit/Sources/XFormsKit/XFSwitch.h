#import <XFormsKit/XFControl.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFHostNode;

@class XFBinding;

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
/// `caseref`: the node whose value is the selected case id (G-26).
@property (nonatomic, strong, readonly, nullable) XFBinding *caserefBinding;
/// XSLTForms case.xsl: the initially selected case gets xforms-select
/// once at start-up (not with caseref).
- (void)dispatchInitialSelect;

+ (nullable instancetype)switchWithElement:(XFXMLElement *)element
                                     model:(nullable id)model
                                     error:(NSError **)error;

- (nullable XFCase *)caseWithIdentifier:(NSString *)identifier;
- (void)selectCase:(XFCase *)caze;

@end

NS_ASSUME_NONNULL_END
