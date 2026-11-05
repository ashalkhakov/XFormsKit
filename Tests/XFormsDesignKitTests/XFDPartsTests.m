/* The designer's parts: every XIB loads with its outlets connected, the
   parts follow the form editor, and the edits the designer makes (the
   outline, the library, design mode and its drag) land in the host
   document and undo; on hello.xhtml, and on piechart.xhtml for SVG's
   hit-testing. The inspectors' edits are XFDInspectorTests'.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFXMLTypes.h>
#import "XFormsDesignKit.h"
#import "XFDInspectorPages.h"
#import "XFDPalettePanel.h"
#import "XFDXPathField.h"
#import "XFDRichTextField.h"
#import "XFDIDRefField.h"

// The panels' loading, which their run methods do before they go modal.
@interface XFDPalettePanel (XFDTesting)
- (BOOL)loadWithValidNames:(NSSet *)validNames parentName:(NSString *)parentName;
@end

@interface XFDEventsConsole (XFDTesting)
- (BOOL)loadPanelIfNeeded;
@end

// The modal panels' (some private to their fields' files, so by name).
@interface NSObject (XFDPanelLoading)
- (BOOL)loadPanel;
- (BOOL)loadPanelWithTitle:(NSString *)title;
@end

@interface XFDPartsTests : XCTestCase
@end

@implementation XFDPartsTests {
    XFDDocument *_document;
    XFDWindowController *_window;
    XFDFormEditor *_editor;
    NSUndoManager *_undo;
}

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
}

- (void)tearDown
{
    [[_window window] orderOut:nil];
    [_window close];
    _window = nil;
    _document = nil;
    _editor = nil;
    [super tearDown];
}

- (NSString *)pathOfForm:(NSString *)name
{
    NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:name ofType:@"xhtml"];
    XCTAssertNotNil(path, @"%@.xhtml is the bundle's", name);
    return path;
}

/// The designer's document and window over a form of the bundle's.
- (void)openForm:(NSString *)name
{
    NSError *error = nil;
    _document = [[XFDDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[self pathOfForm:name]]
                                                    ofType:@"XHTML+XForms"
                                                     error:&error];
    XCTAssertNotNil(_document, @"%@", error);
    [_document makeWindowControllers];
    _window = [[_document windowControllers] firstObject];
    XCTAssertNotNil([_window window], @"the window's XIB loads");
    _editor = _document.formEditor;
    _undo = _editor.undoManager;
    // headless: no run loop closes the group an event would open, and an
    // undo would unwind every edit at once; explicit groups only
    [_undo setGroupsByEvent:NO];
}

- (void)edit:(void (^)(void))block
{
    [_undo beginUndoGrouping];
    block();
    [_undo endUndoGrouping];
}

- (XFDAttributesInspector *)attributes
{
    return _window.inspectorViewController.attributesInspector;
}

- (XFDPreviewViewController *)preview
{
    return _window.previewViewController;
}

- (NSInteger)pageShown
{
    NSTabView *tabs = [self attributes].kindTabView;
    return [tabs indexOfTabViewItem:[tabs selectedTabViewItem]];
}

/// An object's outlets, every one set.
- (void)assertOutlets:(NSArray<NSString *> *)outlets of:(id)object
{
    for (NSString *outlet in outlets) {
        XCTAssertNotNil([object valueForKey:outlet], @"%@.%@ is connected", [object class], outlet);
    }
}

#pragma mark The XIBs

- (void)testEveryPartLoadsFromItsXIBConnected
{
    [self openForm:@"hello"];
    [self assertOutlets:@[ @"outlineHost", @"editorHost", @"inspectorHost" ] of:_window];
    [self assertOutlets:@[ @"outline", @"plusMinusControl" ] of:_window.outlineViewController];
    [self assertOutlets:@[ @"modeControl", @"designModeCheckbox", @"consoleButton", @"centerTabView",
                           @"previewHost", @"sourceHost", @"formView", @"designOverlay", @"sourceView" ]
                     of:[self preview]];
    XFDInspectorViewController *inspector = _window.inspectorViewController;
    [self assertOutlets:@[ @"inspectorTabBar", @"inspectorTabView" ] of:inspector];
    XCTAssertEqual([inspector.inspectorTabView numberOfTabViewItems], 3, @"Identity, Attributes, Events");
    [self assertOutlets:@[ @"identityTitleField", @"identityIdField", @"editorController" ]
                     of:inspector.identityInspector];
    XFDAttributesInspector *attributes = [self attributes];
    [self assertOutlets:@[ @"kindTabView", @"controlPage", @"bindPage", @"submissionPage", @"instancePage",
                           @"elementPage", @"actionPage", @"itemPage", @"itemsetPage" ] of:attributes];
    XCTAssertEqual([attributes.kindTabView numberOfTabViewItems], 8);
    for (NSString *page in @[ @"controlPage", @"bindPage", @"submissionPage", @"instancePage",
                              @"elementPage", @"actionPage", @"itemPage", @"itemsetPage" ]) {
        [self assertOutlets:@[ @"view", @"inspector", @"editorController" ] of:[attributes valueForKey:page]];
    }
    [self assertOutlets:@[ @"view", @"inspector", @"controlRefField", @"controlValueField", @"controlBindField",
                           @"controlBindingStatusField", @"controlCreateBindButton", @"controlModelField",
                           @"controlSubmissionField", @"controlAppearancePopup", @"controlIncrementalCheckbox",
                           @"controlMediatypeField", @"controlLabelField", @"controlHintField",
                           @"controlHelpField", @"controlAlertField" ] of:attributes.controlPage];
    [self assertOutlets:@[ @"view", @"bindNodesetField", @"bindTypeField", @"bindCalculateField",
                           @"bindConstraintField", @"bindRequiredField", @"bindRelevantField",
                           @"bindReadonlyField" ] of:attributes.bindPage];
    [self assertOutlets:@[ @"view", @"submissionResourceField", @"submissionMethodField",
                           @"submissionReplacePopup", @"submissionInstanceField", @"submissionRefField",
                           @"submissionBindField" ] of:attributes.submissionPage];
    [self assertOutlets:@[ @"view", @"instanceSrcField" ] of:attributes.instancePage];
    [self assertOutlets:@[ @"view", @"actionRowsHost" ] of:attributes.actionPage];
    [self assertOutlets:@[ @"view", @"itemLabelField", @"itemValueField" ] of:attributes.itemPage];
    [self assertOutlets:@[ @"view", @"itemsetNodesetField", @"itemsetBindField", @"itemsetLabelRefField",
                           @"itemsetValueRefField" ] of:attributes.itemsetPage];
    [self assertOutlets:@[ @"view", @"hostNewControlButton", @"controlKindMenu" ] of:attributes.elementPage];
    [self assertOutlets:@[ @"table", @"plusMinusControl", @"noteField" ] of:inspector.eventsInspector];

    XFDLibraryViewController *library = [[XFDLibraryViewController alloc] initWithFormEditor:_editor];
    [library view];
    [self assertOutlets:@[ @"filterField", @"table" ] of:library];
    XCTAssertGreaterThan([library.table numberOfRows], 10, @"the catalogue, in its categories");

    XFDEventsConsoleViewController *console = [[XFDEventsConsoleViewController alloc] init];
    [console view];
    [self assertOutlets:@[ @"kindPopup", @"filterField", @"pauseButton", @"table", @"countField" ] of:console];
    XCTAssertEqual([console.kindPopup numberOfItems], 7);
}

- (void)testThePanelsLoadFromTheirXIBs
{
    XFDPalettePanel *palette = [[XFDPalettePanel alloc] init];
    XCTAssertTrue([palette loadWithValidNames:[NSSet setWithObject:@"input"] parentName:@"body"]);
    [self assertOutlets:@[ @"panel", @"libraryHost", @"insertButton" ] of:palette];
    XCTAssertEqualObjects([palette.panel title], @"Insert into body");
    XCTAssertEqual([[palette.libraryHost subviews] count], 1u, @"the library in it");
    XCTAssertFalse([palette.insertButton isEnabled], @"nothing chosen yet");

    XFDEventsConsole *console = [[XFDEventsConsole alloc] init];
    XCTAssertTrue([console loadPanelIfNeeded]);
    XCTAssertNotNil(console.panel);
    XCTAssertEqual([[[console.panel contentView] subviews] count], 1u, @"the console's view in it");
}

- (void)testTheModalPanelsLoadFromTheirXIBs
{
    NSDictionary<NSString *, NSArray *> *panels = @{
        @"XFDInstanceXMLEditor": @[ @"panel", @"text", @"statusField", @"okButton" ],
        @"XFDSubmissionTester": @[ @"panel", @"submissionPopup", @"transportPopup", @"historyPopup",
                                   @"requestLine", @"headersTable", @"bodyView", @"extraHeadersField",
                                   @"statusLine", @"responseHeadersTable", @"responseView" ],
        @"XFDRichTextPanel": @[ @"panel", @"viewControl", @"insertOutputButton", @"tabs", @"richHost",
                                @"richEditor", @"sourceView", @"statusField", @"okButton" ],
        @"XFDPredicateEditor": @[ @"panel", @"introField", @"field", @"statusField", @"table", @"okButton" ],
        @"XFDXPathPicker": @[ @"panel", @"contextField", @"instancePopup", @"styleControl", @"tree",
                              @"stepsTable", @"stepsControl", @"stepsStatusField", @"pathField", @"statusField",
                              @"resultTable", @"okButton", @"editPathButton", @"predicateButton",
                              @"suggestPopup", @"functionInfoField" ],
    };
    for (NSString *name in panels) {
        Class cls = NSClassFromString(name);
        XCTAssertNotNil(cls, @"%@", name);
        id panel = [[cls alloc] init];
        BOOL loaded = [panel respondsToSelector:@selector(loadPanelWithTitle:)]
            ? [panel loadPanelWithTitle:@"A Title"] : [panel loadPanel];
        XCTAssertTrue(loaded, @"%@ loads from its XIB", name);
        [self assertOutlets:panels[name] of:panel];
    }
    // what the XIB cannot say, the code does: the steps' axes, the rich
    // editor in its host
    id picker = [[NSClassFromString(@"XFDXPathPicker") alloc] init];
    [picker loadPanelWithTitle:@"XPath"];
    NSTableView *steps = [picker valueForKey:@"stepsTable"];
    XCTAssertTrue([[[steps tableColumnWithIdentifier:@"axis"] dataCell] isKindOfClass:[NSPopUpButtonCell class]]);
    XCTAssertEqualObjects([[picker valueForKey:@"panel"] title], @"XPath");
    id rich = [[NSClassFromString(@"XFDRichTextPanel") alloc] init];
    [rich loadPanelWithTitle:@"Label"];
    XCTAssertEqual([[rich valueForKey:@"richEditor"] superview], [rich valueForKey:@"richHost"]);
}

- (void)testEveryTipIsInTheXIB
{
    [self openForm:@"hello"];
    XFDAttributesInspector *attributes = [self attributes];
    XCTAssertGreaterThan([[attributes.controlPage.controlRefField toolTip] length], 0u);
    XCTAssertGreaterThan([[attributes.bindPage.bindCalculateField toolTip] length], 0u);
    XCTAssertGreaterThan([[_window.inspectorViewController.identityInspector.identityIdField toolTip] length], 0u);
}

#pragma mark The parts follow the form editor

- (void)testThePartsFollowTheSelection
{
    [self openForm:@"hello"];
    XFXMLElement *body = [_editor bodyElement];
    XFXMLElement *group = [_editor elementChildrenOf:body].firstObject;
    XFXMLElement *input = [_editor elementChildrenOf:group].firstObject;
    _editor.selection = input;
    NSOutlineView *outline = _window.outlineViewController.outline;
    XCTAssertEqual([outline itemAtRow:[outline selectedRow]], input, @"the outline shows it");
    XCTAssertEqual([self pageShown], XFDPageControl);
    XCTAssertEqualObjects([[self attributes].controlPage.controlRefField stringValue], @"name");
    XCTAssertTrue([[_window.inspectorViewController.identityInspector.identityTitleField stringValue]
                      hasPrefix:@"xf:input"]);

    // a click in the outline is the form editor's selection
    [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[outline rowForItem:group]]
         byExtendingSelection:NO];
    XCTAssertEqual(_editor.selection, group);
    XCTAssertEqual([self pageShown], XFDPageControl, @"a group is a control's page");
}

- (void)testTheTextReadAgainKeepsTheSelection
{
    [self openForm:@"hello"];
    XFXMLElement *group = [_editor elementChildrenOf:[_editor bodyElement]].firstObject;
    XFXMLElement *input = [_editor elementChildrenOf:group].firstObject;
    _editor.selection = input;
    NSString *xml = [[_editor hostXMLString] stringByReplacingOccurrencesOfString:@"<xf:label>Name</xf:label>"
                                                                         withString:@"<xf:label>Your name</xf:label>"];
    NSError *error = nil;
    XCTAssertTrue([_editor replaceWithXMLString:xml error:&error], @"%@", error);
    XCTAssertNotEqual(_editor.selection, input, @"a new document's element");
    XCTAssertEqualObjects([_editor.selection localName], @"input", @"at the same place");
    XCTAssertEqualObjects([_editor.hostEdit supportChildText:@"label" onElement:_editor.selection], @"Your name");
    XCTAssertEqualObjects([[self attributes].controlPage.controlLabelField stringValue], @"Your name",
                          @"the inspector filled from the new document");
    XCTAssertFalse([_editor replaceWithXMLString:@"<html><body>" error:&error], @"no form");
    XCTAssertEqualObjects([_editor.selection localName], @"input", @"the form as it was");
}

- (void)testThePartsWorkWithoutAWindow
{
    // as an IDE hosts them: a form editor over text, its parts in panes
    NSUndoManager *undo = [[NSUndoManager alloc] init];
    [undo setGroupsByEvent:NO];
    NSError *error = nil;
    NSString *xml = [NSString stringWithContentsOfFile:[self pathOfForm:@"hello"] encoding:NSUTF8StringEncoding
                                                 error:&error];
    XFDFormEditor *editor = [[XFDFormEditor alloc] initWithXMLString:xml baseURL:nil undoManager:undo error:&error];
    XCTAssertNotNil(editor, @"%@", error);
    XFDOutlineViewController *outline = [[XFDOutlineViewController alloc] initWithFormEditor:editor];
    XFDPreviewViewController *preview = [[XFDPreviewViewController alloc] initWithFormEditor:editor];
    preview.showsSource = NO;
    preview.showsEventsConsoleButton = NO;
    XFDAttributesInspector *attributes = [[XFDAttributesInspector alloc] initWithFormEditor:editor];
    XFDLibraryViewController *library = [[XFDLibraryViewController alloc] initWithFormEditor:editor];
    [outline view];
    [preview view];
    [attributes view];
    [library view];
    XCTAssertTrue([preview.modeControl isHidden]);
    XCTAssertTrue([preview.consoleButton isHidden]);
    XCTAssertEqual(NSMinX([preview.designModeCheckbox frame]), NSMinX([preview.modeControl frame]),
                   @"Design where Form / Source was");

    // the library inserts where the selection is
    editor.selection = [editor bodyElement];
    [library reload];
    XCTAssertTrue([library.validNames containsObject:@"input"]);
    NSUInteger before = editor.processor.controls.count;
    [undo beginUndoGrouping];
    XFXMLElement *trigger = [editor insertElementNamed:@"trigger" error:&error];
    [undo endUndoGrouping];
    XCTAssertNotNil(trigger, @"%@", error);
    XCTAssertEqual(editor.processor.controls.count, before + 1);
    XCTAssertEqual(editor.selection, trigger);
    XCTAssertEqual([outline.outline itemAtRow:[outline.outline selectedRow]], trigger);
    XCTAssertTrue([[editor hostXMLString] containsString:@"<xf:trigger"]);
    [undo undo];
    XCTAssertEqual(editor.processor.controls.count, before, @"undone with the host's undo");
}

#pragma mark The edits (the inspectors' are XFDInspectorTests')

/// A new `name` under `parent`, inserted.
- (XFXMLElement *)insert:(NSString *)name under:(XFXMLElement *)parent
{
    __block XFXMLElement *element = nil;
    [self edit:^{
        element = [self->_editor.hostEdit insertElementNamed:name underParent:parent atIndex:-1 error:NULL];
    }];
    XCTAssertNotNil(element);
    return element;
}

/// A new input under the body, on the name.
- (XFXMLElement *)nameInput
{
    XFXMLElement *input = [self insert:@"input" under:[_editor bodyElement]];
    [self edit:^{ [self->_editor.hostEdit setAttribute:@"ref" value:@"name" onElement:input]; }];
    return input;
}

/// Design mode on, its overlay armed.
- (XFDDesignOverlay *)designMode
{
    XFDPreviewViewController *preview = [self preview];
    [preview.designModeCheckbox setState:NSOnState];
    [preview toggleDesignMode:nil];
    return preview.designOverlay;
}

- (void)testAnInsertIsAControlInTheHost
{
    [self openForm:@"hello"];
    NSUInteger before = _document.processor.controls.count;
    [self nameInput];
    XCTAssertEqual(_document.processor.controls.count, before + 1);
    XCTAssertTrue([[_document hostXMLString] containsString:@"ref=\"name\""]);
}

- (void)testTheLibraryInsertsAtTheSelection
{
    [self openForm:@"hello"];
    NSUInteger before = _document.processor.controls.count;
    _editor.selection = [_editor bodyElement];
    [self edit:^{ [self->_editor insertElementNamed:@"trigger" error:NULL]; }];
    XCTAssertEqual(_document.processor.controls.count, before + 1);
}

- (void)testTheOutlineFlagsAnUnboundControl
{
    [self openForm:@"hello"];
    XFXMLElement *computed = [XFXMLElement elementWithName:@"xf:output"];
    [computed addAttribute:[XFXMLNode attributeWithName:@"value" stringValue:@"event('xforms-insert')/position"]];
    XCTAssertFalse([[_window.outlineViewController titleOfElement:computed] containsString:@"unbound"],
                   @"an output computing @value is bound enough");
    [computed removeAttributeForName:@"value"];
    XCTAssertTrue([[_window.outlineViewController titleOfElement:computed] containsString:@"unbound"]);
}

- (void)testANewBindsIdIsLive
{
    [self openForm:@"hello"];
    XFXMLElement *model = (XFXMLElement *)_document.processor.model.element;
    XFXMLElement *bind = [self insert:@"bind" under:model];
    XCTAssertTrue([[XFDIDRefField identifiersOfKind:@"bind" inProcessor:_document.processor]
                      containsObject:[[bind attributeForName:@"id"] stringValue]]);
}

- (void)testAnActionGetsItsEvent
{
    [self openForm:@"hello"];
    XFXMLElement *trigger = [self insert:@"trigger" under:[_editor bodyElement]];
    XFXMLElement *setvalue = [self insert:@"setvalue" under:trigger];
    XCTAssertEqualObjects([[setvalue attributeForName:@"ev:event"] stringValue], @"DOMActivate");
    XFDEventsInspector *events = _window.inspectorViewController.eventsInspector;
    _editor.selection = trigger;
    XCTAssertEqual(events.handlerElements.count, 1u);
    XCTAssertEqual(events.handlerElements.firstObject, setvalue);
    XCTAssertEqual([events.table numberOfRows], 1);
}

- (void)testDesignModeArmsTheOverlay
{
    [self openForm:@"hello"];
    XFDPreviewViewController *preview = [self preview];
    XCTAssertTrue([preview.designOverlay isHidden]);
    [self designMode];
    XCTAssertFalse([preview.designOverlay isHidden]);
    [preview.designModeCheckbox setState:NSOffState];
    [preview toggleDesignMode:nil];
    XCTAssertTrue([preview.designOverlay isHidden]);
}

- (void)testDesignModePicksTheWidgetsElement
{
    [self openForm:@"hello"];
    XFXMLElement *input = [self nameInput];
    XFDDesignOverlay *overlay = [self designMode];
    XFFormView *form = [self preview].formView;
    NSRect rect = [form layoutFrameOfControl:[_document.processor controlForElement:input]];
    XCTAssertFalse(NSIsEmptyRect(rect));
    XFControl *hit = [form controlAtPoint:NSMakePoint(NSMidX(rect), NSMidY(rect))];
    XCTAssertEqual(hit.element, input);
    _editor.selection = [_editor bodyElement];
    [[self preview] overlay:overlay pickedElement:hit.element];
    XCTAssertEqual(_editor.selection, input);
}

- (void)testADragDropsAfterAndUndoes
{
    [self openForm:@"hello"];
    XFXMLElement *body = [_editor bodyElement];
    XFXMLElement *input = [self nameInput];
    XFXMLElement *trigger = [self insert:@"trigger" under:body];
    XFDDesignOverlay *overlay = [self designMode];
    XFFormView *form = [self preview].formView;
    NSRect triggerRect = [form layoutFrameOfControl:[_document.processor controlForElement:trigger]];
    XCTAssertFalse(NSIsEmptyRect(triggerRect));
    NSDictionary *slot = [[self preview] overlay:overlay
                             dropSlotAtFormPoint:NSMakePoint(NSMidX(triggerRect), NSMaxY(triggerRect) - 2)
                                      forElement:input];
    XCTAssertEqual(slot[@"parent"], body);
    XCTAssertNotNil(slot[@"line"]);
    NSInteger before = (NSInteger)[input index];
    [[self preview] overlay:overlay dropElement:input slot:slot];
    XCTAssertEqual((NSInteger)[input index], (NSInteger)[trigger index] + 1, @"the trigger's bottom band: after it");
    [_undo undo];
    XCTAssertEqual((NSInteger)[input index], before);
}

- (void)testADropOntoItselfIsNowhere
{
    [self openForm:@"hello"];
    XFXMLElement *input = [self nameInput];
    XFDDesignOverlay *overlay = [self designMode];
    NSRect rect = [[self preview].formView layoutFrameOfControl:[_document.processor controlForElement:input]];
    XCTAssertNil([[self preview] overlay:overlay dropSlotAtFormPoint:NSMakePoint(NSMidX(rect), NSMidY(rect))
                              forElement:input]);
}

- (void)testDesignModePicksAPaintedShape
{
    [self openForm:@"piechart"];
    XFDDesignOverlay *overlay = [self designMode];
    XFFormView *form = [self preview].formView;
    XFXMLElement *painted = nil;
    NSRect paintedRect = NSZeroRect;
    for (NSString *shape in @[ @"path", @"rect" ]) {
        for (XFXMLElement *e in [XFXML elementsWithLocalName:shape namespaceURI:@"http://www.w3.org/2000/svg"
                                                      inNode:_document.processor.hostDocument]) {
            NSRect r = [form layoutFrameOfSVGElement:e];
            if (painted == nil && !NSIsEmptyRect(r)) {
                painted = e;
                paintedRect = r;
            }
        }
    }
    XCTAssertNotNil(painted, @"a shape painted a frame");
    XFXMLElement *hit = [form svgElementAtPoint:NSMakePoint(NSMidX(paintedRect), NSMidY(paintedRect))];
    XCTAssertNotNil(hit);
    [[self preview] overlay:overlay pickedElement:hit];
    XCTAssertEqual(_editor.selection, hit);
}

- (void)testAnXPathFieldMarksWhatDoesNotCompile
{
    [self openForm:@"hello"];
    XFXMLElement *input = [self nameInput];
    _editor.selection = input;
    XFDXPathField *field = [self attributes].controlPage.controlRefField;
    [field setStringValue:@"//[bad(("];
    XCTAssertFalse([field isValid]);
    [field setStringValue:@"name"];
    XCTAssertTrue([field isValid]);
}

- (void)testEveryEditUndoes
{
    [self openForm:@"hello"];
    NSUInteger before = _document.processor.controls.count;
    XFXMLElement *trigger = [self insert:@"trigger" under:[_editor bodyElement]];
    [self insert:@"setvalue" under:trigger];
    [self nameInput];
    while ([_undo canUndo]) {
        [_undo undo];
    }
    XCTAssertEqual(_document.processor.controls.count, before);
}

@end
