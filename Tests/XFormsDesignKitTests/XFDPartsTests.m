/* The designer's parts: every XIB loads with its outlets connected, the
   parts follow the form editor, and the edits the designer makes (the
   inspectors, the outline, the library, design mode and its drag) land
   in the host document and undo. Each edit test runs on hello.xhtml and
   on piechart.xhtml, whose SVG design mode hit-tests too.
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
    [self assertOutlets:@[ @"identityTitleField", @"identityIdField" ] of:inspector.identityInspector];
    XFDAttributesInspector *attributes = [self attributes];
    [self assertOutlets:@[ @"kindTabView", @"controlPage", @"bindPage", @"submissionPage", @"instancePage",
                           @"elementPage", @"actionPage", @"itemPage", @"itemsetPage" ] of:attributes];
    XCTAssertEqual([attributes.kindTabView numberOfTabViewItems], 8);
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
    [self assertOutlets:@[ @"view", @"hostNewControlButton" ] of:attributes.elementPage];
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

#pragma mark The edits

/// The self-test's edit pass, on one form.
- (void)runEditPassOnForm:(NSString *)name
{
    [self openForm:name];
    NSError *error = nil;
    NSOutlineView *outline = _window.outlineViewController.outline;
    XCTAssertGreaterThanOrEqual([outline numberOfRows], 4);
    XFXMLElement *body = [_editor bodyElement];
    NSUInteger before = _document.processor.controls.count;

    __block XFXMLElement *input = nil;
    [self edit:^{
        input = [self->_editor.hostEdit insertElementNamed:@"input" underParent:body atIndex:-1 error:NULL];
    }];
    XCTAssertNotNil(input);
    XCTAssertEqual(_document.processor.controls.count, before + 1);
    [self edit:^{
        [self->_editor.hostEdit setAttribute:@"ref" value:@"name" onElement:input];
    }];
    XCTAssertTrue([[_document hostXMLString] containsString:@"ref=\"name\""]);

    // the inspector: selecting the input fills its ref; a label applied
    // lands in the host
    XFDAttributesInspector *attributes = [self attributes];
    XFDControlPage *control = attributes.controlPage;
    _editor.selection = input;
    XCTAssertEqualObjects([control.controlRefField stringValue], @"name");
    [control.controlLabelField setStringValue:@"Your name"];
    [self edit:^{ [attributes inspectorChanged:control.controlLabelField]; }];
    XCTAssertEqualObjects([_editor.hostEdit supportChildText:@"label" onElement:input], @"Your name");

    // rich label content: flagged rich, shown flattened, never flattened
    // by a later apply
    [self edit:^{
        [self->_editor.hostEdit setSupportChild:@"label"
                                     contentXML:@"Nom <strong>complet</strong> <xf:output value=\"'x'\"/>"
                                      onElement:input error:NULL];
    }];
    _editor.selection = input;
    XCTAssertTrue([control.controlLabelField isRich]);
    XCTAssertTrue([[control.controlLabelField stringValue] containsString:@"Nom complet"]);
    [self edit:^{ [attributes inspectorChanged:control.controlLabelField]; }];
    XCTAssertTrue([[_editor.hostEdit supportChildXML:@"label" onElement:input]
                      containsString:@"<strong>complet</strong>"]);
    [self edit:^{ [self->_editor.hostEdit setSupportChild:@"label" text:@"Your name" onElement:input]; }];
    _editor.selection = input;
    XCTAssertFalse([control.controlLabelField isRich]);

    // the outline flags an unbound control, not an output computing @value
    XFXMLElement *computed = [XFXMLElement elementWithName:@"xf:output"];
    [computed addAttribute:[XFXMLNode attributeWithName:@"value" stringValue:@"event('xforms-insert')/position"]];
    XCTAssertFalse([[_window.outlineViewController titleOfElement:computed] containsString:@"unbound"]);
    [computed removeAttributeForName:@"value"];
    XCTAssertTrue([[_window.outlineViewController titleOfElement:computed] containsString:@"unbound"]);

    // the library's insert (the palette and the Library both)
    NSUInteger beforeLibrary = _document.processor.controls.count;
    [self edit:^{ [self->_editor insertElementNamed:@"trigger" error:NULL]; }];
    XCTAssertEqual(_document.processor.controls.count, beforeLibrary + 1);

    // IDREFs: a new bind's id is live, picked it lands as @bind, a
    // dangling one is flagged
    XFXMLElement *model = (XFXMLElement *)_document.processor.model.element;
    __block XFXMLElement *bind = nil;
    [self edit:^{
        bind = [self->_editor.hostEdit insertElementNamed:@"bind" underParent:model atIndex:-1 error:NULL];
    }];
    XCTAssertNotNil(bind);
    NSString *bindID = [[bind attributeForName:@"id"] stringValue];
    XCTAssertTrue([[XFDIDRefField identifiersOfKind:@"bind" inProcessor:_document.processor] containsObject:bindID]);
    _editor.selection = input;
    [control.controlBindField setStringValue:bindID];
    XCTAssertTrue([control.controlBindField isValid]);
    [self edit:^{ [attributes inspectorChanged:control.controlBindField]; }];
    XCTAssertEqualObjects([[input attributeForName:@"bind"] stringValue], bindID);
    [control.controlBindField setStringValue:@"no-such-bind"];
    XCTAssertFalse([control.controlBindField isValid]);
    [control.controlBindField setStringValue:bindID];

    // actions: a setvalue under a trigger gets its ev:event, the Action
    // page, and its rows apply
    __block XFXMLElement *trigger = nil;
    __block XFXMLElement *setvalue = nil;
    [self edit:^{
        trigger = [self->_editor.hostEdit insertElementNamed:@"trigger" underParent:body atIndex:-1 error:NULL];
        setvalue = [self->_editor.hostEdit insertElementNamed:@"setvalue" underParent:trigger atIndex:-1 error:NULL];
    }];
    XCTAssertNotNil(setvalue);
    XCTAssertEqualObjects([[setvalue attributeForName:@"ev:event"] stringValue], @"DOMActivate");
    _editor.selection = setvalue;
    XCTAssertEqual([self pageShown], XFDPageAction);
    XFDActionPage *action = attributes.actionPage;
    XCTAssertGreaterThanOrEqual(action.rows.count, 4u);
    id (^row)(NSString *) = ^id(NSString *attr) {
        for (NSDictionary *r in action.rows) {
            if ([r[@"attr"] isEqualToString:attr]) {
                return r[@"view"];
            }
        }
        return nil;
    };
    [row(@"ref") setStringValue:@"name"];
    [self edit:^{ [attributes inspectorChanged:row(@"ref")]; }];
    XCTAssertEqualObjects([[setvalue attributeForName:@"ref"] stringValue], @"name");
    XCTAssertNotNil(row(@"if"), @"the XForms 1.1 conditionals on every action");
    [row(@"if") setStringValue:@"name != ''"];
    [self edit:^{ [attributes inspectorChanged:row(@"if")]; }];
    XCTAssertEqualObjects([[setvalue attributeForName:@"if"] stringValue], @"name != ''");

    // the Events inspector lists the trigger's handlers; ev:observer
    // takes one to the element it names
    XFDEventsInspector *events = _window.inspectorViewController.eventsInspector;
    _editor.selection = trigger;
    XCTAssertEqual(events.handlerElements.count, 1u);
    XCTAssertEqual(events.handlerElements.firstObject, setvalue);
    XCTAssertEqual([events.table numberOfRows], 1);
    [self edit:^{ [self->_editor.hostEdit setAttribute:@"id" value:@"obs-target" onElement:input]; }];
    _editor.selection = setvalue;
    XCTAssertNotNil(row(@"ev:observer"));
    [row(@"ev:observer") setStringValue:@"obs-target"];
    [self edit:^{ [attributes inspectorChanged:row(@"ev:observer")]; }];
    _editor.selection = input;
    XCTAssertEqual(events.handlerElements.count, 1u);
    XCTAssertEqual(events.handlerElements.firstObject, setvalue, @"the observed element's");
    _editor.selection = trigger;
    XCTAssertEqual(events.handlerElements.count, 0u, @"no longer its parent's");

    // a dispatch's bubbles row, a popup
    __block XFXMLElement *dispatch = nil;
    [self edit:^{
        dispatch = [self->_editor.hostEdit insertElementNamed:@"dispatch" underParent:trigger atIndex:-1 error:NULL];
    }];
    _editor.selection = dispatch;
    XCTAssertNotNil(row(@"bubbles"));
    [(NSPopUpButton *)row(@"bubbles") selectItemWithTitle:@"false"];
    [self edit:^{ [attributes inspectorChanged:row(@"bubbles")]; }];
    XCTAssertEqualObjects([[dispatch attributeForName:@"bubbles"] stringValue], @"false");

    // design mode: the overlay armed, a widget hit-tested to its host
    // element, a pick selected
    XFDPreviewViewController *preview = [self preview];
    XFDDesignOverlay *overlay = preview.designOverlay;
    XCTAssertTrue([overlay isHidden]);
    [preview.designModeCheckbox setState:NSOnState];
    [preview toggleDesignMode:nil];
    XCTAssertFalse([overlay isHidden]);
    XFFormView *form = preview.formView;
    XFControl *inputControl = [_document.processor controlForElement:input];
    NSRect inputRect = [form layoutFrameOfControl:inputControl];
    XCTAssertFalse(NSIsEmptyRect(inputRect));
    XFControl *hit = [form controlAtPoint:NSMakePoint(NSMidX(inputRect), NSMidY(inputRect))];
    XCTAssertEqual(hit.element, input);
    _editor.selection = trigger;
    [preview overlay:overlay pickedElement:hit.element];
    XCTAssertEqual(_editor.selection, input);

    // a drag: the trigger's bottom band drops the input after it; undo
    // takes it back
    NSRect triggerRect = [form layoutFrameOfControl:[_document.processor controlForElement:trigger]];
    XCTAssertFalse(NSIsEmptyRect(triggerRect));
    NSDictionary *slot = [preview overlay:overlay
                      dropSlotAtFormPoint:NSMakePoint(NSMidX(triggerRect), NSMaxY(triggerRect) - 2)
                               forElement:input];
    XCTAssertEqual(slot[@"parent"], body);
    XCTAssertNotNil(slot[@"line"]);
    NSInteger inputBefore = (NSInteger)[input index];
    [preview overlay:overlay dropElement:input slot:slot];
    XCTAssertEqual([input parent], body);
    XCTAssertEqual((NSInteger)[input index], (NSInteger)[trigger index] + 1);
    [_undo undo];
    XCTAssertEqual((NSInteger)[input index], inputBefore);
    NSRect selfRect = [form layoutFrameOfControl:inputControl];
    XCTAssertNil([preview overlay:overlay dropSlotAtFormPoint:NSMakePoint(NSMidX(selfRect), NSMidY(selfRect))
                       forElement:input], @"onto its own middle: nowhere");

    // SVG: a painted shape hit-tested back to its element, and picked
    BOOL hasSVG = NO;
    for (NSView *sub in [form subviews]) {
        hasSVG = hasSVG || [sub isKindOfClass:[XFSVGView class]];
    }
    if (hasSVG) {
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
        XFXMLElement *svgHit = [form svgElementAtPoint:NSMakePoint(NSMidX(paintedRect), NSMidY(paintedRect))];
        XCTAssertNotNil(svgHit);
        [preview overlay:overlay pickedElement:svgHit];
        XCTAssertEqual(_editor.selection, svgHit);
    }
    [preview.designModeCheckbox setState:NSOffState];
    [preview toggleDesignMode:nil];
    XCTAssertTrue([overlay isHidden]);

    // item and itemset pages
    __block XFXMLElement *select1 = nil;
    __block XFXMLElement *itemset = nil;
    [self edit:^{
        select1 = [self->_editor.hostEdit insertElementNamed:@"select1" underParent:body atIndex:-1 error:NULL];
        itemset = [self->_editor.hostEdit insertElementNamed:@"itemset" underParent:select1 atIndex:-1 error:NULL];
    }];
    _editor.selection = itemset;
    XCTAssertEqual([self pageShown], XFDPageItemset);
    [attributes.itemsetPage.itemsetLabelRefField setStringValue:@"name"];
    [self edit:^{ [attributes inspectorChanged:attributes.itemsetPage.itemsetLabelRefField]; }];
    XCTAssertEqualObjects([_editor.hostEdit supportChildAttribute:@"ref" child:@"label" onElement:itemset], @"name");
    __block XFXMLElement *item = nil;
    [self edit:^{
        item = [self->_editor.hostEdit insertElementNamed:@"item" underParent:select1 atIndex:-1 error:NULL];
    }];
    _editor.selection = item;
    XCTAssertEqual([self pageShown], XFDPageItem);
    XCTAssertEqualObjects([attributes.itemPage.itemValueField stringValue], @"item");

    // a ref made a named bind in one gesture
    __block XFXMLElement *input2 = nil;
    [self edit:^{
        input2 = [self->_editor.hostEdit insertElementNamed:@"input" underParent:body atIndex:-1 error:NULL];
        [self->_editor.hostEdit setAttribute:@"ref" value:@"name" onElement:input2];
    }];
    _editor.selection = input2;
    [self edit:^{ [control createBindFromRef:nil]; }];
    NSString *newBindID = [[input2 attributeForName:@"bind"] stringValue];
    XCTAssertGreaterThan(newBindID.length, 0u);
    XCTAssertEqual([[[input2 attributeForName:@"ref"] stringValue] length], 0u);
    XFXMLElement *createdBind = nil;
    for (XFXMLElement *b in [XFXML elementsWithLocalName:@"bind" namespaceURI:XFXFormsNamespaceURI inNode:model]) {
        if ([[[b attributeForName:@"id"] stringValue] isEqualToString:newBindID]) {
            createdBind = b;
        }
    }
    XCTAssertEqualObjects([[createdBind attributeForName:@"nodeset"] stringValue], @"name");

    // a control made of instance data
    XFXMLElement *instance = [XFXML childElementWithLocalName:@"instance" namespaceURI:XFXFormsNamespaceURI
                                                    ofElement:model];
    XFXMLElement *dataRoot = [_editor elementChildrenOf:instance].firstObject;
    XFXMLElement *dataNode = [_editor elementChildrenOf:dataRoot].firstObject;
    if (dataNode != nil) {
        NSUInteger beforeBound = _document.processor.controls.count;
        _editor.selection = dataNode;
        XCTAssertEqual([self pageShown], XFDPageElement);
        XCTAssertTrue([attributes.elementPage.hostNewControlButton isEnabled]);
        [self edit:^{ [attributes.elementPage createBoundControlOfKind:@"input"]; }];
        XCTAssertEqual(_document.processor.controls.count, beforeBound + 1);
    }

    // the XPath fields validate
    [control.controlRefField setStringValue:@"//[bad(("];
    XCTAssertFalse([control.controlRefField isValid]);
    [control.controlRefField setStringValue:@"name"];
    XCTAssertTrue([control.controlRefField isValid]);

    // every edit undone: the form as it was
    while ([_undo canUndo]) {
        [_undo undo];
    }
    XCTAssertEqual(_document.processor.controls.count, before);
    (void)error;
}

- (void)testTheEditsOnHello
{
    [self runEditPassOnForm:@"hello"];
}

- (void)testTheEditsOnPiechart
{
    [self runEditPassOnForm:@"piechart"];
}

@end
