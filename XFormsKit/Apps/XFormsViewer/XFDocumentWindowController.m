#import "XFDocumentWindowController.h"
#import "XFFormDocument.h"
#import <XFormsKit/XFFormView.h>
#import <XFormsKit/XFNodeState.h>
#import <XFormsKit/XFXML.h>
#import <XFormsKit/XFNamespaces.h>

@interface XFTreeItem : NSObject
@property (nonatomic, strong) NSXMLNode *node;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL instanceSide;
@property (nonatomic, strong) NSMutableArray<XFTreeItem *> *children;
@end

@implementation XFTreeItem
@end

@interface XFPaletteItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *group;
@property (nonatomic, copy) NSString *localName;
@property (nonatomic, copy) NSString *idPrefix;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *attributes;
@property (nonatomic, copy) NSString *labelText;
@property (nonatomic, copy) NSString *zone; // model | body | selected
@end

@implementation XFPaletteItem
@end

@interface XFDocumentWindowController () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSSplitView *split;
@property (nonatomic, strong) NSSplitView *leftSplit;
@property (nonatomic, strong) NSTableView *palette;
@property (nonatomic, strong) NSOutlineView *outline;
@property (nonatomic, strong) NSTabView *centerTabs;
@property (nonatomic, strong) NSScrollView *formScroll;
@property (nonatomic, strong) XFFormView *formView;
@property (nonatomic, strong) NSTextView *hostSourceView;
@property (nonatomic, strong) NSTextView *instanceSourceView;
@property (nonatomic, strong) NSView *inspectorPane;
@property (nonatomic, strong) NSScrollView *inspectorScroll;
@property (nonatomic, strong) NSMutableArray<XFTreeItem *> *roots;
@property (nonatomic, strong) XFTreeItem *selectedItem;
@property (nonatomic, strong) NSArray<XFPaletteItem *> *paletteItems;
@property (nonatomic, copy) NSString *restoreIdentifier;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *inspectorBindings;
@property (nonatomic, assign) BOOL windowBuilt;
@end

@implementation XFDocumentWindowController

- (XFFormDocument *)formDocument
{
    return (XFFormDocument *)self.document;
}

#pragma mark - Palette catalog

- (NSArray<XFPaletteItem *> *)buildPalette
{
    NSMutableArray *items = [NSMutableArray array];
    void (^add)(NSString *, NSString *, NSString *, NSString *, NSDictionary *, NSString *) =
    ^(NSString *title, NSString *group, NSString *local, NSString *zone, NSDictionary *attrs, NSString *label) {
        XFPaletteItem *it = [[XFPaletteItem alloc] init];
        it.title = title;
        it.group = group;
        it.localName = local;
        it.zone = zone;
        it.attributes = attrs;
        it.labelText = label;
        it.idPrefix = local;
        [items addObject:it];
    };
    add(@"xf:instance", @"Model", @"instance", @"model", @{}, nil);
    add(@"xf:bind", @"Model", @"bind", @"model", @{ @"nodeset": @"n" }, nil);
    add(@"xf:submission", @"Model", @"submission", @"model",
        @{ @"id": @"save", @"method": @"post", @"resource": @"", @"replace": @"none" }, nil);
    add(@"xf:input", @"Controls", @"input", @"body", @{ @"ref": @"n" }, @"Input");
    add(@"xf:output", @"Controls", @"output", @"body", @{ @"ref": @"n" }, @"Output");
    add(@"xf:secret", @"Controls", @"secret", @"body", @{ @"ref": @"n" }, @"Secret");
    add(@"xf:textarea", @"Controls", @"textarea", @"body", @{ @"ref": @"n" }, @"Text");
    add(@"xf:upload", @"Controls", @"upload", @"body", @{ @"ref": @"n" }, @"Upload");
    add(@"xf:trigger", @"Controls", @"trigger", @"body", @{}, @"Trigger");
    add(@"xf:submit", @"Controls", @"submit", @"body", @{ @"submission": @"save" }, @"Submit");
    add(@"xf:select1", @"Controls", @"select1", @"body", @{ @"ref": @"n" }, @"Select1");
    add(@"xf:select", @"Controls", @"select", @"body", @{ @"ref": @"n" }, @"Select");
    add(@"xf:range", @"Controls", @"range", @"body",
        @{ @"ref": @"n", @"start": @"0", @"end": @"10", @"step": @"1" }, @"Range");
    add(@"xf:group", @"Controls", @"group", @"body", @{}, @"Group");
    add(@"xf:repeat", @"Controls", @"repeat", @"body", @{ @"nodeset": @"n" }, @"Repeat");
    add(@"xf:switch", @"Controls", @"switch", @"body", @{}, @"Switch");
    add(@"xf:case", @"Controls", @"case", @"selected", @{ @"id": @"case1" }, @"Case");
    add(@"xf:label", @"Support", @"label", @"selected", @{}, @"Label");
    add(@"xf:hint", @"Support", @"hint", @"selected", @{}, @"Hint");
    add(@"xf:help", @"Support", @"help", @"selected", @{}, @"Help");
    add(@"xf:alert", @"Support", @"alert", @"selected", @{}, @"Alert");
    add(@"xf:item", @"Support", @"item", @"selected", @{}, @"Item");
    add(@"xf:itemset", @"Support", @"itemset", @"selected", @{ @"nodeset": @"opt" }, nil);
    add(@"xf:value", @"Support", @"value", @"selected", @{}, nil);
    add(@"xf:action", @"Actions", @"action", @"selected", @{}, nil);
    add(@"xf:setvalue", @"Actions", @"setvalue", @"selected", @{ @"ref": @"n", @"value": @"''" }, nil);
    add(@"xf:insert", @"Actions", @"insert", @"selected", @{ @"nodeset": @"n" }, nil);
    add(@"xf:delete", @"Actions", @"delete", @"selected", @{ @"nodeset": @"n" }, nil);
    add(@"xf:send", @"Actions", @"send", @"selected", @{ @"submission": @"save" }, nil);
    add(@"xf:load", @"Actions", @"load", @"selected", @{ @"resource": @"" }, nil);
    add(@"xf:message", @"Actions", @"message", @"selected", @{ @"level": @"ephemeral" }, @"Message");
    add(@"xf:toggle", @"Actions", @"toggle", @"selected", @{ @"case": @"case1" }, nil);
    add(@"xf:setfocus", @"Actions", @"setfocus", @"selected", @{ @"control": @"" }, nil);
    add(@"xf:setindex", @"Actions", @"setindex", @"selected", @{ @"repeat": @"", @"index": @"1" }, nil);
    add(@"xf:rebuild", @"Actions", @"rebuild", @"selected", @{}, nil);
    add(@"xf:recalculate", @"Actions", @"recalculate", @"selected", @{}, nil);
    add(@"xf:revalidate", @"Actions", @"revalidate", @"selected", @{}, nil);
    add(@"xf:refresh", @"Actions", @"refresh", @"selected", @{}, nil);
    add(@"xf:reset", @"Actions", @"reset", @"selected", @{}, nil);
    return items;
}

