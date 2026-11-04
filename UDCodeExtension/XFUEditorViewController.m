/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFUEditorViewController.h"
#import <objc/runtime.h>
#import <UDCodeKit/UDCodeDocument.h>
#import <UDPieceTable/UDTextModel.h>
#import "XFormsDesignKit.h"
#import "XFDInspectorSpecs.h"
#import "XFUTextDiff.h"

// The Document Outline's width when the tab opens, and its narrowest.
static const CGFloat XFUOutlineWidth = 240;
static const CGFloat XFUOutlineMinimum = 160;

// The tab's view (XFUEditor.xib): its controller after it in the chain,
// wherever UDCode puts it, so the Editor menu's items and Undo reach the
// tab. AppKit puts a view controller there by itself (since 10.10);
// gnustep-gui does not; and a view put in another is given its superview
// as the next responder again. It tells its controller when it comes into
// a window and leaves it: the console traces while the tab shows.
@interface XFUEditorView : NSView
@property (nonatomic, weak) IBOutlet NSResponder *controller;
@end

@interface XFUEditorViewController (XFUShowing)
- (void)tabDidMoveToWindow:(NSWindow *)window;
@end

@implementation XFUEditorView

- (void)setNextResponder:(NSResponder *)responder {
  NSResponder *controller = self.controller;
  if (controller == nil || responder == controller) {
    [super setNextResponder:responder];
    return;
  }
  [controller setNextResponder:responder];
  [super setNextResponder:controller];
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  [(XFUEditorViewController *)self.controller tabDidMoveToWindow:[self window]];
}

@end

// The form editor's undo: none, the text's being the undo. Clearing an undo
// manager enables it again (-removeAllActions, on both platforms), and the
// form editor clears it on each read: this one stays off.
@interface XFUNoUndoManager : NSUndoManager
@end

@implementation XFUNoUndoManager

- (instancetype)init {
  if ((self = [super init])) {
    [self setGroupsByEvent:NO];
    [self disableUndoRegistration];
  }
  return self;
}

- (void)removeAllActions {
  [super removeAllActions];
  if ([self isUndoRegistrationEnabled])
    [self disableUndoRegistration];
}

@end

// An inspector's tab's image, as Xcode's are: its SF Symbol on macOS; on
// GNUstep, which has none, the designer's own badge.
static NSImage *XFUInspectorImage(NSViewController *inspector) {
#ifndef GNUSTEP
  NSDictionary *symbols = @{
    @"Identity" : @"person.text.rectangle",
    @"Attributes" : @"slider.horizontal.3",
    @"Events" : @"bolt",
  };
  NSString *symbol = symbols[inspector.title];
  if (symbol != nil && [NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)])
    return [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:inspector.title];
#endif
  NSImage *image = [[XFDInspectorViewController imageForInspector:inspector] copy];
  [image setSize:NSMakeSize(16, 16)];
  return image;
}

@interface XFUEditorViewController () <XFDFormEditorObserver, XFDFormEditorDelegate, XFDLibraryDelegate, NSSplitViewDelegate>
@property (nonatomic, weak) IBOutlet NSView *problemView;
@property (nonatomic, weak) IBOutlet NSTextField *problemLabel;
@property (nonatomic, weak) IBOutlet NSSplitView *split;
@property (nonatomic, weak) IBOutlet NSView *outlineHost;
@property (nonatomic, weak) IBOutlet NSView *previewHost;
@property (nonatomic, readwrite, strong) XFDFormEditor *formEditor;
@property (nonatomic, readwrite, copy) NSString *problem;
@property (nonatomic, readwrite, strong) XFDOutlineViewController *outlineViewController;
@property (nonatomic, readwrite, strong) XFDPreviewViewController *previewViewController;
@property (nonatomic, readwrite, strong) XFDIdentityInspector *identityInspector;
@property (nonatomic, readwrite, strong) XFDAttributesInspector *attributesInspector;
@property (nonatomic, readwrite, strong) XFDEventsInspector *eventsInspector;
@property (nonatomic, readwrite, strong) XFDLibraryViewController *libraryController;
@property (nonatomic, readwrite, strong) XFDEventsConsoleViewController *consoleController;
@end

