#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFSubmission.h>
#import <XFormsKit/XFSubmissionTransport.h>
#import <XFormsKit/XFSendAction.h>
#import <XFormsKit/XFLoadAction.h>
#import <XFormsKit/XFXML.h>
#import <XFormsKit/XFNodeState.h>

@interface XFSubmissionTests : XCTestCase
@end

@implementation XFSubmissionTests

- (XFProcessor *)form:(NSString *)modelBody extra:(NSString *)extra error:(NSError **)error
{
    NSString *xml =
        [NSString stringWithFormat:
         @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
         @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
         @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
         @"  <xf:model id=\"m\">%@</xf:model>%@"
         @"</html>", modelBody, extra ?: @""];
    return [XFProcessor processorWithXMLString:xml error:error];
}

- (void)send:(XFProcessor *)p identifier:(NSString *)identifier
{
    XFAbstractAction *action = [p actionWithIdentifier:identifier];
    XCTAssertNotNil(action);
    [action executeWithContextNode:[[p.model defaultInstance] documentElement] event:nil];
}

- (void)testSubmissionCollectedAndDefaulted
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      @"<xf:submission id=\"save\" resource=\"http://example.test/save\" method=\"put\" replace=\"none\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertEqual(p.model.submissions.count, (NSUInteger)1);
    XCTAssertEqual(p.model.defaultSubmission, p.model.submissions.firstObject);
    XCTAssertEqualObjects(p.model.defaultSubmission.identifier, @"save");
    XCTAssertEqualObjects(p.model.defaultSubmission.method, @"put");
    XCTAssertEqualObjects(p.model.defaultSubmission.replace, @"none");
}

- (void)testSendPostsXMLAndReplacesInstance
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance id=\"data\"><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/echo\" method=\"post\" replace=\"instance\" instance=\"data\"/>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);

    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setXML:@"<data xmlns=\"\"><n>Bob</n></data>" forURL:@"http://example.test/echo"];
    p.model.transport = map;

    [self send:p identifier:@"go"];

    XCTAssertEqualObjects(map.lastRequest.method, @"post");
    XCTAssertEqualObjects(map.lastRequest.URLString, @"http://example.test/echo");
    XCTAssertTrue([map.lastRequest.body containsString:@"Ada"]);
    XCTAssertEqualObjects(map.lastRequest.mediaType, @"application/xml");

    NSXMLNode *n = [[[p.model defaultInstance] documentElement] elementsForName:@"n"].firstObject;
    XCTAssertEqualObjects([XFXML stringValueOfNode:n], @"Bob");
    XCTAssertEqualObjects(p.model.defaultSubmission.lastEventContext[@"error-type"], nil);
    XCTAssertEqualObjects(p.model.defaultSubmission.lastEventContext[@"resource-uri"], @"http://example.test/echo");
}

- (void)testSubmitDoneHandlerRuns
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n><ok/></data></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/ok\" method=\"post\" replace=\"none\">"
                      @"  <xf:setvalue ev:event=\"xforms-submit-done\" ref=\"ok\" value=\"'yes'\"/>"
                      @"</xf:submission>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:204 body:@"" forURL:@"http://example.test/ok"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    NSXMLNode *ok = [[[p.model defaultInstance] documentElement] elementsForName:@"ok"].firstObject;
    XCTAssertEqualObjects([XFXML stringValueOfNode:ok], @"yes");
}

- (void)testResourceErrorDispatchesSubmitError
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n><err/></data></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/missing\" method=\"get\" serialization=\"none\" replace=\"none\">"
                      @"  <xf:setvalue ev:event=\"xforms-submit-error\" ref=\"err\" value=\"'no'\"/>"
                      @"</xf:submission>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    XCTAssertEqualObjects(p.model.defaultSubmission.lastEventContext[@"error-type"], @"resource-error");
    NSXMLNode *err = [[[p.model defaultInstance] documentElement] elementsForName:@"err"].firstObject;
    XCTAssertEqualObjects([XFXML stringValueOfNode:err], @"no");
}

- (void)testValidationErrorBlocksSubmit
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n/></data></xf:instance>"
                      @"<xf:bind ref=\"n\" required=\"true()\"/>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/save\" method=\"post\" replace=\"none\"/>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:200 body:@"" forURL:@"http://example.test/save"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    XCTAssertEqualObjects(p.model.defaultSubmission.lastEventContext[@"error-type"], @"validation-error");
    XCTAssertNil(map.lastRequest);
}

