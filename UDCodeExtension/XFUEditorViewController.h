/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import <UDCodeKit/UDWorkbench.h>
#import <UDCodeKit/UDEditorPanes.h>

@class UDCodeDocument;
@class XFDFormEditor, XFDOutlineViewController, XFDPreviewViewController;
@class XFDIdentityInspector, XFDAttributesInspector, XFDEventsInspector;
@class XFDLibraryViewController, XFDEventsConsoleViewController;

// A form's tab in UDCode (XFUEditor.xib): XFormsDesignKit's parts over a
// form editor of the text, spread over the window's panes as an Xcode
// editor's are (UDEditorPanes):
//
//   - the tab has the live preview (design mode too) and, on its left, the
//     Document Outline (the form's elements, with + and −);
//   - Identity, Attributes and Events are the inspector pane's tabs;
//   - the events console is a bottom-area pane, tracing while the tab
//     shows;
//   - the library of what can go in a form is the Library (⇧⌘L).
//
// The text is the form. Each change the designer makes is written back as
// one edit of the text (the lines it changed), so the text's undo undoes
// it; saving and the tab's dot are the document's; a diff shows what
// changed. The designer records no undo of its own. When the text changes
// some other way (undone, edited as text, reverted) it is read again, the
// element selected kept where it still is. A text that is no form shows
// why, and offers it as text.
@interface XFUEditorViewController : NSViewController <UDEditorPanes>

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench;

@property (nonatomic, readonly, strong) UDCodeDocument *document;
// The form editor, made for the first text that is a form; nil until then.
@property (nonatomic, readonly, strong) XFDFormEditor *formEditor;
// Why the text is no form, while it is not; nil while it is.
@property (nonatomic, readonly, copy) NSString *problem;

// The parts, once there is a form.
@property (nonatomic, readonly, strong) XFDOutlineViewController *outlineViewController;
@property (nonatomic, readonly, strong) XFDPreviewViewController *previewViewController;
@property (nonatomic, readonly, strong) XFDIdentityInspector *identityInspector;
@property (nonatomic, readonly, strong) XFDAttributesInspector *attributesInspector;
@property (nonatomic, readonly, strong) XFDEventsInspector *eventsInspector;
@property (nonatomic, readonly, strong) XFDLibraryViewController *libraryController;
@property (nonatomic, readonly, strong) XFDEventsConsoleViewController *consoleController;

// The text written now, if a change is waiting (it is written as the
// event that made it ends).
- (void)write;

// The Form menu (XFUEditorMenus.xib).
- (IBAction)insertElement:(id)sender;
- (IBAction)deleteElement:(id)sender;
- (IBAction)resetInstances:(id)sender;
// The document's text's undo, which every change of the form is part of.
- (IBAction)undo:(id)sender;
- (IBAction)redo:(id)sender;
// The document in a tab of its own, as XML.
- (IBAction)showAsText:(id)sender;

@end
