#import <XFormsKit/XFControl.h>
#import <XFormsKit/XFXMLTypes.h>

NS_ASSUME_NONNULL_BEGIN

@interface XFItem : NSObject
@property (nonatomic, copy, nullable) NSString *label;
@property (nonatomic, copy, nullable) NSString *value;
@property (nonatomic, copy, nullable) NSString *groupLabel;
@property (nonatomic, strong, nullable) XFXMLNode *copiedNode;
@property (nonatomic, strong, nullable) XFXMLNode *sourceNode;
/// The xf:item (or xf:itemset) element the item comes from: the target of
/// xforms-select / xforms-deselect (G-25).
@property (nonatomic, strong, nullable) XFXMLElement *element;
@property (nonatomic, assign) BOOL selected;
@property (nonatomic, assign, readonly) BOOL usesCopy;
@end

/// `xf:select` / `xf:select1` with `xf:item`, `xf:itemset`, `xf:choices`, `xf:copy`.
@interface XFSelectControl : XFControl

@property (nonatomic, assign) BOOL multiple;
/// selection="open" (8.1.10/8.1.11): free values are accepted — the
/// control never flags out-of-range for a value with no matching item.
@property (nonatomic, assign) BOOL openSelection;
@property (nonatomic, copy, readonly) NSArray<XFItem *> *items;
@property (nonatomic, copy) NSArray<NSString *> *selectedValues;
@property (nonatomic, assign, readonly) BOOL usesCopy;
/// The bound value is not one of the items (XsltForms_select.outRange);
/// changes dispatch xforms-out-of-range / xforms-in-range (G-25).
@property (nonatomic, assign, readonly) BOOL outOfRange;

+ (nullable instancetype)selectWithElement:(XFXMLElement *)element
                                     model:(nullable id)model
                                     error:(NSError **)error;

- (void)rebuildItemsWithContext:(XFExprContext *)context error:(NSError **)error;
/// Recompile item / itemset / choices templates from the element's
/// CURRENT children (the designer inserts and edits them after the
/// control was built), then rebuildItemsWithContext: re-evaluates.
- (BOOL)reloadTemplatesWithError:(NSError **)error;
- (BOOL)selectValue:(NSString *)value;
- (BOOL)toggleValue:(NSString *)value;
- (BOOL)selectItem:(XFItem *)item;
- (BOOL)toggleItem:(XFItem *)item;

@end

NS_ASSUME_NONNULL_END