@implementation XFUEditorViewController {
  __weak id<UDWorkbench> _workbench;
  // The form editor's undo, which records nothing: the text's is the undo.
  NSUndoManager *_formUndo;
  // The text being read (what the form editor reports then is no change of
  // the user's), or written (what the text model reports then is the
  // designer's own).
  BOOL _reading;
  BOOL _writing;
}

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench {
  if ((self = [super initWithNibName:@"XFUEditor"
                              bundle:[NSBundle bundleForClass:[XFUEditorViewController class]]])) {
    _document = document;
    _workbench = workbench;
    _consoleController = [[XFDEventsConsoleViewController alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(textDidChange:)
                                                 name:UDTextModelDidChangeNotification
                                               object:document.textModel];
    [self read];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [_consoleController stop];
}

- (void)loadView {
  [super loadView];
  [_split setPosition:XFUOutlineWidth ofDividerAtIndex:0];
  [self show];
}

#pragma mark Reading

// The folder the form's relative names (its instances' @src, its
// submissions' resources) resolve against: its file's.
- (NSURL *)baseURL {
  return [_document.fileURL URLByDeletingLastPathComponent];
}

// The parts, over the first text that is a form: the form editor's undo
// records nothing (the text's undo is the undo), and the preview has no
// source of its own (the text is) nor a console button (the console is a
// bottom pane).
- (void)makePartsWithXMLString:(NSString *)xml error:(NSError **)error {
  _formUndo = [[XFUNoUndoManager alloc] init];
  XFDFormEditor *editor = [[XFDFormEditor alloc] initWithXMLString:xml
                                                           baseURL:_document.fileURL
                                                       undoManager:_formUndo
                                                             error:error];
  if (editor == nil)
    return;
  editor.delegate = self;
  [editor addObserver:self];
  self.formEditor = editor;
  self.outlineViewController = [[XFDOutlineViewController alloc] initWithFormEditor:editor];
  self.previewViewController = [[XFDPreviewViewController alloc] initWithFormEditor:editor];
  self.previewViewController.showsSource = NO;
  self.previewViewController.showsEventsConsoleButton = NO;
  self.identityInspector = [[XFDIdentityInspector alloc] initWithFormEditor:editor];
  self.attributesInspector = [[XFDAttributesInspector alloc] initWithFormEditor:editor];
  self.eventsInspector = [[XFDEventsInspector alloc] initWithFormEditor:editor];
  self.libraryController = [[XFDLibraryViewController alloc] initWithFormEditor:editor];
  self.libraryController.delegate = self;
}

// The text read into the form editor; or, when it is no form, why.
- (void)read {
  NSString *xml = [_document.textModel getValue] ?: @"";
  NSError *error = nil;
  _reading = YES;
  BOOL read;
  if (self.formEditor == nil) {
    [self makePartsWithXMLString:xml error:&error];
    read = self.formEditor != nil;
  } else {
    read = [self.formEditor replaceWithXMLString:xml error:&error];
  }
  _reading = NO;
  self.problem = read ? nil
                      : [NSString stringWithFormat:@"This is not a form that can be shown: %@",
                                                   [error localizedDescription] ?: @"it cannot be read."];
  [self show];
}

// The text changed, not by the designer: read again, at once while the tab
// shows (an undo), a moment later while it does not (typed in a tab of its
// text, each key would be a read of the whole form).
- (void)textDidChange:(NSNotification *)notification {
  (void)notification;
  if (_writing)
    return;
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(read) object:nil];
  if ([self isViewLoaded] && [[self view] window] != nil)
    [self read];
  else
    [self performSelector:@selector(read) withObject:nil afterDelay:0.3];
}

#pragma mark Writing

// The form changed: written once the change is done (one user's action is
// several of the commands'), so one action is one edit of the text, one
// undo.
- (void)formEditor:(XFDFormEditor *)editor hostDidChange:(XFXMLElement *)element {
  (void)editor;
  (void)element;
  if (_reading)
    return;
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(write) object:nil];
  [self performSelector:@selector(write) withObject:nil afterDelay:0];
}

// The form written as the text: an edit for each run of lines that differs
// (XFULineChanges), made at once, so undone as one, and a diff of the file
// says what changed.
- (void)write {
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(write) object:nil];
  if (self.formEditor == nil || self.problem != nil)
    return;
  NSString *text = [self.formEditor hostXMLString];
  UDTextModel *model = _document.textModel;
  NSString *old = [model getValue];
  if (text == nil || [text isEqualToString:old])
    return;
  NSMutableArray *edits = [NSMutableArray array];
  for (XFUTextChange *change in XFULineChanges(old, text)) {
    UDPosition from = [model getPositionAt:(NSInteger)change.offset];
    UDPosition to = [model getPositionAt:(NSInteger)(change.offset + change.length)];
    UDRange range = {from.line, from.column, to.line, to.column};
    [edits addObject:[[UDTextModelEdit alloc] initWithRange:range text:change.text]];
  }
  _writing = YES;
  [model applyEdits:edits];
  _writing = NO;
  // the commands open a group for each action even with nothing recorded:
  // kept empty, it never says it has something to undo
  [_formUndo removeAllActions];
}

