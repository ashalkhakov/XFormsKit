#import "XFDWindowController.h"
#import "XFDDocument.h"
#import "XFDEditors.h"
#import "XFDDesignOverlay.h"
#import "DMTabBar.h"
#import "DMTabBarItem.h"
#import <XFormsKit/XFormsKit.h>

typedef NS_ENUM(NSInteger, XFDInspectorPage) {
    XFDPageControl = 0,
    XFDPageBind,
    XFDPageSubmission,
    XFDPageInstance,
    XFDPageElement,
    XFDPageAction,
    XFDPageItem,
    XFDPageItemset,
};

/// The Action page's row specs, per action local name (XForms 1.1 §10
/// plus the XSLTForms show/hide pair). Row keys: label, attr, kind
/// (xpath | idref | field | popup | content), idkind for idref rows,
/// options for popup rows (first item = attribute removed). Every action
/// additionally gets the Event (ev:event) row, prepended at build time.
static NSDictionary *XFDActionSpecs(void)
{
    static NSDictionary *specs;
    if (specs == nil) {
        NSArray *modelRow = @[ @{ @"label": @"Model", @"attr": @"model",
                                  @"kind": @"idref", @"idkind": @"model" } ];
        specs = @{
            @"action": @[],
            @"setvalue": @[
                @{ @"label": @"Node", @"attr": @"ref", @"kind": @"xpath", @"expect": @"node", @"tip": @"The node whose value is set (§10.2)." },
                @{ @"label": @"Bind", @"attr": @"bind", @"kind": @"idref", @"idkind": @"bind", @"tip": @"Bind selecting the target nodes, by id (overrides the in-place expression)." },
                @{ @"label": @"Value", @"attr": @"value", @"kind": @"xpath", @"expect": @"value", @"tip": @"Expression computing the new value; alternatively use inline Text (§10.2)." },
                @{ @"label": @"Text", @"kind": @"content", @"tip": @"Inline content: the literal value (setvalue) or the message body (§10.2, §10.12)." },
            ],
            @"insert": @[
                @{ @"label": @"Nodeset", @"attr": @"nodeset", @"kind": @"xpath", @"expect": @"nodeset", @"tip": @"The homogeneous collection inserted into / deleted from (§10.3, §10.4)." },
                @{ @"label": @"Bind", @"attr": @"bind", @"kind": @"idref", @"idkind": @"bind", @"tip": @"Bind selecting the target nodes, by id (overrides the in-place expression)." },
                @{ @"label": @"At", @"attr": @"at", @"kind": @"xpath", @"expect": @"value", @"tip": @"1-based position within the nodeset the action applies at (§10.3, §10.4)." },
                @{ @"label": @"Position", @"attr": @"position", @"kind": @"popup", @"tip": @"Insert before or after the at-node (§10.3).",
                   @"options": @[ @"(default)", @"before", @"after" ] },
                @{ @"label": @"Origin", @"attr": @"origin", @"kind": @"xpath", @"expect": @"nodeset", @"tip": @"Nodes to copy in; defaults to the last node of the target set (§10.3)." },
                @{ @"label": @"Context", @"attr": @"context", @"kind": @"xpath", @"expect": @"node", @"tip": @"Overrides the in-scope evaluation context node (§10.3, §10.4)." },
            ],
            @"delete": @[
                @{ @"label": @"Nodeset", @"attr": @"nodeset", @"kind": @"xpath", @"expect": @"nodeset", @"tip": @"The homogeneous collection inserted into / deleted from (§10.3, §10.4)." },
                @{ @"label": @"Bind", @"attr": @"bind", @"kind": @"idref", @"idkind": @"bind", @"tip": @"Bind selecting the target nodes, by id (overrides the in-place expression)." },
                @{ @"label": @"At", @"attr": @"at", @"kind": @"xpath", @"expect": @"value", @"tip": @"1-based position within the nodeset the action applies at (§10.3, §10.4)." },
                @{ @"label": @"Context", @"attr": @"context", @"kind": @"xpath", @"expect": @"node", @"tip": @"Overrides the in-scope evaluation context node (§10.3, §10.4)." },
            ],
            @"toggle": @[
                @{ @"label": @"Case", @"attr": @"case", @"kind": @"idref", @"idkind": @"case", @"tip": @"Id of the xf:case to switch to (§10.10)." },
            ],
            @"setindex": @[
                @{ @"label": @"Repeat", @"attr": @"repeat", @"kind": @"idref", @"idkind": @"repeat", @"tip": @"Id of the repeat whose index moves (§10.5)." },
                @{ @"label": @"Index", @"attr": @"index", @"kind": @"xpath", @"expect": @"value", @"tip": @"1-based new index, computed (§10.5)." },
            ],
            @"setfocus": @[
                @{ @"label": @"Control", @"attr": @"control", @"kind": @"idref", @"idkind": @"#control", @"tip": @"Id of the form control to focus (§10.7)." },
            ],
            @"send": @[
                @{ @"label": @"Submission", @"attr": @"submission", @"kind": @"idref", @"idkind": @"submission", @"tip": @"Id of the xf:submission to run (§10.11)." },
            ],
            @"dispatch": @[
                @{ @"label": @"Name", @"attr": @"name", @"kind": @"idref", @"idkind": @"#event", @"tip": @"Event to dispatch — standard or your own custom name (§10.9)." },
                @{ @"label": @"Target", @"attr": @"targetid", @"kind": @"idref", @"idkind": @"*", @"tip": @"Id of the element the event is dispatched to (§10.9)." },
                @{ @"label": @"Delay", @"attr": @"delay", @"kind": @"field", @"tip": @"Milliseconds to wait before dispatching (§10.9)." },
                @{ @"label": @"Bubbles", @"attr": @"bubbles", @"kind": @"popup", @"tip": @"Custom events only: whether the dispatched event bubbles (§10.9). Predefined events keep their spec behavior — XSLTForms-family runtimes read the registry, not this attribute.",
                   @"options": @[ @"(default)", @"true", @"false" ] },
                @{ @"label": @"Cancelable", @"attr": @"cancelable", @"kind": @"popup", @"tip": @"Custom events only: whether the dispatched event can be canceled (§10.9). Predefined events keep their spec behavior — XSLTForms-family runtimes read the registry, not this attribute.",
                   @"options": @[ @"(default)", @"true", @"false" ] },
            ],
            @"load": @[
                @{ @"label": @"Resource", @"attr": @"resource", @"kind": @"field", @"tip": @"URI to open (§10.8)." },
                @{ @"label": @"Show", @"attr": @"show", @"kind": @"popup", @"tip": @"Open in place (replace) or in a new window (§10.8).",
                   @"options": @[ @"(default)", @"replace", @"new" ] },
            ],
            @"message": @[
                @{ @"label": @"Level", @"attr": @"level", @"kind": @"popup", @"tip": @"How the message shows: ephemeral (tooltip-like), modeless, or modal (§10.12).",
                   @"options": @[ @"(default)", @"ephemeral", @"modeless", @"modal" ] },
                @{ @"label": @"Text", @"kind": @"content", @"tip": @"Inline content: the literal value (setvalue) or the message body (§10.2, §10.12)." },
            ],
            @"reset": modelRow,
            @"rebuild": modelRow,
            @"recalculate": modelRow,
            @"revalidate": modelRow,
            @"refresh": modelRow,
            @"show": @[
                @{ @"label": @"Dialog", @"attr": @"dialog", @"kind": @"idref", @"idkind": @"dialog" },
            ],
            @"hide": @[
                @{ @"label": @"Dialog", @"attr": @"dialog", @"kind": @"idref", @"idkind": @"dialog" },
            ],
        };
    }
    return specs;
}

/// Widget-bearing element kinds — the Control inspector page.
static NSSet *XFDControlKinds(void)
{
    static NSSet *set;
    if (set == nil) {
        set = [NSSet setWithArray:@[ @"input", @"output", @"secret", @"textarea",
            @"select", @"select1", @"range", @"trigger", @"submit", @"upload",
            @"group", @"repeat", @"switch", @"case", @"dialog" ]];
    }
    return set;
}

/// Value-carrying kinds that need a binding to keep what the user types.
static NSSet *XFDValueControlKinds(void)
{
    static NSSet *set;
    if (set == nil) {
        set = [NSSet setWithArray:@[ @"input", @"output", @"secret", @"textarea",
            @"select", @"select1", @"range", @"upload" ]];
    }
    return set;
}

/// The odd state the user called out: a value control (or repeat) with no
/// ref / nodeset / bind — the preview will not keep what is typed into it.
static BOOL XFDElementIsUnbound(NSXMLElement *element)
{
    NSString *local = [element localName];
    BOOL needs = [XFDValueControlKinds() containsObject:local]
        || [local isEqualToString:@"repeat"];
    if (!needs) {
        return NO;
    }
    if ([local isEqualToString:@"output"]
        && [[element attributeForName:@"value"] stringValue].length) {
        return NO;   // a computed output IS bound — to an expression
    }
    return [[element attributeForName:@"ref"] stringValue].length == 0
        && [[element attributeForName:@"nodeset"] stringValue].length == 0
        && [[element attributeForName:@"bind"] stringValue].length == 0;
}

static NSColor *XFDWarningColor(void)
{
    if ([[NSColor class] respondsToSelector:@selector(systemOrangeColor)]) {
        return [[NSColor class] performSelector:@selector(systemOrangeColor)];
    }
    return [NSColor colorWithCalibratedRed:0.80 green:0.50 blue:0.10 alpha:1.0];
}

