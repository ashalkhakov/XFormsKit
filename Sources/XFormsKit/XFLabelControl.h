#import "XFControl.h"

NS_ASSUME_NONNULL_BEGIN

/// Standalone `xf:label` (XsltForms_label). Caption labels that are the
/// first child of another control are not instantiated; only labels that
/// carry `ref`/`value` or sit outside a control become XFLabelControl.
@interface XFLabelControl : XFControl

+ (nullable instancetype)labelWithElement:(NSXMLElement *)element
                                    model:(nullable id)model
                                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