#pragma mark - Views

- (NSTextView *)makeTextViewEditable:(BOOL)editable
{
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
    [tv setEditable:editable];
    [tv setRichText:NO];
    [tv setFont:[NSFont userFixedPitchFontOfSize:11.0]];
    [tv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    return tv;
}

- (NSScrollView *)wrapView:(NSView *)view
{
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [scroll setHasVerticalScroller:YES];
    [scroll setHasHorizontalScroller:YES];
    [scroll setAutohidesScrollers:YES];
    [scroll setBorderType:NSBezelBorder];
    if (view) {
        [scroll setDocumentView:view];
    }
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    return scroll;
}

- (NSButton *)smallButton:(NSString *)title action:(SEL)action
{
    NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 70, 22)];
    [b setTitle:title];
    [b setBezelStyle:NSRoundedBezelStyle];
    [b setTarget:self];
    [b setAction:action];
    [b setFont:[NSFont systemFontOfSize:11.0]];
    return b;
}

- (instancetype)init
{
    // Do not build the window here: -[NSDocument addWindowController:] sets
    // the document afterwards, and a window built now would be populated
    // from a nil document (an empty form). The first -window call runs
    // -loadWindow / -windowDidLoad once the document is attached.
    return [super initWithWindow:nil];
}

- (void)showWindow:(id)sender
{
    [super showWindow:sender];
    [[[self window] contentView] setNeedsDisplay:YES];
    [[self window] makeKeyAndOrderFront:sender];
}

