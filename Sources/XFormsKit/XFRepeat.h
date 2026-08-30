#import <XFormsKit/XFControl.h>

@class XFModel;

NS_ASSUME_NONNULL_BEGIN

@interface XFRepeatItem : NSObject
@property (nonatomic, strong, nullable) NSXMLNode *node;
@property (nonatomic, assign) NSUInteger position;
@property (nonatomic, assign) BOOL selected;
@property (nonatomic, copy, readonly) NSArray<XFControl *> *controls;
- (void)addControl:(XFControl *)control;
@end

/// Translation of XsltForms_repeat: nodeset binding, 1-based index,
/// per-item cloned controls (no HTML clone — engine instances).
@interface XFRepeat : XFControl

@property (nonatomic, copy, readonly) NSArray<NSXMLNode *> *nodes;
@property (nonatomic, assign, readonly) NSUInteger index;
@property (nonatomic, assign) NSUInteger startIndex;
@property (nonatomic, copy, readonly) NSArray<XFRepeatItem *> *items;
@property (nonatomic, copy, readonly) NSArray<NSXMLElement *> *templateElements;

+ (nullable instancetype)repeatWithElement:(NSXMLElement *)element
                                     model:(nullable id)model
                                     error:(NSError **)error;

- (nullable XFRepeatItem *)currentItem;
- (nullable NSXMLNode *)currentNode;
- (void)setIndex:(NSUInteger)index;
- (void)rebuildItemsWithContext:(XFExprContext *)context error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
