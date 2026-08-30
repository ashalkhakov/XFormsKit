#import <XFormsKit/XFAbstractAction.h>

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_delete / XForms 1.1 §10.4.
@interface XFDeleteAction : XFAbstractAction

@property (nonatomic, copy, readonly) NSArray<NSXMLNode *> *lastDeletedNodes;

@end

NS_ASSUME_NONNULL_END
