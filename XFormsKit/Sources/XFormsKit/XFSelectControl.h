#import <XFormsKit/XFControl.h>

NS_ASSUME_NONNULL_BEGIN

@interface XFItem : NSObject
@property (nonatomic, copy, nullable) NSString *label;
@property (nonatomic, copy, nullable) NSString *value;
@property (nonatomic, copy, nullable) NSString *groupLabel;
@property (nonatomic, strong, nullable) NSXMLNode *copyNode;
@property (nonatomic, strong, nullable) NSXMLNode *sourceNode;
@property (nonatomic, assign) BOOL selected;
@property (nonatomic, assign, readonly) BOOL usesCopy;
@end

/// `xf:select` / `xf:select1` with `xf:item`, `xf:itemset`, `xf:choices`, `xf:copy`.
@interface XFSelectControl : XFControl

@property (nonatomic, assign) BOOL multiple;
@property (nonatomic, copy, readonly) NSArray<XFItem *> *items;
@property (nonatomic, copy) NSArray<NSString *> *selectedValues;
@property (nonatomic, assign, readonly) BOOL usesCopy;

+ (nullable instancetype)selectWithElement:(NSXMLElement *)element
                                     model:(nullable id)model
                                     error:(NSError **)error;

- (void)rebuildItemsWithContext:(XFExprContext *)context error:(NSError **)error;
- (BOOL)selectValue:(NSString *)value;
- (BOOL)toggleValue:(NSString *)value;
- (BOOL)selectItem:(XFItem *)item;
- (BOOL)toggleItem:(XFItem *)item;

@end

NS_ASSUME_NONNULL_END
