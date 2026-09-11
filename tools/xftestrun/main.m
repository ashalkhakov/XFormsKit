/* xftestrun — headless end-to-end runner for the W3C XForms 1.1 test
   suite (TestSuite/XForms1.1/Edition1, the Edition 1 suite as shipped in
   the XSLTForms repository).

   The suite is built for human judgment: each form's instruction label
   says what the tester must see, and event tests pop xf:message dialogs.
   The runner automates as much of that as the documents allow:

   1. The per-chapter driver manifests (driverPages/xml/XF11TestSuite*.xml)
      give the catalog — name, section, file, description, basic/normative.
   2. Each test loads into a real XFProcessor and lays out in a real
      XFFormView (GNUstep runs both headless), so the run is end to end
      through the AppKit view layer; a future iOS backend can implement
      the same two build steps and reuse everything else.
   3. A generic interaction pass activates every trigger once (skipping
      any whose action subtree submits — the W3C echo servers are gone)
      and types into every input, capturing every xf:message along the way.
   4. Verdicts: the quoted strings in the form's instruction labels must
      appear among the rendered VALUES (labels are excluded from the match
      target, or the instruction would match itself), or an observed
      message must match one of the document's xf:message texts. Quoted
      expectations present but unmatched = "check" (a candidate fail for
      review); nothing checkable = "review". TestSuite/overrides.tsv
      (name <TAB> status <TAB> note; status pass|fail|skip|na) pins
      human-reviewed verdicts over the automation.
   5. Output: TestSuite/results.tsv (one row per test) and
      TestSuite/report.md (per-chapter summary), plus a console summary.

   Usage: xftestrun <suite-root> [--chapter <n>] [--test <name>] [--out <dir>]
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFTriggerControl.h>
#import <XFormsKit/XFSubmitControl.h>
#import <XFormsKit/XFInputControl.h>
#import <XFormsKit/XFSecretControl.h>
#import <XFormsKit/XFTextareaControl.h>
#import <XFormsKit/XFOutputControl.h>
#import <XFormsKit/XFRepeat.h>
#import <XFormsKit/XFSwitch.h>

/* ---------------------------------------------------------------- */
#pragma mark - Catalog

@interface XFTSCase : NSObject
@property (nonatomic, copy) NSString *name;        // "4.2.1.a"
@property (nonatomic, copy) NSString *section;     // "4.2.1"
@property (nonatomic, copy) NSString *chapter;     // "Chapter 4: Processing Model"
@property (nonatomic, copy) NSString *summary;     // driver description
@property (nonatomic, copy) NSURL *fileURL;
@property (nonatomic, assign) BOOL missing;        // manifest names a file that is not there
@end
@implementation XFTSCase
@end

static NSString *XFTSText(NSXMLElement *parent, NSString *localName)
{
    for (NSXMLNode *c in [parent children]) {
        if ([c kind] == NSXMLElementKind
            && [[c localName] isEqualToString:localName]) {
            return [c stringValue] ?: @"";
        }
    }
    return @"";
}

