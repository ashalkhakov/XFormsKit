#import <XFormsKit/XFAbstractAction.h>

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_toggle / XForms 1.1 §10.6.
@interface XFToggleAction : XFAbstractAction

@property (nonatomic, copy, readonly, nullable) NSString *caseID;
@property (nonatomic, copy, readonly, nullable) NSString *lastCaseID;

@end

NS_ASSUME_NONNULL_END
