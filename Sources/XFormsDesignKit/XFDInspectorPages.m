/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDInspectorPages.h"
#import "XFDAttributesInspector.h"
#import "XFDFormEditor.h"
#import "XFDEditors.h"
#import "XFDInspectorSpecs.h"
#import "XFDInstanceXMLEditor.h"
#import "XFDSubmissionTester.h"

@implementation XFDInspectorPage

- (XFDFormEditor *)formEditor
{
    return self.inspector.formEditor;
}

- (void)setUp
{
    for (XFDXPathField *field in [self xpathFields]) {
        field.provider = self;
        field.target = self.inspector;
        field.action = @selector(inspectorChanged:);
    }
    for (XFDRichTextField *field in [self richTextFields]) {
        field.provider = self;
        field.target = self.inspector;
        field.action = @selector(inspectorChanged:);
    }
    NSDictionary *kinds = [self idRefFieldKinds];
    for (NSString *outlet in kinds) {
        XFDIDRefField *field = [self valueForKey:outlet];
        field.kind = kinds[outlet];
        field.provider = self;
        field.target = self.inspector;
        field.action = @selector(inspectorChanged:);
    }
}

- (void)fill
{
}

- (void)apply
{
}

- (NSArray<XFDXPathField *> *)xpathFields
{
    return @[];
}

- (NSArray<XFDRichTextField *> *)richTextFields
{
    return @[];
}

- (NSDictionary<NSString *, NSString *> *)idRefFieldKinds
{
    return @{};
}

- (void)applyRichField:(XFDRichTextField *)field name:(NSString *)name toEditor:(XFDElementEditor *)editor
{
    if ([field isRich]) {
        [editor setValue:[field xmlValue] forKey:[name stringByAppendingString:@"XML"]];
    } else {
        [editor setValue:[field stringValue] forKey:[name stringByAppendingString:@"Text"]];
    }
}

#pragma mark The fields' providers

- (XFXMLElement *)hostElementForXPathField:(XFDXPathField *)field
{
    (void)field;
    return self.formEditor.selection;
}

- (XFProcessor *)processorForXPathField:(XFDXPathField *)field
{
    (void)field;
    return self.formEditor.processor;
}

- (XFXMLNode *)contextNodeForXPathField:(XFDXPathField *)field
{
    (void)field;
    return [self.formEditor contextNodeForSelectionNodeset:NO];
}

- (XFXMLElement *)hostElementForRichTextField:(XFDRichTextField *)field
{
    (void)field;
    return self.formEditor.selection;
}

- (XFProcessor *)processorForRichTextField:(XFDRichTextField *)field
{
    (void)field;
    return self.formEditor.processor;
}

/// Outputs inside a label, hint, help or alert evaluate against the
/// control's OWN bound node (the engine's childContextFrom:), so the
/// picker's Relative style starts there.
- (XFXMLNode *)contextNodeForRichTextField:(XFDRichTextField *)field
{
    (void)field;
    return [self.formEditor contextNodeForSelectionContent];
}

- (XFProcessor *)processorForIDRefField:(XFDIDRefField *)field
{
    (void)field;
    return self.formEditor.processor;
}

@end

#pragma mark - Control

@implementation XFDControlPage

- (void)setUp
{
    [super setUp];
    self.controlValueField.expectation = XFDXPathExpectValue;
}

- (NSArray<XFDXPathField *> *)xpathFields
{
    return @[ self.controlRefField, self.controlValueField ];
}

- (NSArray<XFDRichTextField *> *)richTextFields
{
    return @[ self.controlLabelField, self.controlHintField, self.controlHelpField, self.controlAlertField ];
}

- (NSDictionary<NSString *, NSString *> *)idRefFieldKinds
{
    return @{ @"controlBindField": @"bind", @"controlModelField": @"model",
              @"controlSubmissionField": @"submission" };
}

