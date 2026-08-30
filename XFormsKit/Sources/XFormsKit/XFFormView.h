#import <AppKit/AppKit.h>

@class XFProcessor;
@class XFGroup;

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
/// A view for the content of one container only (an `xf:dialog` shown by
/// the host, G-93); nil lays out the whole host body.
- (instancetype)initWithProcessor:(XFProcessor *)processor rootGroup:(nullable XFGroup *)rootGroup;
@property (nonatomic, strong, readonly, nullable) XFGroup *rootGroup;

/// Refresh the controls, rebuild the widgets and call instanceChangedHandler.
- (void)reloadFromProcessor;
/// Rebuild the widgets from the current control state only (for a host
/// that refreshed the processor itself, e.g. after another view's edit).
- (void)rebuildWidgets;

@end

NS_ASSUME_NONNULL_END