- (void)loadWindow
{
    // Never call -window from here: it would re-enter -loadWindow.
    if (self.windowBuilt) {
        return;
    }
    self.windowBuilt = YES;
    self.paletteItems = [self buildPalette];
    self.inspectorBindings = [NSMutableArray array];

    NSRect content = NSMakeRect(0, 0, 1180, 680);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSOffsetRect(content, 60, 60)
                                                   styleMask:(NSTitledWindowMask
                                                              | NSClosableWindowMask
                                                              | NSMiniaturizableWindowMask
                                                              | NSResizableWindowMask)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"XForms"];
    [window setMinSize:NSMakeSize(720, 400)];

    // Use the nominal content size rather than -[contentView bounds]: on
    // GNUstep the content view is not sized until the window is displayed.
    NSSplitView *split = [[NSSplitView alloc] initWithFrame:content];
    [split setVertical:YES];
    [split setDividerStyle:NSSplitViewDividerStyleThin];
    [split setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    self.split = split;

    NSSplitView *left = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 240, 680)];
    [left setVertical:NO];
    [left setDividerStyle:NSSplitViewDividerStyleThin];
    [left setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    self.leftSplit = left;

    NSView *paletteBox = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 220)];
    NSTextField *palLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(6, 196, 80, 16)];
    [palLabel setBezeled:NO];
    [palLabel setEditable:NO];
    [palLabel setDrawsBackground:NO];
    [palLabel setStringValue:@"Palette"];
    [palLabel setFont:[NSFont boldSystemFontOfSize:11.0]];
    NSButton *addBtn = [self smallButton:@"Add" action:@selector(addPaletteItem:)];
    [addBtn setFrame:NSMakeRect(96, 192, 60, 22)];
    NSButton *delBtn = [self smallButton:@"Delete" action:@selector(deleteSelected:)];
    [delBtn setFrame:NSMakeRect(160, 192, 70, 22)];
    NSTableView *palette = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 220, 170)];
    NSTableColumn *pcol = [[NSTableColumn alloc] initWithIdentifier:@"item"];
    [pcol setTitle:@"Item"];
    [pcol setWidth:200];
    [palette addTableColumn:pcol];
    [palette setHeaderView:nil];
    [palette setDataSource:self];
    [palette setDelegate:self];
    [palette setTarget:self];
    [palette setDoubleAction:@selector(addPaletteItem:)];
    [palette setAllowsMultipleSelection:NO];
    self.palette = palette;
    NSScrollView *palScroll = [self wrapView:palette];
    [palScroll setFrame:NSMakeRect(0, 0, 240, 188)];
    [palScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [paletteBox addSubview:palLabel];
    [paletteBox addSubview:addBtn];
    [paletteBox addSubview:delBtn];
    [paletteBox addSubview:palScroll];
    [palLabel setAutoresizingMask:NSViewMaxYMargin];
    [addBtn setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
    [delBtn setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];

    NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 220, 400)];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    [col setTitle:@"Document"];
    [col setWidth:200];
    [outline addTableColumn:col];
    [outline setOutlineTableColumn:col];
    [outline setHeaderView:nil];
    [outline setDataSource:self];
    [outline setDelegate:self];
    [outline setAllowsMultipleSelection:NO];
    self.outline = outline;
    NSScrollView *navScroll = [self wrapView:outline];

    [left addSubview:paletteBox];
    [left addSubview:navScroll];

    NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSZeroRect];
    [tabs setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    self.centerTabs = tabs;

    self.formScroll = [self wrapView:nil];
    NSTabViewItem *formItem = [[NSTabViewItem alloc] initWithIdentifier:@"form"];
    [formItem setLabel:@"Form"];
    [formItem setView:self.formScroll];
    [tabs addTabViewItem:formItem];

    self.hostSourceView = [self makeTextViewEditable:YES];
    NSView *sourceWrap = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
    [sourceWrap setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    NSButton *applySrc = [self smallButton:@"Apply Source" action:@selector(applySource:)];
    [applySrc setFrame:NSMakeRect(8, 8, 110, 24)];
    NSScrollView *srcScroll = [self wrapView:self.hostSourceView];
    [srcScroll setFrame:NSMakeRect(0, 36, 400, 364)];
    [srcScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [sourceWrap addSubview:applySrc];
    [sourceWrap addSubview:srcScroll];
    NSTabViewItem *hostItem = [[NSTabViewItem alloc] initWithIdentifier:@"host"];
    [hostItem setLabel:@"Source"];
    [hostItem setView:sourceWrap];
    [tabs addTabViewItem:hostItem];

    self.instanceSourceView = [self makeTextViewEditable:NO];
    NSTabViewItem *instItem = [[NSTabViewItem alloc] initWithIdentifier:@"instance"];
    [instItem setLabel:@"Instance"];
    [instItem setView:[self wrapView:self.instanceSourceView]];
    [tabs addTabViewItem:instItem];

    self.inspectorPane = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 260, 800)];
    self.inspectorScroll = [self wrapView:self.inspectorPane];

    // Give every pane a real starting frame: Cocoa's NSSplitView does not lay
    // out zero-sized subviews until the window is resized, which left the
    // window blank until the user dragged it.
    NSRect bounds = content;
    CGFloat divider = [split dividerThickness];
    CGFloat leftWidth = 250;
    CGFloat inspectorWidth = 280;
    CGFloat centerWidth = NSWidth(bounds) - leftWidth - inspectorWidth - 2 * divider;
    [left setFrame:NSMakeRect(0, 0, leftWidth, NSHeight(bounds))];
    [tabs setFrame:NSMakeRect(leftWidth + divider, 0, centerWidth, NSHeight(bounds))];
    [self.inspectorScroll setFrame:NSMakeRect(leftWidth + divider + centerWidth + divider, 0,
                                              inspectorWidth, NSHeight(bounds))];
    [paletteBox setFrame:NSMakeRect(0, 0, leftWidth, 220)];
    [navScroll setFrame:NSMakeRect(0, 220 + [left dividerThickness], leftWidth,
                                   NSHeight(bounds) - 220 - [left dividerThickness])];

    [split addSubview:left];
    [split addSubview:tabs];
    [split addSubview:self.inspectorScroll];

    [[window contentView] addSubview:split];
    [self setWindow:window];

    [split adjustSubviews];
    [left adjustSubviews];
    [split setPosition:leftWidth ofDividerAtIndex:0];
    [split setPosition:leftWidth + divider + centerWidth ofDividerAtIndex:1];
    [left setPosition:220 ofDividerAtIndex:0];
    if ([split respondsToSelector:@selector(layoutSubtreeIfNeeded)]) {
        [split layoutSubtreeIfNeeded];
    }
    [self reloadAll];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    [self reloadAll];
}

- (void)setDocument:(id)document
{
    [super setDocument:document];
    if ([self isWindowLoaded]) {
        [self reloadAll];
    }
}

#pragma mark - Tree