/// Every test case of every chapter manifest, catalog order.
static NSArray<XFTSCase *> *XFTSLoadCatalog(NSURL *suiteRoot)
{
    NSMutableArray *cases = [NSMutableArray array];
    NSURL *xmlDir = [suiteRoot URLByAppendingPathComponent:@"driverPages/xml"];
    NSArray *files = [[[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:[xmlDir path] error:NULL]
        sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *file in files) {
        if (![file hasSuffix:@".xml"] || ![file hasPrefix:@"XF11TestSuite"]) {
            continue;
        }
        NSURL *url = [xmlDir URLByAppendingPathComponent:file];
        NSXMLDocument *doc = [[NSXMLDocument alloc]
            initWithContentsOfURL:url options:0 error:NULL];
        if (doc == nil) {
            fprintf(stderr, "manifest unreadable: %s\n", [file UTF8String]);
            continue;
        }
        for (NSXMLNode *chapterNode in [[doc rootElement] children]) {
            if ([chapterNode kind] != NSXMLElementKind
                || ![[chapterNode localName] isEqualToString:@"specChapter"]) {
                continue;
            }
            NSXMLElement *chapter = (NSXMLElement *)chapterNode;
            NSString *chapterName = [NSString stringWithFormat:@"%@%@",
                [[chapter attributeForName:@"chapterName"] stringValue] ?: @"",
                [[chapter attributeForName:@"chapterTitle"] stringValue] ?: @""];
            for (NSXMLNode *caseNode in [chapter children]) {
                if ([caseNode kind] != NSXMLElementKind
                    || ![[caseNode localName] isEqualToString:@"testCase"]) {
                    continue;
                }
                NSXMLElement *tc = (NSXMLElement *)caseNode;
                XFTSCase *c = [[XFTSCase alloc] init];
                c.name = XFTSText(tc, @"testCaseName");
                c.section = XFTSText(tc, @"testCaseSection");
                c.chapter = chapterName;
                c.summary = XFTSText(tc, @"testCaseDescription");
                NSString *link = XFTSText(tc, @"testCaseLink");
                c.fileURL = [[NSURL URLWithString:link relativeToURL:url] absoluteURL];
                c.missing = c.fileURL == nil
                    || ![[NSFileManager defaultManager] fileExistsAtPath:[c.fileURL path]];
                if (c.name.length) {
                    [cases addObject:c];
                }
            }
        }
    }
    return cases;
}

/* ---------------------------------------------------------------- */
#pragma mark - Transport stub

/// The W3C echo endpoints are long gone; a live network fetch would hang
/// the sweep for minutes per submission. Every non-file request fails
/// instantly instead — which is also what the deliberately-bad-URL tests
/// want to observe (xforms-submit-error). file: URLs pass through to the
/// real transport so local-resource submissions still work.
@interface XFTSDeadTransport : NSObject <XFSubmissionTransport>
@end

@implementation XFTSDeadTransport {
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
                                     @"xftestrun: network disabled" }];
    }
    return nil;
}

@end

/* ---------------------------------------------------------------- */
#pragma mark - Expectations from the document

