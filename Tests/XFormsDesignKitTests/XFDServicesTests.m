/* What the designer's parts are built on, without a window: the rich
   text token transforms, the location-path step model, the XPath
   highlighter's tokens, the predicate preview, the submission tester's
   core, the events console's log and its duplicate-id scan, the schema
   paths and the event property table.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFXMLTypes.h>
#import <XFormsKit/XFXMLEvents.h>
#import "XFormsDesignKit.h"
#import "XFDXPathField.h"
#import "XFDRichTextField.h"
#import "XFDSubmissionTester.h"

@interface XFDServicesTests : XCTestCase
@end

@implementation XFDServicesTests

- (XFProcessor *)processorOf:(NSString *)xml
{
    NSError *error = nil;
    XFProcessor *processor = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(processor, @"%@", error);
    return processor;
}

- (void)testOutputTokens
{
    // an xf:output value= rides the rich view as a ⟦expr⟧ token and comes
    // back as the same element
    NSString *tokenized = XFDTokenizeFragment(@"Total: <strong>sum</strong> <xf:output value=\"../price\"/>");
    XCTAssertTrue([tokenized containsString:@"⟦../price⟧"]);
    XCTAssertFalse([tokenized containsString:@"output"]);
    NSString *back = XFDDetokenizeFragment(tokenized);
    XCTAssertTrue([back containsString:@"<xf:output value=\"../price\""]);
    XCTAssertTrue([back containsString:@"<strong>sum</strong>"]);
    XCTAssertFalse([XFDDetokenizeFragment(@"a ⟦b") containsString:@"output"], @"an unmatched bracket stays text");
}

- (void)testLocationPathSteps
{
    NSDictionary *split = XFDSplitLocationPath(@"../line[2]/@qty");
    NSArray *steps = split[@"steps"];
    XCTAssertEqual(steps.count, 3u);
    XCTAssertEqualObjects(steps[0][@"axis"], @"parent");
    XCTAssertEqualObjects(steps[1][@"predicates"], @"[2]");
    XCTAssertEqualObjects(steps[2][@"axis"], @"attribute");
    XCTAssertEqualObjects(steps[2][@"test"], @"qty");
    XCTAssertEqualObjects(XFDJoinLocationPath(split), @"../line[2]/@qty");

    split = XFDSplitLocationPath(@"instance('main')/order/item[@sku='a[1]']/price");
    XCTAssertEqualObjects(split[@"start"], @"instance");
    XCTAssertEqualObjects(split[@"instance"], @"main");
    XCTAssertEqual([split[@"steps"] count], 3u);
    XCTAssertEqualObjects(XFDJoinLocationPath(split), @"instance('main')/order/item[@sku = 'a[1]']/price",
                          @"predicates spelled as the engine's AST spells them");

    for (NSString *computed in @[ @"concat(a,b)", @"a | b", @"../in - ../out", @"a[1" ]) {
        XCTAssertNil(XFDSplitLocationPath(computed), @"%@ is no location path", computed);
    }
    split = XFDSplitLocationPath(@"//name");
    XCTAssertEqual([split[@"steps"] count], 2u);
    XCTAssertEqualObjects(split[@"steps"][0][@"axis"], @"descendant-or-self");
    XCTAssertEqualObjects(XFDSplitLocationPath(@"/data/ancestor-or-self::node()[position()=1]")[@"start"], @"root");
}

- (void)testHighlightTokensAreTheLexers
{
    NSMutableArray *kinds = [NSMutableArray array];
    for (NSDictionary *token in [XFXPath highlightTokensForString:@"instance('m')/a div $x"]) {
        [kinds addObject:token[@"kind"]];
    }
    XCTAssertEqualObjects(kinds, (@[ @"function", @"punct", @"string", @"punct", @"punct", @"name",
                                     @"operator", @"variable", @"variable" ]));
}

- (void)testPredicatePreview
{
    XFProcessor *p = [self processorOf:
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"<head><xf:model><xf:instance><data xmlns=\"\">"
        @"<item n=\"1\">a</item><item n=\"2\">b</item><item n=\"3\">c</item>"
        @"</data></xf:instance></xf:model></head><body/></html>"];
    XFXMLNode *root = [[p defaultInstance] documentElement];
    NSDictionary *pre = XFDPredicatePreview(@"item", @"@n > 1", nil, root, p.model);
    XCTAssertTrue([pre[@"ok"] boolValue]);
    XCTAssertEqualObjects(pre[@"normalized"], @"[@n > 1]");
    XCTAssertEqual([pre[@"total"] unsignedIntegerValue], 3u);
    XCTAssertEqual([pre[@"matching"] unsignedIntegerValue], 2u);
    XCTAssertEqual([pre[@"rows"] count], 3u);
    XCTAssertFalse([[pre[@"rows"] firstObject][@"match"] boolValue]);
    XCTAssertTrue([[pre[@"rows"] lastObject][@"match"] boolValue]);

    pre = XFDPredicatePreview(@"item", @"[position() = last()]", nil, root, p.model);
    XCTAssertTrue([pre[@"ok"] boolValue]);
    XCTAssertEqual([pre[@"matching"] unsignedIntegerValue], 1u);
    XCTAssertFalse([XFDPredicatePreview(@"item", @"[@n >]", nil, root, p.model)[@"ok"] boolValue], @"garbage");
    pre = XFDPredicatePreview(@"item", @"", nil, root, p.model);
    XCTAssertTrue([pre[@"ok"] boolValue]);
    XCTAssertEqual([pre[@"matching"] unsignedIntegerValue], 3u);
    XCTAssertEqual([pre[@"normalized"] length], 0u);
}

- (void)testTheSubmissionTestersCore
{
    // the echo transport round-trips replace="instance" through the REAL
    // submit path, extra headers go in as a host session's would, and
    // offline is the xforms-submit-error path
    XFProcessor *p = [self processorOf:
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"<head><xf:model><xf:instance id=\"d\"><data xmlns=\"\"><n>ping</n></data></xf:instance>"
        @"<xf:submission id=\"s\" resource=\"http://echo.test/x\" method=\"post\""
        @"  replace=\"instance\" instance=\"d\"/>"
        @"</xf:model></head><body/></html>"];
    XFSubmission *submission = p.model.defaultSubmission;
    XFSubmissionRequest *preview = [submission previewRequest];
    XCTAssertEqualObjects(preview.URLString, @"http://echo.test/x");
    XCTAssertTrue([(preview.body ?: @"") containsString:@"<n>ping</n>"]);
    NSDictionary *run = XFDPerformSubmission(submission, [[XFDEchoTransport alloc] init], @{ @"X-Session": @"abc" });
    XCTAssertEqualObjects(run[@"outcome"], @"done");
    XCTAssertEqualObjects(((XFSubmissionRequest *)run[@"request"]).headers[@"X-Session"], @"abc");
    XCTAssertEqualObjects([XFXML stringValueOfNode:[[submission targetInstance] documentElement]], @"ping");
    NSDictionary *offline = XFDPerformSubmission(submission, [[XFMapSubmissionTransport alloc] init], nil);
    XCTAssertEqualObjects(offline[@"outcome"], @"error");
}

- (void)testTheEventsConsolesLog
{
    XFProcessor *p = [self processorOf:
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @" xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"<head><xf:model id=\"m\"><xf:instance><data xmlns=\"\"><n>1</n></data></xf:instance>"
        @"<xf:action id=\"go\" ev:event=\"ping\"><xf:setvalue ref=\"n\" value=\"'2'\"/></xf:action>"
        @"</xf:model></head><body><p id=\"dup\"/><p id=\"dup\"/></body></html>"];
    XFDEventsLog *log = [[XFDEventsLog alloc] init];
    [log install];
    [XFXMLEvents dispatch:p.model name:@"ping"];
    [log uninstall];
    BOOL sawDispatch = NO, sawCaptured = NO, sawSetvalue = NO;
    for (XFDEventsLogEntry *e in log.entries) {
        sawDispatch = sawDispatch || [e.message hasPrefix:@"Dispatching event ping"];
        sawCaptured = sawCaptured || [e.message hasPrefix:@"Captured event ping"];
        sawSetvalue = sawSetvalue || [e.message isEqualToString:@"Setvalue n = 2"];
    }
    XCTAssertTrue(sawDispatch && sawCaptured && sawSetvalue, @"%lu lines", (unsigned long)log.entries.count);
    XCTAssertEqual([log entriesMatchingKind:XFTraceKindAction substring:@"setvalue"].count, 1u);
    XCTAssertEqual([log entriesMatchingKind:-1 substring:@"nothing-matches-this"].count, 0u);
    XCTAssertTrue([[log tracelogXMLString] containsString:@"Setvalue n = 2"]);
    NSUInteger frozen = log.entries.count;
    [XFXMLEvents dispatch:p.model name:@"ping"];
    XCTAssertEqual(log.entries.count, frozen, @"uninstalled, the trace is a no-op");
    XCTAssertEqualObjects(XFDDuplicateIDsInDocument(p.hostDocument), @[ @"dup" ]);

    // the console's view starts and stops its log as the sink
    XFDEventsConsoleViewController *console = [[XFDEventsConsoleViewController alloc] init];
    [console view];
    [console startWithHostDocument:p.hostDocument];
    XCTAssertTrue(console.running);
    [XFXMLEvents dispatch:p.model name:@"ping"];
    [console stop];
    XCTAssertFalse(console.running);
    BOOL warned = NO;
    for (XFDEventsLogEntry *e in console.log.entries) {
        warned = warned || [e.message containsString:@"Duplicate ids: dup"];
    }
    XCTAssertTrue(warned, @"the duplicate-id warning when it starts");
    XCTAssertGreaterThan([console.table numberOfRows], 1);
}

- (void)testSchemaPathsAndEventProperties
{
    XFProcessor *p = [self processorOf:
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"<head><xf:model><xf:instance><data xmlns=\"\"><name/><age/></data></xf:instance></xf:model></head>"
        @"<body/></html>"];
    NSArray *paths = XFDSchemaPathsFromNode([[p defaultInstance] documentElement], 40);
    XCTAssertTrue([paths containsObject:@"name"], @"%@", paths);
    XCTAssertTrue([XFDEventContextProperties(@"xforms-submit-error") containsObject:@"response-status-code"]);
}

@end
