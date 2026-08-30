#import <XFormsKit/XFAbstractAction.h>

@class XFBinding;
@class XFXPath;

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_load.
/// Host-document navigation (`show="replace"|"new"`) is recorded rather than
/// performed; `@instance` (XSLTForms extension) GETs the resource and replaces
/// that instance document.
@interface XFLoadAction : XFAbstractAction

@property (nonatomic, copy, readonly, nullable) NSString *resource;
@property (nonatomic, strong, readonly, nullable) XFXPath *resourceExpr;
@property (nonatomic, strong, readonly, nullable) XFBinding *binding;
@property (nonatomic, copy, readonly, nullable) NSString *show;
@property (nonatomic, copy, readonly, nullable) NSString *targetID;
@property (nonatomic, copy, readonly, nullable) NSString *instanceID;
@property (nonatomic, copy, readonly, nullable) NSString *lastResource;
@property (nonatomic, copy, readonly, nullable) NSDictionary *lastEventContext;

@end

NS_ASSUME_NONNULL_END
