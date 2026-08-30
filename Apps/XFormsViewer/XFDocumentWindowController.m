#import "XFDocumentWindowController.h"
#import "XFFormDocument.h"
#import <XFormsKit/XFFormView.h>
#import <XFormsKit/XFNodeState.h>
#import <XFormsKit/XFXML.h>

@interface XFTreeItem : NSObject
@property (nonatomic, strong) NSXMLNode *node;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSMutableArray<XFTreeItem *> *children;
@end

@implementation XFTreeItem
@end

@interface XFDocumentWindowController () <NSOutlineViewDataSource, NSOutlineViewDelegate>
@property (nonatomic, strong) NSSplitView *split;
@property (nonatomic, strong) NSOutlineView *outline;
@property (nonatomic, strong) NSTabView *centerTabs;
@property (nonatomic, strong) NSScrollView *formScroll;
@property (nonatomic, strong) XFFormView *formView;
@property (nonatomic, strong) NSTextView *hostSourceView;
@property (nonatomic, strong) NSTextView *instanceSourceView;
@property (nonatomic, strong) NSTextView *inspector;
@property (nonatomic, strong) NSMutableArray<XFTreeItem *> *roots;
@property (nonatomic, strong) XFTreeItem *selectedItem;
@end

@implementation XFDocumentWindowController

- (XFFormDocument *)formDocument
{
    return (XFFormDocument *)self.document;
}

- (NSTextView *)makeTextView
{
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
    [tv setEditable:NO];
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
    [scroll setDocumentView:view];
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    return scroll;
}

- (void)loadWindow
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(80, 80, 1100, 640)
                                                   styleMask:(NSTitledWindowMask
                                                              | NSClosableWindowMask
                                                              | NSMiniaturizableWindowMask
                                                              | NSResizableWindowMask)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"XForms"];
    [window setMinSize:NSMakeSize(640, 360)];

    NSSplitView *split = [[NSSplitView alloc] initWithFrame:[[window contentView] bounds]];
    [split setVertical:YES];
    [split setDividerStyle:NSSplitViewDividerStyleThin];
    [split setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    self.split = split;

    NSScrollView *navScroll = [self wrapView:nil];
    NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 220, 600)];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    [col setTitle:@"Document"];
    [col setWidth:200];
    [outline addTableColumn:col];
    [outline setOutlineTableColumn:col];
    [outline setHeaderView:nil];
    [outline setDataSource:self];
    [outline setDelegate:self];
    [outline setAllowsMultipleSelection:NO];
    [navScroll setDocumentView:outline];
    self.outline = outline;

    NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSZeroRect];
    [tabs setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    self.centerTabs = tabs;

    self.formScroll = [self wrapView:nil];
    NSTabViewItem *formItem = [[NSTabViewItem alloc] initWithIdentifier:@"form"];
    [formItem setLabel:@"Form"];
    [formItem setView:self.formScroll];
    [tabs addTabViewItem:formItem];

    self.hostSourceView = [self makeTextView];
    NSTabViewItem *hostItem = [[NSTabViewItem alloc] initWithIdentifier:@"host"];
    [hostItem setLabel:@"Source"];
    [hostItem setView:[self wrapView:self.hostSourceView]];
    [tabs addTabViewItem:hostItem];

    self.instanceSourceView = [self makeTextView];
    NSTabViewItem *instItem = [[NSTabViewItem alloc] initWithIdentifier:@"instance"];
    [instItem setLabel:@"Instance"];
    [instItem setView:[self wrapView:self.instanceSourceView]];
    [tabs addTabViewItem:instItem];

    self.inspector = [self makeTextView];
    NSScrollView *inspScroll = [self wrapView:self.inspector];

    [split addSubview:navScroll];
    [split addSubview:tabs];
    [split addSubview:inspScroll];

    [[window contentView] addSubview:split];
    [self setWindow:window];

    [split setPosition:220 ofDividerAtIndex:0];
    [split setPosition:820 ofDividerAtIndex:1];
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

- (XFTreeItem *)itemForNode:(NSXMLNode *)node
{
    XFTreeItem *item = [[XFTreeItem alloc] init];
    item.node = node;
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
        XFTreeItem *kid = [self itemForNode:child];
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
        XFTreeItem *hostRoot = [self itemForNode:host];
        hostRoot.title = [NSString stringWithFormat:@"host · %@", hostRoot.title];
        [self.roots addObject:hostRoot];
    }
    NSXMLElement *inst = [[doc.processor defaultInstance] documentElement];
    if (inst) {
        XFTreeItem *instRoot = [self itemForNode:inst];
        instRoot.title = [NSString stringWithFormat:@"instance · %@", instRoot.title];
        [self.roots addObject:instRoot];
    }
    [self.outline reloadData];
    for (XFTreeItem *root in self.roots) {
        [self.outline expandItem:root expandChildren:NO];
    }
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
        self.formView = form;
        [self.formScroll setDocumentView:form];
    } else if (doc.loadError) {
        NSTextView *err = [self makeTextView];
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
    [[self window] setTitle:title];
}

