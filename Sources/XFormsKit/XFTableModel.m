#import "XFTableModel.h"
#import "XFHostNode.h"
#import "XFControl.h"
#import "XFRepeat.h"
#import "XFGroup.h"
#import "XFSwitch.h"
#import "XFDialog.h"
#import "XFVarControl.h"
#import <XFormsKit/XFXMLTypes.h>

@implementation XFTableCell
- (instancetype)init
{
    self = [super init];
    if (self) {
        _colspan = 1;
        _text = @"";
        _controls = @[];
    }
    return self;
}
@end

@implementation XFTableRow
- (instancetype)init
{
    self = [super init];
    if (self) {
        _cells = @[];
    }
    return self;
}
- (XFTableCell *)cellAtColumn:(NSUInteger)column
{
    for (XFTableCell *c in self.cells) {
        if (column >= c.column && column < c.column + c.colspan) {
            return c;
        }
    }
    return nil;
}
@end

@interface XFTableModel ()
@property (nonatomic, strong, readwrite) XFHostNode *tableNode;
@property (nonatomic, copy, readwrite) NSString *title;
@property (nonatomic, assign, readwrite) NSUInteger columnCount;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *columnTitles;
@property (nonatomic, copy, readwrite) NSArray<XFTableRow *> *rows;
@property (nonatomic, copy, readwrite) NSArray<XFTableRow *> *headerRows;
@end

@implementation XFTableModel

+ (instancetype)modelWithTableNode:(XFHostNode *)tableNode
{
    XFTableModel *m = [[self alloc] init];
    m.tableNode = tableNode;
    m.title = tableNode.title;
    [m build];
    return m;
}

