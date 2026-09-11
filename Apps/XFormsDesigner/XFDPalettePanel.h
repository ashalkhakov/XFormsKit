/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/// The Xcode-library-style palette: a modal panel opened by + with a
/// search field over category-sectioned rows (badge icon, tag name,
/// description). Tags the current insert target refuses are dimmed and
/// unselectable; Insert (or double-click) returns the chosen tag.
#pragma once
#import <AppKit/AppKit.h>

@interface XFDPalettePanel : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
+ (NSString *)runWithValidNames:(NSSet *)validNames parentName:(NSString *)parentName;
@end

void XFDPalettePanelFilePresent(void);
