#import <XFormsKit/XFControl.h>

NS_ASSUME_NONNULL_BEGIN

/// `xf:range` — numeric binding with start/end/step. AppKit: NSSlider.
@interface XFRangeControl : XFControl

@property (nonatomic, assign) double start;
@property (nonatomic, assign) double end;
@property (nonatomic, assign) double step;
@property (nonatomic, assign) double numericValue;

+ (nullable instancetype)rangeWithElement:(NSXMLElement *)element
                                    model:(nullable id)model
                                    error:(NSError **)error;

- (BOOL)commitNumericValue:(double)value error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
