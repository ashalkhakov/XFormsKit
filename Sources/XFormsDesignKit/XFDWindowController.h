/* XFormsDesigner's document window (XFDDocumentWindow.xib), Xcode's
   three panes: the outline on the left, the preview in the middle, the
   inspectors on the right. It puts the form editor's parts there
   (XFDOutlineViewController, XFDPreviewViewController,
   XFDInspectorViewController), gives the window its document's undo,
   and takes the Form menu's commands to them.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>
#import "XFDFormEditor.h"

NS_ASSUME_NONNULL_BEGIN

@class XFDOutlineViewController, XFDPreviewViewController, XFDInspectorViewController;

@interface XFDWindowController : NSWindowController <NSSplitViewDelegate, XFDFormEditorDelegate>

/// The window over `formEditor`'s parts; nil when its XIB is missing.
- (nullable instancetype)initWithFormEditor:(XFDFormEditor *)formEditor;

@property (nonatomic, strong, readonly) XFDFormEditor *formEditor;
@property (nonatomic, strong, readonly) XFDOutlineViewController *outlineViewController;
@property (nonatomic, strong, readonly) XFDPreviewViewController *previewViewController;
@property (nonatomic, strong, readonly) XFDInspectorViewController *inspectorViewController;

/// The panes the parts' views go in.
@property (nonatomic, strong) IBOutlet NSView *outlineHost;
@property (nonatomic, strong) IBOutlet NSView *editorHost;
@property (nonatomic, strong) IBOutlet NSView *inspectorHost;

/// The Form menu's (XFDDocument +formMenuItem).
- (IBAction)insertElement:(nullable id)sender;
- (IBAction)deleteElement:(nullable id)sender;
- (IBAction)resetInstances:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
