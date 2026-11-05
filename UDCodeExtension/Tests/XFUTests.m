/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
// UDCode's XForms extension against UDCode's own document and text model
// (its SDK): a form is its document's text, each change one edit of it, the
// text's undo undoing it; its parts are the window's panes; a text that is
// no form says why.
#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <UDCodeKit/UDCodeDocument.h>
#import <UDPieceTable/UDTextModel.h>
#import "XFUEditorViewController.h"
#import "XFUExtension.h"
#import "XFUTextDiff.h"
#import "XFormsDesignKit.h"
#import "XFDInspectorPages.h"

// The window's side of what the tab asks of it: what it was asked to show.
@interface XFUTestWorkbench : NSObject
@property (nonatomic, strong) NSMutableArray<NSViewController *> *inspectors;
@property (nonatomic, strong) NSMutableArray<UDCodeDocument *> *shownAsText;
@property (nonatomic, assign) NSUInteger librariesClosed;
@end

@implementation XFUTestWorkbench
- (instancetype)init {
  if ((self = [super init])) {
    _inspectors = [NSMutableArray array];
    _shownAsText = [NSMutableArray array];
  }
  return self;
}
- (BOOL)showEditorInspector:(NSViewController *)inspector {
  [_inspectors addObject:inspector];
  return YES;
}
- (void)closeLibrary {
  _librariesClosed++;
}
- (void)showDocumentAsText:(UDCodeDocument *)document {
  [_shownAsText addObject:document];
}
@end

@interface XFUTests : XCTestCase
@end

@implementation XFUTests {
  UDCodeDocument *_document;
  XFUEditorViewController *_tab;
  XFUTestWorkbench *_workbench;
  NSWindow *_window;
  NSUInteger _edits;
}

- (void)setUp {
  [super setUp];
  [NSApplication sharedApplication];
}

- (void)tearDown {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [[_tab view] removeFromSuperview];
  [_window orderOut:nil];
  [super tearDown];
}

// Tests/Fixtures/hello.xhtml: a model with a name, an input of it and an
// output greeting it, in a group.
- (NSString *)helloForm {
  NSString *here = [[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent];
  // gnustep-make compiles from the bundle's directory, and __FILE__ is then
  // relative to it.
  if (![here isAbsolutePath])
    here = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:here];
  NSString *path = [[[here stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
      stringByAppendingPathComponent:@"Tests/Fixtures/hello.xhtml"];
  return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
}

- (void)countEdit:(NSNotification *)notification {
  (void)notification;
  _edits++;
}

- (void)spin:(NSTimeInterval)seconds {
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

// The tab over a document of the text, its view in a window as UDCode's tab
// would have it.
- (void)openText:(NSString *)text {
  _document = [[UDCodeDocument alloc] initWithText:text fileURL:nil languageMode:nil];
  _workbench = [[XFUTestWorkbench alloc] init];
  _tab = [[XFUEditorViewController alloc] initWithDocument:_document
                                                 workbench:(id<UDWorkbench>)_workbench];
  _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1100, 700)
                                        styleMask:NSWindowStyleMaskTitled
                                          backing:NSBackingStoreBuffered
                                            defer:YES];
  [_window setReleasedWhenClosed:NO];
  [[_tab view] setFrame:[[_window contentView] bounds]];
  [[_window contentView] addSubview:[_tab view]];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(countEdit:)
                                               name:UDTextModelDidChangeNotification
                                             object:_document.textModel];
}

// Whether an image has paint in it: drawn into an image of its size and
// read back (anywhere: a symbol's outline may leave its middle clear).
- (BOOL)imageIsDrawn:(NSImage *)image {
  NSSize size = [image size];
  if (size.width < 1 || size.height < 1)
    return NO;
  NSImage *canvas = [[NSImage alloc] initWithSize:size];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [canvas lockFocus];
  [[NSColor clearColor] set];
  NSRectFill(NSMakeRect(0, 0, size.width, size.height));
  [image drawInRect:NSMakeRect(0, 0, size.width, size.height)
           fromRect:NSZeroRect
          operation:NSCompositeSourceOver
           fraction:1.0];
  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect(0, 0, size.width, size.height)];
  [canvas unlockFocus];
#pragma clang diagnostic pop
  for (NSInteger y = 0; y < [rep pixelsHigh]; y++)
    for (NSInteger x = 0; x < [rep pixelsWide]; x++)
      if ([[rep colorAtX:x y:y] alphaComponent] > 0.5)
        return YES;
  return NO;
}

