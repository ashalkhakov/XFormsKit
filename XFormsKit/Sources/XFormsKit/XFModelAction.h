#import <XFormsKit/XFAbstractAction.h>

NS_ASSUME_NONNULL_BEGIN

/// `xf:rebuild` / `recalculate` / `revalidate` / `refresh` / `reset`.
/// Dispatches the corresponding model event (XSLTForms compiles these to dispatch).
@interface XFModelAction : XFAbstractAction

@property (nonatomic, copy, readonly) NSString *eventName;

@end

NS_ASSUME_NONNULL_END