/// How the control is bound, said under its Bind field.
- (void)refreshBindingStatusForEditor:(XFDControlEditor *)e
{
    NSTextField *status = self.controlBindingStatusField;
    XFXMLElement *selected = self.formEditor.selection;
    if (e.bind.length) {
        if ([[XFDIDRefField identifiersOfKind:@"bind" inProcessor:self.formEditor.processor]
                containsObject:e.bind]) {
            [status setStringValue:[NSString stringWithFormat:@"Bound via bind ‘%@’.", e.bind]];
            [status setTextColor:[NSColor disabledControlTextColor]];
        } else {
            [status setStringValue:[NSString stringWithFormat:@"Bind ‘%@’ does not exist.", e.bind]];
            [status setTextColor:[NSColor redColor]];
        }
        return;
    }
    if (e.ref.length) {
        [status setStringValue:@"Bound in place via ref."];
        [status setTextColor:[NSColor disabledControlTextColor]];
        return;
    }
    if ([[selected localName] isEqualToString:@"output"] && [e attribute:@"value"].length) {
        [status setStringValue:@"Computed via value expression."];
        [status setTextColor:[NSColor disabledControlTextColor]];
        return;
    }
    if (selected != nil && XFDElementIsUnbound(selected)) {
        [status setStringValue:@"Unbound — typed values are not kept."];
        [status setTextColor:XFDWarningColor()];
        return;
    }
    [status setStringValue:@""];
}

- (void)fill
{
    XFXMLElement *selected = self.formEditor.selection;
    XFDControlEditor *e = [XFDControlEditor editorForElement:selected formEditor:self.formEditor];
    // a repeat's ref selects the nodeset it iterates; every other control
    // binds one node
    self.controlRefField.expectation = [[selected localName] isEqualToString:@"repeat"]
        ? XFDXPathExpectNodeSet : XFDXPathExpectNode;
    [self.controlRefField setStringValue:e.ref];
    // @value is xf:output's computed expression, dead weight elsewhere
    BOOL isOutput = [[selected localName] isEqualToString:@"output"];
    [self.controlValueField setStringValue:isOutput ? e.valueExpression : @""];
    [self.controlValueField setEnabled:isOutput];
    [self.controlBindField setStringValue:e.bind];
    [self refreshBindingStatusForEditor:e];
    [self.controlCreateBindButton setEnabled:e.ref.length > 0 && e.bind.length == 0];
    [self.controlModelField setStringValue:e.model];
    // @submission is xf:submit's attribute, dead weight elsewhere
    BOOL isSubmit = [[selected localName] isEqualToString:@"submit"];
    [self.controlSubmissionField setStringValue:isSubmit ? e.submission : @""];
    [self.controlSubmissionField setEnabled:isSubmit];
    NSString *appearance = e.appearance;
    NSInteger idx = appearance.length ? [self.controlAppearancePopup indexOfItemWithTitle:appearance] : 0;
    [self.controlAppearancePopup selectItemAtIndex:idx >= 0 ? idx : 0];
    [self.controlIncrementalCheckbox setState:e.isIncremental ? NSOnState : NSOffState];
    [self.controlMediatypeField setStringValue:e.mediatype];
    [self.controlLabelField setPlainText:e.labelText xml:e.labelXML];
    [self.controlHintField setPlainText:e.hintText xml:e.hintXML];
    [self.controlHelpField setPlainText:e.helpText xml:e.helpXML];
    [self.controlAlertField setPlainText:e.alertText xml:e.alertXML];
}

- (void)apply
{
    XFXMLElement *selected = self.formEditor.selection;
    XFDControlEditor *e = [XFDControlEditor editorForElement:selected formEditor:self.formEditor];
    e.ref = [self.controlRefField stringValue];
    if ([[selected localName] isEqualToString:@"output"]) {
        e.valueExpression = [self.controlValueField stringValue];
    }
    e.bind = [self.controlBindField stringValue];
    e.model = [self.controlModelField stringValue];
    if ([[selected localName] isEqualToString:@"submit"]) {
        e.submission = [self.controlSubmissionField stringValue];
    }
    NSInteger idx = [self.controlAppearancePopup indexOfSelectedItem];
    e.appearance = idx <= 0 ? @"" : [self.controlAppearancePopup titleOfSelectedItem];
    e.incremental = [self.controlIncrementalCheckbox state] == NSOnState;
    e.mediatype = [self.controlMediatypeField stringValue];
    [self applyRichField:self.controlLabelField name:@"label" toEditor:e];
    [self applyRichField:self.controlHintField name:@"hint" toEditor:e];
    [self applyRichField:self.controlHelpField name:@"help" toEditor:e];
    [self applyRichField:self.controlAlertField name:@"alert" toEditor:e];
}

- (IBAction)createBindFromRef:(id)sender
{
    (void)sender;
    if (![self.formEditor createBindFromSelectedRef:NULL]) {
        XFDBeep();
    }
}

@end

#pragma mark - Bind

