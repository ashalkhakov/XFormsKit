#import <AppKit/AppKit.h>

@class XFProcessor;

NS_ASSUME_NONNULL_BEGIN

/// Lays out the control tree with stock AppKit widgets
/// (NSTextField, NSSecureTextField, NSTextView, NSButton, NSPopUpButton,
/// NSSlider, NSBox, NSDatePicker). Shared between GNUstep GUI and Apple AppKit.
@interface XFFormView : NSView

@property (nonatomic, strong, readonly) XFProcessor *processor;
@property (nonatomic, copy, nullable) void (^documentReplaceHandler)(NSString *xml);
/// Called after any user interaction that went through the processor
/// (value commit, trigger, selection, ...): the instance data may have
/// changed, so hosts can refresh live views of it.
@property (nonatomic, copy, nullable) void (^instanceChangedHandler)(void);

- (instancetype)initWithProcessor:(XFProcessor *)processor;

- (void)reloadFromProcessor;

@end

NS_ASSUME_NONNULL_END