/// The palette: every insertable tag with a one-line description. Rows
/// whose tag the current insert target refuses are dimmed (XFHostEdit's
/// insertion zones are the single validity authority).
static NSArray *XFDPaletteCatalog(void)
{
    static NSArray *catalog;
    if (catalog == nil) {
        catalog = @[
            @{ @"cat": @"Controls",   @"name": @"input",      @"desc": @"Single-line text entry bound to a node" },
            @{ @"cat": @"Controls",   @"name": @"textarea",   @"desc": @"Multi-line text entry" },
            @{ @"cat": @"Controls",   @"name": @"secret",     @"desc": @"Masked password entry" },
            @{ @"cat": @"Controls",   @"name": @"output",     @"desc": @"Read-only display of a value" },
            @{ @"cat": @"Controls",   @"name": @"select1",    @"desc": @"Choose one item (popup / radio)" },
            @{ @"cat": @"Controls",   @"name": @"select",     @"desc": @"Choose several items (checkboxes)" },
            @{ @"cat": @"Controls",   @"name": @"range",      @"desc": @"Slider over a numeric range" },
            @{ @"cat": @"Controls",   @"name": @"trigger",    @"desc": @"Button that fires actions" },
            @{ @"cat": @"Controls",   @"name": @"submit",     @"desc": @"Button that runs a submission" },
            @{ @"cat": @"Controls",   @"name": @"upload",     @"desc": @"File chooser bound to a node" },
            @{ @"cat": @"Containers", @"name": @"group",      @"desc": @"Box grouping related controls" },
            @{ @"cat": @"Containers", @"name": @"repeat",     @"desc": @"Repeats its content per nodeset node" },
            @{ @"cat": @"Containers", @"name": @"switch",     @"desc": @"Shows exactly one of its cases" },
            @{ @"cat": @"Containers", @"name": @"case",       @"desc": @"One branch of a switch" },
            @{ @"cat": @"Containers", @"name": @"dialog",     @"desc": @"Panel shown by xf:show" },
            @{ @"cat": @"Choices",    @"name": @"item",       @"desc": @"A fixed choice inside select / select1" },
            @{ @"cat": @"Choices",    @"name": @"itemset",    @"desc": @"Choices generated from instance nodes" },
            @{ @"cat": @"Model",      @"name": @"model",      @"desc": @"The data model of the form (in the head)" },
            @{ @"cat": @"Model",      @"name": @"instance",   @"desc": @"XML data document inside a model" },
            @{ @"cat": @"Model",      @"name": @"bind",       @"desc": @"Type / constraint / calculate for nodes" },
            @{ @"cat": @"Model",      @"name": @"submission", @"desc": @"How instance data is sent and received" },
            @{ @"cat": @"Actions",    @"name": @"action",     @"desc": @"Groups several actions under one event" },
            @{ @"cat": @"Actions",    @"name": @"setvalue",   @"desc": @"Sets an instance node to a value" },
            @{ @"cat": @"Actions",    @"name": @"insert",     @"desc": @"Inserts nodes into a nodeset" },
            @{ @"cat": @"Actions",    @"name": @"delete",     @"desc": @"Deletes nodes from a nodeset" },
            @{ @"cat": @"Actions",    @"name": @"toggle",     @"desc": @"Switches a switch to one of its cases" },
            @{ @"cat": @"Actions",    @"name": @"setindex",   @"desc": @"Moves a repeat's current index" },
            @{ @"cat": @"Actions",    @"name": @"setfocus",   @"desc": @"Gives a form control the focus" },
            @{ @"cat": @"Actions",    @"name": @"send",       @"desc": @"Runs a submission" },
            @{ @"cat": @"Actions",    @"name": @"dispatch",   @"desc": @"Fires an event at a target element" },
            @{ @"cat": @"Actions",    @"name": @"load",       @"desc": @"Opens a resource (link traversal)" },
            @{ @"cat": @"Actions",    @"name": @"message",    @"desc": @"Shows a message to the user" },
            @{ @"cat": @"Actions",    @"name": @"reset",      @"desc": @"Resets a model to its initial data" },
            @{ @"cat": @"Actions",    @"name": @"rebuild",    @"desc": @"Rebuilds a model's dependency graph" },
            @{ @"cat": @"Actions",    @"name": @"recalculate",@"desc": @"Recalculates a model's computed values" },
            @{ @"cat": @"Actions",    @"name": @"revalidate", @"desc": @"Revalidates a model's data" },
            @{ @"cat": @"Actions",    @"name": @"refresh",    @"desc": @"Refreshes the user interface" },
            @{ @"cat": @"Actions",    @"name": @"show",       @"desc": @"Opens a dialog (XSLTForms)" },
            @{ @"cat": @"Actions",    @"name": @"hide",       @"desc": @"Closes a dialog (XSLTForms)" },
        ];
    }
    return catalog;
}

/// Round badge for a tab bar / outline item (the ModelBuilder pattern —
/// drawn, no image resources).
static NSImage *XFDBadge(NSString *letters, CGFloat r, CGFloat g, CGFloat b)
{
    static NSMutableDictionary *cache;
    if (cache == nil) {
        cache = [NSMutableDictionary dictionary];
    }
    NSString *key = [NSString stringWithFormat:@"%@|%.2f%.2f%.2f", letters, r, g, b];
    NSImage *image = cache[key];
    if (image) {
        return image;
    }
    NSSize size = NSMakeSize(15, 15);
    image = [[NSImage alloc] initWithSize:size];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [image lockFocus];
    [[NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.5, 14, 14)] fill];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:letters.length > 1 ? 7.0 : 9.0],
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };
    NSSize ts = [letters sizeWithAttributes:attrs];
    [letters drawAtPoint:NSMakePoint((size.width - ts.width) / 2, (size.height - ts.height) / 2)
          withAttributes:attrs];
    [image unlockFocus];
#pragma clang diagnostic pop
    cache[key] = image;
    return image;
}




/// The Xcode-library-style palette: a modal panel opened by + with a
/// search field over category-sectioned rows (badge icon, tag name,
/// description). Tags the current insert target refuses are dimmed and
/// unselectable; Insert (or double-click) returns the chosen tag.
@interface XFDPalettePanel : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
{
    NSPanel *_panel;
    NSTextField *_searchField;
    NSTableView *_table;
    NSButton *_insertButton;
    NSSet *_validNames;
    NSArray *_rows;      // header dicts {header} and entry dicts from the catalog
    NSString *_result;
}
+ (NSString *)runWithValidNames:(NSSet *)validNames parentName:(NSString *)parentName;
@end

/// Modal XML editor for instance data: paste or type the document, pull
/// an existing file in (Load File…), or Blankify it — clear every leaf
/// value and attribute so imported real data becomes the form's initial
/// data. OK requires well-formed XML with a single root.
@interface XFDInstanceXMLEditor : NSObject
{
    NSPanel *_panel;
    NSTextView *_text;
    NSTextField *_statusField;
    NSButton *_okButton;
    NSString *_result;
}
+ (NSString *)runWithXML:(NSString *)xml title:(NSString *)title;
@end

@implementation XFDWindowController {
    BOOL _updating;
    XFFormView *_formView;
    NSScrollView *_previewScroll;
    NSTextView *_sourceView;
    /* Design mode (the devtools-style element picker): the overlay sits
       over the preview's content area and swallows the mouse while the
       checkbox is on; off = the form is live, as always. */
    XFDDesignOverlay *_designOverlay;
    NSXMLElement *_selected;
    /* Action page rows: built per element (never mid-edit — a rebuild
       under a field currently sending its action would free it). */
    NSArray *_actionRows;            /* dicts: attr / kind / view */
    NSXMLElement *_actionRowsElement;
    /* Events group: the selected element's direct child handlers. */
    NSTableView *_eventsTable;
    NSArray *_handlerElements;
    NSSegmentedControl *_eventsControl;
    NSTextField *_eventsNote;
}

- (XFDDocument *)formDocument
{
    return (XFDDocument *)[self document];
}

- (XFProcessor *)processor
{
    return [self formDocument].processor;
}

#pragma mark - Nib assembly

