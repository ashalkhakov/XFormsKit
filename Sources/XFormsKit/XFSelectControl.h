#import <XFormsKit/XFControl.h>

NS_ASSUME_NONNULL_BEGIN

@interface XFItem : NSObject
@property (nonatomic, copy, nullable) NSString *label;
@property (nonatomic, copy, nullable) NSString *value;
@property (nonatomic, assign) BOOL selected;
@end

/// `xf:select` / `xf:select1` with static `xf:item` and `xf:itemset`.
@interface XFSelectControl : XFControl

@property (nonatomic, assign) BOOL multiple;
@property (nonatomic, copy, readonly) NSArray<XFItem *> *items;
@property (nonatomic, copy) NSArray<NSString *> *selectedValues;

+ (nullable instancetype)selectWithElement:(NSXMLElement *)element
                                     model:(nullable id)model
                                     error:(NSError **)error;

- (void)rebuildItemsWithContext:(XFExprContext *)context error:(NSError **)error;
- (BOOL)selectValue:(NSString *)value;
- (BOOL)toggleValue:(NSString *)value;

@end

NS_ASSUME_NONNULL_END
