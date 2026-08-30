#import <XFormsKit/XFAbstractAction.h>

@class XFBinding;
@class XFXPath;

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_setvalue.
@interface XFSetvalueAction : XFAbstractAction

@property (nonatomic, strong, readonly, nullable) XFBinding *binding;
@property (nonatomic, strong, readonly, nullable) XFXPath *valueExpr;
@property (nonatomic, copy, readonly, nullable) NSString *literal;

@end

/// XsltForms_setvar: `xf:setvar name="x" value="…"` (and `xf:var` inside an
/// action): publishes the value into the enclosing action's variable
/// scope (G-77).
@interface XFSetvarAction : XFAbstractAction
@property (nonatomic, copy, readonly) NSString *name;
@end

/// Translation of XsltForms_setnode (XSLTForms extension, G-95): parse the
/// XML text of `@inner` (replace the bound node's content) or `@outer`
/// (replace the node itself), then rebuild.
@interface XFSetnodeAction : XFAbstractAction
@property (nonatomic, strong, readonly, nullable) XFBinding *binding;
@property (nonatomic, assign, readonly) BOOL inner;
@end

NS_ASSUME_NONNULL_END
