#import "XFAppKitPriv.h"

void XFAppKitHasTableAdapterFile(void) {}

/// A column that answers the adapter's per-row cell.
///
/// A table of XForms controls needs a different cell in different ROWS of one
/// column -- a trigger here, a field there -- and the delegate method for that
/// is `tableView:dataCellForTableColumn:row:`. Cocoa's NSTableView asks for it
/// everywhere. GNUstep asks in `-preparedCellAtColumn:row:`, which covers
/// clicking and editing, but its row DRAWING goes through the theme, and
/// `-[GSTheme drawTableViewRow:clipRect:inView:]` takes the cell from
/// `-[NSTableColumn dataCellForRow:]` instead: a table of controls was live
/// but drawn as plain text -- Samples/calculator.xhtml came up as a grid of
/// "0"s (a trigger's object value is its button state) that worked when
/// pressed.
///
/// Overriding the column's own accessor puts the right cell in front of every
/// caller on both platforms, and leaves selection, highlighting and editing to
/// the table as they were.
@interface XFControlTableColumn : NSTableColumn
@property (nonatomic, weak) XFTableAdapter *adapter;
@end

@implementation XFControlTableColumn

- (NSCell *)dataCellForRow:(NSInteger)row
{
    // the adapter ignores the table it is handed, and this is the one path
    // that has none to hand it
    NSCell *cell = [self.adapter tableView:(NSTableView *)[self tableView]
                    dataCellForTableColumn:self
                                       row:row];
    return cell ?: [super dataCellForRow:row];
}

@end

static const CGFloat kTableRowHeight = 22.0;
static const CGFloat kTableHeaderHeight = 20.0;
static const CGFloat kTableMinColumnWidth = 60.0;
static const CGFloat kTableMaxColumnWidth = 240.0;

#pragma mark - XFTableAdapter

@implementation XFTableAdapter

- (instancetype)initWithModel:(XFTableModel *)model formView:(XFFormView *)formView
{
    self = [super init];
    if (self) {
        _model = model;
        _formView = formView;
        _cells = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)identifierForColumn:(NSUInteger)column
{
    return [NSString stringWithFormat:@"%lu", (unsigned long)column];
}

- (NSUInteger)columnIndexOf:(NSTableColumn *)column
{
    return (NSUInteger)[[column identifier] integerValue];
}

- (XFTableCell *)cellAtRow:(NSInteger)row column:(NSTableColumn *)column
{
    if (row < 0 || (NSUInteger)row >= self.model.rows.count || column == nil) {
        return nil;
    }
    NSUInteger col = [self columnIndexOf:column];
    XFTableCell *cell = [self.model.rows[(NSUInteger)row] cellAtColumn:col];
    // a spanned cell shows its content in its first column only
    return (cell && cell.column == col) ? cell : nil;
}

- (CGFloat)preferredWidthForColumn:(NSUInteger)col
{
    XFFormView *fv = self.formView;
    NSFont *font = [fv bodyFont];
    CGFloat width = kTableMinColumnWidth;
    NSString *title = col < self.model.columnTitles.count ? self.model.columnTitles[col] : nil;
    if (title.length) {
        width = MAX(width, [fv widthOfText:title font:font] + 16);
    }
    for (XFTableRow *row in self.model.rows) {
        XFTableCell *cell = [row cellAtColumn:col];
        if (cell == nil || cell.column != col) {
            continue;
        }
        XFControl *control = cell.control;
        if (control == nil) {
            width = MAX(width, [fv widthOfText:cell.text font:font] + 12);
        } else if ([control isKindOfClass:[XFSelectControl class]]) {
            for (XFItem *item in [(XFSelectControl *)control items]) {
                width = MAX(width, [fv widthOfText:item.label ?: item.value ?: @"" font:font] + 36);
            }
        } else if ([control isKindOfClass:[XFTriggerControl class]]) {
            width = MAX(width, [fv widthOfText:control.label ?: @"" font:font] + 28);
        } else if ([control isKindOfClass:[XFOutputControl class]]) {
            if ([(XFOutputControl *)control displaysHTML]) {
                for (NSString *line in [self displayLinesOfCell:cell]) {
                    width = MAX(width, [fv widthOfText:line font:font] + 12);
                }
            } else {
                width = MAX(width, [fv widthOfText:control.stringValue ?: @"" font:font] + 12);
            }
        } else {
            width = MAX(width, kInlineFieldWidth);
        }
    }
    return MIN(width, kTableMaxColumnWidth);
}

/// The lines a cell shows (paragraphs / <br/> of a rich output, the plain
/// text otherwise) — what wrapping and height estimation work from.
- (NSArray<NSString *> *)displayLinesOfCell:(XFTableCell *)cell
{
    NSString *text = nil;
    XFControl *control = cell.control;
    if (control == nil) {
        text = cell.text;
    } else if ([control isKindOfClass:[XFOutputControl class]]) {
        text = [(XFOutputControl *)control displaysHTML]
            ? [[XFRichText attributedStringFromHTML:control.stringValue ?: @""] string]
            : control.stringValue;
    } else {
        return @[];   // widgets are single-line
    }
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *para in [text ?: @"" componentsSeparatedByString:@"\n"]) {
        [lines addObjectsFromArray:[para componentsSeparatedByString:@"\u2028"]];
    }
    return lines;
}

