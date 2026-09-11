#import <XFormsKit/XFAbstractAction.h>

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_action: a container that runs child actions.
@interface XFAction : XFAbstractAction

@property (nonatomic, strong, readonly) NSMutableArray<XFAbstractAction *> *children;

- (void)addChild:(XFAbstractAction *)action;

@end

NS_ASSUME_NONNULL_END