- (XFTreeItem *)itemForNode:(NSXMLNode *)node instanceSide:(BOOL)instanceSide
{
    XFTreeItem *item = [[XFTreeItem alloc] init];
    item.node = node;
    item.instanceSide = instanceSide;
    item.children = [NSMutableArray array];
    if ([node kind] == NSXMLElementKind) {
        NSXMLElement *el = (NSXMLElement *)node;
        NSString *prefix = [el prefix];
        NSString *local = [el localName] ?: [el name];
        NSString *ident = [[el attributeForName:@"id"] stringValue];
        NSMutableString *title = [NSMutableString string];
        if (prefix.length) {
            [title appendFormat:@"%@:%@", prefix, local];
        } else {
            [title appendString:local ?: @"#element"];
        }
        if (ident.length) {
            [title appendFormat:@" #%@", ident];
        }
        item.title = title;
    } else if ([node kind] == NSXMLTextKind) {
        NSString *text = [[node stringValue] stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (text.length == 0) {
            return nil;
        }
        if (text.length > 32) {
            text = [[text substringToIndex:32] stringByAppendingString:@"…"];
        }
        item.title = [NSString stringWithFormat:@"\"%@\"", text];
    } else {
        item.title = [node name] ?: @"node";
    }
    for (NSXMLNode *child in [node children]) {
        XFTreeItem *kid = [self itemForNode:child instanceSide:instanceSide];
        if (kid) {
            [item.children addObject:kid];
        }
    }
    return item;
}

- (void)rebuildTree
{
    self.roots = [NSMutableArray array];
    XFFormDocument *doc = [self formDocument];
    NSXMLElement *host = doc.processor.hostDocument.rootElement;
    if (host) {
        XFTreeItem *hostRoot = [self itemForNode:host instanceSide:NO];
        hostRoot.title = [NSString stringWithFormat:@"host · %@", hostRoot.title];
        [self.roots addObject:hostRoot];
    }
    NSXMLElement *inst = [[doc.processor defaultInstance] documentElement];
    if (inst) {
        XFTreeItem *instRoot = [self itemForNode:inst instanceSide:YES];
        instRoot.title = [NSString stringWithFormat:@"instance · %@", instRoot.title];
        [self.roots addObject:instRoot];
    }
    [self.outline reloadData];
    for (XFTreeItem *root in self.roots) {
        [self.outline expandItem:root expandChildren:NO];
    }
    self.selectedItem = nil;
    if (self.restoreIdentifier.length) {
        [self selectElementWithID:self.restoreIdentifier];
    } else {
        [self rebuildInspector];
    }
}

- (void)collectExpandedNodes:(XFTreeItem *)item into:(NSMutableArray<NSXMLNode *> *)nodes
{
    if ([self.outline isItemExpanded:item] && item.node) {
        [nodes addObject:item.node];
    }
    for (XFTreeItem *kid in item.children) {
        [self collectExpandedNodes:kid into:nodes];
    }
}

- (void)expandItemsForNodes:(NSArray<NSXMLNode *> *)nodes in:(XFTreeItem *)item
{
    if ([nodes indexOfObjectIdenticalTo:item.node] != NSNotFound) {
        [self.outline expandItem:item];
    }
    for (XFTreeItem *kid in item.children) {
        [self expandItemsForNodes:nodes in:kid];
    }
}

/// Live update of the instance side of the navigator (and the Instance
/// source tab) after the form changed instance data. The host tree is not
/// touched, so selection/expansion there survives; on the instance side,
/// expansion and selection are restored by node identity (setvalue edits
/// text in place, so element nodes are stable).
- (void)refreshInstanceTree
{
    XFFormDocument *doc = [self formDocument];
    NSXMLElement *inst = [[doc.processor defaultInstance] documentElement];
    XFTreeItem *oldRoot = nil;
    for (XFTreeItem *root in self.roots) {
        if (root.instanceSide) {
            oldRoot = root;
            break;
        }
    }
    if (inst == nil || oldRoot == nil) {
        [self rebuildTree];
        [self reloadSources];
        return;
    }
    NSMutableArray<NSXMLNode *> *expanded = [NSMutableArray array];
    [self collectExpandedNodes:oldRoot into:expanded];
    NSXMLNode *selectedNode = self.selectedItem.instanceSide ? self.selectedItem.node : nil;

    XFTreeItem *newRoot = [self itemForNode:inst instanceSide:YES];
    newRoot.title = [NSString stringWithFormat:@"instance · %@", newRoot.title];
    [self.roots replaceObjectAtIndex:[self.roots indexOfObjectIdenticalTo:oldRoot] withObject:newRoot];
    [self.outline reloadData];
    [self.outline expandItem:newRoot];
    [self expandItemsForNodes:expanded in:newRoot];
    if (selectedNode) {
        XFTreeItem *hit = [self findItem:newRoot withNode:selectedNode];
        if (hit) {
            NSInteger row = [self.outline rowForItem:hit];
            if (row >= 0) {
                [self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                          byExtendingSelection:NO];
            }
            self.selectedItem = hit;
            [self rebuildInspector];
        }
    }
    [self.instanceSourceView setString:[doc instanceXMLString] ?: @""];
}

- (XFTreeItem *)findItem:(XFTreeItem *)item withID:(NSString *)ident
{
    if ([item.node kind] == NSXMLElementKind) {
        NSString *have = [[(NSXMLElement *)item.node attributeForName:@"id"] stringValue];
        if ([have isEqualToString:ident]) {
            return item;
        }
    }
    for (XFTreeItem *kid in item.children) {
        XFTreeItem *hit = [self findItem:kid withID:ident];
        if (hit) {
            return hit;
        }
    }
    return nil;
}

- (void)selectElementWithID:(NSString *)ident
{
    XFTreeItem *hit = nil;
    for (XFTreeItem *root in self.roots) {
        hit = [self findItem:root withID:ident];
        if (hit) break;
    }
    if (hit == nil) {
        return;
    }
    NSMutableArray *path = [NSMutableArray array];
    XFTreeItem *walk = hit;
    while (walk) {
        [path insertObject:walk atIndex:0];
        XFTreeItem *parent = nil;
        for (XFTreeItem *root in self.roots) {
            parent = [self parentOf:walk in:root];
            if (parent) break;
        }
        if (parent == nil && [self.roots containsObject:walk] == NO) {
            break;
        }
        walk = parent;
        if (parent == nil) break;
    }
    for (XFTreeItem *step in path) {
        [self.outline expandItem:step];
    }
    NSInteger row = [self.outline rowForItem:hit];
    if (row >= 0) {
        [self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        self.selectedItem = hit;
        [self rebuildInspector];
    }
}

- (XFTreeItem *)parentOf:(XFTreeItem *)item in:(XFTreeItem *)root
{
    for (XFTreeItem *kid in root.children) {
        if (kid == item) {
            return root;
        }
        XFTreeItem *p = [self parentOf:item in:kid];
        if (p) return p;
    }
    return nil;
}

- (void)rebuildForm
{
    XFFormDocument *doc = [self formDocument];
    if (self.formView) {
        [self.formView removeFromSuperview];
        self.formView = nil;
    }
    if (doc.processor) {
        XFFormView *form = [[XFFormView alloc] initWithProcessor:doc.processor];
        __weak XFDocumentWindowController *weakSelf = self;
        form.documentReplaceHandler = ^(NSString *xml) {
            XFDocumentWindowController *strong = weakSelf;
            if (strong == nil) return;
            NSError *err = nil;
            if ([[strong formDocument] replaceHostWithXMLString:xml error:&err]) {
                [strong reloadAll];
            }
        };
        form.instanceChangedHandler = ^{
            [weakSelf refreshInstanceTree];
        };
        self.formView = form;
        [self.formScroll setDocumentView:form];
    } else if (doc.loadError) {
        NSTextView *err = [self makeTextViewEditable:NO];
        [err setString:[doc.loadError localizedDescription] ?: @"Failed to load form"];
        [self.formScroll setDocumentView:err];
    }
}

- (void)reloadSources
{
    XFFormDocument *doc = [self formDocument];
    [self.hostSourceView setString:[doc hostXMLString] ?: @""];
    [self.instanceSourceView setString:[doc instanceXMLString] ?: @""];
    NSString *title = doc.fileURL.lastPathComponent ?: @"Untitled";
    if ([doc isDocumentEdited]) {
        title = [title stringByAppendingString:@" — edited"];
    }
    [[self window] setTitle:title];
}

- (void)reloadAll
{
    [self rebuildForm];
    [self rebuildTree];
    [self reloadSources];
    if (self.selectedItem == nil) {
        [self rebuildInspector];
    }
}

#pragma mark - Inspector

- (NSArray<NSDictionary *> *)fieldsForElement:(NSXMLElement *)el
{
    NSString *local = [el localName] ?: @"";
    NSMutableArray *fields = [NSMutableArray array];
    void (^attr)(NSString *, NSString *) = ^(NSString *key, NSString *label) {
        [fields addObject:@{ @"kind": @"attr", @"key": key, @"label": label }];
    };
    attr(@"id", @"id");
    if ([local isEqualToString:@"bind"]) {
        attr(@"nodeset", @"nodeset");
        attr(@"ref", @"ref");
        attr(@"type", @"type");
        attr(@"calculate", @"calculate");
        attr(@"relevant", @"relevant");
        attr(@"required", @"required");
        attr(@"readonly", @"readonly");
        attr(@"constraint", @"constraint");
    } else if ([local isEqualToString:@"submission"]) {
        attr(@"resource", @"resource");
        attr(@"method", @"method");
        attr(@"replace", @"replace");
        attr(@"instance", @"instance");
        attr(@"serialization", @"serialization");
        attr(@"mediatype", @"mediatype");
        attr(@"mode", @"mode");
        attr(@"ref", @"ref");
        attr(@"targetref", @"targetref");
    } else if ([local isEqualToString:@"repeat"] || [local isEqualToString:@"itemset"]) {
        attr(@"nodeset", @"nodeset");
        attr(@"ref", @"ref");
        attr(@"startindex", @"startindex");
        attr(@"appearance", @"appearance");
    } else if ([local isEqualToString:@"output"]) {
        attr(@"ref", @"ref");
        attr(@"value", @"value");
        attr(@"mediatype", @"mediatype");
        attr(@"appearance", @"appearance");
    } else if ([local isEqualToString:@"submit"]) {
        attr(@"submission", @"submission");
        attr(@"appearance", @"appearance");
    } else if ([local isEqualToString:@"setvalue"] || [local isEqualToString:@"insert"]
               || [local isEqualToString:@"delete"] || [local isEqualToString:@"load"]
               || [local isEqualToString:@"send"] || [local isEqualToString:@"toggle"]
               || [local isEqualToString:@"setfocus"] || [local isEqualToString:@"setindex"]
               || [local isEqualToString:@"dispatch"]) {
        attr(@"ref", @"ref");
        attr(@"nodeset", @"nodeset");
        attr(@"value", @"value");
        attr(@"resource", @"resource");
        attr(@"submission", @"submission");
        attr(@"case", @"case");
        attr(@"control", @"control");
        attr(@"repeat", @"repeat");
        attr(@"index", @"index");
        attr(@"ev:event", @"ev:event");
    } else if ([el URI] && [[el URI] isEqualToString:XFXFormsNamespaceURI]) {
        attr(@"ref", @"ref");
        attr(@"value", @"value");
        attr(@"appearance", @"appearance");
        attr(@"incremental", @"incremental");
    }
    [fields addObject:@{ @"kind": @"child", @"key": @"label", @"label": @"label" }];
    [fields addObject:@{ @"kind": @"child", @"key": @"hint", @"label": @"hint" }];
    [fields addObject:@{ @"kind": @"child", @"key": @"help", @"label": @"help" }];
    [fields addObject:@{ @"kind": @"child", @"key": @"alert", @"label": @"alert" }];
    return fields;
}

- (NSString *)childText:(NSString *)local of:(NSXMLElement *)el
{
    NSXMLElement *child = [XFXML firstElementWithLocalName:local
                                             namespaceURI:XFXFormsNamespaceURI
                                                   inNode:el];
    return child ? [XFXML stringValueOfNode:child] : @"";
}

- (void)setChildText:(NSString *)local of:(NSXMLElement *)el to:(NSString *)text
{
    NSXMLElement *child = [XFXML firstElementWithLocalName:local
                                             namespaceURI:XFXFormsNamespaceURI
                                                   inNode:el];
    if (text.length == 0) {
        if (child) {
            [(NSXMLElement *)[child parent] removeChildAtIndex:[child index]];
        }
        return;
    }
    if (child == nil) {
        child = [[NSXMLElement alloc] initWithName:[@"xf:" stringByAppendingString:local]];
        [el insertChild:child atIndex:0];
    }
    [XFXML setStringValue:text ofNode:child];
}

- (void)setAttribute:(NSString *)name on:(NSXMLElement *)el to:(NSString *)value
{
    if (name.length == 0) {
        return;
    }
    NSRange colon = [name rangeOfString:@":"];
    if (value.length == 0) {
        if (colon.location == NSNotFound) {
            [el removeAttributeForName:name];
        } else {
            NSXMLNode *attr = [el attributeForName:name];
            if (attr) {
                [el removeAttributeForName:[attr name]];
            }
        }
        return;
    }
    NSXMLNode *existing = [el attributeForName:name];
    if (existing) {
        [existing setStringValue:value];
        return;
    }
    [el addAttribute:[NSXMLNode attributeWithName:name stringValue:value]];
}

- (void)rebuildInspector
{
    for (NSView *sub in [[self.inspectorPane subviews] copy]) {
        [sub removeFromSuperview];
    }
    [self.inspectorBindings removeAllObjects];

    XFTreeItem *item = self.selectedItem;
    CGFloat y = 8;
    CGFloat width = 248;

    void (^caption)(NSString *) = ^(NSString *text) {
        NSTextField *lab = [[NSTextField alloc] initWithFrame:NSMakeRect(8, 0, width - 16, 18)];
        [lab setBezeled:NO];
        [lab setEditable:NO];
        [lab setDrawsBackground:NO];
        [lab setFont:[NSFont boldSystemFontOfSize:11.0]];
        [lab setStringValue:text];
        [self.inspectorPane addSubview:lab];
    };

    if (item == nil || item.node == nil) {
        caption(@"Inspector");
        NSTextField *hint = [[NSTextField alloc] initWithFrame:NSMakeRect(8, 28, width - 16, 60)];
        [hint setBezeled:NO];
        [hint setEditable:NO];
        [hint setDrawsBackground:NO];
        [hint setStringValue:@"Select a host element in the navigator, then Add from the palette or edit properties here."];
        [self.inspectorPane addSubview:hint];
        [self.inspectorPane setFrame:NSMakeRect(0, 0, width, 120)];
        return;
    }

    NSButton *apply = [self smallButton:@"Apply" action:@selector(applyInspector:)];
    [apply setFrame:NSMakeRect(8, y, 70, 22)];
    NSButton *dup = [self smallButton:@"Duplicate" action:@selector(duplicateSelected:)];
    [dup setFrame:NSMakeRect(84, y, 80, 22)];
    [self.inspectorPane addSubview:apply];
    [self.inspectorPane addSubview:dup];
    y += 28;

    NSTextField *head = [[NSTextField alloc] initWithFrame:NSMakeRect(8, y, width - 16, 18)];
    [head setBezeled:NO];
    [head setEditable:NO];
    [head setDrawsBackground:NO];
    [head setFont:[NSFont boldSystemFontOfSize:12.0]];
    [head setStringValue:item.title ?: @"element"];
    [self.inspectorPane addSubview:head];
    y += 24;

    if ([item.node kind] != NSXMLElementKind) {
        NSTextField *lab = [[NSTextField alloc] initWithFrame:NSMakeRect(8, y, 70, 18)];
        [lab setBezeled:NO]; [lab setEditable:NO]; [lab setDrawsBackground:NO];
        [lab setStringValue:@"text"];
        NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(80, y, width - 90, 22)];
        [field setStringValue:[item.node stringValue] ?: @""];
        [field setTarget:self];
        [field setAction:@selector(applyInspector:)];
        [self.inspectorPane addSubview:lab];
        [self.inspectorPane addSubview:field];
        [self.inspectorBindings addObject:@{ @"kind": @"text", @"field": field }];
        y += 28;
    } else {
        NSXMLElement *el = (NSXMLElement *)item.node;
        NSArray *fields = [self fieldsForElement:el];
        for (NSDictionary *spec in fields) {
            NSTextField *lab = [[NSTextField alloc] initWithFrame:NSMakeRect(8, y, 78, 18)];
            [lab setBezeled:NO]; [lab setEditable:NO]; [lab setDrawsBackground:NO];
            [lab setFont:[NSFont systemFontOfSize:11.0]];
            [lab setStringValue:spec[@"label"]];
            NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(88, y, width - 98, 22)];
            NSString *kind = spec[@"kind"];
            NSString *value = @"";
            if ([kind isEqualToString:@"attr"]) {
                value = [[el attributeForName:spec[@"key"]] stringValue] ?: @"";
            } else if ([kind isEqualToString:@"child"]) {
                value = [self childText:spec[@"key"] of:el];
            }
            [field setStringValue:value];
            [field setTarget:self];
            [field setAction:@selector(applyInspector:)];
            [self.inspectorPane addSubview:lab];
            [self.inspectorPane addSubview:field];
            NSMutableDictionary *bind = [spec mutableCopy];
            bind[@"field"] = field;
            [self.inspectorBindings addObject:bind];
            y += 26;
        }
        XFFormDocument *doc = [self formDocument];
        XFControl *control = [doc.processor controlForElement:el];
        if (control) {
            NSTextField *info = [[NSTextField alloc] initWithFrame:NSMakeRect(8, y + 6, width - 16, 90)];
            [info setBezeled:NO]; [info setEditable:NO]; [info setDrawsBackground:NO];
            [info setFont:[NSFont userFixedPitchFontOfSize:10.0]];
            [info setStringValue:[NSString stringWithFormat:
                                  @"runtime\n  class  %@\n  value  %@\n  relevant %@  required %@\n  readonly %@  valid %@",
                                  NSStringFromClass([control class]),
                                  control.stringValue ?: @"",
                                  control.relevant ? @"yes" : @"no",
                                  control.required ? @"yes" : @"no",
                                  control.readonly ? @"yes" : @"no",
                                  control.valid ? @"yes" : @"no"]];
            [self.inspectorPane addSubview:info];
            y += 100;
        }
        if (item.instanceSide) {
            NSTextField *note = [[NSTextField alloc] initWithFrame:NSMakeRect(8, y, width - 16, 40)];
            [note setBezeled:NO]; [note setEditable:NO]; [note setDrawsBackground:NO];
            [note setStringValue:@"Instance nodes are live data. Edit values here; structure changes belong on the host tree."];
            [self.inspectorPane addSubview:note];
            y += 44;
        }
    }
    [self.inspectorPane setFrame:NSMakeRect(0, 0, width, MAX(y + 16, 400))];
}

