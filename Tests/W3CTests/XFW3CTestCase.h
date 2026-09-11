/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* Base class for the W3C XForms 1.1 test suite as XCTest assertions.

   Each suite form (TestSuite/XForms1.1/Edition1) states in its
   instruction labels what a human tester must see; these tests assert
   that behavior programmatically — widget state through the real
   XFFormView/XFControl layer and model state through XPath — the way
   the designer selftest does, never pixels. The load path mirrors
   Tools/xftestrun: real processor, real (headless) form view, host
   hooks capturing messages/loads, a dead transport so no test touches
   the network (the W3C echo endpoints are long gone), and the ms68
   event-trace sink recording every dispatched event for the chapter 4
   ordering assertions.

   POLICY: assertions are SPEC-TRUE. A case the engine gets wrong stays
   red here — `make w3ccheck` is a conformance report, and fixing the
   engine is separate work. `make check` stays the green gate. */
#pragma once
#import <XCTest/XCTest.h>
#if __has_include(<AppKit/AppKit.h>)
#import <AppKit/AppKit.h>
#endif
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFXMLEvents.h>
#import <XFormsKit/XFTriggerControl.h>
#import <XFormsKit/XFSubmitControl.h>
#import <XFormsKit/XFInputControl.h>
#import <XFormsKit/XFSecretControl.h>
#import <XFormsKit/XFTextareaControl.h>
#import <XFormsKit/XFOutputControl.h>
#import <XFormsKit/XFSelectControl.h>
#import <XFormsKit/XFRangeControl.h>
#import <XFormsKit/XFRepeat.h>
#import <XFormsKit/XFSwitch.h>
#import <XFormsKit/XFXML.h>

NS_ASSUME_NONNULL_BEGIN

@interface XFW3CTestCase : XCTestCase <XFEventTraceSink>

@property (nonatomic, strong, nullable) XFProcessor *processor;
#if __has_include(<AppKit/AppKit.h>)
/// Built so every case exercises the widget layer too, not just the
/// engine. There is no view layer on iOS yet, where the same cases run
/// against the engine alone.
@property (nonatomic, strong, nullable) XFFormView *formView;
#endif
/// The live echo transport after useEchoTransport (it records requests).
@property (nonatomic, strong, nullable) id echoTransport;
@property (nonatomic, strong, nullable) NSError *loadError;
/// xf:message texts observed, in order (messageHandler).
@property (nonatomic, strong) NSMutableArray<NSString *> *messages;
/// The level of each message, parallel to `messages` (modal/modeless/ephemeral).
@property (nonatomic, strong) NSMutableArray<NSString *> *messageLevels;
/// URLs xf:load asked the host to open (loadRequestHandler; handled, never navigated).
@property (nonatomic, strong) NSMutableArray<NSString *> *loadRequests;
/// The @show of each load request, parallel to `loadRequests`.
@property (nonatomic, strong) NSMutableArray<NSString *> *loadShows;
/// Identifiers of controls the form asked the host to focus (focusRequestHandler).
@property (nonatomic, strong) NSMutableArray<NSString *> *focusRequests;
/// Every event dispatched since load, in dispatch order (ms68 trace sink).
@property (nonatomic, strong) NSMutableArray<NSString *> *dispatchedEvents;

/// TestSuite/XForms1.1/Edition1 (found from the working directory).
+ (NSURL *)suiteRoot;

/// Load a suite form ("Chapt03/3.1/3.1.a.xhtml"), install hooks + dead
/// transport, build the headless form view. nil on load failure
/// (loadError / the raised exception's reason is kept) — for the cases
/// that test load-time behavior.
- (nullable XFProcessor *)loadTest:(NSString *)relPath;
/// loadTest: + XCTAssert the load succeeded.
- (nullable XFProcessor *)loadRequired:(NSString *)relPath;

#pragma mark widget state (the real control layer)

/// Deep walk: groups, repeat items, the selected switch case.
- (NSArray<XFControl *> *)allControls;
/// stringValues of relevant controls, walk order (labels excluded).
- (NSArray<NSString *> *)renderedValues;
/// Is `value` rendered by some relevant control right now?
- (BOOL)valueRendered:(NSString *)value;
- (NSUInteger)countOfClass:(Class)cls;
- (nullable __kindof XFControl *)controlOfClass:(Class)cls index:(NSUInteger)index;
/// First control whose ref/nodeset/bind attribute equals `binding`.
- (nullable __kindof XFControl *)controlWithBinding:(NSString *)binding;
/// First control whose label text (trimmed) contains `text`.
- (nullable __kindof XFControl *)controlWithLabelContaining:(NSString *)text;

#pragma mark interaction (the real activation/edit paths)

- (void)activateTrigger:(XFControl *)trigger;
- (void)activateTriggerAtIndex:(NSUInteger)index;
- (void)activateTriggerLabeled:(NSString *)labelSubstring;
/// The real user-edit path (processor setValue:ofControl:).
- (void)setValue:(NSString *)value ofControl:(XFControl *)control;

#pragma mark model state

/// Evaluate an XPath string against the default model's default
/// instance ("" on failure). Prefixes resolve per the model element.
- (NSString *)stringForXPath:(NSString *)expr;
- (NSString *)stringForXPath:(NSString *)expr model:(XFModel *)model;
- (double)numberForXPath:(NSString *)expr;
- (nullable XFModel *)modelWithID:(NSString *)identifier;

/// Did `eventName` dispatch since load (or since clearing dispatchedEvents)?
- (BOOL)eventDispatched:(NSString *)eventName;
/// Number of times `eventName` dispatched.
- (NSUInteger)countOfEvent:(NSString *)eventName;
/// The names appear in dispatchedEvents in this order (as a subsequence).
- (void)assertOrderedEvents:(NSArray<NSString *> *)names;

/// Positive event case ("you must have seen an X message"): the form's
/// message text was observed, or the event itself dispatched (an event
/// fired mid-construction predates the host's message handler).
- (void)assertSawEvent:(NSString *)eventName;

/// "You must see an <event> message or a fatal error": load failure
/// passes outright; otherwise the message text or the dispatched event
/// is the evidence.
- (void)assertMessageOrFatal:(NSString *)eventName;

/// Swap every model onto an echo transport (200, request body echoed
/// back) — the stand-in for the long-gone W3C echo endpoints, so
/// replace="instance"/"none" submissions can SUCCEED. Requests whose URL
/// contains "invalid" still fail instantly (the deliberate-bad-URL legs).
/// The transport records every request for the chapter 11 serialization
/// assertions (`submittedRequests` / `lastRequest`).
- (void)useEchoTransport;
/// Every request the echo transport saw, in order (nil before
/// useEchoTransport).
- (nullable NSArray<XFSubmissionRequest *> *)submittedRequests;
- (nullable XFSubmissionRequest *)lastRequest;
/// First submission with this id across the processor's models.
- (nullable XFSubmission *)submissionWithID:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
