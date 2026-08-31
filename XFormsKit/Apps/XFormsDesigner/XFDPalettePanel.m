/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDPalettePanel.h"
#import "XFDInspectorSpecs.h"
#import "XFDXPathField.h"

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

@implementation XFDPalettePanel {
    NSPanel *_panel;
    NSTextField *_searchField;
    NSTableView *_table;
    NSButton *_insertButton;
    NSSet *_validNames;
    NSArray *_rows;      // header dicts {header} and entry dicts from the catalog
    NSString *_result;
}

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

void XFDPalettePanelFilePresent(void) {}
