#import <XFormsKit/XFTriggerControl.h>

NS_ASSUME_NONNULL_BEGIN

/// `xf:submit` — trigger whose default activation sends xforms-submit.
@interface XFSubmitControl : XFTriggerControl

@property (nonatomic, copy, nullable) NSString *submissionID;

+ (nullable instancetype)submitWithElement:(NSXMLElement *)element
                                     model:(nullable id)model
                                     error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
