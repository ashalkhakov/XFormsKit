#import <XFormsKit/XFAbstractAction.h>

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_message. Records the text instead of alerting.
@interface XFMessageAction : XFAbstractAction

@property (nonatomic, copy, readonly, nullable) NSString *level;
@property (nonatomic, copy, readonly, nullable) NSString *lastText;

@end

NS_ASSUME_NONNULL_END