- (void)windowDidLoad
{
    [super windowDidLoad];
    [[self window] setDelegate:(id)self];

    /* Inspector chrome: DMTabBar groups Identity / Attributes / Layout
       (Xcode-IB style); the per-kind page lives in the tabless
       inspectorKindTabView inside the Attributes group. */
    struct { NSString *letters; CGFloat r, g, b; NSString *tip; } pages[] = {
        { @"ID", 0.47, 0.53, 0.64, @"Identity" },
        { @"A", 0.36, 0.49, 0.72, @"Attributes" },
        { @"L", 0.32, 0.60, 0.53, @"Layout" },
        { @"E", 0.70, 0.48, 0.32, @"Events" },
    };
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < 4; i++) {
        DMTabBarItem *item = [DMTabBarItem tabBarItemWithIcon:
            XFDBadge(pages[i].letters, pages[i].r, pages[i].g, pages[i].b) tag:i];
        item.toolTip = pages[i].tip;
        [items addObject:item];
    }
    DMTabBar *bar = (DMTabBar *)self.inspectorTabBar;
    bar.tabBarItems = items;
    [bar setTarget:self action:@selector(inspectorTabSelected:)];
    bar.selectedIndex = 1;   /* Attributes, the working page */
    [self.inspectorTabView selectTabViewItemAtIndex:1];
    [self buildEventsPane];
    [self applyAttributeTips];

    /* What the xib deliberately leaves out (IB accepts only the plain
       ModelBuilder dialect): initial segment selection and the bold
       identity title line. */
    [self.modeControl setSelectedSegment:0];
    [self.identityTitleField setFont:
        [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]];

    [self.outline setTarget:self];
    [self.outline setDoubleAction:@selector(outlineDoubleClicked:)];

    /* Every XPath entry is one XFDXPathField: shared picker button and
       validation, wired to the same apply pass as plain fields. */
    for (XFDXPathField *field in [self xpathFields]) {
        field.provider = self;
        field.target = self;
        field.action = @selector(inspectorChanged:);
    }

    /* What each XPath attribute wants back — the picker previews the
       result and warns on a mismatch. */
    self.bindNodesetField.expectation = XFDXPathExpectNodeSet;
    self.controlValueField.expectation = XFDXPathExpectValue;
    self.itemsetNodesetField.expectation = XFDXPathExpectNodeSet;
    self.submissionRefField.expectation = XFDXPathExpectNode;
    self.itemsetLabelRefField.expectation = XFDXPathExpectNode;
    self.itemsetValueRefField.expectation = XFDXPathExpectNode;
    self.bindCalculateField.expectation = XFDXPathExpectValue;
    self.bindConstraintField.expectation = XFDXPathExpectValue;
    self.bindRequiredField.expectation = XFDXPathExpectValue;
    self.bindRelevantField.expectation = XFDXPathExpectValue;
    self.bindReadonlyField.expectation = XFDXPathExpectValue;

    /* The four text rows are XFDRichTextField: plain strings edit in
       place, rich XForms 1.1 content (inline markup + xf:output tokens)
       through the component's own modal editor. */
    for (XFDRichTextField *field in [self richTextFields]) {
        field.provider = self;
        field.target = self;
        field.action = @selector(inspectorChanged:);
    }

    /* Every IDREF attribute is one XFDIDRefField: a combo of the live ids
       of its kind (XForms 1.1 references by id everywhere — bind, model,
       instance, submission), typed or picked, dangling ids flagged red. */
    NSDictionary *idRefKinds = @{
        @"controlBindField": @"bind",
        @"controlModelField": @"model",
        @"controlSubmissionField": @"submission",
        @"submissionInstanceField": @"instance",
        @"submissionBindField": @"bind",
        @"itemsetBindField": @"bind",
    };
    for (NSString *outlet in idRefKinds) {
        XFDIDRefField *field = [self valueForKey:outlet];
        field.kind = idRefKinds[outlet];
        field.provider = self;
        field.target = self;
        field.action = @selector(inspectorChanged:);
    }

    /* Center pane: the live preview and the source text view are code —
       the xib only reserves their host views. */
    _previewScroll = [[NSScrollView alloc] initWithFrame:[self.previewHost bounds]];
    [_previewScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_previewScroll setHasVerticalScroller:YES];
    [_previewScroll setHasHorizontalScroller:YES];
    [_previewScroll setBorderType:NSNoBorder];
    [self.previewHost addSubview:_previewScroll];

    /* Design-mode overlay: a sibling ABOVE the scroll view, hidden until
       the Design checkbox turns the element picker on. */
    _designOverlay = [[XFDDesignOverlay alloc] initWithFrame:[self.previewHost bounds]];
    [_designOverlay setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    _designOverlay.delegate = self;
    _designOverlay.scrollView = _previewScroll;
    [self.previewHost addSubview:_designOverlay];

    NSScrollView *sourceScroll = [[NSScrollView alloc] initWithFrame:[self.sourceHost bounds]];
    [sourceScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [sourceScroll setHasVerticalScroller:YES];
    [sourceScroll setBorderType:NSNoBorder];
    NSTextView *tv = [[NSTextView alloc] initWithFrame:
        NSMakeRect(0, 0, [sourceScroll contentSize].width, [sourceScroll contentSize].height)];
    [tv setFont:[NSFont userFixedPitchFontOfSize:11]];
    [tv setRichText:NO];
    [tv setAllowsUndo:YES];
    [tv setVerticallyResizable:YES];
    [tv setHorizontallyResizable:NO];
    [tv setAutoresizingMask:NSViewWidthSizable];
    [[tv textContainer] setWidthTracksTextView:YES];
    [sourceScroll setDocumentView:tv];
    [self.sourceHost addSubview:sourceScroll];
    _sourceView = tv;

    XFDDocument *doc = [self formDocument];
    __weak XFDWindowController *weakSelf = self;
    doc.hostChangedHandler = ^(NSXMLElement *element) {
        [weakSelf hostChanged:element];
    };
    doc.processorReplacedHandler = ^{
        [weakSelf processorReplaced];
    };

    [self buildFormView];
    [self reloadOutlineKeepingSelection:nil];
    [self showInspectorForSelection];
}

- (void)buildFormView
{
    _formView = [[XFFormView alloc] initWithProcessor:[self processor]];
    [_previewScroll setDocumentView:_formView];
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window
{
    (void)window;
    return [[self document] undoManager];
}

#pragma mark - Change plumbing

/// After every XFHostEdit mutation (undo and redo included).
- (void)hostChanged:(NSXMLElement *)element
{
    (void)element;
    [self reloadOutlineKeepingSelection:_selected];
    [_formView rebuildWidgets];
    [_designOverlay setNeedsDisplay:YES];
    if ([self.centerTabView indexOfTabViewItem:[self.centerTabView selectedTabViewItem]] == 1) {
        [self refreshSourceText];
    }
    if (!_updating) {
        [self fillInspector];
    }
}

/// The processor was replaced (source apply / preview reset).
- (void)processorReplaced
{
    _selected = nil;
    [self buildFormView];
    [self reloadOutlineKeepingSelection:nil];
    [self showInspectorForSelection];
}

#pragma mark - Outline (host document)

- (NSXMLElement *)rootElement
{
    return [[self processor].hostDocument rootElement];
}

- (NSArray *)elementChildrenOf:(NSXMLElement *)element
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSXMLNode *c in [element children]) {
        if ([c kind] == NSXMLElementKind) {
            [out addObject:c];
        }
    }
    return out;
}

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item
{
    (void)ov;
    if (item == nil) {
        return [self rootElement] ? 1 : 0;
    }
    return (NSInteger)[self elementChildrenOf:item].count;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(id)item
{
    (void)ov;
    if (item == nil) {
        return [self rootElement];
    }
    return [self elementChildrenOf:item][(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item
{
    (void)ov;
    return [self elementChildrenOf:item].count > 0;
}

- (id)outlineView:(NSOutlineView *)ov objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
    (void)ov;
    (void)column;
    NSXMLElement *e = item;
    NSString *name = [e name] ?: [e localName] ?: @"?";
    NSString *detail = nil;
    XFHostEdit *edit = [self formDocument].hostEdit;
    NSString *labelText = [edit supportChildText:@"label" onElement:e];
    if (labelText.length) {
        detail = [NSString stringWithFormat:@"‘%@’", labelText];
    } else {
        NSString *ref = [[e attributeForName:@"ref"] stringValue]
            ?: [[e attributeForName:@"nodeset"] stringValue];
        if (ref.length) {
            detail = ref;
        } else {
            NSString *identifier = [[e attributeForName:@"id"] stringValue];
            if (identifier.length) {
                detail = [@"#" stringByAppendingString:identifier];
            }
        }
    }
    NSString *title = detail.length ? [NSString stringWithFormat:@"%@  %@", name, detail] : name;
    if (XFDElementIsUnbound(e)) {
        title = [title stringByAppendingString:@"  · unbound"];
    }
    return title;
}

- (BOOL)outlineView:(NSOutlineView *)ov shouldEditTableColumn:(NSTableColumn *)column item:(id)item
{
    (void)ov;
    (void)column;
    (void)item;
    return NO;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)note
{
    (void)note;
    if (_updating) {
        return;
    }
    NSInteger row = [self.outline selectedRow];
    _selected = row >= 0 ? [self.outline itemAtRow:row] : nil;
    [self showInspectorForSelection];
    [_designOverlay setNeedsDisplay:YES];
}

- (void)reloadOutlineKeepingSelection:(NSXMLElement *)keep
{
    _updating = YES;
    [self.outline reloadData];
    // the always-open levels
    NSXMLElement *root = [self rootElement];
    [self.outline expandItem:root];
    for (NSXMLElement *top in [self elementChildrenOf:root]) {
        [self.outline expandItem:top];
        for (NSXMLElement *second in [self elementChildrenOf:top]) {
            if ([[second localName] isEqualToString:@"model"]) {
                [self.outline expandItem:second];
            }
        }
    }
    if (keep) {
        // expand the ancestors, then reselect by identity
        NSMutableArray *chain = [NSMutableArray array];
        NSXMLNode *walk = [keep parent];
        while (walk && [walk kind] == NSXMLElementKind) {
            [chain insertObject:walk atIndex:0];
            walk = [walk parent];
        }
        for (id ancestor in chain) {
            [self.outline expandItem:ancestor];
        }
        NSInteger row = [self.outline rowForItem:keep];
        if (row >= 0) {
            [self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                      byExtendingSelection:NO];
        }
    }
    _updating = NO;
    _selected = keep;
}

- (void)selectElement:(NSXMLElement *)element
{
    [self reloadOutlineKeepingSelection:element];
    [self showInspectorForSelection];
    [_designOverlay setNeedsDisplay:YES];
}

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
    if ([[_selected localName] isEqualToString:@"output"]
        && [e attribute:@"value"].length) {
        [status setStringValue:@"Computed via value expression."];
        [status setTextColor:[NSColor disabledControlTextColor]];
        return;
    }
    if (_selected != nil && XFDElementIsUnbound(_selected)) {
        [status setStringValue:@"Unbound — typed values are not kept."];
        [status setTextColor:XFDWarningColor()];
        return;
    }
    [status setStringValue:@""];
}

#pragma mark - Instance data editing

/// The xf:instance the selection lives in (the selection itself, or an
/// instance-data ancestor). nil when the selection has nothing to do with
/// an instance.
- (NSXMLElement *)instanceElementForSelection:(NSXMLElement *)element
{
    for (NSXMLNode *walk = element; walk != nil; walk = [walk parent]) {
        if ([walk kind] == NSXMLElementKind
            && [XFXML element:(NSXMLElement *)walk hasLocalName:@"instance"
                 namespaceURI:XFXFormsNamespaceURI]) {
            return (NSXMLElement *)walk;
        }
    }
    return nil;
}

- (IBAction)editInstanceXML:(id)sender
{
    (void)sender;
    NSXMLElement *instance = [self instanceElementForSelection:_selected];
    if (instance == nil) {
        XFDBeep();
        return;
    }
    XFHostEdit *edit = [self formDocument].hostEdit;
    NSString *xml = [XFDInstanceXMLEditor
        runWithXML:[edit contentXMLOfElement:instance]
             title:[NSString stringWithFormat:@"Instance data — %@",
                    [[instance attributeForName:@"id"] stringValue] ?: @"instance"]];
    if (xml == nil) {
        return;
    }
    NSError *error = nil;
    if (![edit setContentXML:xml onElement:instance error:&error]) {
        [self presentError:error];
        return;
    }
    [self selectElement:instance];
}

- (void)outlineDoubleClicked:(id)sender
{
    NSInteger row = [self.outline clickedRow];
    NSXMLElement *element = row >= 0 ? [self.outline itemAtRow:row] : nil;
    if ([self instanceElementForSelection:element] != nil) {
        [self editInstanceXML:sender];
        return;
    }
    // otherwise a double-click toggles expansion
    if (element != nil && [self outlineView:self.outline isItemExpandable:element]) {
        if ([self.outline isItemExpanded:element]) {
            [self.outline collapseItem:element];
        } else {
            [self.outline expandItem:element];
        }
    }
}

#pragma mark - Palette

/// Shared by the palette panel and the Form menu.
- (void)insertPaletteName:(NSString *)name
{
    NSInteger index = -1;
    NSXMLElement *parent = [self insertParentForName:name index:&index];
    if (parent == nil) {
        XFDBeep();
        return;
    }
    NSError *error = nil;
    NSXMLElement *element = [[self formDocument].hostEdit insertElementNamed:name
                                                                underParent:parent
                                                                    atIndex:index
                                                                      error:&error];
    if (element == nil) {
        [self presentError:error ?: [NSError errorWithDomain:@"XFormsDesigner" code:2 userInfo:@{
            NSLocalizedDescriptionKey: @"Cannot insert here." }]];
        return;
    }
    [self selectElement:element];
}

#pragma mark - Inspector pages

- (XFDInspectorPage)pageForElement:(NSXMLElement *)element
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
    [self.inspectorKindTabView selectTabViewItemAtIndex:[self pageForElement:_selected]];
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
    _updating = YES;
    XFDDocument *doc = [self formDocument];
    XFDInspectorPage page = [self pageForElement:_selected];
    XFDElementEditor *base = [XFDElementEditor editorForElement:_selected document:doc];
    [self.identityTitleField setStringValue:base.title ?: @"No Selection"];
    [self.identityIdField setStringValue:base ? base.identifier : @""];
    [self.identityIdField setEnabled:base != nil];
    switch (page) {
        case XFDPageControl: {
            XFDControlEditor *e = [XFDControlEditor editorForElement:_selected document:doc];
            // a repeat's ref selects the nodeset it iterates; every other
            // control binds one node
            self.controlRefField.expectation =
                [[_selected localName] isEqualToString:@"repeat"]
                    ? XFDXPathExpectNodeSet : XFDXPathExpectNode;
            [self.controlRefField setStringValue:e.ref];
            // @value is xf:output's computed expression — dead weight elsewhere
            BOOL isOutput = [[_selected localName] isEqualToString:@"output"];
            [self.controlValueField setStringValue:isOutput ? e.valueExpression : @""];
            [self.controlValueField setEnabled:isOutput];
            [self.controlBindField setStringValue:e.bind];
            [self refreshBindingStatusForEditor:e];
            [self.controlCreateBindButton setEnabled:e.ref.length > 0 && e.bind.length == 0];
            [self.controlModelField setStringValue:e.model];
            // @submission is xf:submit's attribute — dead weight elsewhere
            BOOL isSubmit = [[_selected localName] isEqualToString:@"submit"];
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
            XFDBindEditor *e = [XFDBindEditor editorForElement:_selected document:doc];
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
            XFDSubmissionEditor *e = [XFDSubmissionEditor editorForElement:_selected document:doc];
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
            XFDInstanceEditor *e = [XFDInstanceEditor editorForElement:_selected document:doc];
            [self.instanceSrcField setStringValue:e.src];
            break;
        }
        case XFDPageAction:
            [self fillActionRows];
            break;
        case XFDPageItem: {
            XFDItemEditor *e = [XFDItemEditor editorForElement:_selected document:doc];
            [self.itemLabelField setPlainText:e.labelText xml:e.labelXML];
            [self.itemValueField setStringValue:e.valueText];
            break;
        }
        case XFDPageItemset: {
            XFDItemsetEditor *e = [XFDItemsetEditor editorForElement:_selected document:doc];
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
    [self reloadEventsTable];
    _updating = NO;
}

- (IBAction)inspectorChanged:(id)sender
{
    (void)sender;
    if (_updating || _selected == nil) {
        return;
    }
    XFDDocument *doc = [self formDocument];
    _updating = YES;   // the editors fire hostChanged per set; batch the refill
    XFDElementEditor *base = [XFDElementEditor editorForElement:_selected document:doc];
    base.identifier = [self.identityIdField stringValue];
    switch ([self pageForElement:_selected]) {
        case XFDPageControl: {
            XFDControlEditor *e = [XFDControlEditor editorForElement:_selected document:doc];
            e.ref = [self.controlRefField stringValue];
            if ([[_selected localName] isEqualToString:@"output"]) {
                e.valueExpression = [self.controlValueField stringValue];
            }
            e.bind = [self.controlBindField stringValue];
            e.model = [self.controlModelField stringValue];
            if ([[_selected localName] isEqualToString:@"submit"]) {
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
            XFDBindEditor *e = [XFDBindEditor editorForElement:_selected document:doc];
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
            XFDSubmissionEditor *e = [XFDSubmissionEditor editorForElement:_selected document:doc];
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
            XFDInstanceEditor *e = [XFDInstanceEditor editorForElement:_selected document:doc];
            e.src = [self.instanceSrcField stringValue];
            break;
        }
        case XFDPageAction:
            [self applyActionRows];
            break;
        case XFDPageItem: {
            XFDItemEditor *e = [XFDItemEditor editorForElement:_selected document:doc];
            [self applyRichField:self.itemLabelField name:@"label" toEditor:e];
            e.valueText = [self.itemValueField stringValue];
            break;
        }
        case XFDPageItemset: {
            XFDItemsetEditor *e = [XFDItemsetEditor editorForElement:_selected document:doc];
            e.nodeset = [self.itemsetNodesetField stringValue];
            e.bind = [self.itemsetBindField stringValue];
            e.labelRef = [self.itemsetLabelRefField stringValue];
            e.valueRef = [self.itemsetValueRefField stringValue];
            break;
        }
        case XFDPageElement:
            break;
    }
    _updating = NO;
    [self reloadOutlineKeepingSelection:_selected];
    [self fillInspector];
}

#pragma mark - Palette (+ / −)

- (IBAction)plusMinusClicked:(NSSegmentedControl *)sender
{
    if ([sender selectedSegment] == 0) {
        [self insertElement:sender];
    } else {
        [self deleteElement:sender];
    }
}

- (NSXMLElement *)insertStartParent
{
    if (_selected != nil) {
        return _selected;
    }
    NSXMLElement *body = nil;
    for (NSXMLElement *top in [self elementChildrenOf:[self rootElement]]) {
        if ([[top localName] isEqualToString:@"body"]) {
            body = top;
        }
    }
    return body;
}

/// Where a palette insert would go: the selection itself when it can
/// contain children, else the nearest ancestor that can — inserting AFTER
/// the selection there (so "+ with an input selected" adds a sibling,
/// like Xcode's outline). No selection targets the body.
- (NSXMLElement *)insertParentForSelection:(NSInteger *)indexOut
{
    NSXMLElement *parent = [self insertStartParent];
    NSXMLElement *child = nil;
    while (parent != nil && [XFHostEdit insertableNamesUnderParent:parent].count == 0) {
        child = parent;
        NSXMLNode *up = [child parent];
        parent = (up != nil && [up kind] == NSXMLElementKind) ? (NSXMLElement *)up : nil;
    }
    if (indexOut) {
        *indexOut = (parent != nil && child != nil) ? (NSInteger)[child index] + 1 : -1;
    }
    return parent;
}

/// The parent that would receive `name` specifically — different depths
/// accept different sets now that actions nest inside controls: with an
/// input selected, setvalue goes INTO the input while another input lands
/// as its SIBLING in the container above. Nearest accepting ancestor
/// wins; nil when nothing on the chain takes the name.
- (NSXMLElement *)insertParentForName:(NSString *)name index:(NSInteger *)indexOut
{
    NSXMLElement *parent = [self insertStartParent];
    NSXMLElement *child = nil;
    while (parent != nil && ![XFHostEdit canInsertElementNamed:name underParent:parent]) {
        child = parent;
        NSXMLNode *up = [child parent];
        parent = (up != nil && [up kind] == NSXMLElementKind) ? (NSXMLElement *)up : nil;
    }
    if (indexOut) {
        *indexOut = (parent != nil && child != nil) ? (NSInteger)[child index] + 1 : -1;
    }
    return parent;
}

/// Every name insertable SOMEWHERE on the selection's ancestor chain —
/// what the palette panel offers (each name resolves its own depth on
/// insert).
- (NSSet *)insertableNamesForSelection
{
    NSMutableSet *names = [NSMutableSet set];
    NSXMLElement *parent = [self insertStartParent];
    while (parent != nil) {
        [names addObjectsFromArray:[XFHostEdit insertableNamesUnderParent:parent]];
        NSXMLNode *up = [parent parent];
        parent = (up != nil && [up kind] == NSXMLElementKind) ? (NSXMLElement *)up : nil;
    }
    return names;
}

- (IBAction)insertElement:(id)sender
{
    (void)sender;
    NSSet *valid = [self insertableNamesForSelection];
    if (valid.count == 0) {
        XFDBeep();
        return;
    }
    NSXMLElement *start = [self insertStartParent];
    NSString *name = [XFDPalettePanel
        runWithValidNames:valid
               parentName:[start name] ?: @"element"];
    if (name != nil) {
        [self insertPaletteName:name];
    }
}

- (IBAction)deleteElement:(id)sender
{
    (void)sender;
    NSXMLElement *element = _selected;
    if (element == nil) {
        XFDBeep();
        return;
    }
    NSString *local = [element localName];
    BOOL structural = [local isEqualToString:@"html"] || [local isEqualToString:@"head"]
        || [local isEqualToString:@"body"] || [local isEqualToString:@"model"];
    if (structural || [element parent] == nil) {
        XFDBeep();
        return;
    }
    NSXMLElement *parent = (NSXMLElement *)[element parent];
    [[self formDocument].hostEdit deleteElement:element];
    [self selectElement:parent];
}

#pragma mark - Center pane (Form / Source)

- (IBAction)modeChanged:(NSSegmentedControl *)sender
{
    NSInteger mode = [sender selectedSegment];
    if (mode == 1) {
        [self refreshSourceText];
    }
    [self.centerTabView selectTabViewItemAtIndex:mode];
}

- (IBAction)toggleDesignMode:(id)sender
{
    (void)sender;
    BOOL on = [self.designModeCheckbox state] == NSOnState;
    [_designOverlay setHidden:!on];
    [[self window] setAcceptsMouseMovedEvents:on];
    if (on) {
        [[self window] makeFirstResponder:_designOverlay];
        [_designOverlay refreshHighlights];
    } else if ([[self window] firstResponder] == _designOverlay) {
        [[self window] makeFirstResponder:nil];
    }
}

#pragma mark - Design overlay (the element picker)

- (XFFormView *)formViewForOverlay:(id)overlay
{
    (void)overlay;
    return _formView;
}

- (NSXMLElement *)selectedElementForOverlay:(id)overlay
{
    (void)overlay;
    return _selected;
}

- (void)overlay:(id)overlay pickedElement:(NSXMLElement *)element
{
    (void)overlay;
    // widget hits come through control.element (repeat-item and
    // table-cell controls instantiate straight from host children, so
    // that IS the host element); SVG hits are host elements already
    if (element != nil && [element rootDocument] == [self processor].hostDocument) {
        [self selectElement:element];
    }
}

- (NSXMLElement *)bodyElement
{
    for (NSXMLNode *c in [[self rootElement] children]) {
        if ([c kind] == NSXMLElementKind
            && [[(NSXMLElement *)c localName] isEqualToString:@"body"]) {
            return (NSXMLElement *)c;
        }
    }
    return nil;
}

static NSDictionary *XFDDropSlot(NSXMLElement *parent, NSInteger index, NSRect line)
{
    return @{ @"parent": parent, @"index": @(index),
              @"line": [NSValue valueWithRect:line] };
}

static NSString * const XFDSVGNamespaceURI = @"http://www.w3.org/2000/svg";

/// The zone gate the drop slots use: XForms elements follow XFHostEdit's
/// insertion zones; SVG shapes reorder freely among SVG parents (the
/// engine's moveElement applies the same rule).
static BOOL XFDZoneAccepts(NSXMLElement *dragged, NSXMLElement *parent)
{
    if ([[dragged URI] isEqualToString:XFDSVGNamespaceURI]) {
        return [[parent URI] isEqualToString:XFDSVGNamespaceURI];
    }
    return [XFHostEdit canInsertElementNamed:[dragged localName] underParent:parent];
}

/// The drop slot for dragging `dragged` over `fp` (form-view coords):
/// hover a widget's or SVG shape's edge bands to become its sibling
/// (before / after), hover a container's middle to drop inside it,
/// hover below everything to land at the end of the body. nil = nothing
/// may drop here.
- (NSDictionary *)overlay:(id)overlay dropSlotAtFormPoint:(NSPoint)fp
               forElement:(NSXMLElement *)dragged
{
    (void)overlay;
    XFFormView *form = _formView;
    if (form == nil || dragged == nil
        || [dragged rootDocument] != [self processor].hostDocument) {
        return nil;
    }
    NSString *local = [dragged localName];
    (void)local;

    NSDictionary * (^siblingSlot)(NSXMLElement *, NSRect, BOOL) =
        ^NSDictionary *(NSXMLElement *te, NSRect r, BOOL before) {
        NSXMLElement *parent = (NSXMLElement *)[te parent];
        if ([parent kind] != NSXMLElementKind || !XFDZoneAccepts(dragged, parent)) {
            return nil;
        }
        NSInteger index = (NSInteger)[te index] + (before ? 0 : 1);
        if (parent == [dragged parent]) {
            NSInteger own = (NSInteger)[dragged index];
            if (index == own || index == own + 1) {
                return nil;   // dropping right where it already is
            }
        }
        CGFloat y = before ? NSMinY(r) - 3 : NSMaxY(r) + 1;
        return XFDDropSlot(parent, index,
                           NSMakeRect(NSMinX(r) - 4, y, NSWidth(r) + 8, 3));
    };

    NSXMLElement *te = [form svgElementAtPoint:fp];
    NSRect targetRect = NSZeroRect;
    if (te != nil) {
        targetRect = [form layoutFrameOfSVGElement:te];
    } else {
        XFControl *target = [form controlAtPoint:fp];
        te = target.element;
        if (target != nil) {
            targetRect = [form layoutFrameOfControl:target];
        }
    }
    if (te != nil && te != dragged) {
        // never into (or beside a node inside) the dragged subtree
        for (NSXMLNode *walk = te; walk != nil; walk = [walk parent]) {
            if (walk == dragged) {
                return nil;
            }
        }
        if ([te rootDocument] != [self processor].hostDocument) {
            return nil;
        }
        NSRect r = targetRect;
        if (NSIsEmptyRect(r)) {
            return nil;
        }
        CGFloat band = MIN(8.0, NSHeight(r) / 3.0);
        if (fp.y < NSMinY(r) + band) {
            return siblingSlot(te, r, YES);
        }
        if (fp.y > NSMaxY(r) - band) {
            return siblingSlot(te, r, NO);
        }
        // middle: into the target when its zone takes this kind
        // (containers — group, case, repeat, and SVG parents for SVG
        // shapes); plain widgets refuse and fall back to the nearer edge
        if (XFDZoneAccepts(dragged, te)) {
            NSRect line = NSMakeRect(NSMinX(r) + 6, NSMaxY(r) - 8,
                                     NSWidth(r) - 12, 3);
            return XFDDropSlot(te, -1, line);
        }
        return siblingSlot(te, r, fp.y < NSMidY(r));
    }

    // over empty space below the last widget: append to the body
    NSXMLElement *body = [self bodyElement];
    if (body == nil || !XFDZoneAccepts(dragged, body)) {
        return nil;
    }
    CGFloat maxY = 0;
    for (XFControl *top in [self processor].controls) {
        NSRect r = [form layoutFrameOfControl:top];
        if (!NSIsEmptyRect(r)) {
            maxY = MAX(maxY, NSMaxY(r));
        }
    }
    if (fp.y <= maxY + 4) {
        return nil;
    }
    // a no-op when the dragged element already closes the body
    NSXMLNode *lastChild = [body childCount] ? [body childAtIndex:[body childCount] - 1] : nil;
    if (lastChild == dragged) {
        return nil;
    }
    NSRect line = NSMakeRect(8, maxY + 6, MAX(NSWidth([form bounds]) - 16, 120), 3);
    return XFDDropSlot(body, -1, line);
}

- (void)overlay:(id)overlay dropElement:(NSXMLElement *)dragged slot:(NSDictionary *)slot
{
    (void)overlay;
    NSXMLElement *parent = slot[@"parent"];
    if (dragged == nil || parent == nil) {
        return;
    }
    NSUndoManager *undo = [[self document] undoManager];
    [undo beginUndoGrouping];
    BOOL moved = [[self formDocument].hostEdit moveElement:dragged
                                              underParent:parent
                                                  atIndex:[slot[@"index"] integerValue]];
    [undo endUndoGrouping];
    if (moved) {
        [self selectElement:dragged];
    } else {
        XFDBeep();
    }
}

- (void)refreshSourceText
{
    [_sourceView setString:[[self formDocument] hostXMLString] ?: @""];
}

- (IBAction)applySource:(id)sender
{
    (void)sender;
    NSError *error = nil;
    if (![[self formDocument] applySourceXML:[_sourceView string] error:&error]) {
        [self presentError:error];
    }
}

- (IBAction)resetInstances:(id)sender
{
    (void)sender;
    NSError *error = nil;
    if (![[self formDocument] resetPreview:&error]) {
        [self presentError:error];
    }
}

#pragma mark - Events group (the handler table)

/// XForms actions are supplementary: a handler observes the ELEMENT IT
/// SITS IN (XML Events attribute module — the observer defaults to the
/// parent of the element bearing ev:event). The Events group makes that
/// visible: a table of the selection's direct child actions, with + / −
/// and double-click to jump into a handler's own inspector.
- (void)buildEventsPane
{
    NSView *host = self.eventsHost;
    NSRect bounds = [host bounds];
    CGFloat W = NSWidth(bounds), H = NSHeight(bounds);

    _eventsNote = [[NSTextField alloc] initWithFrame:NSMakeRect(8, H - 34, W - 16, 28)];
    [_eventsNote setEditable:NO];
    [_eventsNote setBordered:NO];
    [_eventsNote setDrawsBackground:NO];
    [_eventsNote setFont:[NSFont systemFontOfSize:11]];
    [[_eventsNote cell] setWraps:YES];
    [_eventsNote setStringValue:@"Handlers below listen on this element's events."];
    [_eventsNote setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [host addSubview:_eventsNote];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:
        NSMakeRect(8, 40, W - 16, H - 80)];
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];
    _eventsTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, W - 16, H - 80)];
    struct { NSString *ident; NSString *title; CGFloat width; } cols[] = {
        { @"event", @"Event", 96 },
        { @"action", @"Action", 64 },
        { @"detail", @"Detail", 90 },
    };
    for (NSUInteger i = 0; i < 3; i++) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:cols[i].ident];
        [[col headerCell] setStringValue:cols[i].title];
        [col setWidth:cols[i].width];
        [[col dataCell] setEditable:NO];
        [[col dataCell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [_eventsTable addTableColumn:col];
    }
    [_eventsTable setDataSource:self];
    [_eventsTable setDelegate:self];
    [_eventsTable setTarget:self];
    [_eventsTable setDoubleAction:@selector(eventsRowDoubleClicked:)];
    [_eventsTable setAllowsMultipleSelection:NO];
    [scroll setDocumentView:_eventsTable];
    [host addSubview:scroll];

    _eventsControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(8, 8, 68, 24)];
    [_eventsControl setSegmentCount:2];
    [_eventsControl setLabel:@"+" forSegment:0];
    [_eventsControl setLabel:@"−" forSegment:1];
    [_eventsControl setAutoresizingMask:NSViewMaxYMargin];
    [(NSSegmentedCell *)[_eventsControl cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
    [_eventsControl setTarget:self];
    [_eventsControl setAction:@selector(eventsPlusMinusClicked:)];
    [host addSubview:_eventsControl];
}

static BOOL XFDElementIsActionHandler(NSXMLElement *e)
{
    return XFDActionSpecs()[[e localName]] != nil
        && [XFXML element:e hasLocalName:[e localName]
             namespaceURI:XFXFormsNamespaceURI];
}

/// The handler's effective observer id (ev:observer, engine-style "#id"
/// tolerated) — empty when it observes its parent, the default.
static NSString *XFDHandlerObserverID(NSXMLElement *e)
{
    NSString *observer = [XFXML attributeValue:@"observer"
                                  namespaceURI:XFXMLEventsNamespaceURI
                                     onElement:e];
    if ([observer hasPrefix:@"#"]) {
        observer = [observer substringFromIndex:1];
    }
    return observer ?: @"";
}

static void XFDCollectHandlersObserving(NSString *observerID, NSXMLElement *scope,
                                        NSXMLElement *skipParent, NSMutableArray *out)
{
    for (NSXMLNode *c in [scope children]) {
        if ([c kind] != NSXMLElementKind) {
            continue;
        }
        NSXMLElement *e = (NSXMLElement *)c;
        if ([e parent] != skipParent && XFDElementIsActionHandler(e)
            && [XFDHandlerObserverID(e) isEqualToString:observerID]) {
            [out addObject:e];
        }
        XFDCollectHandlersObserving(observerID, e, skipParent, out);
    }
}

- (NSArray *)handlerElementsOf:(NSXMLElement *)element
{
    // The table shows what LISTENS ON this element. XML Events defaults
    // the observer to the handler's parent, but ev:observer redirects it:
    // a child observing elsewhere drops out, and any handler in the
    // document naming this element's id comes in (its Detail column shows
    // the ev:observer that brought it here).
    NSString *elementID = [[element attributeForName:@"id"] stringValue];
    NSMutableArray *out = [NSMutableArray array];
    for (NSXMLNode *c in [element children]) {
        if ([c kind] != NSXMLElementKind) {
            continue;
        }
        NSXMLElement *e = (NSXMLElement *)c;
        if (!XFDElementIsActionHandler(e)) {
            continue;
        }
        NSString *observer = XFDHandlerObserverID(e);
        if (observer.length && ![observer isEqualToString:elementID]) {
            continue;   // redirected away — it does not listen here
        }
        [out addObject:e];
    }
    if (elementID.length && [self rootElement] != nil) {
        XFDCollectHandlersObserving(elementID, [self rootElement], element, out);
    }
    return out;
}

/// The action names the + menu offers for the selection.
- (NSArray *)addableHandlerNames
{
    NSMutableArray *names = [NSMutableArray array];
    if (_selected != nil) {
        for (NSString *name in [XFHostEdit insertableNamesUnderParent:_selected]) {
            if (XFDActionSpecs()[name] != nil) {
                [names addObject:name];
            }
        }
    }
    return names;
}

- (void)reloadEventsTable
{
    _handlerElements = _selected ? [self handlerElementsOf:_selected] : @[];
    BOOL canAdd = [self addableHandlerNames].count > 0;
    [_eventsControl setEnabled:canAdd forSegment:0];
    [_eventsControl setEnabled:[_eventsTable selectedRow] >= 0
                    forSegment:1];
    [_eventsNote setStringValue:_selected == nil
        ? @"No selection."
        : (canAdd || _handlerElements.count
            ? @"Handlers below listen on this element's events."
            : @"This element does not take event handlers.")];
    [_eventsTable reloadData];
}

- (void)eventsPlusMinusClicked:(NSSegmentedControl *)sender
{
    if ([sender selectedSegment] == 0) {
        NSArray *names = [self addableHandlerNames];
        if (names.count == 0) {
            XFDBeep();
            return;
        }
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Add Handler"];
        for (NSString *name in names) {
            NSMenuItem *item = [menu addItemWithTitle:name
                                               action:@selector(eventsAddHandler:)
                                        keyEquivalent:@""];
            [item setTarget:self];
            [item setRepresentedObject:name];
        }
        // [NSApp currentEvent] is the mouse-UP by action time and menus
        // cannot track from it — synthesize a mouse-down over the control
        NSPoint where = [[sender superview] convertPoint:[sender frame].origin toView:nil];
        NSEvent *down = [NSEvent mouseEventWithType:NSLeftMouseDown
                                           location:where
                                      modifierFlags:0
                                          timestamp:0
                                       windowNumber:[[sender window] windowNumber]
                                            context:nil
                                        eventNumber:0
                                         clickCount:1
                                           pressure:1];
        [NSMenu popUpContextMenu:menu withEvent:down forView:sender];
    } else {
        NSInteger row = [_eventsTable selectedRow];
        if (row < 0 || (NSUInteger)row >= _handlerElements.count) {
            XFDBeep();
            return;
        }
        [[self formDocument].hostEdit deleteElement:_handlerElements[(NSUInteger)row]];
    }
}

- (void)eventsAddHandler:(NSMenuItem *)item
{
    NSString *name = [item representedObject];
    NSError *error = nil;
    NSXMLElement *element = [[self formDocument].hostEdit
        insertElementNamed:name underParent:_selected atIndex:-1 error:&error];
    if (element == nil) {
        [self presentError:error];
        return;
    }
    // stay on the parent — the table is the point here; double-click the
    // new row to edit the handler in depth
    NSUInteger row = [[self handlerElementsOf:_selected] indexOfObject:element];
    if (row != NSNotFound) {
        [_eventsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                  byExtendingSelection:NO];
    }
}

- (void)eventsRowDoubleClicked:(id)sender
{
    (void)sender;
    NSInteger row = [_eventsTable clickedRow];
    if (row < 0) {
        row = [_eventsTable selectedRow];
    }
    if (row < 0 || (NSUInteger)row >= _handlerElements.count) {
        return;
    }
    // jump into the handler's own inspector (the Attributes group's
    // Action page)
    DMTabBar *bar = (DMTabBar *)self.inspectorTabBar;
    bar.selectedIndex = 1;
    [self.inspectorTabView selectTabViewItemAtIndex:1];
    [self selectElement:_handlerElements[(NSUInteger)row]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
    if ([note object] == _eventsTable) {
        [_eventsControl setEnabled:[_eventsTable selectedRow] >= 0 forSegment:1];
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
    return table == _eventsTable ? (NSInteger)_handlerElements.count : 0;
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
    if (table != _eventsTable || (NSUInteger)row >= _handlerElements.count) {
        return nil;
    }
    NSXMLElement *e = _handlerElements[(NSUInteger)row];
    NSString *ident = [column identifier];
    if ([ident isEqualToString:@"event"]) {
        return [XFXML attributeValue:@"event"
                        namespaceURI:XFXMLEventsNamespaceURI
                           onElement:e] ?: @"";
    }
    if ([ident isEqualToString:@"action"]) {
        return [e localName] ?: @"";
    }
    // detail: the interesting attributes, else the text content
    NSMutableArray *parts = [NSMutableArray array];
    for (NSXMLNode *attr in [e attributes]) {
        NSString *name = [attr name] ?: @"";
        if ([name isEqualToString:@"id"] || [name hasSuffix:@":event"]
            || [name isEqualToString:@"event"]) {
            continue;
        }
        [parts addObject:[NSString stringWithFormat:@"%@=%@", name, [attr stringValue] ?: @""]];
    }
    if (parts.count == 0) {
        NSString *text = [[XFXML stringValueOfNode:e] stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return text ?: @"";
    }
    return [parts componentsJoinedByString:@"  "];
}

#pragma mark - Action page (data-driven rows)

/// (Re)build the Action page's rows for the selected action element —
/// only when the element actually changed: rebuilding under a component
/// that is mid-action-send would free it.
- (void)buildActionRowsIfNeeded
{
    if (_actionRowsElement == _selected && _actionRows != nil) {
        return;
    }
    for (NSView *sub in [[self.actionRowsHost subviews] copy]) {
        [sub removeFromSuperview];
    }
    NSMutableArray *rows = [NSMutableArray array];
    NSArray *specs = XFDActionSpecs()[[_selected localName]] ?: @[];
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

    NSRect bounds = [self.actionRowsHost bounds];
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
        [self.actionRowsHost addSubview:label];

        NSRect frame = NSMakeRect(98, y - 4, NSWidth(bounds) - 106, 21);
        NSView *view = nil;
        if ([kind isEqualToString:@"xpath"]) {
            XFDXPathField *field = [[XFDXPathField alloc] initWithFrame:frame];
            field.provider = self;
            field.target = self;
            field.action = @selector(inspectorChanged:);
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
            field.target = self;
            field.action = @selector(inspectorChanged:);
            view = field;
        } else if ([kind isEqualToString:@"content"]) {
            XFDRichTextField *field = [[XFDRichTextField alloc] initWithFrame:frame];
            field.provider = self;
            field.target = self;
            field.action = @selector(inspectorChanged:);
            view = field;
        } else if ([kind isEqualToString:@"popup"]) {
            NSPopUpButton *popup = [[NSPopUpButton alloc]
                initWithFrame:NSMakeRect(98, y - 5, NSWidth(bounds) - 106, 22) pullsDown:NO];
            [[popup cell] setControlSize:NSSmallControlSize];
            [popup setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
            [popup addItemsWithTitles:spec[@"options"]];
            [popup setTarget:self];
            [popup setAction:@selector(inspectorChanged:)];
            view = popup;
        } else {   // field
            NSTextField *field = [[NSTextField alloc] initWithFrame:
                NSMakeRect(98, y - 3, NSWidth(bounds) - 106, 19)];
            [[field cell] setControlSize:NSSmallControlSize];
            [field setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
            [[field cell] setScrollable:YES];
            [[field cell] setSendsActionOnEndEditing:YES];
            [field setTarget:self];
            [field setAction:@selector(inspectorChanged:)];
            view = field;
        }
        [view setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        if (spec[@"tip"] != nil) {
            [view setToolTip:spec[@"tip"]];
        }
        [self.actionRowsHost addSubview:view];
        [rows addObject:@{ @"attr": spec[@"attr"] ?: @"", @"kind": kind, @"view": view }];
        y -= 26;
    }
    _actionRows = rows;
    _actionRowsElement = _selected;
}

- (void)fillActionRows
{
    [self buildActionRowsIfNeeded];
    XFDElementEditor *e = [XFDElementEditor editorForElement:_selected
                                                    document:[self formDocument]];
    for (NSDictionary *row in _actionRows) {
        NSString *kind = row[@"kind"];
        id view = row[@"view"];
        if ([kind isEqualToString:@"content"]) {
            XFHostEdit *edit = [[self formDocument] hostEdit];
            NSString *xml = [edit inlineContentXMLOfElement:_selected];
            [(XFDRichTextField *)view setPlainText:[XFXML stringValueOfNode:_selected] ?: @""
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

- (void)applyActionRows
{
    if (_actionRowsElement != _selected || _actionRows == nil) {
        return;
    }
    XFDElementEditor *e = [XFDElementEditor editorForElement:_selected
                                                    document:[self formDocument]];
    for (NSDictionary *row in _actionRows) {
        NSString *kind = row[@"kind"];
        id view = row[@"view"];
        if ([kind isEqualToString:@"content"]) {
            XFHostEdit *edit = [[self formDocument] hostEdit];
            XFDRichTextField *field = view;
            NSString *xml = [field isRich] ? [field xmlValue]
                                           : XFDEscapeXML([field stringValue]);
            [edit setInlineContentXML:xml onElement:_selected error:NULL];
        } else if ([kind isEqualToString:@"popup"]) {
            NSInteger idx = [(NSPopUpButton *)view indexOfSelectedItem];
            [e setAttribute:row[@"attr"]
                      value:idx <= 0 ? @"" : [(NSPopUpButton *)view titleOfSelectedItem]];
        } else {
            [e setAttribute:row[@"attr"] value:[(id)view stringValue]];
        }
    }
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
    if (_selected == nil || [self pageForElement:_selected] != XFDPageControl) {
        XFDBeep();
        return;
    }
    XFDControlEditor *e = [XFDControlEditor editorForElement:_selected
                                                    document:[self formDocument]];
    NSString *ref = e.ref;
    if (ref.length == 0 || e.bind.length) {
        XFDBeep();
        return;
    }
    XFHostEdit *edit = [self formDocument].hostEdit;
    NSXMLElement *modelEl = (NSXMLElement *)[self processor].model.element;
    NSError *error = nil;
    NSXMLElement *bind = [edit insertElementNamed:@"bind" underParent:modelEl
                                          atIndex:-1 error:&error];
    if (bind == nil) {
        [self presentError:error];
        return;
    }
    [edit setAttribute:@"nodeset" value:ref onElement:bind];
    NSString *identifier = [[bind attributeForName:@"id"] stringValue];
    [edit setAttribute:@"bind" value:identifier onElement:_selected];
    [edit setAttribute:@"ref" value:@"" onElement:_selected];
    [self selectElement:_selected];
}

/// The instance-data node under the selection when there is one (the
/// selection itself must live INSIDE an xf:instance, not be the instance).
- (NSXMLElement *)selectedInstanceDataNode
{
    if (_selected == nil
        || [XFXML element:_selected hasLocalName:[_selected localName]
             namespaceURI:XFXFormsNamespaceURI]) {
        return nil;
    }
    NSXMLElement *instance = [self instanceElementForSelection:_selected];
    return (instance != nil && instance != _selected) ? _selected : nil;
}

/// The ref that reaches `node` from the picker's default context: plain
/// steps for the default instance, instance('id')/… for a named one, nil
/// when the node's instance cannot be addressed.
- (NSString *)refForDataNode:(NSXMLElement *)node
{
    // the outline shows the HOST document's inline instance content;
    // XFInstance works on a COPY — map through the owning xf:instance
    NSXMLElement *instanceHost = [self instanceElementForSelection:node];
    NSXMLElement *dataRoot = nil;
    for (NSXMLNode *c in [instanceHost children]) {
        if ([c kind] == NSXMLElementKind) {
            dataRoot = (NSXMLElement *)c;
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
    NSXMLElement *dataNode = [self selectedInstanceDataNode];
    NSString *ref = dataNode ? [self refForDataNode:dataNode] : nil;
    if (ref == nil) {
        XFDBeep();
        return;
    }
    NSXMLElement *body = nil;
    for (NSXMLElement *top in [self elementChildrenOf:[self rootElement]]) {
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
    NSXMLElement *control = [edit insertElementNamed:kind underParent:body
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
        NSMenuItem *item = [menu addItemWithTitle:kind
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

- (NSXMLElement *)hostElementForXPathField:(XFDXPathField *)field
{
    (void)field;
    return _selected;
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
        if (bind.element == _selected) {
            return bind;
        }
        XFBind *nested = [self bindForSelectionIn:bind.binds];
        if (nested != nil) {
            return nested;
        }
    }
    return nil;
}

- (NSXMLNode *)contextNodeForXPathField:(XFDXPathField *)field
{
    if ([self pageForElement:_selected] == XFDPageBind) {
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
    if ([self pageForElement:_selected] == XFDPageControl) {
        XFControl *control = [[self processor] controlForElement:_selected];
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

- (NSXMLElement *)hostElementForRichTextField:(XFDRichTextField *)field
{
    (void)field;
    return _selected;
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
- (NSXMLNode *)contextNodeForRichTextField:(XFDRichTextField *)field
{
    (void)field;
    if ([self pageForElement:_selected] == XFDPageControl) {
        XFControl *control = [[self processor] controlForElement:_selected];
        while (control != nil && control.boundNode == nil) {
            control = control.parentControl;
        }
        if (control.boundNode != nil) {
            return control.boundNode;
        }
    }
    return [[[self processor] defaultInstance] documentElement];
}

#pragma mark - Undo plumbing (responder chain)

- (void)undo:(id)sender
{
    (void)sender;
    [[[self document] undoManager] undo];
}

- (void)redo:(id)sender
{
    (void)sender;
    [[[self document] undoManager] redo];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    SEL action = [item action];
    if (action == @selector(undo:)) {
        return [[[self document] undoManager] canUndo];
    }
    if (action == @selector(redo:)) {
        return [[[self document] undoManager] canRedo];
    }
    if (action == @selector(insertElement:)) {
        return [self insertParentForSelection:NULL] != nil;
    }
    if (action == @selector(deleteElement:)) {
        return _selected != nil;
    }
    return YES;
}

#pragma mark - Split view

- (CGFloat)splitView:(NSSplitView *)sv constrainMinCoordinate:(CGFloat)proposed
         ofSubviewAt:(NSInteger)index
{
    (void)sv;
    (void)proposed;
    return index == 0 ? 180 : 420;
}

- (CGFloat)splitView:(NSSplitView *)sv constrainMaxCoordinate:(CGFloat)proposed
         ofSubviewAt:(NSInteger)index
{
    (void)sv;
    if (index == 1) {
        return [sv frame].size.width - 240;
    }
    return proposed;
}

@end




#pragma mark - Palette panel

/// Badge tints per palette category.
static NSImage *XFDPaletteIcon(NSString *name, NSString *category)
{
    CGFloat r = 0.36, g = 0.49, b = 0.72;                 // Controls: blue
    if ([category isEqualToString:@"Containers"]) {
        r = 0.32; g = 0.60; b = 0.53;                     // green
    } else if ([category isEqualToString:@"Choices"]) {
        r = 0.80; g = 0.58; b = 0.28;                     // amber
    } else if ([category isEqualToString:@"Model"]) {
        r = 0.55; g = 0.42; b = 0.65;                     // purple
    }
    return XFDBadge([[name substringToIndex:1] uppercaseString], r, g, b);
}

@implementation XFDPalettePanel

- (void)rebuildRowsWithFilter:(NSString *)filter
{
    NSMutableArray *rows = [NSMutableArray array];
    NSString *category = nil;
    for (NSDictionary *entry in XFDPaletteCatalog()) {
        if (filter.length) {
            NSString *haystack = [NSString stringWithFormat:@"%@ %@", entry[@"name"], entry[@"desc"]];
            if ([haystack rangeOfString:filter options:NSCaseInsensitiveSearch].location == NSNotFound) {
                continue;
            }
        }
        if (![entry[@"cat"] isEqualToString:category]) {
            category = entry[@"cat"];
            [rows addObject:@{ @"header": category }];
        }
        [rows addObject:entry];
    }
    _rows = rows;
    [_table reloadData];
    [_insertButton setEnabled:NO];
}

- (void)buildPanelWithParentName:(NSString *)parentName
{
    const CGFloat W = 420, H = 520;
    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, W, H)
                                        styleMask:NSTitledWindowMask | NSClosableWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    [_panel setTitle:[NSString stringWithFormat:@"Insert into %@", parentName]];
    NSView *content = [_panel contentView];

    _searchField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, H - 34, W - 24, 22)];
    [_searchField setFont:[NSFont systemFontOfSize:12]];
    [[_searchField cell] setPlaceholderString:@"Filter"];
    [_searchField setDelegate:self];
    [content addSubview:_searchField];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 46, W - 24, H - 92)];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];
    _table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, W - 24, H - 92)];
    NSTableColumn *iconColumn = [[NSTableColumn alloc] initWithIdentifier:@"icon"];
    [iconColumn setWidth:24];
    NSImageCell *imageCell = [[NSImageCell alloc] init];
    [iconColumn setDataCell:imageCell];
    NSTableColumn *textColumn = [[NSTableColumn alloc] initWithIdentifier:@"text"];
    [textColumn setWidth:W - 80];
    [[textColumn dataCell] setEditable:NO];
    [[textColumn dataCell] setWraps:YES];
    [_table addTableColumn:iconColumn];
    [_table addTableColumn:textColumn];
    [_table setHeaderView:nil];
    [_table setRowHeight:32];
    [_table setDataSource:self];
    [_table setDelegate:self];
    [_table setTarget:self];
    [_table setDoubleAction:@selector(rowDoubleClicked:)];
    [scroll setDocumentView:_table];
    [content addSubview:scroll];

    NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(W - 190, 8, 84, 28)];
    [cancel setTitle:@"Cancel"];
    [cancel setBezelStyle:NSRoundedBezelStyle];
    [cancel setKeyEquivalent:@"\033"];
    [cancel setTarget:self];
    [cancel setAction:@selector(cancelClicked:)];
    [content addSubview:cancel];
    _insertButton = [[NSButton alloc] initWithFrame:NSMakeRect(W - 100, 8, 84, 28)];
    [_insertButton setTitle:@"Insert"];
    [_insertButton setBezelStyle:NSRoundedBezelStyle];
    [_insertButton setKeyEquivalent:@"\r"];
    [_insertButton setTarget:self];
    [_insertButton setAction:@selector(insertClicked:)];
    [_insertButton setEnabled:NO];
    [content addSubview:_insertButton];
    [_panel setDelegate:(id)self];
}

#pragma mark table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
    (void)table;
    return (NSInteger)_rows.count;
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)table;
    NSDictionary *entry = _rows[(NSUInteger)row];
    BOOL isIcon = [[column identifier] isEqualToString:@"icon"];
    if (entry[@"header"] != nil) {
        if (isIcon) {
            return nil;
        }
        return [[NSAttributedString alloc] initWithString:entry[@"header"] attributes:@{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:11],
            NSForegroundColorAttributeName: [NSColor disabledControlTextColor] }];
    }
    if (isIcon) {
        return XFDPaletteIcon(entry[@"name"], entry[@"cat"]);
    }
    BOOL valid = [_validNames containsObject:entry[@"name"]];
    NSColor *nameColor = valid ? [NSColor controlTextColor] : [NSColor disabledControlTextColor];
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
    [text appendAttributedString:[[NSAttributedString alloc]
        initWithString:entry[@"name"]
            attributes:@{ NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]],
                          NSForegroundColorAttributeName: nameColor }]];
    [text appendAttributedString:[[NSAttributedString alloc]
        initWithString:[@"\n" stringByAppendingString:entry[@"desc"]]
            attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:10],
                          NSForegroundColorAttributeName: [NSColor disabledControlTextColor] }]];
    return text;
}

- (BOOL)tableView:(NSTableView *)table shouldSelectRow:(NSInteger)row
{
    (void)table;
    NSDictionary *entry = _rows[(NSUInteger)row];
    return entry[@"header"] == nil && [_validNames containsObject:entry[@"name"]];
}

- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)table;
    (void)column;
    (void)row;
    return NO;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
    (void)note;
    [_insertButton setEnabled:[self selectedName] != nil];
}

- (NSString *)selectedName
{
    NSInteger row = [_table selectedRow];
    if (row < 0) {
        return nil;
    }
    NSDictionary *entry = _rows[(NSUInteger)row];
    NSString *name = entry[@"name"];
    return (name != nil && [_validNames containsObject:name]) ? name : nil;
}

#pragma mark search / buttons

- (void)controlTextDidChange:(NSNotification *)note
{
    (void)note;
    [self rebuildRowsWithFilter:[_searchField stringValue]];
}

- (void)rowDoubleClicked:(id)sender
{
    (void)sender;
    if ([self selectedName] != nil) {
        [self insertClicked:sender];
    }
}

- (void)insertClicked:(id)sender
{
    (void)sender;
    _result = [self selectedName];
    if (_result == nil) {
        XFDBeep();
        return;
    }
    [NSApp stopModal];
    [_panel orderOut:nil];
}

- (void)cancelClicked:(id)sender
{
    (void)sender;
    _result = nil;
    [NSApp abortModal];
    [_panel orderOut:nil];
}

/// The titlebar close button behaves like Cancel.
- (BOOL)windowShouldClose:(id)sender
{
    (void)sender;
    [self cancelClicked:sender];
    return NO;
}

+ (NSString *)runWithValidNames:(NSSet *)validNames parentName:(NSString *)parentName
{
    XFDPalettePanel *panel = [[XFDPalettePanel alloc] init];
    panel->_validNames = validNames ?: [NSSet set];
    [panel buildPanelWithParentName:parentName];
    [panel rebuildRowsWithFilter:nil];
    [panel->_panel center];
    [panel->_panel makeFirstResponder:panel->_searchField];
    [NSApp runModalForWindow:panel->_panel];
    return panel->_result;
}

@end

#pragma mark - Instance XML editor panel

@implementation XFDInstanceXMLEditor

- (void)buildPanelWithTitle:(NSString *)title
{
    const CGFloat W = 560, H = 500;
    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, W, H)
                                        styleMask:NSTitledWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    [_panel setTitle:title];
    NSView *content = [_panel contentView];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 72, W - 24, H - 84)];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];
    _text = [[NSTextView alloc] initWithFrame:
        NSMakeRect(0, 0, [scroll contentSize].width, [scroll contentSize].height)];
    [_text setFont:[NSFont userFixedPitchFontOfSize:11]];
    [_text setRichText:NO];
    [_text setAllowsUndo:YES];
    [_text setVerticallyResizable:YES];
    [_text setHorizontallyResizable:NO];
    [_text setAutoresizingMask:NSViewWidthSizable];
    [[_text textContainer] setWidthTracksTextView:YES];
    [_text setDelegate:(id)self];
    [scroll setDocumentView:_text];
    [content addSubview:scroll];

    _statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 46, W - 24, 17)];
    [_statusField setEditable:NO];
    [_statusField setBordered:NO];
    [_statusField setDrawsBackground:NO];
    [_statusField setFont:[NSFont systemFontOfSize:11]];
    [content addSubview:_statusField];

    NSButton *load = [[NSButton alloc] initWithFrame:NSMakeRect(12, 8, 110, 28)];
    [load setTitle:@"Load File…"];
    [load setBezelStyle:NSRoundedBezelStyle];
    [load setTarget:self];
    [load setAction:@selector(loadClicked:)];
    [content addSubview:load];
    NSButton *blank = [[NSButton alloc] initWithFrame:NSMakeRect(126, 8, 100, 28)];
    [blank setTitle:@"Blankify"];
    [blank setBezelStyle:NSRoundedBezelStyle];
    [blank setToolTip:@"Clear every leaf value and attribute — real data becomes initial data"];
    [blank setTarget:self];
    [blank setAction:@selector(blankifyClicked:)];
    [content addSubview:blank];

    NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(W - 190, 8, 84, 28)];
    [cancel setTitle:@"Cancel"];
    [cancel setBezelStyle:NSRoundedBezelStyle];
    [cancel setTarget:self];
    [cancel setAction:@selector(cancelClicked:)];
    [content addSubview:cancel];
    _okButton = [[NSButton alloc] initWithFrame:NSMakeRect(W - 100, 8, 84, 28)];
    [_okButton setTitle:@"OK"];
    [_okButton setBezelStyle:NSRoundedBezelStyle];
    [_okButton setKeyEquivalent:@"\r"];
    [_okButton setTarget:self];
    [_okButton setAction:@selector(okClicked:)];
    [content addSubview:_okButton];
}

