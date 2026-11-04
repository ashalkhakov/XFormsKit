/* The form running (XFDPreviewViewController.xib): the live preview of
   the form editor's processor, its design mode (the devtools-style
   element picker:
   a click selects the element under it, a drag moves it), and the form's
   XML in a Source tab with Apply. A host that keeps the text itself turns
   the source off (showsSource), and one that shows the events console in
   a pane of its own its button (showsEventsConsoleButton).
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import "XFDPartViewController.h"
#import "XFDDesignOverlay.h"

NS_ASSUME_NONNULL_BEGIN

@interface XFDPreviewViewController : XFDPartViewController <XFDDesignOverlayDelegate>

@property (nonatomic, strong) IBOutlet NSSegmentedControl *modeControl;
@property (nonatomic, strong) IBOutlet NSButton *designModeCheckbox;
@property (nonatomic, strong) IBOutlet NSButton *consoleButton;
@property (nonatomic, strong) IBOutlet NSTabView *centerTabView;
@property (nonatomic, strong) IBOutlet NSView *previewHost;
@property (nonatomic, strong) IBOutlet NSView *sourceHost;

/// The form view, the overlay over it, the source text: made in code
/// (the form view is the processor's; the XIB keeps their hosts).
@property (nonatomic, strong, readonly, nullable) XFFormView *formView;
@property (nonatomic, strong, readonly) XFDDesignOverlay *designOverlay;
@property (nonatomic, strong, readonly) NSTextView *sourceView;

/// Form / Source; NO: the form only. YES by default.
@property (nonatomic) BOOL showsSource;
/// The Events Console button beside Design. YES by default.
@property (nonatomic) BOOL showsEventsConsoleButton;

- (IBAction)modeChanged:(nullable id)sender;
- (IBAction)toggleDesignMode:(nullable id)sender;
- (IBAction)toggleEventsConsole:(nullable id)sender;
/// The source tab's text read as the form.
- (IBAction)applySource:(nullable id)sender;
/// The preview's instance data fresh.
- (IBAction)resetInstances:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
