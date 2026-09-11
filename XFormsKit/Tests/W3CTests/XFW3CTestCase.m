/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFW3CTestCase.h"
#import <XFormsKit/XFSubmissionTransport.h>
#import <XFormsKit/XFXPath.h>
#import <XFormsKit/XFXPathValue.h>
#import <XFormsKit/XFExprContext.h>
#import <XFormsKit/XFInstance.h>
#import <XFormsKit/XFModel.h>
#import <XFormsKit/XFBind.h>

/// Tools/xftestrun's transport stub: every non-file request fails
/// instantly (the deliberately-bad-URL cases observe exactly that as
/// xforms-submit-error); file: URLs pass through so local-resource
/// submissions still work.
@interface XFW3CDeadTransport : NSObject <XFSubmissionTransport>
@end

@implementation XFW3CDeadTransport {
    XFHTTPSubmissionTransport *_files;
}

- (XFSubmissionResponse *)performRequest:(XFSubmissionRequest *)request
                                   error:(NSError **)error
{
    NSURL *url = [NSURL URLWithString:request.URLString];
    if ([url isFileURL]) {
        if (_files == nil) {
            _files = [[XFHTTPSubmissionTransport alloc] init];
        }
        return [_files performRequest:request error:error];
    }
    if (error) {
        *error = [NSError errorWithDomain:NSURLErrorDomain
                                     code:NSURLErrorCannotConnectToHost
                                 userInfo:@{ NSLocalizedDescriptionKey:
                                     @"XFW3CTests: network disabled" }];
    }
    return nil;
}

@end

/// 200-echo for every request except URLs containing "invalid" (those
/// fail instantly, like the dead transport) — lets a suite form's good
/// submission succeed and its deliberately-bad one fail, offline.
@interface XFW3CEchoTransport : NSObject <XFSubmissionTransport>
/// Every request seen, in order — the bad-URL ones included.
@property (nonatomic, strong) NSMutableArray<XFSubmissionRequest *> *requests;
@end

@implementation XFW3CEchoTransport

- (instancetype)init
{
    self = [super init];
    if (self) {
        _requests = [NSMutableArray array];
    }
    return self;
}

- (XFSubmissionResponse *)performRequest:(XFSubmissionRequest *)request
                                   error:(NSError **)error
{
    [self.requests addObject:request];
    if ([request.URLString rangeOfString:@"invalid"].location != NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:NSURLErrorDomain
                                         code:NSURLErrorCannotConnectToHost
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                         @"XFW3CTests: deliberately-bad URL" }];
        }
        return nil;
    }
    XFSubmissionResponse *response = [[XFSubmissionResponse alloc] init];
    response.statusCode = 200;
    response.body = request.body ?: @"";
    response.mediaType = request.mediaType ?: @"application/xml";
    return response;
}

@end

@implementation XFW3CTestCase

+ (void)initialize
{
    if (self == [XFW3CTestCase class]) {
        [NSApplication sharedApplication];   // AppKit headless bring-up
    }
}

+ (NSURL *)suiteRoot
{
    NSFileManager *fm = [NSFileManager defaultManager];
#ifdef XFW3C_SUITE_ROOT
    // Xcode runs the bundle from DerivedData, nowhere near the repo —
    // the target bakes the suite path in via GCC_PREPROCESSOR_DEFINITIONS
    // (XFW3C_SUITE_ROOT=$(SRCROOT)/TestSuite/XForms1.1/Edition1 — no
    // quotes: Xcode's setting pipeline strips them unreliably, so the
    // define is a bare token sequence and we stringize it here).
#define XFW3CStringize2(x) #x
#define XFW3CStringize(x) XFW3CStringize2(x)
    NSString *compiled = [NSString stringWithUTF8String:XFW3CStringize(XFW3C_SUITE_ROOT)];
    if ([fm fileExistsAtPath:compiled]) {
        return [NSURL fileURLWithPath:compiled];
    }
#endif
    // `make w3ccheck` runs xctest from the repo root; also walk upward
    // so a manually-launched run from a subdirectory still resolves.
    NSString *dir = [fm currentDirectoryPath];
    for (int i = 0; i < 6 && dir.length > 1; i++) {
        NSString *candidate = [dir stringByAppendingPathComponent:
            @"TestSuite/XForms1.1/Edition1"];
        if ([fm fileExistsAtPath:candidate]) {
            return [NSURL fileURLWithPath:candidate];
        }
        dir = [dir stringByDeletingLastPathComponent];
    }
    return nil;
}