/// Rows fit the tallest cell of the table: text wraps at the column width,
/// paragraphs stack. (Uniform — GNUstep's NSTableView declares
/// tableView:heightOfRow: but its layout ignores it, so per-row heights
/// are not portable.)
- (CGFloat)preferredRowHeightWithColumnWidths:(NSArray<NSNumber *> *)widths
{
    XFFormView *fv = self.formView;
    NSFont *font = [fv bodyFont];
    NSUInteger most = 1;
    for (XFTableRow *row in self.model.rows) {
        for (XFTableCell *cell in row.cells) {
            if (cell.column >= widths.count) {
                continue;
            }
            CGFloat avail = MAX([widths[cell.column] doubleValue] - 10, 40);
            NSUInteger lines = 0;
            for (NSString *line in [self displayLinesOfCell:cell]) {
                CGFloat w = [fv widthOfText:line font:font];
                lines += MAX(1, (NSUInteger)ceil(w / avail));
            }
            most = MAX(most, MAX(lines, 1));
        }
    }
    return kTableRowHeight + (most - 1) * ([font pointSize] + 4);
}

- (NSSize)build
{
    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView = table;
    [table setRowHeight:kTableRowHeight];
    [table setAllowsColumnReordering:NO];
    [table setAllowsColumnSelection:NO];
    [table setAllowsEmptySelection:YES];
    [table setAllowsMultipleSelection:NO];
    [table setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
    CGFloat width = 0;
    for (NSUInteger col = 0; col < self.model.columnCount; col++) {
        XFControlTableColumn *column = [[XFControlTableColumn alloc]
            initWithIdentifier:[self identifierForColumn:col]];
        column.adapter = self;
        NSString *title = col < self.model.columnTitles.count ? self.model.columnTitles[col] : @"";
        [[column headerCell] setStringValue:title ?: @""];
        CGFloat w = [self preferredWidthForColumn:col];
        [column setWidth:w];
        [column setMinWidth:kTableMinColumnWidth];
        [column setEditable:YES];
        [table addTableColumn:column];
        width += w + [table intercellSpacing].width;
    }
    BOOL hasHeader = self.model.columnTitles != nil;
    if (!hasHeader) {
        [table setHeaderView:nil];
    }
    NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
    for (NSTableColumn *column in [table tableColumns]) {
        [widths addObject:@([column width])];
    }
    CGFloat rowHeight = [self preferredRowHeightWithColumnWidths:widths];
    [table setRowHeight:rowHeight];
    [table setDataSource:self];
    [table setDelegate:self];
    // a repeat's current item is the selected row, and vice versa
    [self selectCurrentRow];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [scroll setBorderType:NSBezelBorder];
    [scroll setHasVerticalScroller:NO];
    [scroll setHasHorizontalScroller:NO];
    [scroll setDocumentView:table];
    self.scrollView = scroll;

    CGFloat rows = MAX((CGFloat)self.model.rows.count, 1);
    CGFloat height = rows * (rowHeight + [table intercellSpacing].height)
        + (hasHeader ? kTableHeaderHeight : 0) + 4;
    [table setFrame:NSMakeRect(0, 0, width, height)];
    return NSMakeSize(width + 4, height);
}

- (void)selectCurrentRow
{
    XFTableRow *selected = [self.model selectedRow];
    NSUInteger idx = selected ? [self.model.rows indexOfObjectIdenticalTo:selected] : NSNotFound;
    self.selecting = YES;
    if (idx != NSNotFound) {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
    } else {
        [self.tableView deselectAll:nil];
    }
    self.selecting = NO;
}

- (void)refreshInPlace
{
    [self.tableView reloadData];
    [self selectCurrentRow];
}

#pragma mark data source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    (void)tableView;
    return (NSInteger)self.model.rows.count;
}