- (NSXMLDocument *)parsedDocument:(NSError **)error
{
    return [[NSXMLDocument alloc] initWithXMLString:[_text string] options:0 error:error];
}

- (void)validateNow
{
    NSError *error = nil;
    NSXMLDocument *doc = [self parsedDocument:&error];
    if (doc != nil) {
        [_statusField setStringValue:@"✓ well-formed"];
        [_statusField setTextColor:[NSColor disabledControlTextColor]];
        [_okButton setEnabled:YES];
    } else {
        [_statusField setStringValue:[@"✗ " stringByAppendingString:
            [error localizedDescription] ?: @"not well-formed XML"]];
        [_statusField setTextColor:[NSColor redColor]];
        [_okButton setEnabled:NO];
    }
}

- (void)textDidChange:(NSNotification *)note
{
    (void)note;
    [self validateNow];
}

/// Clear every leaf element's text and every attribute value, keeping the
/// structure — imported real data becomes the form's default data.
static void XFDBlankify(NSXMLElement *element)
{
    for (NSXMLNode *attribute in [element attributes]) {
        [attribute setStringValue:@""];
    }
    BOOL hasElementChildren = NO;
    for (NSXMLNode *child in [element children]) {
        if ([child kind] == NSXMLElementKind) {
            hasElementChildren = YES;
            XFDBlankify((NSXMLElement *)child);
        }
    }
    if (!hasElementChildren) {
        [element setStringValue:@""];
    }
}

