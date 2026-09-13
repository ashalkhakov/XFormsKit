#import <Foundation/Foundation.h>
#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>

@class XFProcessor;
@class XFUploadControl;
@class XFGroup;

NS_ASSUME_NONNULL_BEGIN

/// The iOS form: a grouped table view, one control per row, scrolling in
/// one direction only.
///
/// Deliberately not the AppKit layout ported across. That one is a
/// fixed-width two-column form — a 110pt label column beside a 280pt field
/// column on a canvas at least 620pt wide — which on a phone means
/// sideways scrolling from the first row. Here the rows come from
/// XFFormRows (portable, tested without a screen) and each is shown by a
/// cell in the iOS idiom.
///
/// The controls remain the source of truth: a cell is a view OF a control
/// for as long as it is on screen, never its owner. That is what lets
/// cells recycle while controls — which hold the value, the MIP state and
/// the focus — do not.
@interface XFFormViewController : UIViewController <UITableViewDataSource,
                                                   UITableViewDelegate,
                                                   UIDocumentPickerDelegate>

- (instancetype)initWithProcessor:(XFProcessor *)processor;

@property (nonatomic, strong, readonly) XFProcessor *processor;
@property (nonatomic, strong, readonly) UITableView *tableView;
/// A view for one container only (an xf:dialog the host presents); nil
/// shows the whole host body.
@property (nonatomic, strong, nullable) XFGroup *rootGroup;

/// Refresh the controls from the processor, rebuild the rows and reload.
- (void)reloadFromProcessor;

/// Take `url` as the file chosen for `upload`. The document picker this
/// controller presents funnels into this, and a host that presents its own
/// chooser — a camera, a cloud provider — can call it directly.
- (BOOL)commitPickedFileAtURL:(NSURL *)url forUpload:(XFUploadControl *)upload;

@end

NS_ASSUME_NONNULL_END

#endif
