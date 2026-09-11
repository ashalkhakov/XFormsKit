#import <XFormsKit/XFControl.h>
#import <XFormsKit/XFXMLTypes.h>

NS_ASSUME_NONNULL_BEGIN

/// `xf:range` — numeric binding with start/end/step. AppKit: NSSlider.
@interface XFRangeControl : XFControl

@property (nonatomic, assign) double start;
@property (nonatomic, assign) double end;
@property (nonatomic, assign) double step;
@property (nonatomic, assign) double numericValue;
/// The bound value lies outside [start, end] (the CSS :out-of-range
/// state; announced by xforms-in-range / xforms-out-of-range).
@property (nonatomic, assign, readonly) BOOL outOfRange;

+ (nullable instancetype)rangeWithElement:(XFXMLElement *)element
                                    model:(nullable id)model
                                    error:(NSError **)error;

- (BOOL)commitNumericValue:(double)value error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
