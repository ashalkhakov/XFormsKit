#import <XFormsKit/XFAbstractAction.h>

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_message. Records the text instead of alerting.
@interface XFMessageAction : XFAbstractAction

/// `level`: modal (default) | modeless | ephemeral (G-51).
@property (nonatomic, copy, readonly, nullable) NSString *level;
@property (nonatomic, copy, readonly, nullable) NSString *lastText;

@end

/// Translation of XsltForms_confirm (`ajx:confirm`, G-95): shows the text
/// like xf:message and asks the host (`confirmHandler`) whether to go on;
/// a refusal stops the event's propagation so the following actions of the
/// handler do not run. Without a handler the answer is YES.
@interface XFConfirmAction : XFMessageAction
@property (nonatomic, assign, readonly) BOOL lastAnswer;
@end

NS_ASSUME_NONNULL_END