- (void)blankifyClicked:(id)sender
{
    (void)sender;
    NSError *error = nil;
    NSXMLDocument *doc = [self parsedDocument:&error];
    if (doc == nil) {
        XFDBeep();
        return;
    }
    XFDBlankify([doc rootElement]);
    [_text setString:[[doc rootElement] XMLStringWithOptions:NSXMLNodePrettyPrint] ?: @""];
    [self validateNow];
}

- (void)loadClicked:(id)sender
{
    (void)sender;
    NSOpenPanel *open = [NSOpenPanel openPanel];
    if ([open runModal] != NSOKButton) {
        return;
    }
    NSURL *url = [[open URLs] firstObject] ?: [open URL];
    NSString *xml = [NSString stringWithContentsOfURL:url
                                             encoding:NSUTF8StringEncoding
                                                error:NULL]
        ?: [NSString stringWithContentsOfURL:url encoding:NSISOLatin1StringEncoding error:NULL];
    if (xml == nil) {
        XFDBeep();
        return;
    }
    [_text setString:xml];
    [self validateNow];
}

- (void)okClicked:(id)sender
{
    (void)sender;
    _result = [_text string];
    [NSApp stopModal];
    [_panel orderOut:nil];
}

- (void)cancelClicked:(id)sender
{
    (void)sender;
    _result = nil;
    [NSApp abortModal];
    [_panel orderOut:nil];
}

+ (NSString *)runWithXML:(NSString *)xml title:(NSString *)title
{
    XFDInstanceXMLEditor *editor = [[XFDInstanceXMLEditor alloc] init];
    [editor buildPanelWithTitle:title];
    [editor->_text setString:xml.length ? xml : @"<data xmlns=\"\">\n</data>"];
    [editor validateNow];
    [editor->_panel center];
    [NSApp runModalForWindow:editor->_panel];
    return editor->_result;
}

@end