static NSString *XFTrim(NSString *s)
{
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (XFTableCell *)cellFromNode:(XFHostNode *)node column:(NSUInteger)column
{
    XFTableCell *cell = [[XFTableCell alloc] init];
    cell.hostNode = node;
    cell.column = column;
    cell.header = node.header;
    NSString *span = [[node.element attributeForName:@"colspan"] stringValue];
    NSInteger n = span.length ? [span integerValue] : 1;
    cell.colspan = (NSUInteger)MAX(1, n);
    NSArray<XFControl *> *controls = [node allControls];
    cell.controls = controls;
    cell.text = XFTrim([node textContent]);
    // control-only cell: the single control (descending through a switch's
    // selected case / a group that shows exactly one control, as XSLTForms
    // renders the container's content in the cell — the calculator's "="),
    // with only whitespace beside it
    XFControl *only = controls.count == 1 ? controls.firstObject : nil;
    NSInteger guard = 0;
    while (only && [only isBlockLevel] && guard++ < 8) {
        NSArray<XFControl *> *inner = nil;
        if ([only isKindOfClass:[XFSwitch class]]) {
            inner = [(XFSwitch *)only selectedCase].children;
        } else if ([only isKindOfClass:[XFDialog class]] || [only isKindOfClass:[XFRepeat class]]) {
            break;
        } else if ([only isKindOfClass:[XFGroup class]]) {
            inner = [(XFGroup *)only children];
        } else {
            break;
        }
        only = inner.count == 1 ? inner.firstObject : nil;
    }
    if (only && ![only isBlockLevel] && ![only isKindOfClass:[XFVarControl class]]) {
        NSMutableString *other = [NSMutableString string];
        [self appendTextExcludingControlsOf:node into:other];
        if (XFTrim(other).length == 0) {
            cell.control = only;
        }
    }
    return cell;
}

- (void)appendTextExcludingControlsOf:(XFHostNode *)node into:(NSMutableString *)out
{
    if (node.kind == XFHostNodeKindControl) {
        return;
    }
    if (node.kind == XFHostNodeKindText) {
        [out appendString:node.text ?: @""];
        return;
    }
    for (XFHostNode *c in node.children) {
        [self appendTextExcludingControlsOf:c into:out];
    }
}

- (XFTableRow *)rowFromNode:(XFHostNode *)tr header:(BOOL)header footer:(BOOL)footer
{
    XFTableRow *row = [[XFTableRow alloc] init];
    row.hostNode = tr;
    row.header = header;
    row.footer = footer;
    NSMutableArray *cells = [NSMutableArray array];
    NSUInteger column = 0;
    BOOL allHeaders = YES;
    for (XFHostNode *c in tr.children) {
        if (c.kind != XFHostNodeKindTableCell) {
            continue;
        }
        XFTableCell *cell = [self cellFromNode:c column:column];
        column += cell.colspan;
        allHeaders = allHeaders && cell.header;
        [cells addObject:cell];
    }
    row.cells = cells;
    if (cells.count && allHeaders && !footer) {
        row.header = YES;
    }
    return row;
}

/// Collect the rows under `node` (table / section / repeat content).
- (void)collectRowsFrom:(NSArray<XFHostNode *> *)nodes
                 header:(BOOL)header
                 footer:(BOOL)footer
                 repeat:(XFRepeat *)repeat
                   item:(XFRepeatItem *)item
                   into:(NSMutableArray<XFTableRow *> *)rows
{
    for (XFHostNode *node in nodes) {
        switch (node.kind) {
            case XFHostNodeKindTableRow: {
                XFTableRow *row = [self rowFromNode:node header:header footer:footer];
                row.repeat = repeat;
                row.repeatItem = item;
                [rows addObject:row];
                break;
            }
            case XFHostNodeKindTableSection: {
                BOOL h = header || [node.tag isEqualToString:@"thead"];
                BOOL f = footer || [node.tag isEqualToString:@"tfoot"];
                [self collectRowsFrom:node.children header:h footer:f repeat:repeat item:item into:rows];
                break;
            }
            case XFHostNodeKindControl: {
                // XSLTForms group.xsl: a repeat under table/tbody becomes a
                // tbody whose items are <tr>s; a group there is a tbody too
                XFControl *control = node.control;
                if ([control isKindOfClass:[XFRepeat class]]) {
                    XFRepeat *rep = (XFRepeat *)control;
                    for (XFRepeatItem *it in rep.items) {
                        [self collectRowsFrom:it.hostNodes header:header footer:footer repeat:rep item:it into:rows];
                    }
                } else if ([control respondsToSelector:@selector(hostNodes)]) {
                    if (control.relevant) {
                        [self collectRowsFrom:[(id)control hostNodes] header:header footer:footer repeat:repeat item:item into:rows];
                    }
                }
                break;
            }
            default:
                break;
        }
    }
}

- (void)build
{
    NSMutableArray<XFTableRow *> *all = [NSMutableArray array];
    [self collectRowsFrom:self.tableNode.children header:NO footer:NO repeat:nil item:nil into:all];

    NSUInteger columns = 0;
    for (XFTableRow *row in all) {
        NSUInteger width = 0;
        for (XFTableCell *c in row.cells) {
            width += c.colspan;
        }
        columns = MAX(columns, width);
    }
    self.columnCount = columns;

    NSMutableArray *headers = [NSMutableArray array];
    NSMutableArray *body = [NSMutableArray array];
    for (XFTableRow *row in all) {
        [(row.header ? headers : body) addObject:row];
    }
    self.headerRows = headers;
    self.rows = body;

    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    BOOL any = NO;
    XFTableRow *source = headers.lastObject;
    for (NSUInteger col = 0; col < columns; col++) {
        NSString *title = @"";
        if (source) {
            XFTableCell *cell = [source cellAtColumn:col];
            if (cell && cell.column == col) {
                title = cell.text;
            }
        } else {
            // no thead: the labels of the first body row's controls name
            // the columns (XSLTForms shows them inside every cell)
            XFTableRow *first = body.firstObject;
            XFTableCell *cell = [first cellAtColumn:col];
            if (cell && cell.column == col && cell.control.label.length && [cell.control isValueControl]) {
                title = cell.control.label;
            }
        }
        any = any || title.length > 0;
        [titles addObject:title];
    }
    self.columnTitles = any ? titles : nil;
}

- (XFTableRow *)selectedRow
{
    for (XFTableRow *row in self.rows) {
        if (row.repeatItem && row.repeatItem.selected) {
            return row;
        }
    }
    return nil;
}

@end
