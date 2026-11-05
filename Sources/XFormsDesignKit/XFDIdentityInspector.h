/* The Identity inspector (XFDIdentityInspector.xib): what the selection
   is, and its id.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import "XFDPartViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface XFDIdentityInspector : XFDPartViewController

@property (nonatomic, strong) IBOutlet NSTextField *identityTitleField;
@property (nonatomic, strong) IBOutlet NSTextField *identityIdField;

/// The id field applied to the selection.
- (IBAction)inspectorChanged:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