- (void)applyInspector:(id)sender
{
    XFTreeItem *item = self.selectedItem;
    if (item == nil) {
        return;
    }
    if ([item.node kind] != NSXMLElementKind) {
        NSTextField *field = self.inspectorBindings.firstObject[@"field"];
        [item.node setStringValue:[field stringValue] ?: @""];
        if ([item.node parent].kind == NSXMLElementKind) {
            [[[self formDocument] processor] noteElementChanged:(NSXMLElement *)[item.node parent]];
        }
        [self refreshLiveKeepingNode:item.node];
        return;
    }
    NSXMLElement *el = (NSXMLElement *)item.node;
    if (item.instanceSide) {
        for (NSDictionary *bind in self.inspectorBindings) {
            if ([bind[@"kind"] isEqualToString:@"attr"] && [bind[@"key"] isEqualToString:@"id"]) {
                [self setAttribute:@"id" on:el to:[bind[@"field"] stringValue]];
            }
        }
        NSError *err = nil;
        XFInstance *inst = [[self formDocument].processor defaultInstance];
        NSString *xml = [[inst document] XMLString];
        if (![inst replaceWithXMLString:xml error:&err]) {
            NSBeep();
        }
        [[[self formDocument] processor] refresh:NULL];
        [self.formView reloadFromProcessor];
        [self reloadSources];
        return;
    }
    NSString *keepID = [[el attributeForName:@"id"] stringValue];
    for (NSDictionary *bind in self.inspectorBindings) {
        NSString *kind = bind[@"kind"];
        NSString *key = bind[@"key"];
        NSString *value = [bind[@"field"] stringValue];
        if ([kind isEqualToString:@"attr"]) {
            [self setAttribute:key on:el to:value];
            if ([key isEqualToString:@"id"] && value.length) {
                keepID = value;
            }
        } else if ([kind isEqualToString:@"child"]) {
            [self setChildText:key of:el to:value];
        }
    }
    self.restoreIdentifier = keepID;
    [[[self formDocument] processor] noteElementChanged:el];
    [self refreshLiveKeepingNode:el];
}