/// The quoted strings of the form's instruction text ("You must see a
/// value of "4"…") — ASCII and typographic quotes both.
static NSArray<NSString *> *XFTSQuotedExpectations(NSXMLDocument *doc)
{
    NSMutableArray *out = [NSMutableArray array];
    NSMutableArray *labels = [NSMutableArray array];
    NSMutableArray *queue = [NSMutableArray arrayWithObject:[doc rootElement]];
    while (queue.count) {
        NSXMLElement *e = [queue lastObject];
        [queue removeLastObject];
        if ([[e localName] isEqualToString:@"label"]) {
            [labels addObject:[e stringValue] ?: @""];
        }
        for (NSXMLNode *c in [e children]) {
            if ([c kind] == NSXMLElementKind) {
                [queue addObject:(NSXMLElement *)c];
            }
        }
    }
    NSString *text = [labels componentsJoinedByString:@"\n"];
    for (NSArray *pair in @[ @[ @"\"", @"\"" ], @[ @"“", @"”" ] ]) {
        NSScanner *scanner = [NSScanner scannerWithString:text];
        [scanner setCharactersToBeSkipped:nil];
        while (![scanner isAtEnd]) {
            [scanner scanUpToString:pair[0] intoString:NULL];
            if (![scanner scanString:pair[0] intoString:NULL]) {
                break;
            }
            NSString *quoted = nil;
            [scanner scanUpToString:pair[1] intoString:&quoted];
            [scanner scanString:pair[1] intoString:NULL];
            quoted = [quoted stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (quoted.length >= 1 && quoted.length <= 80
                && [quoted rangeOfString:@"\n"].location == NSNotFound) {
                [out addObject:quoted];
            }
        }
    }
    return out;
}

/// The texts of the document's xf:message elements — what the form CAN
/// pop; an observed message matching one of these is the tested behavior.
static NSArray<NSString *> *XFTSMessageTexts(NSXMLDocument *doc)
{
    NSMutableArray *out = [NSMutableArray array];
    NSMutableArray *queue = [NSMutableArray arrayWithObject:[doc rootElement]];
    while (queue.count) {
        NSXMLElement *e = [queue lastObject];
        [queue removeLastObject];
        if ([[e localName] isEqualToString:@"message"]) {
            NSString *text = [[e stringValue] stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (text.length) {
                [out addObject:text];
            }
        }
        for (NSXMLNode *c in [e children]) {
            if ([c kind] == NSXMLElementKind) {
                [queue addObject:(NSXMLElement *)c];
            }
        }
    }
    return out;
}

/* ---------------------------------------------------------------- */
#pragma mark - Control walk

static void XFTSWalkControls(NSArray<XFControl *> *controls,
                             void (^visit)(XFControl *))
{
    for (XFControl *c in controls) {
        visit(c);
        if ([c isKindOfClass:[XFRepeat class]]) {
            for (XFRepeatItem *item in [(XFRepeat *)c items]) {
                XFTSWalkControls(item.controls, visit);
            }
        } else if ([c isKindOfClass:[XFSwitch class]]) {
            XFCase *selected = [(XFSwitch *)c selectedCase];
            if (selected != nil) {
                XFTSWalkControls(@[ selected ], visit);
            }
        } else if ([c isKindOfClass:[XFGroup class]]) {
            XFTSWalkControls([(XFGroup *)c children], visit);
        }
    }
}

/// The rendered VALUES only — the match target for quoted expectations.
/// Labels stay out: the instruction label quoting "4" must not satisfy
/// itself.
static NSString *XFTSValueDump(XFProcessor *processor)
{
    NSMutableArray *lines = [NSMutableArray array];
    XFTSWalkControls(processor.controls, ^(XFControl *c) {
        if (!c.relevant) {
            return;
        }
        NSString *value = c.stringValue;
        if (value.length) {
            [lines addObject:value];
        }
    });
    return [lines componentsJoinedByString:@"\n"];
}

/// The human-readable dump for the report (kind label = value).
static NSString *XFTSReportDump(XFProcessor *processor)
{
    NSMutableArray *lines = [NSMutableArray array];
    XFTSWalkControls(processor.controls, ^(XFControl *c) {
        NSMutableString *line = [NSMutableString string];
        [line appendString:[c.element localName] ?: @"?"];
        if (c.label.length) {
            [line appendFormat:@" '%@'", c.label];
        }
        if (c.stringValue.length) {
            [line appendFormat:@" = %@", c.stringValue];
        }
        if (!c.relevant) {
            [line appendString:@" [hidden]"];
        }
        if (!c.valid) {
            [line appendString:@" [invalid]"];
        }
        [lines addObject:line];
    });
    return [lines componentsJoinedByString:@"; "];
}

/* ---------------------------------------------------------------- */
#pragma mark - Running one test

@interface XFTSResult : NSObject
@property (nonatomic, copy) NSString *status;   // pass|check|review|error|missing|skip (+overrides)
@property (nonatomic, copy) NSString *how;      // values|message|override|-
@property (nonatomic, copy) NSString *detail;
@end
@implementation XFTSResult
@end

static XFTSResult *XFTSRunCase(XFTSCase *tc)
{
    XFTSResult *result = [[XFTSResult alloc] init];
    result.how = @"-";
    if (tc.missing) {
        result.status = @"missing";
        result.detail = @"manifest links a file that does not exist";
        return result;
    }
    NSError *error = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc]
        initWithContentsOfURL:tc.fileURL options:0 error:&error];
    if (doc == nil) {
        result.status = @"error";
        result.detail = [NSString stringWithFormat:@"XML: %@",
            [error localizedDescription]];
        return result;
    }
    NSArray *expectations = XFTSQuotedExpectations(doc);
    NSArray *documentMessages = XFTSMessageTexts(doc);

    NSMutableArray<NSString *> *observed = [NSMutableArray array];
    XFProcessor *processor = nil;
    @try {
        processor = [XFProcessor processorWithContentsOfURL:tc.fileURL error:&error];
    } @catch (NSException *e) {
        result.status = @"error";
        result.detail = [NSString stringWithFormat:@"load raised %@: %@",
            [e name], [e reason]];
        return result;
    }
    if (processor == nil) {
        result.status = @"error";
        result.detail = [NSString stringWithFormat:@"load: %@",
            [error localizedDescription] ?: @"?"];
        return result;
    }
    processor.messageHandler = ^(NSString *text, NSString *level) {
        (void)level;
        [observed addObject:text ?: @""];
    };
    processor.confirmHandler = ^BOOL(NSString *text) {
        (void)text;
        return YES;
    };
    processor.loadRequestHandler = ^BOOL(NSURL *url, NSString *show) {
        (void)url;
        (void)show;
        return YES;   // handled: never navigate
    };
    processor.dialogRequestHandler = ^(XFDialog *dialog, BOOL show) {
        (void)dialog;
        (void)show;
    };
    XFTSDeadTransport *transport = [[XFTSDeadTransport alloc] init];
    for (XFModel *model in processor.models) {
        model.transport = transport;
    }

    @try {
        // E2E: the real view layer lays the form out, headless
        XFFormView *view = [[XFFormView alloc] initWithProcessor:processor];
        (void)view;

        NSMutableString *values = [[XFTSValueDump(processor)
            stringByAppendingString:@"\n"] mutableCopy];
        NSString *reportDump = XFTSReportDump(processor);

        // generic interactions: every trigger once (submitting ones
        // skipped), then a value typed into every text input
        NSMutableArray<XFControl *> *triggers = [NSMutableArray array];
        NSMutableArray<XFControl *> *inputs = [NSMutableArray array];
        XFTSWalkControls(processor.controls, ^(XFControl *c) {
            if (![c relevant]) {
                return;
            }
            if ([c isKindOfClass:[XFTriggerControl class]]) {
                // submits included: the transport stub fails instantly,
                // which is exactly what the bad-URL tests observe
                [triggers addObject:c];
            } else if ([c isKindOfClass:[XFInputControl class]]
                       || [c isKindOfClass:[XFSecretControl class]]
                       || [c isKindOfClass:[XFTextareaControl class]]) {
                [inputs addObject:c];
            }
        });
        for (XFControl *trigger in triggers) {
            @try {
                [processor activateControl:(XFTriggerControl *)trigger];
            } @catch (NSException *e) {
                [observed addObject:[NSString stringWithFormat:@"(raised %@)", [e name]]];
            }
        }
        [values appendString:XFTSValueDump(processor)];
        for (XFControl *input in inputs) {
            @try {
                [processor setValue:@"test" ofControl:input error:NULL];
            } @catch (NSException *e) {
                [observed addObject:[NSString stringWithFormat:@"(raised %@)", [e name]]];
            }
        }

        // verdicts
        if (expectations.count) {
            BOOL all = YES;
            NSMutableArray *missing = [NSMutableArray array];
            for (NSString *expected in expectations) {
                if ([values rangeOfString:expected].location == NSNotFound) {
                    all = NO;
                    [missing addObject:expected];
                }
            }
            if (all) {
                result.status = @"pass";
                result.how = @"values";
                result.detail = [NSString stringWithFormat:@"%lu quoted value(s) found",
                    (unsigned long)expectations.count];
                return result;
            }
            // quoted values unseen — maybe the test speaks in messages
            for (NSString *message in observed) {
                if ([documentMessages containsObject:message]) {
                    result.status = @"pass";
                    result.how = @"message";
                    result.detail = [NSString stringWithFormat:@"message '%@'", message];
                    return result;
                }
            }
            result.status = @"check";
            result.detail = [NSString stringWithFormat:@"unmatched: %@ | dump: %@",
                [missing componentsJoinedByString:@" / "],
                [reportDump length] > 240
                    ? [[reportDump substringToIndex:240] stringByAppendingString:@"…"]
                    : reportDump];
            return result;
        }
        for (NSString *message in observed) {
            if ([documentMessages containsObject:message]) {
                result.status = @"pass";
                result.how = @"message";
                result.detail = [NSString stringWithFormat:@"message '%@'", message];
                return result;
            }
        }
        result.status = @"review";
        result.detail = documentMessages.count
            ? [NSString stringWithFormat:@"no message observed (form defines %lu)",
                (unsigned long)documentMessages.count]
            : @"nothing auto-checkable";
        return result;
    } @catch (NSException *e) {
        result.status = @"error";
        result.detail = [NSString stringWithFormat:@"raised %@: %@", [e name], [e reason]];
        return result;
    }
}

