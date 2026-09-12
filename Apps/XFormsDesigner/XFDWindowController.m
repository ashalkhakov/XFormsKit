/* XFormsDesigner document window â the core: nib assembly, the change
   plumbing every XFHostEdit mutation flows through, undo, and the split
   view. The rest of the controller lives beside this file:
   +Outline (left pane), +Inspector (right pane), +Preview (center pane
   and design mode); the Events group and the Action page are their own
   objects (XFDEventsPane, XFDActionRowsPane); the modal palette and the
   instance XML editor are XFDPalettePanel / XFDInstanceXMLEditor; the
   shared catalogs live in XFDInspectorSpecs.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDWindowControllerPriv.h"
#import <XFormsKit/XFXMLTypes.h>
#import "XFDDocument.h"
#import "XFDEditors.h"
#import "XFDDesignOverlay.h"
#import "XFDInspectorSpecs.h"
#import "XFDPalettePanel.h"
#import "XFDInstanceXMLEditor.h"
#import "XFDSubmissionTester.h"
#import "XFDEventsConsole.h"
#import "DMTabBar.h"
#import "DMTabBarItem.h"

/* A split file missing from the GNUmakefile or a pbxproj fails at LINK
   time instead of misbehaving at runtime (the AppKit split's pattern). */
__attribute__((used)) static void (*const XFDWindowControllerFileChecks[])(void) = {
    XFDWindowControllerOutlineFilePresent,
    XFDWindowControllerInspectorFilePresent,
    XFDWindowControllerPreviewFilePresent,
    XFDInspectorSpecsFilePresent,
    XFDPalettePanelFilePresent,
    XFDInstanceXMLEditorFilePresent,
    XFDEventsPaneFilePresent,
    XFDActionRowsPaneFilePresent,
    XFDSubmissionTesterFilePresent,
    XFDEventsConsoleFilePresent,
};

@implementation XFDWindowController

- (XFDDocument *)formDocument
{
    return (XFDDocument *)[self document];
}

- (XFProcessor *)processor
{
    return [self formDocument].processor;
}

#pragma mark - Nib assembly

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
    self.eventsPane = [[XFDEventsPane alloc] initWithController:self
                                                            host:self.eventsHost];
    self.actionRowsPane = [[XFDActionRowsPane alloc] initWithController:self
                                                                   host:self.actionRowsHost];
    [self applyAttributeTips];

    /* What the xib deliberately leaves out (IB accepts only the plain
       ModelBuilder dialect): initial segment selection and the bold
       identity title line. */
    [self.modeControl setSelectedSegment:0];
    [self.identityTitleField setFont:
        [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]];

    /* The Submission page gets its Test… button in code — the xib stays
       untouched (the tester panel itself is XFDSubmissionTester). */
    NSView *submissionPage = [[self.inspectorKindTabView
        tabViewItemAtIndex:XFDPageSubmission] view];
    NSButton *testButton = [[NSButton alloc] initWithFrame:NSMakeRect(12, 8, 150, 26)];
    [testButton setTitle:@"Test Submission…"];
    [testButton setBezelStyle:NSRoundedBezelStyle];
    [[testButton cell] setControlSize:NSSmallControlSize];
    [testButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [testButton setToolTip:@"Postman-style test run: preview the exact request, send it through the real xforms-submit path, inspect the response."];
    [testButton setTarget:self];
    [testButton setAction:@selector(testSubmissionClicked:)];
    [submissionPage addSubview:testButton];

    /* The events console toggle sits beside the Design checkbox — in
       code, like the tester button, so the xib stays untouched. */
    if (self.designModeCheckbox) {
        NSRect near = [self.designModeCheckbox frame];
        NSButton *consoleButton = [[NSButton alloc] initWithFrame:
            NSMakeRect(NSMaxX(near) + 8, NSMinY(near) - 2, 130, NSHeight(near) + 4)];
        [consoleButton setTitle:@"Events Console"];
        [consoleButton setBezelStyle:NSRoundedBezelStyle];
        [[consoleButton cell] setControlSize:NSSmallControlSize];
        [consoleButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [consoleButton setToolTip:@"The XSLTForms events console: every dispatched event, handler run, and engine action, live."];
        [consoleButton setTarget:self];
        [consoleButton setAction:@selector(toggleEventsConsole:)];
        [consoleButton setAutoresizingMask:[self.designModeCheckbox autoresizingMask]];
        [[self.designModeCheckbox superview] addSubview:consoleButton];
    }

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
    self.previewScroll = [[NSScrollView alloc] initWithFrame:[self.previewHost bounds]];
    [self.previewScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [self.previewScroll setHasVerticalScroller:YES];
    [self.previewScroll setHasHorizontalScroller:YES];
    [self.previewScroll setBorderType:NSNoBorder];
    [self.previewHost addSubview:self.previewScroll];

    /* Design-mode overlay: a sibling ABOVE the scroll view, hidden until
       the Design checkbox turns the element picker on. */
    self.designOverlay = [[XFDDesignOverlay alloc] initWithFrame:[self.previewHost bounds]];
    [self.designOverlay setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    self.designOverlay.delegate = self;
    self.designOverlay.scrollView = self.previewScroll;
    [self.previewHost addSubview:self.designOverlay];

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
    self.sourceView = tv;

    XFDDocument *doc = [self formDocument];
    __weak XFDWindowController *weakSelf = self;
    doc.hostChangedHandler = ^(XFXMLElement *element) {
        [weakSelf hostChanged:element];
    };
    doc.processorReplacedHandler = ^{
        [weakSelf processorReplaced];
    };

    [self buildFormView];
    [self reloadOutlineKeepingSelection:nil];
    [self showInspectorForSelection];
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window
{
    (void)window;
    return [[self document] undoManager];
}

#pragma mark - Change plumbing

#pragma mark - Change plumbing

/// After every XFHostEdit mutation (undo and redo included).
- (void)hostChanged:(XFXMLElement *)element
{
    (void)element;
    [self reloadOutlineKeepingSelection:self.selected];
    [self.formView rebuildWidgets];
    [self.designOverlay setNeedsDisplay:YES];
    if ([self.centerTabView indexOfTabViewItem:[self.centerTabView selectedTabViewItem]] == 1) {
        [self refreshSourceText];
    }
    if (!self.updating) {
        [self fillInspector];
    }
}

/// The processor was replaced (source apply / preview reset).
- (void)processorReplaced
{
    self.selected = nil;
    [self buildFormView];
    [self reloadOutlineKeepingSelection:nil];
    [self showInspectorForSelection];
}

#pragma mark - The panes' state, exposed (the selftest reads these)

- (NSArray *)handlerElements
{
    return self.eventsPane.handlerElements;
}

- (NSTableView *)eventsTable
{
    return self.eventsPane.table;
}

- (NSArray *)actionRows
{
    return self.actionRowsPane.rows;
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
