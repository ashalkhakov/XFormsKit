/* The inspectors, bound to the selection's editor: every field is bound
   to its key (validated where it is typed into), each page shows the
   selection's values and keeps up with changes made elsewhere, and what
   a field gives lands in the host document as one undoable change. The
   designer's window over hello.xhtml.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFXMLTypes.h>
#import "XFormsDesignKit.h"
#import "XFDInspectorPages.h"
#import "XFDActionPage.h"
#import "XFDEditors.h"
#import "XFDXPathField.h"
#import "XFDRichTextField.h"
#import "XFDIDRefField.h"

/// An XPath field that records the error it would present.
@interface XFDRecordingXPathField : XFDXPathField
@property (nonatomic, strong) NSError *presented;
@end

@implementation XFDRecordingXPathField
- (void)presentError:(NSError *)error modalForWindow:(NSWindow *)window delegate:(id)delegate
  didPresentSelector:(SEL)selector contextInfo:(void *)info
{
    (void)window; (void)delegate; (void)selector; (void)info;
    self.presented = error;
}
@end

@interface XFDInspectorTests : XCTestCase
@end

@implementation XFDInspectorTests {
    XFDDocument *_document;
    XFDWindowController *_window;
    XFDFormEditor *_editor;
    NSUndoManager *_undo;
}

- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
    NSError *error = nil;
    NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"hello" ofType:@"xhtml"];
    _document = [[XFDDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]
                                                    ofType:@"XHTML+XForms" error:&error];
    XCTAssertNotNil(_document, @"%@", error);
    [_document makeWindowControllers];
    _window = [[_document windowControllers] firstObject];
    XCTAssertNotNil([_window window], @"the window's XIB loads, and the parts' with it");
    _editor = _document.formEditor;
    _undo = _editor.undoManager;
    // headless: no run loop closes the group an event would open; explicit
    // groups only
    [_undo setGroupsByEvent:NO];
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

- (XFDIdentityInspector *)identity
{
    return _window.inspectorViewController.identityInspector;
}

- (XFDControlPage *)controlPage
{
    return [self attributes].controlPage;
}

/// hello's input, on the name.
- (XFXMLElement *)input
{
    XFXMLElement *group = [_editor elementChildrenOf:[_editor bodyElement]].firstObject;
    return [_editor elementChildrenOf:group].firstObject;
}

- (XFXMLElement *)model
{
    return (XFXMLElement *)_document.processor.model.element;
}

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

/// `field` given `value` as typed, and committed.
- (void)give:(NSString *)value to:(id)field
{
    [field setStringValue:value];
    [self edit:^{ XCTAssertTrue([field commitEditing]); }];
}

/// The action page's field for `attr`.
- (id)rowFor:(NSString *)attr
{
    for (NSDictionary *row in [self attributes].actionPage.rows) {
        if ([row[@"attr"] isEqualToString:attr]) {
            return row[@"view"];
        }
    }
    return nil;
}

#pragma mark The bindings, as the XIBs make them

- (void)assertField:(id)field ofPage:(XFDInspectorPage *)page binding:(NSString *)binding
                key:(NSString *)key validated:(BOOL)validated
{
    NSDictionary *info = [field infoForBinding:binding];
    XCTAssertNotNil(info, @"%@ is bound (%@)", key, binding);
    XCTAssertEqual(info[NSObservedObjectKey], page.editorController, @"%@: to the page's editor", key);
    XCTAssertEqualObjects(info[NSObservedKeyPathKey], [@"content." stringByAppendingString:key]);
    XCTAssertEqual([info[NSOptionsKey][NSValidatesImmediatelyBindingOption] boolValue], validated,
                   @"%@ validated as typed", key);
}

- (void)testEveryControlFieldIsBoundToItsKey
{
    XFDControlPage *p = [self controlPage];
    NSDictionary *fields = @{ @"controlRefField": @"ref", @"controlValueField": @"valueExpression",
                              @"controlBindField": @"bind", @"controlModelField": @"model",
                              @"controlSubmissionField": @"submission", @"controlMediatypeField": @"mediatype",
                              @"controlLabelField": @"labelContent", @"controlHintField": @"hintContent",
                              @"controlHelpField": @"helpContent", @"controlAlertField": @"alertContent" };
    for (NSString *outlet in fields) {
        [self assertField:[p valueForKey:outlet] ofPage:p binding:NSValueBinding key:fields[outlet] validated:YES];
    }
    [self assertField:p.controlIncrementalCheckbox ofPage:p binding:NSValueBinding key:@"incremental" validated:NO];
    [self assertField:p.controlAppearancePopup ofPage:p binding:NSSelectedValueBinding key:@"appearanceTitle"
            validated:NO];
    [self assertField:p.controlBindingStatusField ofPage:p binding:NSValueBinding key:@"bindingStatus" validated:NO];
    [self assertField:p.controlValueField ofPage:p binding:NSEnabledBinding key:@"takesValueExpression" validated:NO];
    [self assertField:p.controlSubmissionField ofPage:p binding:NSEnabledBinding key:@"takesSubmission" validated:NO];
    [self assertField:p.controlCreateBindButton ofPage:p binding:NSEnabledBinding key:@"canCreateBind" validated:NO];
}

- (void)testEveryOtherPagesFieldIsBoundToItsKey
{
    XFDAttributesInspector *a = [self attributes];
    NSArray *pages = @[
        @[ a.bindPage, @{ @"bindNodesetField": @"nodeset", @"bindTypeField": @"typeName",
                          @"bindCalculateField": @"calculate", @"bindConstraintField": @"constraint",
                          @"bindRequiredField": @"required", @"bindRelevantField": @"relevant",
                          @"bindReadonlyField": @"readonly" } ],
        @[ a.submissionPage, @{ @"submissionResourceField": @"resource", @"submissionMethodField": @"method",
                                @"submissionInstanceField": @"instance", @"submissionRefField": @"ref",
                                @"submissionBindField": @"bind" } ],
        @[ a.instancePage, @{ @"instanceSrcField": @"src" } ],
        @[ a.itemPage, @{ @"itemLabelField": @"labelContent", @"itemValueField": @"valueText" } ],
        @[ a.itemsetPage, @{ @"itemsetNodesetField": @"nodeset", @"itemsetBindField": @"bind",
                             @"itemsetLabelRefField": @"labelRef", @"itemsetValueRefField": @"valueRef" } ],
    ];
    for (NSArray *pair in pages) {
        XFDInspectorPage *page = pair[0];
        NSDictionary *fields = pair[1];
        for (NSString *outlet in fields) {
            [self assertField:[page valueForKey:outlet] ofPage:page binding:NSValueBinding
                          key:fields[outlet] validated:YES];
        }
    }
    [self assertField:a.submissionPage.submissionReplacePopup ofPage:a.submissionPage
              binding:NSSelectedValueBinding key:@"replaceTitle" validated:NO];
    [self assertField:a.elementPage.hostNewControlButton ofPage:a.elementPage
              binding:NSEnabledBinding key:@"takesBoundControl" validated:NO];
}

- (void)testTheIdentityFieldsAreBound
{
    XFDIdentityInspector *identity = [self identity];
    NSDictionary *info = [identity.identityIdField infoForBinding:NSValueBinding];
    XCTAssertEqual(info[NSObservedObjectKey], identity.editorController);
    XCTAssertEqualObjects(info[NSObservedKeyPathKey], @"content.identifier");
    XCTAssertTrue([info[NSOptionsKey][NSValidatesImmediatelyBindingOption] boolValue]);
    XCTAssertEqualObjects([identity.identityTitleField infoForBinding:NSValueBinding][NSObservedKeyPathKey],
                          @"content.title");
}

- (void)testTheCustomFieldsAreSetUpByTheXIB
{
    XFDControlPage *p = [self controlPage];
    XCTAssertEqual(p.controlRefField.provider, p);
    XCTAssertEqual(p.controlLabelField.provider, p);
    XCTAssertEqual(p.controlBindField.provider, p);
    XCTAssertEqualObjects(p.controlBindField.kind, @"bind");
    XCTAssertEqualObjects(p.controlModelField.kind, @"model");
    XCTAssertEqual(p.controlValueField.expectation, XFDXPathExpectValue);
    XCTAssertEqual([self attributes].bindPage.bindNodesetField.expectation, XFDXPathExpectNodeSet);
    XCTAssertEqualObjects([self attributes].submissionPage.submissionInstanceField.kind, @"instance");
}

- (void)testTheKindMenuIsTheXIBs
{
    NSMenu *menu = [self attributes].elementPage.controlKindMenu;
    XCTAssertEqualObjects([[menu itemArray] valueForKey:@"title"],
                          (@[ @"input", @"textarea", @"secret", @"select1", @"select", @"range", @"output", @"upload" ]));
    XCTAssertEqual([[menu itemAtIndex:0] target], [self attributes].elementPage);
}

#pragma mark Showing the selection

- (void)testNoSelectionShowsNoSelection
{
    _editor.selection = nil;
    XCTAssertEqualObjects([[[self identity].identityTitleField cell] placeholderString], @"No Selection");
    XCTAssertFalse([[self identity].identityIdField isEnabled]);
}

- (void)testAControlsValuesAreShown
{
    _editor.selection = [self input];
    XFDControlPage *p = [self controlPage];
    XCTAssertEqualObjects([p.controlRefField stringValue], @"name");
    XCTAssertEqualObjects([p.controlLabelField stringValue], @"Name");
    XCTAssertEqualObjects([p.controlBindingStatusField stringValue], @"Bound in place via ref.");
    XCTAssertEqualObjects([p.controlAppearancePopup titleOfSelectedItem], @"(default)");
    XCTAssertTrue([p.controlCreateBindButton isEnabled]);
    XCTAssertTrue([[[self identity].identityTitleField stringValue] hasPrefix:@"xf:input"]);
    XCTAssertTrue([[self identity].identityIdField isEnabled]);
}

- (void)testAnInputHasNoValueExpression
{
    _editor.selection = [self input];
    XCTAssertEqualObjects([[self controlPage].controlValueField stringValue], @"");
}

- (void)testAChangeElsewhereIsShown
{
    XFXMLElement *input = [self input];
    _editor.selection = input;
    [self edit:^{ [self->_editor.hostEdit setAttribute:@"ref" value:@"other" onElement:input]; }];
    XCTAssertEqualObjects([[self controlPage].controlRefField stringValue], @"other");
}

- (void)testAnUndoIsShown
{
    _editor.selection = [self input];
    [self give:@"Your name" to:[self controlPage].controlLabelField];
    [_undo undo];
    XCTAssertEqualObjects([[self controlPage].controlLabelField stringValue], @"Name");
}

- (void)testARichLabelIsShownFlattenedAndKept
{
    XFXMLElement *input = [self input];
    [self edit:^{
        [self->_editor.hostEdit setSupportChild:@"label"
                                     contentXML:@"Nom <strong>complet</strong> <xf:output value=\"'x'\"/>"
                                      onElement:input error:NULL];
    }];
    _editor.selection = input;
    XFDRichTextField *label = [self controlPage].controlLabelField;
    XCTAssertTrue([label isRich]);
    XCTAssertTrue([[label stringValue] containsString:@"Nom complet"]);
    XCTAssertTrue([label commitEditing], @"nothing changed, nothing given");
    XCTAssertTrue([[_editor.hostEdit supportChildXML:@"label" onElement:input] containsString:@"<strong>complet</strong>"]);
}

- (void)testAnItemsValueIsShown
{
    XFXMLElement *select1 = [self insert:@"select1" under:[_editor bodyElement]];
    _editor.selection = [self insert:@"item" under:select1];
    XCTAssertEqualObjects([[self attributes].itemPage.itemValueField stringValue], @"item");
}

#pragma mark What a field gives

- (void)testALabelGivenLandsInTheHost
{
    XFXMLElement *input = [self input];
    _editor.selection = input;
    [self give:@"Your name" to:[self controlPage].controlLabelField];
    XCTAssertEqualObjects([_editor.hostEdit supportChildText:@"label" onElement:input], @"Your name");
    XCTAssertTrue([_undo canUndo], @"one undoable change");
}

- (void)testABindPickedLandsAsTheBindAttribute
{
    XFXMLElement *input = [self input];
    XFXMLElement *bind = [self insert:@"bind" under:[self model]];
    NSString *bindID = [[bind attributeForName:@"id"] stringValue];
    _editor.selection = input;
    XFDIDRefField *field = [self controlPage].controlBindField;
    [self give:bindID to:field];
    XCTAssertTrue([field isValid]);
    XCTAssertEqualObjects([[input attributeForName:@"bind"] stringValue], bindID);
    XCTAssertEqualObjects([[self controlPage].controlBindingStatusField stringValue],
                          ([NSString stringWithFormat:@"Bound via bind ‘%@’.", bindID]));
}

- (void)testADanglingBindIsFlagged
{
    _editor.selection = [self input];
    XFDIDRefField *field = [self controlPage].controlBindField;
    [field setStringValue:@"no-such-bind"];
    XCTAssertFalse([field isValid]);
}

- (void)testAnItemsetsLabelRefLands
{
    XFXMLElement *select1 = [self insert:@"select1" under:[_editor bodyElement]];
    XFXMLElement *itemset = [self insert:@"itemset" under:select1];
    _editor.selection = itemset;
    [self give:@"name" to:[self attributes].itemsetPage.itemsetLabelRefField];
    XCTAssertEqualObjects([_editor.hostEdit supportChildAttribute:@"ref" child:@"label" onElement:itemset], @"name");
}

- (void)testAPopUpPickLands
{
    XFXMLElement *input = [self input];
    _editor.selection = input;
    NSPopUpButton *popup = [self controlPage].controlAppearancePopup;
    [popup selectItemWithTitle:@"minimal"];
    [self edit:^{ [popup sendAction:[popup action] to:[popup target]]; }];
    XCTAssertEqualObjects([[input attributeForName:@"appearance"] stringValue], @"minimal");
}

- (void)testACheckboxClickLands
{
    XFXMLElement *input = [self input];
    _editor.selection = input;
    [self edit:^{ [[self controlPage].controlIncrementalCheckbox performClick:nil]; }];
    XCTAssertEqualObjects([[input attributeForName:@"incremental"] stringValue], @"true");
}

/// A text field typed into and left, as the author does: the edited value
/// given when editing ends, through its binding.
- (void)testAnIdTypedLandsWhenEditingEnds
{
    XFXMLElement *input = [self input];
    _editor.selection = input;
    NSWindow *window = [_window window];
    [window makeKeyAndOrderFront:nil];
    [_window.inspectorViewController showInspector:[self identity]];
    NSTextField *field = [self identity].identityIdField;
    XCTAssertEqual([field window], window, @"the Identity inspector shown");
    XCTAssertTrue([window makeFirstResponder:field]);
    NSText *text = [field currentEditor];
    XCTAssertNotNil(text, @"the field edited");
    // typed, as a key press inserts: setting the text is no edit to AppKit;
    // the typing's own undo, which would open groups of its own on the
    // document's undo manager, is no part of this
    [(NSTextView *)text setAllowsUndo:NO];
    [text selectAll:nil];
    [(NSTextView *)text insertText:@"your-name" replacementRange:NSMakeRange(NSNotFound, 0)];
    [self edit:^{ XCTAssertTrue([window makeFirstResponder:nil]); }];
    XCTAssertEqualObjects([[input attributeForName:@"id"] stringValue], @"your-name");
    XCTAssertTrue([[[self identity].identityTitleField stringValue] hasSuffix:@"your-name"], @"the title follows");
}

#pragma mark Refused values

- (void)testAnExpressionThatDoesNotCompileIsRefusedAndKept
{
    XFXMLElement *input = [self input];
    _editor.selection = input;
    XFDControlPage *p = [self controlPage];
    XFDRecordingXPathField *field = [[XFDRecordingXPathField alloc] initWithFrame:NSMakeRect(0, 0, 200, 21)];
    field.provider = p;
    [field bind:NSValueBinding toObject:p.editorController withKeyPath:@"content.ref"
        options:@{ NSValidatesImmediatelyBindingOption: @YES }];
    XCTAssertEqualObjects([field stringValue], @"name");
    [field setStringValue:@"//[bad(("];
    XCTAssertFalse([field isValid], @"marked as typed");
    XCTAssertFalse([field commitEditing]);
    XCTAssertEqualObjects(field.presented.domain, XFDEditorErrorDomain, @"the editor's reason, presented");
    XCTAssertEqualObjects([field stringValue], @"//[bad((", @"kept for the author to correct");
    XCTAssertEqualObjects([[input attributeForName:@"ref"] stringValue], @"name", @"the host unchanged");
    [field unbind:NSValueBinding];
}

- (void)testAnIdThatIsTakenIsRefused
{
    XFXMLElement *other = [self insert:@"trigger" under:[_editor bodyElement]];
    _editor.selection = [self input];
    id taken = [[other attributeForName:@"id"] stringValue];
    NSError *error = nil;
    XCTAssertFalse([[self identity].editorController validateValue:&taken forKeyPath:@"content.identifier"
                                                             error:&error]);
    XCTAssertEqualObjects(error.domain, XFDEditorErrorDomain);
}

#pragma mark Actions

- (void)testAnActionsRowsAreItsAttributes
{
    XFXMLElement *trigger = [self insert:@"trigger" under:[_editor bodyElement]];
    _editor.selection = [self insert:@"setvalue" under:trigger];
    XCTAssertEqual([[self attributes].kindTabView indexOfTabViewItem:[[self attributes].kindTabView selectedTabViewItem]],
                   XFDPageAction);
    XCTAssertGreaterThanOrEqual([self attributes].actionPage.rows.count, 4u);
    XCTAssertEqualObjects([[self rowFor:@"ev:event"] stringValue], @"DOMActivate");
    XCTAssertNotNil([self rowFor:@"if"], @"the XForms 1.1 conditionals on every action");
    XCTAssertEqualObjects([[self rowFor:@"ref"] toolTip], @"The node whose value is set (§10.2).");
}

- (void)testAnActionsRowsLand
{
    XFXMLElement *trigger = [self insert:@"trigger" under:[_editor bodyElement]];
    XFXMLElement *setvalue = [self insert:@"setvalue" under:trigger];
    _editor.selection = setvalue;
    [self give:@"name" to:[self rowFor:@"ref"]];
    [self give:@"name != ''" to:[self rowFor:@"if"]];
    XCTAssertEqualObjects([[setvalue attributeForName:@"ref"] stringValue], @"name");
    XCTAssertEqualObjects([[setvalue attributeForName:@"if"] stringValue], @"name != ''");
}

- (void)testAnActionsPopUpRowLands
{
    XFXMLElement *trigger = [self insert:@"trigger" under:[_editor bodyElement]];
    XFXMLElement *dispatch = [self insert:@"dispatch" under:trigger];
    _editor.selection = dispatch;
    NSPopUpButton *bubbles = [self rowFor:@"bubbles"];
    XCTAssertEqualObjects([bubbles titleOfSelectedItem], @"(default)");
    [bubbles selectItemWithTitle:@"false"];
    [self edit:^{ [bubbles sendAction:[bubbles action] to:[bubbles target]]; }];
    XCTAssertEqualObjects([[dispatch attributeForName:@"bubbles"] stringValue], @"false");
}

- (void)testAnObserverMovesTheHandler
{
    XFXMLElement *input = [self input];
    XFXMLElement *trigger = [self insert:@"trigger" under:[_editor bodyElement]];
    XFXMLElement *setvalue = [self insert:@"setvalue" under:trigger];
    [self edit:^{ [self->_editor.hostEdit setAttribute:@"id" value:@"obs-target" onElement:input]; }];
    XFDEventsInspector *events = _window.inspectorViewController.eventsInspector;
    _editor.selection = trigger;
    XCTAssertEqual(events.handlerElements.firstObject, setvalue);
    _editor.selection = setvalue;
    [self give:@"obs-target" to:[self rowFor:@"ev:observer"]];
    _editor.selection = input;
    XCTAssertEqual(events.handlerElements.firstObject, setvalue, @"the observed element's");
    _editor.selection = trigger;
    XCTAssertEqual(events.handlerElements.count, 0u, @"no longer its parent's");
}

- (void)testTheRowsStayWhileTheActionDoes
{
    XFXMLElement *trigger = [self insert:@"trigger" under:[_editor bodyElement]];
    _editor.selection = [self insert:@"setvalue" under:trigger];
    id before = [self rowFor:@"ref"];
    [self give:@"name" to:before];
    XCTAssertEqual([self rowFor:@"ref"], before, @"an edit keeps the row, and its focus");
}

#pragma mark The pages' commands

- (void)testARefMadeANamedBind
{
    XFXMLElement *input = [self insert:@"input" under:[_editor bodyElement]];
    [self edit:^{ [self->_editor.hostEdit setAttribute:@"ref" value:@"name" onElement:input]; }];
    _editor.selection = input;
    [self edit:^{ [[self controlPage] createBindFromRef:nil]; }];
    NSString *bindID = [[input attributeForName:@"bind"] stringValue];
    XCTAssertGreaterThan(bindID.length, 0u);
    XCTAssertNil([input attributeForName:@"ref"]);
    XCTAssertFalse([[self controlPage].controlCreateBindButton isEnabled], @"bound by bind now");
}

- (void)testAControlMadeOfInstanceData
{
    XFXMLElement *instance = [XFXML childElementWithLocalName:@"instance" namespaceURI:XFXFormsNamespaceURI
                                                    ofElement:[self model]];
    XFXMLElement *dataRoot = [_editor elementChildrenOf:instance].firstObject;
    XFXMLElement *dataNode = [_editor elementChildrenOf:dataRoot].firstObject;
    XCTAssertNotNil(dataNode);
    NSUInteger before = _document.processor.controls.count;
    _editor.selection = dataNode;
    XFDElementPage *page = [self attributes].elementPage;
    XCTAssertTrue([page.hostNewControlButton isEnabled]);
    [self edit:^{ [page boundControlKindPicked:[page.controlKindMenu itemAtIndex:0]]; }];
    XCTAssertEqual(_document.processor.controls.count, before + 1);
}

- (void)testNoControlIsOfferedForMarkup
{
    _editor.selection = [_editor bodyElement];
    XCTAssertFalse([[self attributes].elementPage.hostNewControlButton isEnabled]);
}

@end
