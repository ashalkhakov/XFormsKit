#import <XFormsKit/XFControl.h>

@class XFModel;
@class XFHostNode;

NS_ASSUME_NONNULL_BEGIN

@interface XFRepeatItem : NSObject
@property (nonatomic, strong, nullable) NSXMLNode *node;
@property (nonatomic, assign) NSUInteger position; // 1-based
@property (nonatomic, assign) BOOL selected;
@property (nonatomic, copy, readonly) NSArray<XFControl *> *controls;
/// Host-markup tree of the item (the repeat's content instantiated for
/// this node, G-20); `controls` are the controls found in it.
@property (nonatomic, copy) NSArray<XFHostNode *> *hostNodes;
- (void)addControl:(XFControl *)control;
@end

/// Translation of XsltForms_repeat: nodeset binding, 1-based index,
/// per-item cloned controls (no HTML clone — engine instances).
@interface XFRepeat : XFControl

@property (nonatomic, copy, readonly) NSArray<NSXMLNode *> *nodes;
@property (nonatomic, assign, readonly) NSUInteger index;      // 1-based; 0 if empty
@property (nonatomic, assign) NSUInteger startIndex; // default 1
@property (nonatomic, copy, readonly) NSArray<XFRepeatItem *> *items;
@property (nonatomic, copy, readonly) NSArray<NSXMLElement *> *templateElements;

+ (nullable instancetype)repeatWithElement:(NSXMLElement *)element
                                     model:(nullable id)model
                                     error:(NSError **)error;

- (nullable XFRepeatItem *)currentItem;
- (nullable NSXMLNode *)currentNode;
- (void)setIndex:(NSUInteger)index;
/// XForms 1.1 repeat processing: when an outer repeat's index changes —
/// or its indexed item is replaced by an insert/delete — the indexes of
/// repeats NESTED in it re-initialize to their startindex.
- (void)resetNestedRepeatIndexes;

- (void)rebuildItemsWithContext:(XFExprContext *)context error:(NSError **)error;
- (void)reloadTemplates;

@end

NS_ASSUME_NONNULL_END