#pragma mark - Insert / delete

- (NSXMLElement *)makeElement:(XFPaletteItem *)spec
{
    NSXMLElement *el = [[NSXMLElement alloc] initWithName:[@"xf:" stringByAppendingString:spec.localName]];
    [spec.attributes enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        (void)stop;
        if ([k isEqualToString:@"id"]) {
            return;
        }
        if (v.length) {
            [el addAttribute:[NSXMLNode attributeWithName:k stringValue:v]];
        }
    }];
    NSString *ident = [[self formDocument] uniqueIdentifierWithPrefix:spec.idPrefix];
    [el addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:ident]];
    if (spec.labelText.length) {
        NSXMLElement *label = [[NSXMLElement alloc] initWithName:@"xf:label"];
        [label setStringValue:spec.labelText];
        [el addChild:label];
    }
    if ([spec.localName isEqualToString:@"select1"] || [spec.localName isEqualToString:@"select"]) {
        NSXMLElement *item = [[NSXMLElement alloc] initWithName:@"xf:item"];
        NSXMLElement *l = [[NSXMLElement alloc] initWithName:@"xf:label"];
        [l setStringValue:@"One"];
        NSXMLElement *v = [[NSXMLElement alloc] initWithName:@"xf:value"];
        [v setStringValue:@"one"];
        [item addChild:l];
        [item addChild:v];
        [el addChild:item];
    }
    if ([spec.localName isEqualToString:@"switch"]) {
        NSXMLElement *c = [[NSXMLElement alloc] initWithName:@"xf:case"];
        [c addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:
                         [[self formDocument] uniqueIdentifierWithPrefix:@"case"]]];
        NSXMLElement *l = [[NSXMLElement alloc] initWithName:@"xf:label"];
        [l setStringValue:@"Case"];
        [c addChild:l];
        [el addChild:c];
    }
    if ([spec.localName isEqualToString:@"instance"]) {
        NSXMLElement *data = [[NSXMLElement alloc] initWithName:@"data"];
        [data addChild:[[NSXMLElement alloc] initWithName:@"n"]];
        [el addChild:data];
    }
    return el;
}

