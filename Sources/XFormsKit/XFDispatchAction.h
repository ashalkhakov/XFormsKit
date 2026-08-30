#import <XFormsKit/XFAbstractAction.h>

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_dispatch.
@interface XFDispatchAction : XFAbstractAction

@property (nonatomic, copy, readonly, nullable) NSString *name;
@property (nonatomic, copy, readonly, nullable) NSString *targetID;

@end

NS_ASSUME_NONNULL_END