- (void)setUp
{
    [super setUp];
    self.messages = [NSMutableArray array];
    self.messageLevels = [NSMutableArray array];
    self.loadRequests = [NSMutableArray array];
    self.loadShows = [NSMutableArray array];
    self.focusRequests = [NSMutableArray array];
    self.dispatchedEvents = [NSMutableArray array];
    [[[XFXMLEvents sharedEvents] exceptionMessages] removeAllObjects];
    [XFXMLEvents setTraceSink:self];
}

- (void)tearDown
{
    if ([XFXMLEvents traceSink] == (id)self) {
        [XFXMLEvents setTraceSink:nil];
    }
    [self.processor close];
    self.processor = nil;
    self.formView = nil;
    [super tearDown];
}

- (void)traceEventOfKind:(XFTraceKind)kind
                 message:(NSString *)message
               eventName:(NSString *)eventName
                 element:(XFXMLElement *)element
{
    (void)message; (void)element;
    if (kind == XFTraceKindEvent && eventName.length) {
        [self.dispatchedEvents addObject:eventName];
    }
}

#pragma mark - loading

- (XFProcessor *)loadTest:(NSString *)relPath
{
    NSURL *root = [[self class] suiteRoot];
    XCTAssertNotNil(root, @"TestSuite/XForms1.1/Edition1 not found from cwd");
    if (root == nil) {
        return nil;
    }
    NSURL *url = [root URLByAppendingPathComponent:relPath];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[url path]],
                  @"suite form missing: %@", relPath);
    NSError *error = nil;
    XFProcessor *processor = nil;
    @try {
        processor = [XFProcessor processorWithContentsOfURL:url error:&error];
    } @catch (NSException *e) {
        error = [NSError errorWithDomain:@"XFW3CTests" code:1 userInfo:
            @{ NSLocalizedDescriptionKey:
                   [NSString stringWithFormat:@"load raised %@: %@", [e name], [e reason]] }];
    }
    self.loadError = error;
    if (processor == nil) {
        return nil;
    }
    self.processor = processor;

    __weak XFW3CTestCase *weakSelf = self;
    processor.messageHandler = ^(NSString *text, NSString *level) {
        [weakSelf.messages addObject:text ?: @""];
        [weakSelf.messageLevels addObject:level ?: @""];
    };
    processor.confirmHandler = ^BOOL(NSString *text) {
        (void)text;
        return YES;
    };
    processor.loadRequestHandler = ^BOOL(NSURL *loadURL, NSString *show) {
        [weakSelf.loadRequests addObject:[loadURL absoluteString] ?: @""];
        [weakSelf.loadShows addObject:show ?: @""];
        return YES;   // handled: never navigate
    };
    processor.dialogRequestHandler = ^(XFDialog *dialog, BOOL show) {
        (void)dialog;
        (void)show;
    };
    XFW3CDeadTransport *transport = [[XFW3CDeadTransport alloc] init];
    for (XFModel *model in processor.models) {
        model.transport = transport;
    }
    self.formView = [[XFFormView alloc] initWithProcessor:processor];
    // The form view installs its own focusRequestHandler (first-responder
    // routing) in its initializer — install the capture AFTER it, chained,
    // or the capture is silently clobbered.
    void (^viewFocusHandler)(XFControl *) = processor.focusRequestHandler;
    processor.focusRequestHandler = ^(XFControl *control) {
        [weakSelf.focusRequests addObject:control.identifier ?: @"?"];
        if (viewFocusHandler) {
            viewFocusHandler(control);
        }
    };
    return processor;
}