- (NSXMLElement *)parentForPalette:(XFPaletteItem *)spec
{
    XFFormDocument *doc = [self formDocument];
    NSXMLElement *selected = nil;
    if (self.selectedItem && !self.selectedItem.instanceSide
        && [self.selectedItem.node kind] == NSXMLElementKind) {
        selected = (NSXMLElement *)self.selectedItem.node;
    }
    if ([spec.zone isEqualToString:@"model"]) {
        return [doc modelElement] ?: selected;
    }
    if ([spec.zone isEqualToString:@"body"]) {
        if (selected) {
            NSString *local = [selected localName];
            if ([local isEqualToString:@"group"] || [local isEqualToString:@"repeat"]
                || [local isEqualToString:@"case"] || [local isEqualToString:@"body"]) {
                return selected;
            }
        }
        return [doc bodyElement] ?: selected;
    }
    return selected ?: [doc bodyElement];
}

- (void)addPaletteItem:(id)sender
{
    NSInteger row = [self.palette selectedRow];
    if (row < 0 || row >= (NSInteger)self.paletteItems.count) {
        return;
    }
    if (self.selectedItem.instanceSide) {
        NSBeep();
        return;
    }
    XFPaletteItem *spec = self.paletteItems[(NSUInteger)row];
    NSXMLElement *parent = [self parentForPalette:spec];
    if (parent == nil) {
        NSBeep();
        return;
    }
    NSXMLElement *el = [self makeElement:spec];
    [parent addChild:el];
    self.restoreIdentifier = [[el attributeForName:@"id"] stringValue];
    [[[self formDocument] processor] attachElement:el error:NULL];
    [self refreshLiveKeepingNode:el];
}

