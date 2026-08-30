#import <Foundation/Foundation.h>

@class XFModel;

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_globals.openAction / closeAction / closeChanges.
/// Nested actions increment `cont`; when the outermost action ends, each
/// changed model is rebuilt or recalculated and the UI is refreshed.
@interface XFDeferredUpdates : NSObject

@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *messages;
@property (nonatomic, strong, readonly) NSMutableArray *changedModels;

+ (instancetype)sharedUpdates;

- (void)openAction:(NSString *)name;
- (void)closeAction:(NSString *)name;
- (void)addChangedModel:(XFModel *)model;
- (void)closeChanges;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
