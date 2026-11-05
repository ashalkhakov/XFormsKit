/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import <objc/runtime.h>
#import "XFDWindowController.h"
#import "XFDOutlineViewController.h"
#import "XFDPreviewViewController.h"
#import "XFDInspectorViewController.h"
#import "XFDPartViewController.h"

/// The window's nib in this framework's bundle, not the host app's: compiled
/// (.nib) by Xcode, the xib itself on GNUstep, which loads it through GSXib5.
static NSString *XFDWindowNibPath(void)
{
    NSBundle *bundle = [XFDPartViewController designKitBundle];
    return [bundle pathForResource:@"XFDDocumentWindow" ofType:@"nib"]
        ?: [bundle pathForResource:@"XFDDocumentWindow" ofType:@"xib"];
}

@implementation XFDWindowController

- (instancetype)initWithFormEditor:(XFDFormEditor *)formEditor
{
    NSString *path = XFDWindowNibPath();
    if (path == nil) {
        NSLog(@"XFormsDesignKit: XFDDocumentWindow is not in %@",
              [[XFDPartViewController designKitBundle] bundlePath]);
        return nil;
    }
    if ((self = [super initWithWindowNibPath:path owner:self])) {
        _formEditor = formEditor;
        formEditor.delegate = self;
        _outlineViewController = [[XFDOutlineViewController alloc] initWithFormEditor:formEditor];
        _previewViewController = [[XFDPreviewViewController alloc] initWithFormEditor:formEditor];
        _inspectorViewController = [[XFDInspectorViewController alloc] initWithFormEditor:formEditor];
    }
    return self;
}

/// A part's view filling its pane.
static void XFDPutView(NSView *view, NSView *host)
{
    [view setFrame:[host bounds]];
    [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [host addSubview:view];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    [[self window] setDelegate:(id)self];
    XFDPutView([self.outlineViewController view], self.outlineHost);
    XFDPutView([self.previewViewController view], self.editorHost);
    XFDPutView([self.inspectorViewController view], self.inspectorHost);
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window
{
    (void)window;
    return self.formEditor.undoManager;
}

#pragma mark What the parts ask (XFDFormEditorDelegate)

- (void)formEditorShowAttributes:(XFDFormEditor *)editor
{
    (void)editor;
    [self.inspectorViewController showInspector:(NSViewController *)self.inspectorViewController.attributesInspector];
}

- (void)formEditorDidApplySource:(XFDFormEditor *)editor
{
    (void)editor;
    [[self document] updateChangeCount:NSChangeDone];
}

#pragma mark The Form menu

- (IBAction)insertElement:(id)sender
{
    [self.outlineViewController insertElement:sender];
}

- (IBAction)deleteElement:(id)sender
{
    [self.outlineViewController deleteElement:sender];
}

- (IBAction)resetInstances:(id)sender
{
    [self.previewViewController resetInstances:sender];
}

- (void)undo:(id)sender
{
    (void)sender;
    [self.formEditor.undoManager undo];
}

- (void)redo:(id)sender
{
    (void)sender;
    [self.formEditor.undoManager redo];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    SEL action = [item action];
    if (sel_isEqual(action, @selector(undo:))) {
        return [self.formEditor.undoManager canUndo];
    }
    if (sel_isEqual(action, @selector(redo:))) {
        return [self.formEditor.undoManager canRedo];
    }
    if (sel_isEqual(action, @selector(insertElement:))) {
        return [self.formEditor insertParentForSelection:NULL] != nil;
    }
    if (sel_isEqual(action, @selector(deleteElement:))) {
        return [self.formEditor canDeleteSelection];
    }
    return YES;
}

#pragma mark The split view

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed
         ofSubviewAt:(NSInteger)index
{
    (void)splitView;
    (void)proposed;
    return index == 0 ? 180 : 420;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposed
         ofSubviewAt:(NSInteger)index
{
    if (index == 1) {
        return [splitView frame].size.width - 240;
    }
    return proposed;
}

@end
