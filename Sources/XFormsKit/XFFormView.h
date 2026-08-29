#import <AppKit/AppKit.h>

@class XFProcessor;

NS_ASSUME_NONNULL_BEGIN

/// Lays out the current slice's xf:input / xf:output controls as labeled
/// AppKit fields. Shared between GNUstep GUI and Apple AppKit.
@interface XFFormView : NSView

@property (nonatomic, strong, readonly) XFProcessor *processor;

- (instancetype)initWithProcessor:(XFProcessor *)processor;

- (void)reloadFromProcessor;

@end

NS_ASSUME_NONNULL_END