- (XFProcessor *)loadRequired:(NSString *)relPath
{
    XFProcessor *p = [self loadTest:relPath];
    XCTAssertNotNil(p, @"%@ failed to load: %@", relPath,
                    [self.loadError localizedDescription]);
    return p;
}

#pragma mark - widget state

static void XFW3CWalk(NSArray<XFControl *> *controls, void (^visit)(XFControl *))
{
    for (XFControl *c in controls) {
        visit(c);
        if ([c isKindOfClass:[XFRepeat class]]) {
            for (XFRepeatItem *item in [(XFRepeat *)c items]) {
                XFW3CWalk(item.controls, visit);
            }
        } else if ([c isKindOfClass:[XFSwitch class]]) {
            XFCase *selected = [(XFSwitch *)c selectedCase];
            if (selected != nil) {
                XFW3CWalk(@[ selected ], visit);
            }
        } else if ([c isKindOfClass:[XFCase class]]) {
            // XFCase is NOT an XFGroup — without this branch the walk
            // never enters a case's content (xftestrun's blind spot)
            XFW3CWalk([(XFCase *)c children], visit);
        } else if ([c isKindOfClass:[XFGroup class]]) {
            XFW3CWalk([(XFGroup *)c children], visit);
        }
    }
}

- (NSArray<XFControl *> *)allControls
{
    NSMutableArray *out = [NSMutableArray array];
    XFW3CWalk(self.processor.controls, ^(XFControl *c) {
        [out addObject:c];
    });
    return out;
}

- (NSArray<NSString *> *)renderedValues
{
    NSMutableArray *out = [NSMutableArray array];
    XFW3CWalk(self.processor.controls, ^(XFControl *c) {
        if (!c.relevant) {
            return;
        }
        NSString *value = c.stringValue;
        if (value.length) {
            [out addObject:value];
        }
    });
    return out;
}

