#import <XFormsKit/XFAbstractAction.h>

NS_ASSUME_NONNULL_BEGIN

/// XForms 1.1 §10.7 `xf:setfocus`.
@interface XFSetfocusAction : XFAbstractAction

@property (nonatomic, copy, readonly, nullable) NSString *controlID;
@property (nonatomic, weak, readonly, nullable) id lastFocused;

@end

NS_ASSUME_NONNULL_END
