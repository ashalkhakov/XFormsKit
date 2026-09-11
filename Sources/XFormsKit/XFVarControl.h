#import <XFormsKit/XFControl.h>
#import <XFormsKit/XFXMLTypes.h>

NS_ASSUME_NONNULL_BEGIN

@class XFXPathValue;

/// Translation of XsltForms_var (`xf:var name="x" value="…"` inside UI
/// markup): evaluated with its siblings during the refresh and published to
/// the enclosing variable scope, so `$x` in following expressions of the
/// same scope resolves to it (G-77). Never laid out.
@interface XFVarControl : XFControl

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, strong, readonly, nullable) XFXPathValue *value;

+ (nullable instancetype)varWithElement:(XFXMLElement *)element
                                  model:(nullable id)model
                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