- (void)reloadAll
{
    [self rebuildForm];
    [self rebuildTree];
    [self reloadSources];
    [self.inspector setString:@"Select a node in the navigator."];
}

- (void)inspectItem:(XFTreeItem *)item
{
    if (item == nil) {
        [self.inspector setString:@""];
        return;
    }
    NSMutableString *text = [NSMutableString string];
    NSXMLNode *node = item.node;
    [text appendFormat:@"Kind: %ld\n", (long)[node kind]];
    [text appendFormat:@"Name: %@\n", [node name] ?: @""];
    if ([node kind] == NSXMLElementKind) {
        NSXMLElement *el = (NSXMLElement *)node;
        [text appendFormat:@"Local: %@\n", [el localName] ?: @""];
        [text appendFormat:@"URI: %@\n", [el URI] ?: @""];
        [text appendString:@"\nAttributes:\n"];
        if ([[el attributes] count] == 0) {
            [text appendString:@"  (none)\n"];
        }
        for (NSXMLNode *attr in [el attributes]) {
            [text appendFormat:@"  @%@ = %@\n", [attr name], [attr stringValue]];
        }
        XFFormDocument *doc = [self formDocument];
        XFControl *control = [doc.processor controlForElement:el];
        if (control) {
            [text appendFormat:@"\nControl: %@\n", NSStringFromClass([control class])];
            [text appendFormat:@"  id: %@\n", control.identifier ?: @"-"];
            [text appendFormat:@"  label: %@\n", control.label ?: @"-"];
            [text appendFormat:@"  value: %@\n", control.stringValue ?: @""];
            [text appendFormat:@"  relevant: %@\n", control.relevant ? @"yes" : @"no"];
            [text appendFormat:@"  readonly: %@\n", control.readonly ? @"yes" : @"no"];
            [text appendFormat:@"  required: %@\n", control.required ? @"yes" : @"no"];
            [text appendFormat:@"  valid: %@\n", control.valid ? @"yes" : @"no"];
            [text appendFormat:@"  appearance: %@\n", control.appearance ?: @"-"];
            [text appendFormat:@"  hint: %@\n", control.hint ?: @"-"];
            if (control.binding) {
                [text appendFormat:@"  binding: %@\n", control.binding.expression];
            }
        }
    }
    XFNodeState *state = [XFNodeState existingStateOnNode:node];
    if (state) {
        [text appendString:@"\nMIPs:\n"];
        [text appendFormat:@"  type: %@\n", state.typeName ?: @"-"];
        [text appendFormat:@"  relevant: %@\n", state.relevant ? @"yes" : @"no"];
        [text appendFormat:@"  readonly: %@\n", state.readonly ? @"yes" : @"no"];
        [text appendFormat:@"  required: %@\n", state.required ? @"yes" : @"no"];
        [text appendFormat:@"  valid: %@\n", state.valid ? @"yes" : @"no"];
        [text appendFormat:@"  constraint: %@\n", state.constraint ? @"yes" : @"no"];
        if (state.repeatIdentifier.length) {
            [text appendFormat:@"  repeat: %@\n", state.repeatIdentifier];
        }
    }
    NSString *value = [[node stringValue] stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (value.length && [node kind] != NSXMLElementKind) {
        [text appendFormat:@"\nText:\n%@\n", value];
    }
    [self.inspector setString:text];
}

#pragma mark - Outline

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
        [self inspectItem:nil];
        return;
    }
    XFTreeItem *item = [self.outline itemAtRow:row];
    self.selectedItem = item;
    [self inspectItem:item];
}

- (void)refreshForm:(id)sender
{
    XFFormDocument *doc = [self formDocument];
    [doc.processor refresh:NULL];
    [self.formView reloadFromProcessor];
    [self rebuildTree];
    [self reloadSources];
    [self inspectItem:self.selectedItem];
}

@end
