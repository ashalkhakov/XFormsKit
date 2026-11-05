/* The library of what can go in a form (XFDLibrary.xib), as Xcode's is:
   the catalogue (XFDPaletteCatalog) in its categories, each tag with its
   badge and what it is, filtered as you type. Tags that can go nowhere
   near the selection are dimmed and cannot be chosen. A double click
   chooses one: the delegate is told, and with none it is inserted where
   it can go nearest the selection.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class XFDFormEditor, XFDLibraryViewController;

@protocol XFDLibraryDelegate <NSObject>
/// A tag chosen (a double click).
- (void)library:(XFDLibraryViewController *)library didChooseName:(NSString *)name;
@optional
/// The row selected changed (what can be chosen now: -selectedName).
- (void)librarySelectionDidChange:(XFDLibraryViewController *)library;
@end

@interface XFDLibraryViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>

/// The library of `formEditor`'s form, what it offers its selection's.
- (instancetype)initWithFormEditor:(nullable XFDFormEditor *)formEditor;

@property (nonatomic, strong) IBOutlet NSTextField *filterField;
@property (nonatomic, strong) IBOutlet NSTableView *table;

@property (nonatomic, weak, readonly, nullable) XFDFormEditor *formEditor;
@property (nonatomic, weak, nullable) id<XFDLibraryDelegate> delegate;
/// The tags that can be chosen (the rest are dimmed); the form editor's
/// selection's, each time the view is shown, when there is one.
@property (nonatomic, copy) NSSet<NSString *> *validNames;
/// The tag of the row selected, when it can be chosen.
@property (nonatomic, readonly, nullable) NSString *selectedName;

/// The rows made again: the filter as typed, and the tags the selection
/// takes now.
- (void)reload;
- (IBAction)rowDoubleClicked:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
