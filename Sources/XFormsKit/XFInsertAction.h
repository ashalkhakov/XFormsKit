#import <XFormsKit/XFAbstractAction.h>

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_insert / XForms 1.1 §10.3.
@interface XFInsertAction : XFAbstractAction

@property (nonatomic, copy, readonly, nullable) NSString *position; // before | after
@property (nonatomic, copy, readonly) NSArray<NSXMLNode *> *lastInsertedNodes;

@end

NS_ASSUME_NONNULL_END