#pragma mark Showing

static void XFUPutView(NSView *view, NSView *host) {
  if ([view superview] == host)
    return;
  [view setFrame:[host bounds]];
  [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [host addSubview:view];
}

// The outline and the preview in the tab; or why there is none.
- (void)show {
  if (![self isViewLoaded])
    return;
  if (self.problem == nil && self.formEditor != nil) {
    XFUPutView([self.outlineViewController view], _outlineHost);
    XFUPutView([self.previewViewController view], _previewHost);
    [_split setHidden:NO];
    [self.problemView setHidden:YES];
  } else {
    [_split setHidden:YES];
    [self.problemLabel setStringValue:self.problem ?: @""];
    [self.problemView setHidden:NO];
  }
}

// The console traces while the tab shows: the engine has one trace sink,
// and the form in front is the one being looked at.
- (void)tabDidMoveToWindow:(NSWindow *)window {
  if (window != nil && self.formEditor != nil)
    [self.consoleController startWithHostDocument:self.formEditor.processor.hostDocument];
  else
    [self.consoleController stop];
}

// The Document Outline keeps its width as the tab is resized, the preview
// taking the difference.
- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview {
  (void)splitView;
  return subview != _outlineHost;
}

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMinCoordinate:(CGFloat)proposed
               ofSubviewAt:(NSInteger)index {
  (void)splitView;
  (void)index;
  return MAX(proposed, XFUOutlineMinimum);
}

#pragma mark The window's panes (UDEditorPanes)

- (NSArray<NSViewController *> *)inspectorViewControllers {
  if (self.formEditor == nil || self.problem != nil)
    return @[];
  return @[ self.identityInspector, self.attributesInspector, self.eventsInspector ];
}

- (NSImage *)imageForInspectorViewController:(NSViewController *)viewController {
  return XFUInspectorImage(viewController);
}

- (NSArray<NSViewController *> *)bottomAreaViewControllers {
  return self.formEditor != nil && self.problem == nil ? @[ self.consoleController ] : @[];
}

- (NSImage *)imageForBottomAreaViewController:(NSViewController *)viewController {
  if (viewController != self.consoleController)
    return nil;
  NSImage *image = [XFDBadge(@"C", 0.70, 0.48, 0.32) copy];
  [image setSize:NSMakeSize(16, 16)];
  return image;
}

- (NSViewController *)libraryViewController {
  if (self.formEditor == nil || self.problem != nil)
    return nil;
  [self.libraryController reload];
  return self.libraryController;
}

#pragma mark What the parts ask

// A tag chosen in the Library: inserted where it can go nearest the
// selection, and the Library closed.
- (void)library:(XFDLibraryViewController *)library didChooseName:(NSString *)name {
  (void)library;
  NSError *error = nil;
  if ([self.formEditor insertElementNamed:name error:&error] == nil) {
    [self presentError:error];
    return;
  }
  [_workbench closeLibrary];
}

- (void)formEditorShowAttributes:(XFDFormEditor *)editor {
  (void)editor;
  [_workbench showEditorInspector:self.attributesInspector];
}

#pragma mark Actions

- (IBAction)insertElement:(id)sender {
  [self.outlineViewController insertElement:sender];
}

- (IBAction)deleteElement:(id)sender {
  [self.outlineViewController deleteElement:sender];
}

- (IBAction)resetInstances:(id)sender {
  [self.previewViewController resetInstances:sender];
}

- (IBAction)undo:(id)sender {
  (void)sender;
  [self write];
  [_document.textModel.undoManager undo];
}

- (IBAction)redo:(id)sender {
  (void)sender;
  [_document.textModel.undoManager redo];
}

- (IBAction)showAsText:(id)sender {
  (void)sender;
  [_workbench showDocumentAsText:_document];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
  SEL action = [item action];
  if (sel_isEqual(action, @selector(undo:)))
    return _document.textModel.undoManager.canUndo;
  if (sel_isEqual(action, @selector(redo:)))
    return _document.textModel.undoManager.canRedo;
  BOOL form = self.formEditor != nil && self.problem == nil;
  if (sel_isEqual(action, @selector(insertElement:)))
    return form && [self.formEditor insertParentForSelection:NULL] != nil;
  if (sel_isEqual(action, @selector(deleteElement:)))
    return form && [self.formEditor canDeleteSelection];
  if (sel_isEqual(action, @selector(resetInstances:)))
    return form;
  return YES;
}

@end