- (XFXMLElement *)inputOf:(XFDFormEditor *)editor {
  XFXMLElement *group = [editor elementChildrenOf:[editor bodyElement]].firstObject;
  return [editor elementChildrenOf:group].firstObject;
}

- (void)testAFormOpensInTheDesigner {
  NSString *text = [self helloForm];
  XCTAssertNotNil(text);
  XCTAssertTrue([XFUExtension textIsAForm:text]);
  XCTAssertFalse([XFUExtension textIsAForm:@"<html xmlns=\"http://www.w3.org/1999/xhtml\"><body/></html>"],
                 @"XHTML without XForms is text");
  [self openText:text];
  XCTAssertNil(_tab.problem);
  XCTAssertNotNil(_tab.formEditor);
  XCTAssertGreaterThanOrEqual([_tab.outlineViewController.outline numberOfRows], 4, @"the Document Outline");
  XCTAssertNotNil(_tab.previewViewController.formView, @"the form, running");
  XCTAssertTrue([_tab.previewViewController.modeControl isHidden], @"no Source: the text is the source");
  XCTAssertTrue([_tab.previewViewController.consoleButton isHidden], @"the console is a bottom pane");
  XCTAssertNotNil([[_tab.outlineViewController view] superview]);
  XCTAssertNotNil([[_tab.previewViewController view] superview]);
  [self spin:0.1];
  XCTAssertEqualObjects([_document.textModel getValue], text, @"opened, the text as it was");
  XCTAssertEqual(_edits, 0u);
}

- (void)testEachChangeIsOneEditOfItsLinesAndTheTextsUndoUndoesIt {
  NSString *text = [self helloForm];
  [self openText:text];
  XFDFormEditor *editor = _tab.formEditor;
  // the inspector in the window, as UDCode's inspector pane has it
  [[_window contentView] addSubview:[_tab.attributesInspector view]];
  editor.selection = [self inputOf:editor];
  XFDControlPage *control = _tab.attributesInspector.controlPage;
  XCTAssertEqualObjects([control.controlRefField stringValue], @"name");
  _edits = 0;
  [control.controlLabelField setStringValue:@"Your name"];
  XCTAssertTrue([control.controlLabelField commitEditing]);
  [self spin:0.1];
  NSString *changed = [_document.textModel getValue];
  XCTAssertTrue([changed containsString:@"<xf:label>Your name</xf:label>"]);
  XCTAssertEqual(_edits, 1u, @"one action, one edit of the text");
  // the first change also writes the root's start tag as XFormsKit writes
  // it (its namespaces on one line); the label's line, and that, only
  NSArray *changes = XFULineChanges(text, changed);
  XCTAssertEqual(changes.count, 2u);
  XCTAssertTrue([((XFUTextChange *)changes.firstObject).text hasPrefix:@"<?xml"]);
  XCTAssertTrue([((XFUTextChange *)changes.lastObject).text containsString:@"Your name"]);
  // after it, a change is its own lines
  [control.controlLabelField setStringValue:@"Full name"];
  XCTAssertTrue([control.controlLabelField commitEditing]);
  [self spin:0.1];
  NSArray *second = XFULineChanges(changed, [_document.textModel getValue]);
  XCTAssertEqual(second.count, 1u, @"only the label's line");
  XCTAssertEqualObjects(((XFUTextChange *)second.firstObject).text, @"        <xf:label>Full name</xf:label>\n");
  [_tab undo:nil];
  [self spin:0.1];
  XCTAssertEqualObjects([_document.textModel getValue], changed, @"one undo, one change");

  [_tab undo:nil];
  [self spin:0.1];
  XCTAssertEqualObjects([_document.textModel getValue], text, @"the text's undo");
  XCTAssertEqualObjects([editor.hostEdit supportChildText:@"label" onElement:editor.selection], @"Name",
                        @"read again, the input still selected");
  XCTAssertEqualObjects([editor.selection localName], @"input");
}

- (void)testTheTextChangedElsewhereIsReadAgain {
  [self openText:[self helloForm]];
  XFDFormEditor *editor = _tab.formEditor;
  NSString *text = [_document.textModel getValue];
  NSRange at = [text rangeOfString:@"<name>World</name>"];
  UDPosition from = [_document.textModel getPositionAt:(NSInteger)at.location];
  UDPosition to = [_document.textModel getPositionAt:(NSInteger)NSMaxRange(at)];
  UDRange range = {from.line, from.column, to.line, to.column};
  [_document.textModel applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:range text:@"<name>Form</name>"] ]];
  [self spin:0.1];
  XFXMLNode *name = [[editor.processor defaultInstance] documentElement];
  XCTAssertTrue([[XFXML stringValueOfNode:name] containsString:@"Form"], @"the form read again");
}

