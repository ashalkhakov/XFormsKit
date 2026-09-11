#import <XFormsKit/XFAbstractAction.h>

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_dispatch.
@interface XFDispatchAction : XFAbstractAction

@property (nonatomic, copy, readonly, nullable) NSString *name;
@property (nonatomic, copy, readonly, nullable) NSString *targetID;

@end

/// `xf:show` / `xf:hide` (show-hide.xsl): a dispatch of xforms-dialog-open /
/// xforms-dialog-close at the `@dialog` target — G-93.
@interface XFShowHideAction : XFDispatchAction
@end

NS_ASSUME_NONNULL_END
