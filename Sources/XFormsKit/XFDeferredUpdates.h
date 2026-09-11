#import <Foundation/Foundation.h>

@class XFModel;
@class XFXPathValue;

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_globals.openAction / closeAction / closeChanges.
/// Nested actions increment `cont`; when the outermost action ends, each
/// changed model is rebuilt or recalculated and the UI is refreshed.
@interface XFDeferredUpdates : NSObject

@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *messages;

/// Variable scopes (XSLTForms varScope / varResolver, G-77): containers
/// push a scope while refreshing their children and actions while running
/// theirs; xf:var / xf:setvar publish into the innermost scope; `$x`
/// looks outward through the stack.
- (void)pushVariableScope;
- (void)popVariableScope;
- (void)setVariable:(nullable XFXPathValue *)value named:(NSString *)name;
- (nullable XFXPathValue *)variableNamed:(NSString *)name;
@property (nonatomic, strong, readonly) NSMutableArray *changedModels;
/// XsltForms_globals.building: YES while the UI is being refreshed. Changes
/// recorded meanwhile go to the pending lists and become current after the
/// refresh (see -finishRefresh).
@property (nonatomic, assign) BOOL building;

+ (instancetype)sharedUpdates;

- (void)openAction:(NSString *)name;
- (void)closeAction:(NSString *)name;
- (void)addChangedModel:(XFModel *)model;
- (void)closeChanges;
/// XsltForms_globals.refresh bookkeeping: promote the pending change lists
/// (models and per-model nodes) recorded during the UI refresh, clear the
/// rest, and reset `rebuilded`. Runs after the UI has been refreshed.
- (void)finishRefreshForModels:(NSArray<XFModel *> *)models;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
