#import <AppKit/AppKit.h>

@class XFFormDocument;

NS_ASSUME_NONNULL_BEGIN

@interface XFDocumentWindowController : NSWindowController
- (instancetype)init;
- (void)reloadAll;
@end

NS_ASSUME_NONNULL_END
