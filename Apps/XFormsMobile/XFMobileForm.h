/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

@class XFProcessor;

NS_ASSUME_NONNULL_BEGIN

/// One opened form: the processor, the file it came from, and that file's
/// read access.
///
/// A URL from the document picker is security-scoped, and access has to
/// stay open for as long as the form might reach back to the file —
/// `xf:instance src=`, an XML Schema, a submission reading a resource
/// beside the document — not just for the read that builds the
/// processor. So the scope belongs to an object with the form's own
/// lifetime rather than to the load call, and is given up in -dealloc.
@interface XFMobileForm : NSObject

/// Reads the form at `url` and builds its processor. nil with an error
/// when the file cannot be read or is not a form XFormsKit can construct
/// (the error is the engine's, and says what the form got wrong).
+ (nullable instancetype)formWithContentsOfURL:(NSURL *)url error:(NSError **)error;

@property (nonatomic, strong, readonly) XFProcessor *processor;
@property (nonatomic, strong, readonly) NSURL *url;
/// What to put in the navigation bar: the file name without its
/// extension. XForms has a host `<title>`, but the engine does not keep
/// it, and a file name is what the user just picked anyway.
@property (nonatomic, copy, readonly) NSString *title;

@end

NS_ASSUME_NONNULL_END
