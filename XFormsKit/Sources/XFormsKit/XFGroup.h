#import <XFormsKit/XFControl.h>

@class XFModel;

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_group: optional single-node binding, relevance,
/// child controls refreshed against the bound node.
@interface XFGroup : XFControl

@property (nonatomic, copy, readonly) NSArray<XFControl *> *children;

+ (nullable instancetype)groupWithElement:(NSXMLElement *)element
                                    model:(nullable id)model
                                    error:(NSError **)error;

- (void)addChild:(XFControl *)child;
- (void)removeChild:(XFControl *)child;

@end

NS_ASSUME_NONNULL_END