- (BOOL)valueRendered:(NSString *)value
{
    for (NSString *v in [self renderedValues]) {
        if ([v isEqualToString:value]
            || [v rangeOfString:value].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

- (NSUInteger)countOfClass:(Class)cls
{
    NSUInteger __block n = 0;
    XFW3CWalk(self.processor.controls, ^(XFControl *c) {
        if ([c isKindOfClass:cls]) {
            n++;
        }
    });
    return n;
}

- (__kindof XFControl *)controlOfClass:(Class)cls index:(NSUInteger)index
{
    NSMutableArray *found = [NSMutableArray array];
    XFW3CWalk(self.processor.controls, ^(XFControl *c) {
        if ([c isKindOfClass:cls]) {
            [found addObject:c];
        }
    });
    return index < found.count ? found[index] : nil;
}

- (__kindof XFControl *)controlWithBinding:(NSString *)binding
{
    XFControl *__block match = nil;
    XFW3CWalk(self.processor.controls, ^(XFControl *c) {
        if (match != nil) {
            return;
        }
        for (NSString *attr in @[ @"ref", @"nodeset", @"bind" ]) {
            if ([[[c.element attributeForName:attr] stringValue]
                    isEqualToString:binding]) {
                match = c;
                return;
            }
        }
    });
    return match;
}

- (__kindof XFControl *)controlWithLabelContaining:(NSString *)text
{
    XFControl *__block match = nil;
    XFW3CWalk(self.processor.controls, ^(XFControl *c) {
        if (match == nil && c.label.length
            && [c.label rangeOfString:text].location != NSNotFound) {
            match = c;
        }
    });
    return match;
}

#pragma mark - interaction

- (void)activateTrigger:(XFControl *)trigger
{
    XCTAssertNotNil(trigger, @"no trigger to activate");
    if (trigger != nil) {
        [self.processor activateControl:(XFTriggerControl *)trigger];
    }
}

- (void)activateTriggerAtIndex:(NSUInteger)index
{
    [self activateTrigger:[self controlOfClass:[XFTriggerControl class] index:index]];
}

- (void)activateTriggerLabeled:(NSString *)labelSubstring
{
    XFControl *__block match = nil;
    XFW3CWalk(self.processor.controls, ^(XFControl *c) {
        if (match == nil && [c isKindOfClass:[XFTriggerControl class]]
            && [c.label rangeOfString:labelSubstring].location != NSNotFound) {
            match = c;
        }
    });
    XCTAssertNotNil(match, @"no trigger labeled '%@'", labelSubstring);
    if (match != nil) {
        [self activateTrigger:match];
    }
}

- (void)setValue:(NSString *)value ofControl:(XFControl *)control
{
    XCTAssertNotNil(control, @"no control to type into");
    if (control != nil) {
        [self.processor setValue:value ofControl:control error:NULL];
    }
}

#pragma mark - model state

- (NSString *)stringForXPath:(NSString *)expr
{
    return [self stringForXPath:expr model:self.processor.models.firstObject];
}

- (NSString *)stringForXPath:(NSString *)expr model:(XFModel *)model
{
    if (model == nil) {
        return @"";
    }
    NSError *error = nil;
    XFXPath *xp = [XFXPath xpathWithString:expr element:model.element error:&error];
    if (xp == nil) {
        return @"";
    }
    XFXMLNode *root = [[model defaultInstance].document rootElement];
    if (root == nil) {
        return @"";
    }
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:root];
    ctx.model = model;
    XFXPathValue *v = [xp evaluateInContext:ctx error:&error];
    return v ? [v stringValue] : @"";
}

- (double)numberForXPath:(NSString *)expr
{
    NSString *s = [self stringForXPath:expr];
    return s.length ? [s doubleValue] : NAN;
}

- (XFModel *)modelWithID:(NSString *)identifier
{
    for (XFModel *m in self.processor.models) {
        if ([m.identifier isEqualToString:identifier]) {
            return m;
        }
    }
    return nil;
}

- (BOOL)eventDispatched:(NSString *)eventName
{
    return [self.dispatchedEvents containsObject:eventName];
}

- (NSUInteger)countOfEvent:(NSString *)eventName
{
    NSUInteger n = 0;
    for (NSString *e in self.dispatchedEvents) {
        if ([e isEqualToString:eventName]) {
            n++;
        }
    }
    return n;
}

- (void)assertOrderedEvents:(NSArray<NSString *> *)names
{
    NSUInteger pos = 0;
    for (NSString *e in self.dispatchedEvents) {
        if (pos < names.count && [e isEqualToString:names[pos]]) {
            pos++;
        }
    }
    XCTAssertEqual(pos, names.count,
                   @"expected ordered %@; dispatched: %@", names, self.dispatchedEvents);
}

- (void)assertSawEvent:(NSString *)eventName
{
    XCTAssertNotNil(self.processor, @"form did not load: %@",
                    [self.loadError localizedDescription]);
    XCTAssertTrue([self.messages containsObject:eventName]
                      || [self eventDispatched:eventName],
                  @"expected %@; messages: %@; events: %@",
                  eventName, self.messages, self.dispatchedEvents);
}

- (void)assertMessageOrFatal:(NSString *)eventName
{
    if (self.processor == nil) {
        return;   // "or a fatal error" — the load failure IS the pass
    }
    XCTAssertTrue([self.messages containsObject:eventName]
                      || [self eventDispatched:eventName],
                  @"expected %@ (message or dispatch) or a load failure; "
                  @"messages: %@; events: %@",
                  eventName, self.messages, self.dispatchedEvents);
}

- (void)useEchoTransport
{
    XFW3CEchoTransport *echo = [[XFW3CEchoTransport alloc] init];
    self.echoTransport = echo;
    for (XFModel *model in self.processor.models) {
        model.transport = echo;
    }
}

- (NSArray<XFSubmissionRequest *> *)submittedRequests
{
    return [(XFW3CEchoTransport *)self.echoTransport requests];
}

- (XFSubmissionRequest *)lastRequest
{
    return [self submittedRequests].lastObject;
}

- (XFSubmission *)submissionWithID:(NSString *)identifier
{
    for (XFModel *model in self.processor.models) {
        for (XFSubmission *sub in model.submissions) {
            if ([sub.identifier isEqualToString:identifier]) {
                return sub;
            }
        }
    }
    return nil;
}

@end
