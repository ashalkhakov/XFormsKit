#import <Foundation/Foundation.h>

@class XFHostNode;
@class XFControl;
@class XFRepeat;
@class XFRepeatItem;

NS_ASSUME_NONNULL_BEGIN

/// One `<td>` / `<th>` of a host table, reduced to what a table view can
/// show: either a single inline control (`control`) or plain text (`text`).
@interface XFTableCell : NSObject
@property (nonatomic, strong) XFHostNode *hostNode;
@property (nonatomic, assign) NSUInteger column;      // first column covered
@property (nonatomic, assign) NSUInteger colspan;     // >= 1
@property (nonatomic, assign) BOOL header;            // <th>
/// The cell's only control when its content is that control (plus
/// whitespace); nil for text / mixed cells.
@property (nonatomic, strong, nullable) XFControl *control;
/// Text content (controls contribute their value) for text / mixed cells.
@property (nonatomic, copy) NSString *text;
/// The controls found in the cell, document order (also set for text cells).
@property (nonatomic, copy) NSArray<XFControl *> *controls;
@end

/// One `<tr>`: static, or produced by an `xf:repeat` item.
@interface XFTableRow : NSObject
@property (nonatomic, strong) XFHostNode *hostNode;
@property (nonatomic, copy) NSArray<XFTableCell *> *cells;
@property (nonatomic, assign) BOOL header;   // inside <thead> (or all-th)
@property (nonatomic, assign) BOOL footer;   // inside <tfoot>
@property (nonatomic, strong, nullable) XFRepeat *repeat;
@property (nonatomic, strong, nullable) XFRepeatItem *repeatItem;
- (nullable XFTableCell *)cellAtColumn:(NSUInteger)column;
@end

/// A host `<table>` flattened into rows × columns for NSTableView (G-20
/// phase 2): thead rows become column titles, `xf:repeat` children of
/// table/tbody/thead/tfoot contribute one row per item, colspans keep
/// their content in the first covered column.
@interface XFTableModel : NSObject

@property (nonatomic, strong, readonly) XFHostNode *tableNode;
@property (nonatomic, copy, readonly, nullable) NSString *title;   // <caption>
@property (nonatomic, assign, readonly) NSUInteger columnCount;
/// Column titles: from the (last) thead row, else from the labels of the
/// controls in the first body row; nil when neither gives any title.
@property (nonatomic, copy, readonly, nullable) NSArray<NSString *> *columnTitles;
/// Body + footer rows in document order (header rows are not listed).
@property (nonatomic, copy, readonly) NSArray<XFTableRow *> *rows;
@property (nonatomic, copy, readonly) NSArray<XFTableRow *> *headerRows;

+ (instancetype)modelWithTableNode:(XFHostNode *)tableNode;

/// The row that is the current item of its repeat (index), if any.
- (nullable XFTableRow *)selectedRow;

@end

NS_ASSUME_NONNULL_END
