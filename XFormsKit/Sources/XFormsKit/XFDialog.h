#import <XFormsKit/XFGroup.h>

NS_ASSUME_NONNULL_BEGIN

/// `xf:dialog` (dialog.xsl: a `div.xforms-dialog` whose label is the
/// title, hidden until `xforms-dialog-open` is dispatched at it by `xf:show`
/// and hidden again by `xforms-dialog-close` / `xf:hide`) — G-93. The
/// engine only tracks `shown`; the host's `dialogRequestHandler` presents
/// the dialog's content (its `hostNodes`) in a sheet or panel.
@interface XFDialog : XFGroup

/// YES between xforms-dialog-open and xforms-dialog-close.
@property (nonatomic, assign, readonly) BOOL shown;

+ (nullable instancetype)dialogWithElement:(NSXMLElement *)element
                                     model:(nullable id)model
                                     error:(NSError **)error;

/// XsltForms_browser.dialog.show / hide (default actions of the events).
- (void)show;
- (void)hide;

@end

NS_ASSUME_NONNULL_END