- (void)testATextThatIsNoFormSaysWhy {
  [self openText:@"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\"><body>"];
  XCTAssertNotNil(_tab.problem);
  XCTAssertTrue([_tab.problem hasPrefix:@"This is not a form that can be shown"]);
  XCTAssertEqual([_tab inspectorViewControllers].count, 0u);
  XCTAssertNil([_tab libraryViewController]);
  [_tab showAsText:nil];
  XCTAssertEqual(_workbench.shownAsText.firstObject, _document);
}

- (void)testItsPartsAreTheWindowsPanes {
  [self openText:[self helloForm]];
  NSArray *inspectors = [_tab inspectorViewControllers];
  XCTAssertEqual(inspectors.count, 3u);
  XCTAssertEqualObjects([inspectors valueForKey:@"title"], (@[ @"Identity", @"Attributes", @"Events" ]));
  for (NSViewController *inspector in inspectors) {
    NSImage *image = [_tab imageForInspectorViewController:inspector];
    XCTAssertNotNil(image, @"%@'s image", inspector.title);
    XCTAssertTrue([self imageIsDrawn:image], @"%@'s image has its badge in it", inspector.title);
  }
  XCTAssertEqualObjects([_tab bottomAreaViewControllers], @[ _tab.consoleController ]);
  NSImage *console = [_tab imageForBottomAreaViewController:_tab.consoleController];
  XCTAssertNotNil(console);
  XCTAssertTrue([self imageIsDrawn:console], @"the console's image has its badge in it");

  // the Events inspector's double click asks for the Attributes inspector
  [_tab.formEditor showAttributes];
  XCTAssertEqual(_workbench.inspectors.lastObject, _tab.attributesInspector);

  // a tag chosen in the Library goes in, the Library closes
  XFDLibraryViewController *library = (XFDLibraryViewController *)[_tab libraryViewController];
  XCTAssertNotNil(library);
  _tab.formEditor.selection = [_tab.formEditor bodyElement];
  NSUInteger before = _tab.formEditor.processor.controls.count;
  [(id<XFDLibraryDelegate>)_tab library:library didChooseName:@"trigger"];
  [self spin:0.1];
  XCTAssertEqual(_tab.formEditor.processor.controls.count, before + 1);
  XCTAssertEqual(_workbench.librariesClosed, 1u);
  XCTAssertTrue([[_document.textModel getValue] containsString:@"<xf:trigger"], @"written into the text");
}

- (void)testTheConsoleTracesWhileTheTabShows {
  [self openText:[self helloForm]];
  XCTAssertTrue(_tab.consoleController.running, @"in a window: tracing");
  [[_tab view] removeFromSuperview];
  XCTAssertFalse(_tab.consoleController.running, @"out of it: not");
}

- (void)testTheFormMenu {
  NSArray<NSMenuItem *> *items = [XFUExtension editorMenuItems];
  XCTAssertEqual(items.count, 1u);
  XCTAssertEqualObjects(items.firstObject.title, @"Form");
  NSArray *titles = [[items.firstObject.submenu itemArray] valueForKey:@"title"];
  XCTAssertEqualObjects(titles, (@[ @"Insert Element…", @"Delete Element", @"", @"Reset Instance Data" ]));
  [self openText:[self helloForm]];
  NSMenuItem *delete = [items.firstObject.submenu itemAtIndex:1];
  _tab.formEditor.selection = [_tab.formEditor bodyElement];
  XCTAssertFalse([_tab validateMenuItem:delete], @"the body stays");
  _tab.formEditor.selection = [self inputOf:_tab.formEditor];
  XCTAssertTrue([_tab validateMenuItem:delete]);
}

- (void)testLineChanges {
  XCTAssertEqual(XFULineChanges(@"a\nb\nc\n", @"a\nb\nc\n").count, 0u);
  NSArray *changes = XFULineChanges(@"a\nb\nc\n", @"a\nB\nc\n");
  XCTAssertEqual(changes.count, 1u);
  XFUTextChange *change = changes.firstObject;
  XCTAssertEqual(change.offset, 2u);
  XCTAssertEqual(change.length, 2u);
  XCTAssertEqualObjects(change.text, @"B\n");
}

@end
