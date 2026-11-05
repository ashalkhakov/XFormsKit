/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDLibraryViewController.h"
#import "XFDFormEditor.h"
#import "XFDPartViewController.h"
#import "XFDInspectorSpecs.h"
#import "XFDXPathField.h"

/// Badge tints per catalogue category.
static NSImage *XFDLibraryIcon(NSString *name, NSString *category)
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

@implementation XFDLibraryViewController {
    /// Header rows {header} and catalogue entries, as shown.
    NSArray *_rows;
}

- (instancetype)initWithFormEditor:(XFDFormEditor *)formEditor
{
    if ((self = [super initWithNibName:@"XFDLibrary" bundle:[XFDPartViewController designKitBundle]])) {
        _formEditor = formEditor;
        _validNames = [NSSet set];
        _rows = @[];
        self.title = @"Library";
    }
    return self;
}

- (void)loadView
{
    [super loadView];
    [self reload];
}

- (void)setValidNames:(NSSet<NSString *> *)validNames
{
    _validNames = [validNames copy] ?: [NSSet set];
    [self reload];
}

- (void)reload
{
    if (self.formEditor != nil) {
        _validNames = [self.formEditor insertableNamesForSelection];
    }
    NSString *filter = [self.filterField stringValue];
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
    [self.table reloadData];
    [self.table deselectAll:nil];
}

- (NSString *)selectedName
{
    NSInteger row = [self.table selectedRow];
    if (row < 0 || (NSUInteger)row >= _rows.count) {
        return nil;
    }
    NSString *name = _rows[(NSUInteger)row][@"name"];
    return (name != nil && [self.validNames containsObject:name]) ? name : nil;
}

- (void)controlTextDidChange:(NSNotification *)note
{
    (void)note;
    [self reload];
}

- (IBAction)rowDoubleClicked:(id)sender
{
    (void)sender;
    NSString *name = [self selectedName];
    if (name == nil) {
        return;
    }
    if (self.delegate != nil) {
        [self.delegate library:self didChooseName:name];
        return;
    }
    NSError *error = nil;
    if ([self.formEditor insertElementNamed:name error:&error] == nil) {
        [self presentError:error];
        return;
    }
    [self reload];
}

#pragma mark The table

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
        return XFDLibraryIcon(entry[@"name"], entry[@"cat"]);
    }
    BOOL valid = [self.validNames containsObject:entry[@"name"]];
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
    return entry[@"header"] == nil && [self.validNames containsObject:entry[@"name"]];
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
    if ([self.delegate respondsToSelector:@selector(librarySelectionDidChange:)]) {
        [self.delegate librarySelectionDidChange:self];
    }
}

@end
