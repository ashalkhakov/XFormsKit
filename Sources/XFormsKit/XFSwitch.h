#import <XFormsKit/XFControl.h>

NS_ASSUME_NONNULL_BEGIN

@interface XFCase : XFControl
@property (nonatomic, assign) BOOL selected;
@property (nonatomic, copy, readonly) NSArray<XFControl *> *children;
- (void)addChild:(XFControl *)child;
@end

/// XForms `xf:switch` / `xf:case`. Toggle selects a case by id.
@interface XFSwitch : XFControl

@property (nonatomic, copy, readonly) NSArray<XFCase *> *cases;
@property (nonatomic, weak, nullable, readonly) XFCase *selectedCase;

+ (nullable instancetype)switchWithElement:(NSXMLElement *)element
                                     model:(nullable id)model
                                     error:(NSError **)error;

- (nullable XFCase *)caseWithIdentifier:(NSString *)identifier;
- (void)selectCase:(XFCase *)caze;

@end

NS_ASSUME_NONNULL_END
