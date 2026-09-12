/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* The right pane: inspector page routing, the fill / apply passes over
   the XFDEditors facades, binding status and workflow shortcuts, the
   attribute tooltips, and the field-provider plumbing every
   XFDXPathField / XFDRichTextField / XFDIDRefField shares. */
#import "XFDWindowControllerPriv.h"
#import <XFormsKit/XFXMLTypes.h>
#import "XFDDocument.h"
#import "XFDEditors.h"
#import "XFDInspectorSpecs.h"
#import "XFDSubmissionTester.h"
#import "DMTabBar.h"

@implementation XFDWindowController (XFDInspector)

#pragma mark - Binding UX

/// Every bind id in every model — the Bind popup's menu ("refer to a
/// ready-made binding by id"; in-place ref stays the other route).
- (void)refreshBindingStatusForEditor:(XFDControlEditor *)e
{
    NSTextField *status = self.controlBindingStatusField;
    if (e.bind.length) {
        if ([[XFDIDRefField identifiersOfKind:@"bind" inProcessor:[self processor]]
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
    if ([[self.selected localName] isEqualToString:@"output"]
        && [e attribute:@"value"].length) {
        [status setStringValue:@"Computed via value expression."];
        [status setTextColor:[NSColor disabledControlTextColor]];
        return;
    }
    if (self.selected != nil && XFDElementIsUnbound(self.selected)) {
        [status setStringValue:@"Unbound — typed values are not kept."];
        [status setTextColor:XFDWarningColor()];
        return;
    }
    [status setStringValue:@""];
}

#pragma mark - Inspector pages

- (XFDInspectorPage)pageForElement:(XFXMLElement *)element
{
    if (element == nil) {
        return XFDPageElement;
    }
    if (![XFXML element:element hasLocalName:[element localName]
           namespaceURI:XFXFormsNamespaceURI]) {
        return XFDPageElement;
    }
    NSString *local = [element localName];
    if ([XFDControlKinds() containsObject:local]) {
        return XFDPageControl;
    }
    if ([local isEqualToString:@"bind"]) {
        return XFDPageBind;
    }
    if ([local isEqualToString:@"submission"]) {
        return XFDPageSubmission;
    }
    if ([local isEqualToString:@"instance"]) {
        return XFDPageInstance;
    }
    if (XFDActionSpecs()[local] != nil) {
        return XFDPageAction;
    }
    if ([local isEqualToString:@"item"]) {
        return XFDPageItem;
    }
    if ([local isEqualToString:@"itemset"]) {
        return XFDPageItemset;
    }
    return XFDPageElement;
}

- (void)showInspectorForSelection
{
    // the group (Identity/Attributes/Layout) is the USER'S choice on the
    // tab bar; only the nested kind page follows the selection
    [self.inspectorKindTabView selectTabViewItemAtIndex:[self pageForElement:self.selected]];
    [self fillInspector];
}

- (void)inspectorTabSelected:(id)sender
{
    (void)sender;
    DMTabBar *bar = (DMTabBar *)self.inspectorTabBar;
    [self.inspectorTabView selectTabViewItemAtIndex:(NSInteger)bar.selectedIndex];
}

- (void)fillInspector
{
    self.updating = YES;
    XFDDocument *doc = [self formDocument];
    XFDInspectorPage page = [self pageForElement:self.selected];
    XFDElementEditor *base = [XFDElementEditor editorForElement:self.selected document:doc];
    [self.identityTitleField setStringValue:base.title ?: @"No Selection"];
    [self.identityIdField setStringValue:base ? base.identifier : @""];
    [self.identityIdField setEnabled:base != nil];
    switch (page) {
        case XFDPageControl: {
            XFDControlEditor *e = [XFDControlEditor editorForElement:self.selected document:doc];
            // a repeat's ref selects the nodeset it iterates; every other
            // control binds one node
            self.controlRefField.expectation =
                [[self.selected localName] isEqualToString:@"repeat"]
                    ? XFDXPathExpectNodeSet : XFDXPathExpectNode;
            [self.controlRefField setStringValue:e.ref];
            // @value is xf:output's computed expression — dead weight elsewhere
            BOOL isOutput = [[self.selected localName] isEqualToString:@"output"];
            [self.controlValueField setStringValue:isOutput ? e.valueExpression : @""];
            [self.controlValueField setEnabled:isOutput];
            [self.controlBindField setStringValue:e.bind];
            [self refreshBindingStatusForEditor:e];
            [self.controlCreateBindButton setEnabled:e.ref.length > 0 && e.bind.length == 0];
            [self.controlModelField setStringValue:e.model];
            // @submission is xf:submit's attribute — dead weight elsewhere
            BOOL isSubmit = [[self.selected localName] isEqualToString:@"submit"];
            [self.controlSubmissionField setStringValue:isSubmit ? e.submission : @""];
            [self.controlSubmissionField setEnabled:isSubmit];
            NSString *appearance = e.appearance;
            NSInteger idx = appearance.length
                ? [self.controlAppearancePopup indexOfItemWithTitle:appearance] : 0;
            [self.controlAppearancePopup selectItemAtIndex:idx >= 0 ? idx : 0];
            [self.controlIncrementalCheckbox setState:e.isIncremental ? NSOnState : NSOffState];
            [self.controlMediatypeField setStringValue:e.mediatype];
            [self.controlLabelField setPlainText:e.labelText xml:e.labelXML];
            [self.controlHintField setPlainText:e.hintText xml:e.hintXML];
            [self.controlHelpField setPlainText:e.helpText xml:e.helpXML];
            [self.controlAlertField setPlainText:e.alertText xml:e.alertXML];
            break;
        }
        case XFDPageBind: {
            XFDBindEditor *e = [XFDBindEditor editorForElement:self.selected document:doc];
            [self.bindNodesetField setStringValue:e.nodeset];
            [self.bindTypeField setStringValue:e.typeName];
            [self.bindCalculateField setStringValue:e.calculate];
            [self.bindConstraintField setStringValue:e.constraint];
            [self.bindRequiredField setStringValue:e.required];
            [self.bindRelevantField setStringValue:e.relevant];
            [self.bindReadonlyField setStringValue:e.readonly];
            break;
        }
        case XFDPageSubmission: {
            XFDSubmissionEditor *e = [XFDSubmissionEditor editorForElement:self.selected document:doc];
            [self.submissionResourceField setStringValue:e.resource];
            [self.submissionMethodField setStringValue:e.method];
            NSString *replace = e.replace;
            NSInteger idx = replace.length
                ? [self.submissionReplacePopup indexOfItemWithTitle:replace] : 0;
            [self.submissionReplacePopup selectItemAtIndex:idx >= 0 ? idx : 0];
            [self.submissionInstanceField setStringValue:e.instance];
            [self.submissionBindField setStringValue:e.bind];
            [self.submissionRefField setStringValue:e.ref];
            break;
        }
        case XFDPageInstance: {
            XFDInstanceEditor *e = [XFDInstanceEditor editorForElement:self.selected document:doc];
            [self.instanceSrcField setStringValue:e.src];
            break;
        }
        case XFDPageAction:
            [self.actionRowsPane fillForElement:self.selected];
            break;
        case XFDPageItem: {
            XFDItemEditor *e = [XFDItemEditor editorForElement:self.selected document:doc];
            [self.itemLabelField setPlainText:e.labelText xml:e.labelXML];
            [self.itemValueField setStringValue:e.valueText];
            break;
        }
        case XFDPageItemset: {
            XFDItemsetEditor *e = [XFDItemsetEditor editorForElement:self.selected document:doc];
            [self.itemsetNodesetField setStringValue:e.nodeset];
            [self.itemsetBindField setStringValue:e.bind];
            [self.itemsetLabelRefField setStringValue:e.labelRef];
            [self.itemsetValueRefField setStringValue:e.valueRef];
            break;
        }
        case XFDPageElement:
            [self.hostNewControlButton setEnabled:[self selectedInstanceDataNode] != nil];
            break;
    }
    for (XFDXPathField *field in [self xpathFields]) {
        [field validate];
    }
    [self.eventsPane reload];
    self.updating = NO;
}

- (IBAction)inspectorChanged:(id)sender
{
    (void)sender;
    if (self.updating || self.selected == nil) {
        return;
    }
    XFDDocument *doc = [self formDocument];
    self.updating = YES;   // the editors fire hostChanged per set; batch the refill
    XFDElementEditor *base = [XFDElementEditor editorForElement:self.selected document:doc];
    base.identifier = [self.identityIdField stringValue];
    switch ([self pageForElement:self.selected]) {
        case XFDPageControl: {
            XFDControlEditor *e = [XFDControlEditor editorForElement:self.selected document:doc];
            e.ref = [self.controlRefField stringValue];
            if ([[self.selected localName] isEqualToString:@"output"]) {
                e.valueExpression = [self.controlValueField stringValue];
            }
            e.bind = [self.controlBindField stringValue];
            e.model = [self.controlModelField stringValue];
            if ([[self.selected localName] isEqualToString:@"submit"]) {
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
            break;
        }
        case XFDPageBind: {
            XFDBindEditor *e = [XFDBindEditor editorForElement:self.selected document:doc];
            e.nodeset = [self.bindNodesetField stringValue];
            e.typeName = [self.bindTypeField stringValue];
            e.calculate = [self.bindCalculateField stringValue];
            e.constraint = [self.bindConstraintField stringValue];
            e.required = [self.bindRequiredField stringValue];
            e.relevant = [self.bindRelevantField stringValue];
            e.readonly = [self.bindReadonlyField stringValue];
            break;
        }
        case XFDPageSubmission: {
            XFDSubmissionEditor *e = [XFDSubmissionEditor editorForElement:self.selected document:doc];
            e.resource = [self.submissionResourceField stringValue];
            e.method = [self.submissionMethodField stringValue];
            NSInteger idx = [self.submissionReplacePopup indexOfSelectedItem];
            e.replace = idx <= 0 ? @"" : [self.submissionReplacePopup titleOfSelectedItem];
            e.instance = [self.submissionInstanceField stringValue];
            e.bind = [self.submissionBindField stringValue];
            e.ref = [self.submissionRefField stringValue];
            break;
        }
        case XFDPageInstance: {
            XFDInstanceEditor *e = [XFDInstanceEditor editorForElement:self.selected document:doc];
            e.src = [self.instanceSrcField stringValue];
            break;
        }
        case XFDPageAction:
            [self.actionRowsPane applyToElement:self.selected];
            break;
        case XFDPageItem: {
            XFDItemEditor *e = [XFDItemEditor editorForElement:self.selected document:doc];
            [self applyRichField:self.itemLabelField name:@"label" toEditor:e];
            e.valueText = [self.itemValueField stringValue];
            break;
        }
        case XFDPageItemset: {
            XFDItemsetEditor *e = [XFDItemsetEditor editorForElement:self.selected document:doc];
            e.nodeset = [self.itemsetNodesetField stringValue];
            e.bind = [self.itemsetBindField stringValue];
            e.labelRef = [self.itemsetLabelRefField stringValue];
            e.valueRef = [self.itemsetValueRefField stringValue];
            break;
        }
        case XFDPageElement:
            break;
    }
    self.updating = NO;
    [self reloadOutlineKeepingSelection:self.selected];
    [self fillInspector];
}

#pragma mark - ID ref field provider

- (XFProcessor *)processorForIDRefField:(XFDIDRefField *)field
{
    (void)field;
    return [self processor];
}

#pragma mark - Attribute tips

/// One tooltip per editable row, condensed from the XForms 1.1 spec — the
/// palette already explains the TAGS; this explains the ATTRIBUTES. On the
/// component rows the tip sits on the container view, so a validation
/// error on the inner field still wins while it is showing.
- (void)applyAttributeTips
{
    NSDictionary *tips = @{
        @"identityIdField": @"Unique id (xsd:ID) other elements reference — binds, toggles, setfocus, dispatch targets.",
        @"controlRefField": @"Binding expression selecting the node this control edits, evaluated in the parent's context (§3.2.3). A repeat's ref selects the node-set it iterates.",
        @"controlValueField": @"xf:output only: display a COMPUTED expression instead of a bound node (§8.1.5) — mutually exclusive with Ref/Bind.",
        @"controlBindField": @"Reference an xf:bind by id instead of binding in place; when set, it overrides Ref.",
        @"controlModelField": @"Id of the model the Ref evaluates against (defaults to the first model; only meaningful with Ref).",
        @"controlSubmissionField": @"Id of the xf:submission this submit button starts (§10.11).",
        @"controlAppearancePopup": @"Appearance hint (§8.1.2): minimal / compact / full pick different widget styles per control.",
        @"controlIncrementalCheckbox": @"Commit on every keystroke instead of on leaving the field — xforms-value-changed fires per change (§8.1.1).",
        @"controlMediatypeField": @"Media type of the bound content — image/* on upload, application/xhtml+xml for the rich textarea.",
        @"controlLabelField": @"The control's label (§8.3.3): plain text, inline markup, or dynamic output content.",
        @"controlHintField": @"Hint shown on hover/focus (§8.3.5); appearance=\"minimal\" renders it as placeholder text.",
        @"controlHelpField": @"Help shown on request (§8.3.4).",
        @"controlAlertField": @"Message shown while the bound value is invalid (§8.3.6).",
        @"controlCreateBindButton": @"Move this control's Ref into a new named xf:bind under the model and reference it by id.",
        @"bindNodesetField": @"The nodes this bind applies to (§7.4), evaluated in the outer bind's context — nested binds chain.",
        @"bindTypeField": @"xsd datatype applied to the nodes (xsd:date, xsd:integer, …) — drives widget choice and validation (§6.1.6).",
        @"bindCalculateField": @"Computes the value from other nodes; calculated nodes become readonly unless overridden (§6.1.3).",
        @"bindConstraintField": @"Validity condition, evaluated per node (§6.1.1).",
        @"bindRequiredField": @"XPath deciding whether a value is required (§6.1.2).",
        @"bindRelevantField": @"XPath deciding whether the nodes are relevant — irrelevant controls disappear (§6.1.4).",
        @"bindReadonlyField": @"XPath deciding whether the nodes are read-only (§6.1.5).",
        @"submissionResourceField": @"Where to submit (URI); the legacy @action spelling is preserved when the document uses it (§11.1).",
        @"submissionMethodField": @"Serialization + protocol: post, get, put, delete, urlencoded-post, … (§11.1).",
        @"submissionReplacePopup": @"What the response replaces: none, all (the page), an instance, or text (§11.1).",
        @"submissionInstanceField": @"Id of the instance the response replaces when Replace = instance (§11.2).",
        @"submissionRefField": @"Root of the submitted data; defaults to the default instance's root.",
        @"submissionBindField": @"Bind selecting the submitted data, by id (overrides Ref).",
        @"instanceSrcField": @"External URI for the instance data; when set, inline content is ignored (§3.3.2).",
        @"itemLabelField": @"The choice's visible label (§8.3.3).",
        @"itemValueField": @"Value stored in the bound node when this choice is selected (§8.2.2).",
        @"itemsetNodesetField": @"One choice per node in this set (§9.3.3).",
        @"itemsetBindField": @"Bind selecting the choice nodes, by id.",
        @"itemsetLabelRefField": @"Each choice's label, evaluated relative to its node (§9.3.3).",
        @"itemsetValueRefField": @"Each choice's stored value, evaluated relative to its node (§9.3.3).",
        @"hostNewControlButton": @"Add a control at the end of the body bound to the selected data node.",
    };
    for (NSString *outlet in tips) {
        id view = nil;
        @try {
            view = [self valueForKey:outlet];
        } @catch (NSException *e) {
            continue;   // no such outlet — a tip for nothing
        }
        if ([view isKindOfClass:[NSView class]]) {
            [(NSView *)view setToolTip:tips[outlet]];
        }
    }
}

#pragma mark - Binding workflow shortcuts

/// Promote an in-place ref to a named bind: a new xf:bind under the model
/// takes the control's ref as its nodeset, the control references it by
/// id, and the ref attribute goes away — one undoable gesture.
- (IBAction)createBindFromRef:(id)sender
{
    (void)sender;
    if (self.selected == nil || [self pageForElement:self.selected] != XFDPageControl) {
        XFDBeep();
        return;
    }
    XFDControlEditor *e = [XFDControlEditor editorForElement:self.selected
                                                    document:[self formDocument]];
    NSString *ref = e.ref;
    if (ref.length == 0 || e.bind.length) {
        XFDBeep();
        return;
    }
    XFHostEdit *edit = [self formDocument].hostEdit;
    XFXMLElement *modelEl = (XFXMLElement *)[self processor].model.element;
    NSError *error = nil;
    XFXMLElement *bind = [edit insertElementNamed:@"bind" underParent:modelEl
                                          atIndex:-1 error:&error];
    if (bind == nil) {
        [self presentError:error];
        return;
    }
    [edit setAttribute:@"nodeset" value:ref onElement:bind];
    NSString *identifier = [[bind attributeForName:@"id"] stringValue];
    [edit setAttribute:@"bind" value:identifier onElement:self.selected];
    [edit setAttribute:@"ref" value:@"" onElement:self.selected];
    [self selectElement:self.selected];
}

/// The instance-data node under the selection when there is one (the
/// selection itself must live INSIDE an xf:instance, not be the instance).
- (XFXMLElement *)selectedInstanceDataNode
{
    if (self.selected == nil
        || [XFXML element:self.selected hasLocalName:[self.selected localName]
             namespaceURI:XFXFormsNamespaceURI]) {
        return nil;
    }
    XFXMLElement *instance = [self instanceElementForSelection:self.selected];
    return (instance != nil && instance != self.selected) ? self.selected : nil;
}

/// The ref that reaches `node` from the picker's default context: plain
/// steps for the default instance, instance('id')/… for a named one, nil
/// when the node's instance cannot be addressed.
- (NSString *)refForDataNode:(XFXMLElement *)node
{
    // the outline shows the HOST document's inline instance content;
    // XFInstance works on a COPY — map through the owning xf:instance
    XFXMLElement *instanceHost = [self instanceElementForSelection:node];
    XFXMLElement *dataRoot = nil;
    for (XFXMLNode *c in [instanceHost children]) {
        if ([c kind] == XFXMLElementKind) {
            dataRoot = (XFXMLElement *)c;
            break;
        }
    }
    if (dataRoot == nil) {
        return nil;
    }
    NSString *tail = [XFHostEdit pathFromNode:dataRoot toNode:node];
    if (tail == nil) {
        return nil;
    }
    XFProcessor *p = [self processor];
    XFInstance *owner = nil;
    for (XFModel *model in p.models) {
        for (XFInstance *instance in model.instances) {
            if (instance.element == instanceHost) {
                owner = instance;
            }
        }
    }
    if (owner == nil) {
        return nil;
    }
    if (owner == [p defaultInstance]) {
        return tail;   // "." for the root itself
    }
    if (owner.identifier.length == 0) {
        return nil;    // unaddressable: not default, no id
    }
    return [tail isEqualToString:@"."]
        ? [NSString stringWithFormat:@"instance('%@')", owner.identifier]
        : [NSString stringWithFormat:@"instance('%@')/%@", owner.identifier, tail];
}

/// Insert a control of `kind` at the end of the body, bound to the
/// selected instance-data node — form-building straight from the data.
- (void)createBoundControlOfKind:(NSString *)kind
{
    XFXMLElement *dataNode = [self selectedInstanceDataNode];
    NSString *ref = dataNode ? [self refForDataNode:dataNode] : nil;
    if (ref == nil) {
        XFDBeep();
        return;
    }
    XFXMLElement *body = nil;
    for (XFXMLElement *top in [self elementChildrenOf:[self rootElement]]) {
        if ([[top localName] isEqualToString:@"body"]) {
            body = top;
        }
    }
    if (body == nil) {
        XFDBeep();
        return;
    }
    XFHostEdit *edit = [self formDocument].hostEdit;
    NSError *error = nil;
    XFXMLElement *control = [edit insertElementNamed:kind underParent:body
                                             atIndex:-1 error:&error];
    if (control == nil) {
        [self presentError:error];
        return;
    }
    [edit setAttribute:@"ref" value:ref onElement:control];
    [edit setSupportChild:@"label" text:
        [[[dataNode localName] substringToIndex:1].uppercaseString
            stringByAppendingString:[[dataNode localName] substringFromIndex:1]]
              onElement:control];
    [self selectElement:control];
}

- (IBAction)elementCreateBoundControl:(id)sender
{
    if ([self selectedInstanceDataNode] == nil) {
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

#pragma mark - Rich text rows (label / hint / help / alert)

- (NSArray *)richTextFields
{
    return @[ self.controlLabelField, self.controlHintField,
              self.controlHelpField, self.controlAlertField,
              self.itemLabelField ];
}

/// Apply one text row: rich content goes through the XML command (markup
/// kept verbatim), plain text through the plain-text command — never the
/// other way around, so a rich label is not flattened by the apply pass.
- (void)applyRichField:(XFDRichTextField *)field
                  name:(NSString *)name
              toEditor:(XFDElementEditor *)editor
{
    if ([field isRich]) {
        [editor setValue:[field xmlValue] forKey:[name stringByAppendingString:@"XML"]];
    } else {
        [editor setValue:[field stringValue] forKey:[name stringByAppendingString:@"Text"]];
    }
}

#pragma mark - XPath field provider

- (NSArray *)xpathFields
{
    return @[ self.controlRefField, self.controlValueField,
              self.bindNodesetField, self.bindCalculateField,
              self.bindConstraintField, self.bindRequiredField, self.bindRelevantField,
              self.bindReadonlyField, self.submissionRefField,
              self.itemsetNodesetField, self.itemsetLabelRefField,
              self.itemsetValueRefField ];
}

- (XFXMLElement *)hostElementForXPathField:(XFDXPathField *)field
{
    (void)field;
    return self.selected;
}

- (XFProcessor *)processorForXPathField:(XFDXPathField *)field
{
    (void)field;
    return [self processor];
}

/// The node a control's ref evaluates against: the nearest bound ancestor
/// control's node, else the default instance root (binds and submissions
/// fall back to the instance root too — nested-bind contexts are a later
/// refinement).
/// The selected bind's compiled XFBind (binds nest — search recursively).
- (XFBind *)bindForSelectionIn:(NSArray *)binds
{
    for (XFBind *bind in binds) {
        if (bind.element == self.selected) {
            return bind;
        }
        XFBind *nested = [self bindForSelectionIn:bind.binds];
        if (nested != nil) {
            return nested;
        }
    }
    return nil;
}

- (XFXMLNode *)contextNodeForXPathField:(XFDXPathField *)field
{
    if ([self pageForElement:self.selected] == XFDPageBind) {
        // MIP expressions (calculate, constraint, …) evaluate PER BOUND
        // NODE — `../in - ../out` from bind.xhtml means nothing from the
        // instance root. The nodeset field evaluates in the OUTER context:
        // the parent bind's node for a nested bind, the root otherwise.
        for (XFModel *model in [self processor].models) {
            XFBind *bind = [self bindForSelectionIn:model.binds];
            if (bind == nil) {
                continue;
            }
            if (field == self.bindNodesetField) {
                if (bind.parent.nodes.count) {
                    return bind.parent.nodes.firstObject;
                }
                break;
            }
            if (bind.nodes.count) {
                return bind.nodes.firstObject;
            }
        }
        return [[[self processor] defaultInstance] documentElement];
    }
    if ([self pageForElement:self.selected] == XFDPageControl) {
        XFControl *control = [[self processor] controlForElement:self.selected];
        XFControl *up = control.parentControl;
        while (up != nil && up.boundNode == nil) {
            up = up.parentControl;
        }
        if (up.boundNode != nil) {
            return up.boundNode;
        }
    }
    return [[[self processor] defaultInstance] documentElement];
}

#pragma mark - Rich text field provider (the Insert Output token flow)

- (XFXMLElement *)hostElementForRichTextField:(XFDRichTextField *)field
{
    (void)field;
    return self.selected;
}

- (XFProcessor *)processorForRichTextField:(XFDRichTextField *)field
{
    (void)field;
    return [self processor];
}

/// Outputs inside a label / hint / help / alert evaluate against the
/// control's OWN bound node (the engine's childContextFrom:), so the
/// picker's Relative style starts there — one level closer than the ref
/// field's context — then the nearest bound ancestor, then the default
/// instance root.
- (XFXMLNode *)contextNodeForRichTextField:(XFDRichTextField *)field
{
    (void)field;
    if ([self pageForElement:self.selected] == XFDPageControl) {
        XFControl *control = [[self processor] controlForElement:self.selected];
        while (control != nil && control.boundNode == nil) {
            control = control.parentControl;
        }
        if (control.boundNode != nil) {
            return control.boundNode;
        }
    }
    return [[[self processor] defaultInstance] documentElement];
}

- (IBAction)testSubmissionClicked:(id)sender
{
    (void)sender;
    NSString *identifier = nil;
    if ([self pageForElement:self.selected] == XFDPageSubmission) {
        identifier = [[self.selected attributeForName:@"id"] stringValue];
    }
    [XFDSubmissionTester runForProcessor:[self processor]
                       initialSubmission:identifier];
}

- (void)showAttributesGroup
{
    DMTabBar *bar = (DMTabBar *)self.inspectorTabBar;
    bar.selectedIndex = 1;
    [self.inspectorTabView selectTabViewItemAtIndex:1];
}

@end

void XFDWindowControllerInspectorFilePresent(void) {}
