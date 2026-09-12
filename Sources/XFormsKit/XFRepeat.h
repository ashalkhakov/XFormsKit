#import <XFormsKit/XFControl.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFModel;
@class XFHostNode;

NS_ASSUME_NONNULL_BEGIN

@interface XFRepeatItem : NSObject
@property (nonatomic, strong, nullable) XFXMLNode *node;
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

@property (nonatomic, copy, readonly) NSArray<XFXMLNode *> *nodes;
@property (nonatomic, assign, readonly) NSUInteger index;      // 1-based; 0 if empty
@property (nonatomic, assign) NSUInteger startIndex; // default 1
@property (nonatomic, copy, readonly) NSArray<XFRepeatItem *> *items;
@property (nonatomic, copy, readonly) NSArray<XFXMLElement *> *templateElements;

+ (nullable instancetype)repeatWithElement:(XFXMLElement *)element
                                     model:(nullable id)model
                                     error:(NSError **)error;

- (nullable XFRepeatItem *)currentItem;
- (nullable XFXMLNode *)currentNode;
- (void)setIndex:(NSUInteger)index;
/// The next rebuild constructs every item fresh instead of reusing
/// unchanged rows — required after subform content was imported into or
/// removed from item subtrees (per-item xf:load embedding).
- (void)invalidateItems;

/// XForms 1.1 repeat processing: when an outer repeat's index changes —
/// or its indexed item is replaced by an insert/delete — the indexes of
/// repeats NESTED in it re-initialize to their startindex.
- (void)resetNestedRepeatIndexes;

- (void)rebuildItemsWithContext:(XFExprContext *)context error:(NSError **)error;

/* Add / remove driven by the HOST's own affordance rather than by the
   form (the iOS table view's insert row and swipe-to-delete, G-20).

   A form that asks for these with xf:insert / xf:delete keeps working
   exactly as it did — these do not replace the actions. They are the
   narrow case of §10.3 / §10.4 in which the nodeset is this repeat's own
   and the position is already known, so nothing is evaluated: the node
   to copy or to remove is in `nodes` already. Everything after that is
   what the actions do — dispose the bindings, mutate the instance, mark
   the model rebuilt, dispatch xforms-insert / xforms-delete, rebuild the
   items and move the index — inside one deferred-update action, so the
   rebuild / recalculate / revalidate / refresh cycle runs once at the
   end.

   `position` is 1-based, as everywhere in XForms. Both answer NO and
   change nothing when it names no item, or when the item cannot be
   edited (an instance root has no parent to be removed from). */

/// Copy the item at `position` and insert the copy after it, the way
/// `<xf:insert>` with no @origin copies the last node.
- (BOOL)insertItemAfterPosition:(NSUInteger)position;
/// Remove the item at `position`.
- (BOOL)deleteItemAtPosition:(NSUInteger)position;
- (void)reloadTemplates;

@end

NS_ASSUME_NONNULL_END