@implementation XFDBindPage

- (void)setUp
{
    [super setUp];
    self.bindNodesetField.expectation = XFDXPathExpectNodeSet;
    for (XFDXPathField *field in @[ self.bindCalculateField, self.bindConstraintField, self.bindRequiredField,
                                    self.bindRelevantField, self.bindReadonlyField ]) {
        field.expectation = XFDXPathExpectValue;
    }
}

- (NSArray<XFDXPathField *> *)xpathFields
{
    return @[ self.bindNodesetField, self.bindCalculateField, self.bindConstraintField,
              self.bindRequiredField, self.bindRelevantField, self.bindReadonlyField ];
}

/// The nodeset in the outer bind's context; the model item properties
/// per bound node.
- (XFXMLNode *)contextNodeForXPathField:(XFDXPathField *)field
{
    return [self.formEditor contextNodeForSelectionNodeset:field == self.bindNodesetField];
}

- (void)fill
{
    XFDBindEditor *e = [XFDBindEditor editorForElement:self.formEditor.selection formEditor:self.formEditor];
    [self.bindNodesetField setStringValue:e.nodeset];
    [self.bindTypeField setStringValue:e.typeName];
    [self.bindCalculateField setStringValue:e.calculate];
    [self.bindConstraintField setStringValue:e.constraint];
    [self.bindRequiredField setStringValue:e.required];
    [self.bindRelevantField setStringValue:e.relevant];
    [self.bindReadonlyField setStringValue:e.readonly];
}

- (void)apply
{
    XFDBindEditor *e = [XFDBindEditor editorForElement:self.formEditor.selection formEditor:self.formEditor];
    e.nodeset = [self.bindNodesetField stringValue];
    e.typeName = [self.bindTypeField stringValue];
    e.calculate = [self.bindCalculateField stringValue];
    e.constraint = [self.bindConstraintField stringValue];
    e.required = [self.bindRequiredField stringValue];
    e.relevant = [self.bindRelevantField stringValue];
    e.readonly = [self.bindReadonlyField stringValue];
}

@end

#pragma mark - Submission

@implementation XFDSubmissionPage

- (void)setUp
{
    [super setUp];
    self.submissionRefField.expectation = XFDXPathExpectNode;
}

- (NSArray<XFDXPathField *> *)xpathFields
{
    return @[ self.submissionRefField ];
}

- (NSDictionary<NSString *, NSString *> *)idRefFieldKinds
{
    return @{ @"submissionInstanceField": @"instance", @"submissionBindField": @"bind" };
}

- (void)fill
{
    XFDSubmissionEditor *e = [XFDSubmissionEditor editorForElement:self.formEditor.selection
                                                        formEditor:self.formEditor];
    [self.submissionResourceField setStringValue:e.resource];
    [self.submissionMethodField setStringValue:e.method];
    NSString *replace = e.replace;
    NSInteger idx = replace.length ? [self.submissionReplacePopup indexOfItemWithTitle:replace] : 0;
    [self.submissionReplacePopup selectItemAtIndex:idx >= 0 ? idx : 0];
    [self.submissionInstanceField setStringValue:e.instance];
    [self.submissionBindField setStringValue:e.bind];
    [self.submissionRefField setStringValue:e.ref];
}

- (void)apply
{
    XFDSubmissionEditor *e = [XFDSubmissionEditor editorForElement:self.formEditor.selection
                                                        formEditor:self.formEditor];
    e.resource = [self.submissionResourceField stringValue];
    e.method = [self.submissionMethodField stringValue];
    NSInteger idx = [self.submissionReplacePopup indexOfSelectedItem];
    e.replace = idx <= 0 ? @"" : [self.submissionReplacePopup titleOfSelectedItem];
    e.instance = [self.submissionInstanceField stringValue];
    e.bind = [self.submissionBindField stringValue];
    e.ref = [self.submissionRefField stringValue];
}

- (IBAction)testSubmission:(id)sender
{
    (void)sender;
    [XFDSubmissionTester runForProcessor:self.formEditor.processor
                       initialSubmission:[[self.formEditor.selection attributeForName:@"id"] stringValue]];
}

@end

#pragma mark - Instance

@implementation XFDInstancePage

- (void)fill
{
    XFDInstanceEditor *e = [XFDInstanceEditor editorForElement:self.formEditor.selection
                                                    formEditor:self.formEditor];
    [self.instanceSrcField setStringValue:e.src];
}

