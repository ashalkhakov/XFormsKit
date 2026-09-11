#import <XFormsKit/XFAbstractAction.h>
#import <XFormsKit/XFXMLTypes.h>

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_insert / XForms 1.1 §10.3.
@interface XFInsertAction : XFAbstractAction

@property (nonatomic, copy, readonly, nullable) NSString *position; // before | after
@property (nonatomic, copy, readonly) NSArray<XFXMLNode *> *lastInsertedNodes;

@end

NS_ASSUME_NONNULL_END