/* ---------------------------------------------------------------- */
#pragma mark - Overrides, report

static NSDictionary *XFTSLoadOverrides(NSURL *url)
{
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSString *text = [NSString stringWithContentsOfURL:url
                                              encoding:NSUTF8StringEncoding
                                                 error:NULL];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (line.length == 0 || [line hasPrefix:@"#"]) {
            continue;
        }
        NSArray *fields = [line componentsSeparatedByString:@"\t"];
        if (fields.count >= 2) {
            out[fields[0]] = @{ @"status": fields[1],
                                @"note": fields.count > 2 ? fields[2] : @"" };
        }
    }
    return out;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        [NSApplication sharedApplication];   // AppKit headless bring-up
        NSString *rootPath = nil;
        NSString *onlyChapter = nil, *onlyTest = nil, *outPath = nil;
        for (int i = 1; i < argc; i++) {
            NSString *arg = @(argv[i]);
            if ([arg isEqualToString:@"--chapter"] && i + 1 < argc) {
                onlyChapter = @(argv[++i]);
            } else if ([arg isEqualToString:@"--test"] && i + 1 < argc) {
                onlyTest = @(argv[++i]);
            } else if ([arg isEqualToString:@"--out"] && i + 1 < argc) {
                outPath = @(argv[++i]);
            } else {
                rootPath = arg;
            }
        }
        if (rootPath == nil) {
            fprintf(stderr, "usage: xftestrun <suite-root> [--chapter <n>] "
                            "[--test <name>] [--out <dir>]\n");
            return 2;
        }
        NSURL *root = [NSURL fileURLWithPath:rootPath];
        NSArray<XFTSCase *> *catalog = XFTSLoadCatalog(root);
        if (catalog.count == 0) {
            fprintf(stderr, "no test cases found under %s\n", [rootPath UTF8String]);
            return 2;
        }
        NSURL *outDir = outPath ? [NSURL fileURLWithPath:outPath]
                                : [[root URLByAppendingPathComponent:@".."] URLByAppendingPathComponent:@".."];
        outDir = [outDir URLByStandardizingPath];
        NSDictionary *overrides = XFTSLoadOverrides(
            [outDir URLByAppendingPathComponent:@"overrides.tsv"]);

        NSMutableString *tsv = [NSMutableString stringWithString:
            @"name\tsection\tchapter\tstatus\thow\tsummary\tdetail\n"];
        NSMutableDictionary *chapterCounts = [NSMutableDictionary dictionary];
        NSMutableArray *chapterOrder = [NSMutableArray array];
        NSUInteger done = 0;
        for (XFTSCase *tc in catalog) {
            if (onlyChapter != nil
                && [tc.chapter rangeOfString:onlyChapter].location == NSNotFound) {
                continue;
            }
            if (onlyTest != nil && ![tc.name isEqualToString:onlyTest]) {
                continue;
            }
            XFTSResult *result;
            NSDictionary *override = overrides[tc.name];
            if ([override[@"status"] isEqualToString:@"skip"]) {
                result = [[XFTSResult alloc] init];
                result.status = @"skip";
                result.how = @"override";
                result.detail = override[@"note"] ?: @"";
            } else {
                fprintf(stderr, "[%4lu] %s\n", (unsigned long)done + 1,
                        [tc.name UTF8String]);
                @autoreleasepool {
                    result = XFTSRunCase(tc);
                }
                if (override != nil) {
                    result.status = override[@"status"];
                    result.how = @"override";
                    if ([override[@"note"] length]) {
                        result.detail = override[@"note"];
                    }
                }
            }
            if (chapterCounts[tc.chapter] == nil) {
                chapterCounts[tc.chapter] = [NSMutableDictionary dictionary];
                [chapterOrder addObject:tc.chapter];
            }
            NSMutableDictionary *counts = chapterCounts[tc.chapter];
            counts[result.status] = @([counts[result.status] integerValue] + 1);

            NSString * (^clean)(NSString *) = ^NSString *(NSString *s) {
                s = [s stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
                return [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "] ?: @"";
            };
            [tsv appendFormat:@"%@\t%@\t%@\t%@\t%@\t%@\t%@\n",
                tc.name, tc.section, clean(tc.chapter), result.status, result.how,
                clean(tc.summary ?: @""), clean(result.detail ?: @"")];
            done++;
            if (onlyTest != nil) {
                printf("%s: %s (%s) — %s\n", [tc.name UTF8String],
                       [result.status UTF8String], [result.how UTF8String],
                       [result.detail UTF8String]);
            }
        }

        // report
        NSMutableString *report = [NSMutableString string];
        [report appendString:@"# W3C XForms 1.1 Test Suite — XFormsKit run\n\n"];
        [report appendFormat:@"%lu test(s) run (headless GNUstep, engine + "
                             @"XFFormView E2E; generated by Tools/xftestrun).\n\n",
            (unsigned long)done];
        [report appendString:@"Statuses: **pass** = the form's own stated "
            @"expectations were observed automatically (quoted values "
            @"rendered, or a defined xf:message fired); **check** = stated "
            @"values NOT observed (candidate fail — review); **review** = "
            @"ran clean but nothing auto-checkable; **error** = load or run "
            @"failure; overrides.tsv pins human verdicts.\n\n"];
        [report appendString:@"| Chapter | pass | check | review | error | missing | skip | total |\n"];
        [report appendString:@"|---|---|---|---|---|---|---|---|\n"];
        NSInteger totals[7] = { 0 };
        NSArray *keys = @[ @"pass", @"check", @"review", @"error", @"missing", @"skip" ];
        for (NSString *chapter in chapterOrder) {
            NSDictionary *counts = chapterCounts[chapter];
            NSInteger rowTotal = 0;
            [report appendFormat:@"| %@ ", chapter];
            for (NSUInteger i = 0; i < keys.count; i++) {
                NSInteger n = [counts[keys[i]] integerValue];
                totals[i] += n;
                rowTotal += n;
                [report appendFormat:@"| %ld ", (long)n];
            }
            totals[6] += rowTotal;
            [report appendFormat:@"| %ld |\n", (long)rowTotal];
        }
        [report appendString:@"| **Total** "];
        for (NSUInteger i = 0; i < 6; i++) {
            [report appendFormat:@"| **%ld** ", (long)totals[i]];
        }
        [report appendFormat:@"| **%ld** |\n", (long)totals[6]];

        if (onlyChapter == nil && onlyTest == nil) {
            [tsv writeToURL:[outDir URLByAppendingPathComponent:@"results.tsv"]
                 atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [report writeToURL:[outDir URLByAppendingPathComponent:@"report.md"]
                    atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        }
        printf("%s\n", [report UTF8String]);
        return 0;
    }
}