- (void)testGetAppendsUrlencodedQuery
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><q>hello world</q></data></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/search\" method=\"get\" replace=\"none\"/>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:200 body:@"" forURL:@"http://example.test/search"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    XCTAssertEqualObjects(map.lastRequest.method, @"get");
    XCTAssertEqualObjects(map.lastRequest.URLString, @"http://example.test/search?q=hello%20world");
}

- (void)testRelevantOmitsNonRelevantSubtree
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><keep>1</keep><drop>secret</drop></data></xf:instance>"
                      @"<xf:bind ref=\"drop\" relevant=\"false()\"/>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/save\" method=\"post\" replace=\"none\"/>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:204 body:@"" forURL:@"http://example.test/save"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    XCTAssertTrue([map.lastRequest.body containsString:@"keep"]);
    XCTAssertFalse([map.lastRequest.body containsString:@"secret"]);
}

- (void)testReplaceTextWritesTargetref
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/txt\" method=\"post\" serialization=\"none\" replace=\"text\" targetref=\"n\"/>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:200 body:@"Zoe" forURL:@"http://example.test/txt"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    NSXMLNode *n = [[[p.model defaultInstance] documentElement] elementsForName:@"n"].firstObject;
    XCTAssertEqualObjects([XFXML stringValueOfNode:n], @"Zoe");
}

- (void)testHeadersAndResourceChild
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><ep>http://example.test/h</ep></data></xf:instance>"
                      @"<xf:submission id=\"s\" method=\"post\" replace=\"none\">"
                      @"  <xf:resource value=\"ep\"/>"
                      @"  <xf:header>"
                      @"    <xf:name>X-Token</xf:name>"
                      @"    <xf:value>abc</xf:value>"
                      @"  </xf:header>"
                      @"</xf:submission>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:204 body:@"" forURL:@"http://example.test/h"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    XCTAssertEqualObjects(map.lastRequest.URLString, @"http://example.test/h");
    XCTAssertEqualObjects(map.lastRequest.headers[@"X-Token"], @"abc");
}

- (void)testCancelSubmitDefaultAction
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/save\" method=\"post\" replace=\"none\">"
                      @"  <xf:action ev:event=\"xforms-submit\" ev:defaultAction=\"cancel\"/>"
                      @"</xf:submission>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:204 body:@"" forURL:@"http://example.test/save"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    XCTAssertNil(map.lastRequest);
}

- (void)testSendWithoutSubmissionIdUsesDefault
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/d\" method=\"put\" replace=\"none\"/>"
                      @"<xf:send id=\"go\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:204 body:@"" forURL:@"http://example.test/d"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    XCTAssertEqualObjects(map.lastRequest.method, @"put");
}

- (void)testLoadRecordsResource
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      @"<xf:load id=\"go\" ev:event=\"xforms-ready\" resource=\"http://example.test/page\" show=\"new\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFLoadAction *load = (XFLoadAction *)[p actionWithIdentifier:@"go"];
    XCTAssertEqualObjects(load.lastResource, @"http://example.test/page");
    XCTAssertEqualObjects(load.show, @"new");
    XCTAssertTrue([load wasInvokedForEvent:@"xforms-ready"]);
}

- (void)testLoadReplacesInstance
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance id=\"data\"><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      @"<xf:load id=\"go\" resource=\"http://example.test/doc.xml\" instance=\"data\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setXML:@"<data xmlns=\"\"><n>Loaded</n></data>" forURL:@"http://example.test/doc.xml"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    NSXMLNode *n = [[[p.model defaultInstance] documentElement] elementsForName:@"n"].firstObject;
    XCTAssertEqualObjects([XFXML stringValueOfNode:n], @"Loaded");
    XFLoadAction *load = (XFLoadAction *)[p actionWithIdentifier:@"go"];
    XCTAssertEqualObjects(load.lastEventContext[@"resource-uri"], @"http://example.test/doc.xml");
}

- (void)testRefBindingSubmitsSubset
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><inner><n>only</n></inner><other>nope</other></data></xf:instance>"
                      @"<xf:submission id=\"s\" ref=\"inner\" resource=\"http://example.test/part\" method=\"post\" replace=\"none\"/>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:204 body:@"" forURL:@"http://example.test/part"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    XCTAssertTrue([map.lastRequest.body containsString:@"only"]);
    XCTAssertFalse([map.lastRequest.body containsString:@"nope"]);
}

@end
