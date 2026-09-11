#import <XFormsKit/XFAbstractAction.h>

NS_ASSUME_NONNULL_BEGIN

/// `xf:setindex` — XForms 1.1 §10.5. Sets the repeat index.
@interface XFSetindexAction : XFAbstractAction

@property (nonatomic, copy, readonly, nullable) NSString *repeatID;
@property (nonatomic, copy, readonly, nullable) NSString *indexExpression;

@end

NS_ASSUME_NONNULL_END
