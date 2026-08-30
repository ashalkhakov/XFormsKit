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

NS_ASSUME_NONNULL_END
