/* The Identity inspector (XFDIdentityInspector.xib): what the selection
   is, and its id, its fields bound to the selection's editor (its editor
   controller's content), the id validated there.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import "XFDPartViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class XFDElementEditor;

@interface XFDIdentityInspector : XFDPartViewController

@property (nonatomic, strong) IBOutlet NSTextField *identityTitleField;
@property (nonatomic, strong) IBOutlet NSTextField *identityIdField;
/// What the fields are bound to: `content.title`, `content.identifier`.
@property (nonatomic, strong) IBOutlet NSObjectController *editorController;

/// The selection's editor, the controller's content.
@property (nonatomic, strong, readonly, nullable) XFDElementEditor *editor;

@end

NS_ASSUME_NONNULL_END