- (void)apply
{
    XFDInstanceEditor *e = [XFDInstanceEditor editorForElement:self.formEditor.selection
                                                    formEditor:self.formEditor];
    e.src = [self.instanceSrcField stringValue];
}

- (IBAction)editInstanceXML:(id)sender
{
    (void)sender;
    NSError *error = nil;
    if (![XFDInstanceXMLEditor editInstanceOfElement:self.formEditor.selection
                                        inFormEditor:self.formEditor error:&error]
        && error != nil) {
        [self.inspector presentError:error];
    }
}

@end

#pragma mark - Action

@implementation XFDActionPage {
    XFXMLElement *_element;
}

@synthesize rows = _rows;

/// Held by the perform request until the run loop turns; see below.
- (void)releaseRetiredRows:(NSArray *)retired
{
    (void)retired;
}

/// The rows (re)made for the selected action, only when the element
/// changed: a row keeps its editor and focus while nothing about the
/// element's shape did.
- (void)buildRowsIfNeededForElement:(XFXMLElement *)element
{
    if (_element == element && _rows != nil) {
        return;
    }
    // The old rows leave the page now but stay alive until the event is
    // over: a rebuild can run from inside a row's own action, and AppKit
    // goes on using the sender after the action returns (a button's
    // -[NSControl mouseDown:] still has its cell to finish with; GNUstep's
    // -[NSTextField textDidEndEditing:] asks its window for the first
    // responder). The form view retires its widgets the same way.
    NSView *host = self.actionRowsHost;
    NSArray *retired = [[host subviews] copy];
    for (NSView *sub in retired) {
        [sub removeFromSuperview];
    }
    if (retired.count) {
        [self performSelector:@selector(releaseRetiredRows:) withObject:retired afterDelay:0];
    }
    NSMutableArray *rows = [NSMutableArray array];
    NSArray *specs = XFDActionSpecs()[[element localName]] ?: @[];
    // every handler starts with its trigger, the XML Events attribute
    // module's observer/target redirections, and the XForms 1.1 §10.1.1
    // conditionals: if (condition), while (iteration) — plus iterate,
    // the XSLTForms / 2.0 extension the engine also compiles
    NSMutableArray *all = [NSMutableArray arrayWithArray:@[
        @{ @"label": @"Event", @"attr": @"ev:event", @"kind": @"idref", @"idkind": @"#event",
           @"tip": @"The event this handler listens for — on its parent element, or on the Observer when set (XML Events)." },
        @{ @"label": @"Observer", @"attr": @"ev:observer", @"kind": @"idref", @"idkind": @"*",
           @"tip": @"Listen on this element instead of the parent — id of the observer (XML Events attribute module)." },
        @{ @"label": @"Target filter", @"attr": @"ev:target", @"kind": @"idref", @"idkind": @"*",
           @"tip": @"Only fire when the event's original target is this element — id filter for bubbled events (XML Events attribute module)." },
        @{ @"label": @"If", @"attr": @"if", @"kind": @"xpath", @"expect": @"value",
           @"tip": @"Condition: the action runs only when this is true (§10.1.1)." },
        @{ @"label": @"While", @"attr": @"while", @"kind": @"xpath", @"expect": @"value",
           @"tip": @"Loop: the action repeats while this stays true (§10.1.1)." },
        @{ @"label": @"Iterate", @"attr": @"iterate", @"kind": @"xpath", @"expect": @"nodeset",
           @"tip": @"Run once per node in this set, each as context (XSLTForms / XForms 2.0)." },
    ]];
    [all addObjectsFromArray:specs];

    // the rows are the action's spec's, so made here rather than in the XIB
    id target = self.inspector;
    SEL action = @selector(inspectorChanged:);
    NSRect bounds = [host bounds];
    CGFloat y = NSHeight(bounds) - 30;
    for (NSDictionary *spec in all) {
        NSString *kind = spec[@"kind"];
        NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, y, 92, 14)];
        [label setEditable:NO];
        [label setBordered:NO];
        [label setDrawsBackground:NO];
        [label setAlignment:NSRightTextAlignment];
        [label setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [label setStringValue:spec[@"label"] ?: @""];
        [label setAutoresizingMask:NSViewMinYMargin];
        [host addSubview:label];

        NSRect frame = NSMakeRect(98, y - 4, NSWidth(bounds) - 106, 21);
        NSView *view = nil;
        if ([kind isEqualToString:@"xpath"]) {
            XFDXPathField *field = [[XFDXPathField alloc] initWithFrame:frame];
            field.provider = self;
            field.target = target;
            field.action = action;
            NSString *expect = spec[@"expect"];
            field.expectation = [expect isEqualToString:@"nodeset"] ? XFDXPathExpectNodeSet
                : ([expect isEqualToString:@"node"] ? XFDXPathExpectNode
                : ([expect isEqualToString:@"value"] ? XFDXPathExpectValue : XFDXPathExpectAny));
            view = field;
        } else if ([kind isEqualToString:@"idref"]) {
            XFDIDRefField *field = [[XFDIDRefField alloc]
                initWithFrame:NSMakeRect(98, y - 5, NSWidth(bounds) - 106, 23)];
            field.kind = spec[@"idkind"];
            field.provider = self;
            field.target = target;
            field.action = action;
            view = field;
        } else if ([kind isEqualToString:@"content"]) {
            XFDRichTextField *field = [[XFDRichTextField alloc] initWithFrame:frame];
            field.provider = self;
            field.target = target;
            field.action = action;
            view = field;
        } else if ([kind isEqualToString:@"popup"]) {
            NSPopUpButton *popup = [[NSPopUpButton alloc]
                initWithFrame:NSMakeRect(98, y - 5, NSWidth(bounds) - 106, 22) pullsDown:NO];
            [[popup cell] setControlSize:NSSmallControlSize];
            [popup setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
            [popup addItemsWithTitles:spec[@"options"]];
            [popup setTarget:target];
            [popup setAction:action];
            view = popup;
        } else {   // field
            NSTextField *field = [[NSTextField alloc] initWithFrame:
                NSMakeRect(98, y - 3, NSWidth(bounds) - 106, 19)];
            [[field cell] setControlSize:NSSmallControlSize];
            [field setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
            [[field cell] setScrollable:YES];
            [[field cell] setSendsActionOnEndEditing:YES];
            [field setTarget:target];
            [field setAction:action];
            view = field;
        }
        [view setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        if (spec[@"tip"] != nil) {
            [view setToolTip:spec[@"tip"]];
        }
        [host addSubview:view];
        [rows addObject:@{ @"attr": spec[@"attr"] ?: @"", @"kind": kind, @"view": view }];
        y -= 26;
    }
    _rows = rows;
    _element = element;
}

- (NSArray<XFDXPathField *> *)xpathFields
{
    NSMutableArray *fields = [NSMutableArray array];
    for (NSDictionary *row in _rows) {
        if ([row[@"view"] isKindOfClass:[XFDXPathField class]]) {
            [fields addObject:row[@"view"]];
        }
    }
    return fields;
}

- (void)fill
{
    XFXMLElement *element = self.formEditor.selection;
    [self buildRowsIfNeededForElement:element];
    XFDElementEditor *e = [XFDElementEditor editorForElement:element formEditor:self.formEditor];
    for (NSDictionary *row in _rows) {
        NSString *kind = row[@"kind"];
        id view = row[@"view"];
        if ([kind isEqualToString:@"content"]) {
            NSString *xml = [self.formEditor.hostEdit inlineContentXMLOfElement:element];
            [(XFDRichTextField *)view setPlainText:[XFXML stringValueOfNode:element] ?: @""
                                               xml:xml.length ? xml : nil];
        } else if ([kind isEqualToString:@"popup"]) {
            NSString *value = [e attribute:row[@"attr"]];
            NSInteger idx = value.length ? [(NSPopUpButton *)view indexOfItemWithTitle:value] : 0;
            [(NSPopUpButton *)view selectItemAtIndex:idx >= 0 ? idx : 0];
        } else {
            [(id)view setStringValue:[e attribute:row[@"attr"]]];
        }
    }
}

- (void)apply
{
    XFXMLElement *element = self.formEditor.selection;
    if (_element != element || _rows == nil) {
        return;
    }
    XFDElementEditor *e = [XFDElementEditor editorForElement:element formEditor:self.formEditor];
    for (NSDictionary *row in _rows) {
        NSString *kind = row[@"kind"];
        id view = row[@"view"];
        if ([kind isEqualToString:@"content"]) {
            XFDRichTextField *field = view;
            NSString *xml = [field isRich] ? [field xmlValue] : XFDEscapeXML([field stringValue]);
            [self.formEditor.hostEdit setInlineContentXML:xml onElement:element error:NULL];
        } else if ([kind isEqualToString:@"popup"]) {
            NSInteger idx = [(NSPopUpButton *)view indexOfSelectedItem];
            [e setAttribute:row[@"attr"]
                      value:idx <= 0 ? @"" : [(NSPopUpButton *)view titleOfSelectedItem]];
        } else {
            [e setAttribute:row[@"attr"] value:[(id)view stringValue]];
        }
    }
}

@end

#pragma mark - Item, Itemset

@implementation XFDItemPage

- (NSArray<XFDRichTextField *> *)richTextFields
{
    return @[ self.itemLabelField ];
}

- (void)fill
{
    XFDItemEditor *e = [XFDItemEditor editorForElement:self.formEditor.selection formEditor:self.formEditor];
    [self.itemLabelField setPlainText:e.labelText xml:e.labelXML];
    [self.itemValueField setStringValue:e.valueText];
}

- (void)apply
{
    XFDItemEditor *e = [XFDItemEditor editorForElement:self.formEditor.selection formEditor:self.formEditor];
    [self applyRichField:self.itemLabelField name:@"label" toEditor:e];
    e.valueText = [self.itemValueField stringValue];
}

@end

@implementation XFDItemsetPage

- (void)setUp
{
    [super setUp];
    self.itemsetNodesetField.expectation = XFDXPathExpectNodeSet;
    self.itemsetLabelRefField.expectation = XFDXPathExpectNode;
    self.itemsetValueRefField.expectation = XFDXPathExpectNode;
}

- (NSArray<XFDXPathField *> *)xpathFields
{
    return @[ self.itemsetNodesetField, self.itemsetLabelRefField, self.itemsetValueRefField ];
}

- (NSDictionary<NSString *, NSString *> *)idRefFieldKinds
{
    return @{ @"itemsetBindField": @"bind" };
}

- (void)fill
{
    XFDItemsetEditor *e = [XFDItemsetEditor editorForElement:self.formEditor.selection
                                                  formEditor:self.formEditor];
    [self.itemsetNodesetField setStringValue:e.nodeset];
    [self.itemsetBindField setStringValue:e.bind];
    [self.itemsetLabelRefField setStringValue:e.labelRef];
    [self.itemsetValueRefField setStringValue:e.valueRef];
}

- (void)apply
{
    XFDItemsetEditor *e = [XFDItemsetEditor editorForElement:self.formEditor.selection
                                                  formEditor:self.formEditor];
    e.nodeset = [self.itemsetNodesetField stringValue];
    e.bind = [self.itemsetBindField stringValue];
    e.labelRef = [self.itemsetLabelRefField stringValue];
    e.valueRef = [self.itemsetValueRefField stringValue];
}

@end

#pragma mark - Any other element

@implementation XFDElementPage

- (void)fill
{
    [self.hostNewControlButton setEnabled:[self.formEditor selectedInstanceDataNode] != nil];
}

- (IBAction)elementCreateBoundControl:(id)sender
{
    if ([self.formEditor selectedInstanceDataNode] == nil) {
        XFDBeep();
        return;
    }
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Control Kind"];
    for (NSString *kind in @[ @"input", @"textarea", @"secret", @"select1",
                              @"select", @"range", @"output", @"upload" ]) {
        NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:kind
                                                         action:@selector(boundControlKindPicked:)
                                                  keyEquivalent:@""];
        [item setTarget:self];
        [item setRepresentedObject:kind];
    }
    NSView *anchor = [sender isKindOfClass:[NSView class]] ? sender : self.hostNewControlButton;
    NSPoint where = [[anchor superview] convertPoint:[anchor frame].origin toView:nil];
    NSEvent *down = [NSEvent mouseEventWithType:NSLeftMouseDown
                                       location:where
                                  modifierFlags:0
                                      timestamp:0
                                   windowNumber:[[anchor window] windowNumber]
                                        context:nil
                                    eventNumber:0
                                     clickCount:1
                                       pressure:1];
    [NSMenu popUpContextMenu:menu withEvent:down forView:anchor];
}

- (void)boundControlKindPicked:(NSMenuItem *)item
{
    [self createBoundControlOfKind:[item representedObject]];
}

- (void)createBoundControlOfKind:(NSString *)kind
{
    if ([self.formEditor createControlOfKind:kind boundToSelectedDataNode:NULL] == nil) {
        XFDBeep();
    }
}

@end
