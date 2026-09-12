/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The app's first screen: the bundled sample forms, and a way to pick
/// any other form file. Either opens it as a form.
///
/// Deliberately the whole app. XForms is a client for a form SERVER —
/// submissions, `xf:load`, instances fetched over HTTP — and there is no
/// server to point at yet, so the useful thing a host can do today is
/// open a document from the file system and let the engine and the UIKit
/// form layer take it from there.
@interface XFFormBrowserViewController : UITableViewController

/// Open the form at `url` and push it. NO when it cannot be read or
/// constructed, in which case the reason has been shown to the user.
- (BOOL)openFormAtURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
