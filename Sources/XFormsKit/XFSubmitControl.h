#import <XFormsKit/XFTriggerControl.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFXPath;

NS_ASSUME_NONNULL_BEGIN

/// `xf:submit` — trigger whose default activation sends xforms-submit.
@interface XFSubmitControl : XFTriggerControl

/// jsgen/submit.xsl: the DOMActivate handler is a dispatch of
/// xforms-submit guarded by @if / @while (G-47).
@property (nonatomic, strong, readonly, nullable) XFXPath *ifExpr;
@property (nonatomic, strong, readonly, nullable) XFXPath *whileExpr;
@property (nonatomic, copy, nullable) NSString *submissionID;

+ (nullable instancetype)submitWithElement:(XFXMLElement *)element
                                     model:(nullable id)model
                                     error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
