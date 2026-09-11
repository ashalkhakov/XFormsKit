#import <XFormsKit/XFAbstractAction.h>

@class XFSubmission;

NS_ASSUME_NONNULL_BEGIN

/// `xf:send` — XForms 1.1 §10.15. Dispatches `xforms-submit` to a submission
/// (XSLTForms compiles send to the same dispatch).
@interface XFSendAction : XFAbstractAction

@property (nonatomic, copy, readonly, nullable) NSString *submissionID;

@end

NS_ASSUME_NONNULL_END
