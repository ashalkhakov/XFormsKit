/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/// The + palette: the library (XFDLibraryViewController) in a modal panel
/// (XFDPalettePanel.xib) with Cancel and Insert. Tags the insert target
/// refuses are dimmed and unselectable; Insert (or a double click)
/// returns the chosen tag.
#pragma once
#import <AppKit/AppKit.h>
#import "XFDLibraryViewController.h"

@interface XFDPalettePanel : NSObject <XFDLibraryDelegate, NSWindowDelegate>

@property (nonatomic, strong) IBOutlet NSPanel *panel;
@property (nonatomic, strong) IBOutlet NSView *libraryHost;
@property (nonatomic, strong) IBOutlet NSButton *insertButton;

+ (NSString *)runWithValidNames:(NSSet *)validNames parentName:(NSString *)parentName;

- (IBAction)insertClicked:(id)sender;
- (IBAction)cancelClicked:(id)sender;

@end
