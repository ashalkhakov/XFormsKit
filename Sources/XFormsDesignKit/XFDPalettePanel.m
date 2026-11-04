/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDPalettePanel.h"
#import "XFDPartViewController.h"
#import "XFDXPathField.h"

@implementation XFDPalettePanel {
    XFDLibraryViewController *_library;
    NSArray *_topLevelObjects;
    NSString *_result;
}

/// The panel from its XIB, the library in it.
- (BOOL)loadWithValidNames:(NSSet *)validNames parentName:(NSString *)parentName
{
    NSArray *objects = nil;
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"XFDPalettePanel"
                                          bundle:[XFDPartViewController designKitBundle]];
    if (![nib instantiateWithOwner:self topLevelObjects:&objects] || self.panel == nil) {
        NSLog(@"XFormsDesignKit: XFDPalettePanel did not load");
        return NO;
    }
    _topLevelObjects = objects;
    [self.panel setTitle:[NSString stringWithFormat:@"Insert into %@", parentName]];
    _library = [[XFDLibraryViewController alloc] initWithFormEditor:nil];
    _library.delegate = self;
    NSView *view = [_library view];
    [view setFrame:[self.libraryHost bounds]];
    [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [self.libraryHost addSubview:view];
    _library.validNames = validNames ?: [NSSet set];
    return YES;
}

- (void)library:(XFDLibraryViewController *)library didChooseName:(NSString *)name
{
    (void)library;
    (void)name;
    [self insertClicked:nil];
}

- (void)librarySelectionDidChange:(XFDLibraryViewController *)library
{
    [self.insertButton setEnabled:library.selectedName != nil];
}

- (IBAction)insertClicked:(id)sender
{
    (void)sender;
    _result = _library.selectedName;
    if (_result == nil) {
        XFDBeep();
        return;
    }
    [NSApp stopModal];
    [self.panel orderOut:nil];
}

- (IBAction)cancelClicked:(id)sender
{
    (void)sender;
    _result = nil;
    [NSApp abortModal];
    [self.panel orderOut:nil];
}

/// The title bar's close button is Cancel.
- (BOOL)windowShouldClose:(id)sender
{
    [self cancelClicked:sender];
    return NO;
}

+ (NSString *)runWithValidNames:(NSSet *)validNames parentName:(NSString *)parentName
{
    XFDPalettePanel *palette = [[XFDPalettePanel alloc] init];
    if (![palette loadWithValidNames:validNames parentName:parentName]) {
        return nil;
    }
    [palette.panel center];
    [palette.panel makeFirstResponder:palette->_library.filterField];
    [NSApp runModalForWindow:palette.panel];
    return palette->_result;
}

@end
