/* A part of the designer over a form editor: its view from the XIB of
   its class's name in this framework, and the form editor's news (it is
   an observer from the start). The outline, the preview, the inspectors,
   the library and the events console are parts; whoever shows them
   (XFDWindowController, an IDE's editor) puts their views where it
   likes.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>
#import "XFDFormEditor.h"

NS_ASSUME_NONNULL_BEGIN

@interface XFDPartViewController : NSViewController <XFDFormEditorObserver>

/// The part over `formEditor`, its view from the XIB of its class's name.
- (instancetype)initWithFormEditor:(XFDFormEditor *)formEditor;
/// Its view from `nibName` (in this framework) instead.
- (instancetype)initWithFormEditor:(XFDFormEditor *)formEditor nibName:(NSString *)nibName NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, weak, readonly) XFDFormEditor *formEditor;

/// The framework's bundle, where the parts' XIBs are.
+ (NSBundle *)designKitBundle;

/// The view loaded: what a part sets up once its outlets are connected.
/// The default does nothing.
- (void)viewDidLoadFromNib;

@end

NS_ASSUME_NONNULL_END