- (BOOL)isBooleanInput:(XFControl *)control
{
    if (![control isKindOfClass:[XFInputControl class]]) {
        return NO;
    }
    XFNodeState *state = [XFNodeState existingStateOnNode:control.boundNode];
    NSString *type = state.typeName ?: @"";
    if ([type rangeOfString:@"boolean"].location != NSNotFound) {
        return YES;
    }
    NSString *v = control.stringValue ?: @"";
    return [v isEqualToString:@"true"] || [v isEqualToString:@"false"];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)tableView;
    XFTableCell *cell = [self cellAtRow:row column:column];
    if (cell == nil) {
        return @"";
    }
    XFControl *control = cell.control;
    if (control == nil) {
        return cell.text;
    }
    if (!control.relevant) {
        return @"";
    }
    if ([control isKindOfClass:[XFTriggerControl class]]) {
        return @(NSOffState);
    }
    if ([control isKindOfClass:[XFOutputControl class]] && [(XFOutputControl *)control displaysHTML]) {
        return [XFRichText decoratedString:
            [XFRichText attributedStringFromHTML:control.stringValue ?: @""] baseFont:nil];
    }
    if ([control isKindOfClass:[XFSelectControl class]]) {
        // popup cells carry a blank first entry (G-25): index + 1
        NSInteger i = 1;
        for (XFItem *item in [(XFSelectControl *)control items]) {
            if (item.selected) {
                return @(i);
            }
            i++;
        }
        return @(0);
    }
    if ([self isBooleanInput:control]) {
        BOOL on = [control.stringValue isEqualToString:@"true"] || [control.stringValue isEqualToString:@"1"];
        return @(on ? NSOnState : NSOffState);
    }
    if ([control isKindOfClass:[XFRangeControl class]]) {
        return @([(XFRangeControl *)control numericValue]);
    }
    if ([control isKindOfClass:[XFOutputControl class]] && control.label.length
        && ![self labelIsColumnTitle:control.label column:column]) {
        // XSLTForms shows the label inside the cell: "M: 0"
        return [NSString stringWithFormat:@"%@ %@", control.label, control.stringValue ?: @""];
    }
    return control.stringValue ?: @"";
}

- (BOOL)labelIsColumnTitle:(NSString *)label column:(NSTableColumn *)column
{
    NSUInteger col = [self columnIndexOf:column];
    NSString *title = col < self.model.columnTitles.count ? self.model.columnTitles[col] : nil;
    return [title isEqualToString:label];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)tableView;
    XFTableCell *cell = [self cellAtRow:row column:column];
    XFControl *control = cell.control;
    XFFormView *fv = self.formView;
    if (control == nil || fv == nil || !control.relevant) {
        return;
    }
    if (row >= 0 && (NSUInteger)row < self.model.rows.count) {
        [fv tableAdapter:self didSelectRow:self.model.rows[(NSUInteger)row]];
    }
    if ([control isKindOfClass:[XFTriggerControl class]]) {
        [fv tableAdapter:self didActivateTrigger:(XFTriggerControl *)control];
        return;
    }
    if (control.readonly) {
        return;
    }
    if ([control isKindOfClass:[XFSelectControl class]]) {
        NSInteger idx = [value integerValue] - 1;   // blank first entry
        NSArray *items = [(XFSelectControl *)control items];
        if (idx >= 0 && (NSUInteger)idx < items.count) {
            XFItem *item = items[(NSUInteger)idx];
            [fv tableAdapter:self didCommitControl:control value:item.value ?: @""];
        }
        return;
    }
    if ([self isBooleanInput:control]) {
        BOOL on = [value integerValue] == NSOnState;
        [fv tableAdapter:self didCommitControl:control value:on ? @"true" : @"false"];
        return;
    }
    if ([control isKindOfClass:[XFRangeControl class]]) {
        [fv tableAdapter:self didCommitControl:control value:[NSString stringWithFormat:@"%g", [value doubleValue]]];
        return;
    }
    [fv tableAdapter:self didCommitControl:control value:[value description] ?: @""];
}

#pragma mark delegate