- (void)deleteSelected:(id)sender
{
    XFTreeItem *item = self.selectedItem;
    if (item == nil || item.instanceSide || [item.node parent] == nil) {
        NSBeep();
        return;
    }
    if ([item.node kind] != NSXMLElementKind) {
        NSXMLNode *parent = [item.node parent];
        // parent is an NSXMLElement or NSXMLDocument; both implement this.
        [(NSXMLElement *)parent removeChildAtIndex:[item.node index]];
        self.restoreIdentifier = nil;
        [self refreshLiveKeepingNode:parent];
        return;
    }
    NSXMLElement *el = (NSXMLElement *)item.node;
    NSString *local = [el localName];
    if ([local isEqualToString:@"html"] || [local isEqualToString:@"head"] || [local isEqualToString:@"body"]) {
        NSBeep();
        return;
    }
    NSXMLNode *parent = [el parent];
    [[[self formDocument] processor] detachElement:el];
    [(NSXMLElement *)parent removeChildAtIndex:[el index]];
    self.selectedItem = nil;
    self.restoreIdentifier = nil;
    [self refreshLiveKeepingNode:parent];
}

- (void)duplicateSelected:(id)sender
{
    XFTreeItem *item = self.selectedItem;
    if (item == nil || item.instanceSide || [item.node kind] != NSXMLElementKind) {
        NSBeep();
        return;
    }
    NSXMLElement *el = (NSXMLElement *)item.node;
    NSXMLElement *copy = [el copy];
    NSString *ident = [[self formDocument] uniqueIdentifierWithPrefix:[el localName]];
    NSXMLNode *idAttr = [copy attributeForName:@"id"];
    if (idAttr) {
        [idAttr setStringValue:ident];
    } else {
        [copy addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:ident]];
    }
    [(NSXMLElement *)[el parent] insertChild:copy atIndex:[el index] + 1];
    self.restoreIdentifier = ident;
    [[[self formDocument] processor] attachElement:copy error:NULL];
    [self refreshLiveKeepingNode:copy];
}

- (XFTreeItem *)findItem:(XFTreeItem *)item withNode:(NSXMLNode *)node
{
    if (item.node == node) {
        return item;
    }
    for (XFTreeItem *kid in item.children) {
        XFTreeItem *hit = [self findItem:kid withNode:node];
        if (hit) return hit;
    }
    return nil;
}

- (void)selectNode:(NSXMLNode *)node
{
    XFTreeItem *hit = nil;
    for (XFTreeItem *root in self.roots) {
        hit = [self findItem:root withNode:node];
        if (hit) break;
    }
    if (hit == nil) {
        [self rebuildInspector];
        return;
    }
    NSInteger row = [self.outline rowForItem:hit];
    if (row >= 0) {
        [self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        self.selectedItem = hit;
        [self rebuildInspector];
    }
}

- (void)refreshLiveKeepingNode:(NSXMLNode *)node
{
    [[self formDocument] markHostEdited];
    [self rebuildForm];
    [self rebuildTree];
    [self reloadSources];
    if (node) {
        [self selectNode:node];
    } else {
        [self rebuildInspector];
    }
}

- (void)commitAndReload
{
    [self refreshLiveKeepingNode:self.selectedItem.node];
}

- (void)applySource:(id)sender
{
    NSError *error = nil;
    if (![[self formDocument] replaceHostWithXMLString:[self.hostSourceView string] error:&error]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Source is not well-formed XForms"];
        [alert setInformativeText:[error localizedDescription] ?: @""];
        [alert runModal];
        return;
    }
    self.restoreIdentifier = nil;
    [self reloadAll];
}

- (void)refreshForm:(id)sender
{
    XFFormDocument *doc = [self formDocument];
    [doc.processor refresh:NULL];
    [self.formView reloadFromProcessor];
    [self rebuildTree];
    [self reloadSources];
    [self rebuildInspector];
}

#pragma mark - Outline / table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)self.paletteItems.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)self.paletteItems.count) {
        return @"";
    }
    XFPaletteItem *it = self.paletteItems[(NSUInteger)row];
    return [NSString stringWithFormat:@"%@  ·  %@", it.group, it.title];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    if (item == nil) {
        return (NSInteger)self.roots.count;
    }
    return (NSInteger)[(XFTreeItem *)item children].count;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return [(XFTreeItem *)item children].count > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    NSArray *list = item ? [(XFTreeItem *)item children] : self.roots;
    if (index < 0 || index >= (NSInteger)list.count) {
        return nil;
    }
    return list[(NSUInteger)index];
}

- (id)outlineView:(NSOutlineView *)outlineView
objectValueForTableColumn:(NSTableColumn *)tableColumn
           byItem:(id)item
{
    return [(XFTreeItem *)item title];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
    NSInteger row = [self.outline selectedRow];
    if (row < 0) {
        self.selectedItem = nil;
        [self rebuildInspector];
        return;
    }
    XFTreeItem *item = [self.outline itemAtRow:row];
    self.selectedItem = item;
    [self rebuildInspector];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    SEL a = [menuItem action];
    if (a == @selector(deleteSelected:) || a == @selector(duplicateSelected:)) {
        return self.selectedItem != nil && !self.selectedItem.instanceSide;
    }
    return YES;
}

@end
