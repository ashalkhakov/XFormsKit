/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* Postman-style tester for xf:submission: pick a
   submission, see the EXACT request the runtime builds from the live
   preview's instance data (method, resolved URI with the serialized
   query, merged headers, body — computed by the engine's own
   previewRequest, never a reimplementation), inject extra headers the
   way a host session would, and Send it through the REAL xforms-submit
   path — live HTTP (the document's transport, cookie jar included), an
   echo transport for offline round-trips, or an offline transport for
   the error path — then inspect the response, what replace did, and the
   run history. Runs against the live preview data; Reset Preview
   restores it. */
#pragma once
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>

NS_ASSUME_NONNULL_BEGIN

@class XFSubmission;
@protocol XFSubmissionTransport;

/// Offline echo: answers every request with its own body (200, the
/// request's media type) — replace="instance" round-trips without a
/// server.
@interface XFDEchoTransport : NSObject <XFSubmissionTransport>
@end

/// The testable core of one tester run (the selftest drives it headless
/// — modal panels cannot run under XFD_SELFTEST): sends `submission`
/// through the REAL submit path over `transport` (wrapped so the
/// request and response are captured; `extraHeaders` are injected the
/// way a host session transport would), restores the submission's own
/// transport afterwards, and summarizes:
/// { request: XFSubmissionRequest, response: XFSubmissionResponse?,
///   outcome: @"done"|@"error", error-type?, status: @(code) }.
NSDictionary *XFDPerformSubmission(XFSubmission *submission,
                                   id<XFSubmissionTransport> transport,
                                   NSDictionary *_Nullable extraHeaders);

@interface XFDSubmissionTester : NSObject
    <NSTableViewDataSource, NSTableViewDelegate>
/// Modal. `identifier` preselects a submission (nil = the first).
+ (void)runForProcessor:(XFProcessor *)processor
      initialSubmission:(nullable NSString *)identifier;
@end

NS_ASSUME_NONNULL_END

void XFDSubmissionTesterFilePresent(void);