- (NSCell *)tableView:(NSTableView *)tableView dataCellForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)tableView;
    if (column == nil) {
        return nil;
    }
    NSString *key = [NSString stringWithFormat:@"%ld:%@", (long)row, [column identifier]];
    NSCell *cached = self.cells[key];
    if (cached) {
        return cached;
    }
    XFTableCell *cell = [self cellAtRow:row column:column];
    XFControl *control = cell.control;
    NSCell *made = nil;
    if (control == nil) {
        NSTextFieldCell *tc = [[NSTextFieldCell alloc] initTextCell:@""];
        [tc setEditable:NO];
        [tc setSelectable:NO];
        [tc setWraps:YES];
        if (cell.header) {
            [tc setFont:[[NSFontManager sharedFontManager] convertFont:[self.formView bodyFont] toHaveTrait:NSBoldFontMask]];
        }
        made = tc;
    } else if ([control isKindOfClass:[XFTriggerControl class]]) {
        NSButtonCell *bc = [[NSButtonCell alloc] initTextCell:control.label ?: @"OK"];
        [bc setBezelStyle:NSRoundedBezelStyle];
        [bc setButtonType:NSMomentaryPushInButton];
        made = bc;
    } else if ([control isKindOfClass:[XFSelectControl class]]) {
        NSPopUpButtonCell *pc = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
        [pc setBordered:NO];
        [pc addItemWithTitle:@""];
        for (XFItem *item in [(XFSelectControl *)control items]) {
            [pc addItemWithTitle:item.label ?: item.value ?: @""];
        }
        made = pc;
    } else if ([self isBooleanInput:control]) {
        NSButtonCell *bc = [[NSButtonCell alloc] initTextCell:@""];
        [bc setButtonType:NSSwitchButton];
        made = bc;
    } else if ([control isKindOfClass:[XFRangeControl class]]) {
        NSSliderCell *sc = [[NSSliderCell alloc] init];
        [sc setMinValue:[(XFRangeControl *)control start]];
        [sc setMaxValue:[(XFRangeControl *)control end]];
        made = sc;
    } else if ([control isKindOfClass:[XFSecretControl class]]) {
        NSSecureTextFieldCell *sc = [[NSSecureTextFieldCell alloc] initTextCell:@""];
        [sc setEditable:YES];
        made = sc;
    } else {
        NSTextFieldCell *tc = [[NSTextFieldCell alloc] initTextCell:@""];
        BOOL editable = [control isKindOfClass:[XFInputControl class]]
            || [control isKindOfClass:[XFTextareaControl class]];
        [tc setEditable:editable];
        [tc setSelectable:YES];
        if (editable) {
            [tc setBezeled:YES];
            [tc setDrawsBackground:YES];
        } else {
            [tc setWraps:YES];   // outputs show every line (rich HTML too)
        }
        made = tc;
    }
    if (control) {
        [made setEnabled:control.relevant && !control.readonly];
    }
    self.cells[key] = made;
    return made;
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)tableView;
    XFTableCell *cell = [self cellAtRow:row column:column];
    XFControl *control = cell.control;
    if (control == nil || !control.relevant || control.readonly) {
        return NO;
    }
    return [control isKindOfClass:[XFInputControl class]]
        || [control isKindOfClass:[XFSecretControl class]]
        || [control isKindOfClass:[XFTextareaControl class]];
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)tableView;
    XFTableCell *tc = [self cellAtRow:row column:column];
    XFControl *control = tc.control;
    if (control && [cell respondsToSelector:@selector(setTextColor:)] && [cell isKindOfClass:[NSTextFieldCell class]]) {
        [(NSTextFieldCell *)cell setTextColor:control.valid ? [NSColor controlTextColor] : XFInvalidTextColor()];
    }
    // A trigger's title, re-applied after the table has set the cell's object
    // value. The object value is the button's STATE (NSOffState), which is
    // what Cocoa's NSButtonCell reads it as -- GNUstep's takes it as the
    // cell's contents instead and draws every button captioned "0", which is
    // what Samples/calculator.xhtml looked like there: a working keypad with
    // no labels on it.
    if ([control isKindOfClass:[XFTriggerControl class]]
        && [cell isKindOfClass:[NSButtonCell class]]) {
        [(NSButtonCell *)cell setTitle:control.label ?: @"OK"];
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
    (void)note;
    if (self.selecting) {
        return;
    }
    NSInteger row = [self.tableView selectedRow];
    if (row >= 0 && (NSUInteger)row < self.model.rows.count) {
        [self.formView tableAdapter:self didSelectRow:self.model.rows[(NSUInteger)row]];
    }
}

@end

#pragma mark - XFListBoxAdapter

@implementation XFListBoxAdapter

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    (void)tableView;
    return (NSInteger)self.select.items.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)tableView; (void)column;
    if (row < 0 || (NSUInteger)row >= self.select.items.count) {
        return @"";
    }
    XFItem *item = self.select.items[(NSUInteger)row];
    return item.label ?: item.value ?: @"";
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)tableView; (void)column; (void)row;
    return NO;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
    if (self.selecting) {
        return;
    }
    NSTableView *table = [note object];
    [self.formView listBox:self didSelectRows:[table selectedRowIndexes]];
}

@end
