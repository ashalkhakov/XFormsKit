#import <XFormsKit/XFControl.h>
#import <XFormsKit/XFXMLTypes.h>

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_trigger. Activation dispatches DOMActivate.
@interface XFTriggerControl : XFControl

+ (nullable instancetype)triggerWithElement:(XFXMLElement *)element
                                      model:(nullable id)model
                                      error:(NSError **)error;

- (void)activate;

@end

NS_ASSUME_NONNULL_END
