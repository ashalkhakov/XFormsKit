#import "XFControl.h"
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface XFOutputControl : XFControl
@property (nonatomic, copy, nullable) NSString *mediaType;
@property (nonatomic, assign, readonly) BOOL displaysImage;
@property (nonatomic, assign, readonly) BOOL displaysHTML;
- (nullable NSData *)imageData;
/// The size to show a picture of `natural` size at.
///
/// XFOutput.js writes an `<img>`, so the picture shows at its natural
/// size — but a swatch (the 1x1 data-URI pixel in Samples/output-image.xhtml
/// is a real one) would then be a single invisible point, and a photograph
/// would take the whole screen. So a tiny picture is scaled UP to a
/// visible square and a large one is capped. Both view layers ask this,
/// so a picture is the same size on a Mac and on a phone.
+ (CGSize)displaySizeForImageOfNaturalSize:(CGSize)natural;
@end

NS_ASSUME_NONNULL_END
