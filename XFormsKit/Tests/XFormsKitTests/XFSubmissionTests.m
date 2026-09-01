#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFAbstractAction.h>
#import <XFormsKit/XFTriggerControl.h>
#import <XFormsKit/XFSubmitControl.h>
#import <XFormsKit/XFSubmission.h>
#import <XFormsKit/XFSubmissionTransport.h>
#import <XFormsKit/XFSendAction.h>
#import <XFormsKit/XFLoadAction.h>
#import <XFormsKit/XFXML.h>
#import <XFormsKit/XFNodeState.h>
#import <XFormsKit/XFUploadControl.h>


#pragma mark - Transport policy test doubles

/// Scripted HTTP conversation: performSingleRequest pops the next canned
/// response and records the hop it was asked to make — the POLICY above
/// it (redirects, cookies, challenges) is what the tests observe.
@interface XFScriptedHTTPTransport : XFHTTPSubmissionTransport
@property (nonatomic, strong) NSMutableArray<XFSubmissionResponse *> *script;
@property (nonatomic, strong) NSMutableArray<XFSubmissionRequest *> *hops;
@property (nonatomic, copy) NSString *fixedCNonce;
@end

@implementation XFScriptedHTTPTransport

- (instancetype)init
{
    self = [super init];
    if (self) {
        _script = [NSMutableArray array];
        _hops = [NSMutableArray array];
    }
    return self;
}

- (void)addResponse:(NSInteger)status headers:(NSDictionary *)headers body:(NSString *)body
{
    XFSubmissionResponse *r = [[XFSubmissionResponse alloc] init];
    r.statusCode = status;
    r.headers = headers ?: @{};
    r.body = body ?: @"";
    [self.script addObject:r];
}

- (XFSubmissionResponse *)performSingleRequest:(XFSubmissionRequest *)request
                                         error:(NSError **)error
{
    (void)error;
    [self.hops addObject:request];
    if (self.script.count == 0) {
        XFSubmissionResponse *ok = [[XFSubmissionResponse alloc] init];
        ok.statusCode = 200;
        ok.body = @"";
        return ok;
    }
    XFSubmissionResponse *next = self.script.firstObject;
    [self.script removeObjectAtIndex:0];
    return next;
}

- (NSString *)makeCNonce
{
    return self.fixedCNonce ?: [super makeCNonce];
}

@end

/// Fixed-credential host port.
@interface XFTestAuthProvider : NSObject <XFSubmissionAuth>
@property (nonatomic, copy) NSString *user;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, strong) NSURLProtectionSpace *lastSpace;
@end

@implementation XFTestAuthProvider

- (NSURLCredential *)credentialForProtectionSpace:(NSURLProtectionSpace *)space
                                          request:(XFSubmissionRequest *)request
{
    (void)request;
    self.lastSpace = space;
    if (self.user.length == 0) {
        return nil;
    }
    return [NSURLCredential credentialWithUser:self.user
                                      password:self.password ?: @""
                                   persistence:NSURLCredentialPersistenceNone];
}

@end

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

- (void)testHeaderValueXPath
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><tok>secret</tok></data></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/h2\" method=\"post\" replace=\"none\">"
                      @"  <xf:header name=\"X-Auth\">"
                      @"    <xf:value value=\"concat('Bearer ', tok)\"/>"
                      @"  </xf:header>"
                      @"</xf:submission>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:204 body:@"" forURL:@"http://example.test/h2"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    XCTAssertEqualObjects(map.lastRequest.headers[@"X-Auth"], @"Bearer secret");
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

- (void)testMultipartFormDataIncludesFilePart
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><title>pic</title><bin/></data></xf:instance>"
                      @"<xf:bind ref=\"bin\" type=\"xsd:base64Binary\"/>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/up\" method=\"post\""
                      @"   serialization=\"multipart/form-data\" replace=\"none\"/>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:
                      @"<xf:upload ref=\"bin\"><xf:label>F</xf:label></xf:upload>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFUploadControl *up = nil;
    for (XFControl *c in p.controls) {
        if ([c isKindOfClass:[XFUploadControl class]]) { up = (XFUploadControl *)c; break; }
    }
    NSData *bytes = [@"XYZ" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([up commitFileData:bytes fileName:@"x.bin" mediaType:@"application/octet-stream" error:&error], @"%@", error);
    // the empty xsd:base64Binary node was invalid at init (G-12); a UI commit
    // always runs the deferred cycle so the node is revalidated before send
    [p controlDidChangeValue:up];

    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:204 body:@"" forURL:@"http://example.test/up"];
    p.model.transport = map;
    [self send:p identifier:@"go"];

    XCTAssertTrue([map.lastRequest.mediaType hasPrefix:@"multipart/form-data"]);
    NSString *body = map.lastRequest.body;
    XCTAssertTrue([body containsString:@"name=\"title\""]);
    XCTAssertTrue([body containsString:@"pic"]);
    XCTAssertTrue([body containsString:@"filename=\"x.bin\""]);
    XCTAssertTrue([body containsString:@"XYZ"]);
    XCTAssertNotNil(map.lastRequest.bodyData);
}

- (void)testTargetrefReplacesSubtree
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance id=\"data\"><data xmlns=\"\"><keep>yes</keep><slot><n>Ada</n></slot></data></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/part\" method=\"post\""
                      @"   replace=\"instance\" instance=\"data\" targetref=\"slot\"/>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setXML:@"<slot xmlns=\"\"><n>Bob</n></slot>" forURL:@"http://example.test/part"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    NSXMLElement *root = [[p.model defaultInstance] documentElement];
    XCTAssertEqualObjects([XFXML stringValueOfNode:[root elementsForName:@"keep"].firstObject], @"yes");
    XCTAssertEqualObjects([XFXML stringValueOfNode:
                          [[[root elementsForName:@"slot"] firstObject] elementsForName:@"n"].firstObject],
                          @"Bob");
}

- (void)testReplaceTextTargetref
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><msg>old</msg></data></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/txt\" method=\"post\""
                      @"   replace=\"text\" targetref=\"msg\"/>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:200 body:@"hello-text" forURL:@"http://example.test/txt"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    NSXMLNode *msg = [[[p.model defaultInstance] documentElement] elementsForName:@"msg"].firstObject;
    XCTAssertEqualObjects([XFXML stringValueOfNode:msg], @"hello-text");
    XCTAssertEqualObjects(p.model.defaultSubmission.lastEventContext[@"response-status-code"], @200);
}

- (void)testReplaceAllRecordsBody
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/page\" method=\"post\" replace=\"all\"/>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:200 body:@"<html>new</html>" forURL:@"http://example.test/page"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    XCTAssertEqualObjects(p.model.defaultSubmission.lastAllReplacement, @"<html>new</html>");
}

- (void)testAsyncModeCompletesOnRunLoop
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance id=\"data\"><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/echo\" method=\"post\""
                      @"   replace=\"instance\" instance=\"data\" mode=\"asynchronous\"/>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setXML:@"<data xmlns=\"\"><n>Async</n></data>" forURL:@"http://example.test/echo"];
    p.model.transport = map;
    XFSubmission *sub = p.model.defaultSubmission;
    XCTAssertTrue(sub.asynchronous);
    [self send:p identifier:@"go"];
    XCTAssertTrue([sub waitUntilFinished:2.0], @"async submission did not finish");
    NSXMLNode *n = [[[p.model defaultInstance] documentElement] elementsForName:@"n"].firstObject;
    XCTAssertEqualObjects([XFXML stringValueOfNode:n], @"Async");
}


- (void)testCompoundMethodsPostWithProperContentType // G-07
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      @"<xf:submission id=\"u\" resource=\"http://example.test/u\" method=\"urlencoded-post\" replace=\"none\"/>"
                      @"<xf:submission id=\"m\" resource=\"http://example.test/m\" method=\"multipart-post\" replace=\"none\"/>"
                      @"<xf:submission id=\"f\" resource=\"http://example.test/f\" method=\"form-data-post\" replace=\"none\"/>"
                      @"<xf:submission id=\"g\" resource=\"http://example.test/g\" method=\"get\" replace=\"instance\"/>"
                      @"<xf:submission id=\"t\" resource=\"http://example.test/t\" method=\"get\" replace=\"none\"/>"
                      @"<xf:submission id=\"a\" resource=\"http://example.test/a\" method=\"get\" replace=\"none\">"
                      @"  <xf:header><xf:name>Accept</xf:name><xf:value>text/csv</xf:value></xf:header>"
                      @"</xf:submission>"
                      @"<xf:send id=\"su\" submission=\"u\"/><xf:send id=\"sm\" submission=\"m\"/>"
                      @"<xf:send id=\"sf\" submission=\"f\"/><xf:send id=\"sg\" submission=\"g\"/>"
                      @"<xf:send id=\"st\" submission=\"t\"/><xf:send id=\"sa\" submission=\"a\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    for (NSString *u in @[ @"u", @"m", @"f", @"g", @"t", @"a" ]) {
        [map setXML:@"<data xmlns=\"\"><n>x</n></data>" forURL:[@"http://example.test/" stringByAppendingString:u]];
    }
    p.model.transport = map;

    [self send:p identifier:@"su"];
    XCTAssertEqualObjects(map.lastRequest.method, @"post", @"urlencoded-post is an HTTP POST");
    XCTAssertEqualObjects(map.lastRequest.mediaType, @"application/x-www-form-urlencoded");
    XCTAssertEqualObjects(map.lastRequest.body, @"n=Ada");

    [self send:p identifier:@"sm"];
    XCTAssertEqualObjects(map.lastRequest.method, @"post");
    XCTAssertTrue([map.lastRequest.mediaType hasPrefix:@"multipart/related"], @"%@", map.lastRequest.mediaType);

    [self send:p identifier:@"sf"];
    XCTAssertEqualObjects(map.lastRequest.method, @"post");
    XCTAssertTrue([map.lastRequest.mediaType hasPrefix:@"multipart/form-data"], @"%@", map.lastRequest.mediaType);

    [self send:p identifier:@"sg"];
    XCTAssertEqualObjects(map.lastRequest.method, @"get");
    XCTAssertEqualObjects(map.lastRequest.headers[@"Accept"], @"application/xml,text/xml");
    [self send:p identifier:@"st"];
    XCTAssertEqualObjects(map.lastRequest.headers[@"Accept"], @"text/plain");
    [self send:p identifier:@"sa"];
    XCTAssertEqualObjects(map.lastRequest.headers[@"Accept"], @"text/csv", @"an explicit Accept header wins");
}

- (void)testReplaceInstanceTargetsInstanceOfSubmittedNode // G-08
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance id=\"main\"><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      @"<xf:instance id=\"other\"><other xmlns=\"\"><v>1</v></other></xf:instance>"
                      @"<xf:submission id=\"s\" ref=\"instance('other')\" resource=\"http://example.test/o\" method=\"post\" replace=\"instance\"/>"
                      @"<xf:submission id=\"d\" resource=\"http://example.test/d\" method=\"post\" replace=\"instance\" instance=\"other\"/>"
                      @"<xf:send id=\"go\" submission=\"s\"/><xf:send id=\"gd\" submission=\"d\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setXML:@"<other xmlns=\"\"><v>2</v></other>" forURL:@"http://example.test/o"];
    [map setXML:@"<other xmlns=\"\"><v>3</v></other>" forURL:@"http://example.test/d"];
    p.model.transport = map;

    // ref points into instance 'other': that instance is replaced, not the default one
    [self send:p identifier:@"go"];
    XCTAssertTrue([map.lastRequest.body containsString:@"<v>1</v>"]);
    NSXMLElement *other = [[p.model instanceWithIdentifier:@"other"] documentElement];
    XCTAssertEqualObjects([XFXML stringValueOfNode:[other elementsForName:@"v"].firstObject], @"2");
    NSXMLElement *main = [[p.model defaultInstance] documentElement];
    XCTAssertEqualObjects([main name], @"data");
    XCTAssertEqualObjects([XFXML stringValueOfNode:[main elementsForName:@"n"].firstObject], @"Ada");

    // no ref + @instance: the default instance is submitted, @instance is replaced
    [self send:p identifier:@"gd"];
    XCTAssertTrue([map.lastRequest.body containsString:@"<n>Ada</n>"], @"%@", map.lastRequest.body);
    other = [[p.model instanceWithIdentifier:@"other"] documentElement];
    XCTAssertEqualObjects([XFXML stringValueOfNode:[other elementsForName:@"v"].firstObject], @"3");
    XCTAssertEqualObjects([[[p.model defaultInstance] documentElement] name], @"data");
}

- (void)testHeaderElementsAreEvaluatedAndCombined
{
    // XsltForms_submission: xf:header with name/value children, @nodeset
    // iteration, @combine (G-17)
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><tok>abc</tok><k>one</k><k>two</k></data></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/h\" method=\"get\" replace=\"none\">"
                      @"  <xf:header><xf:name>X-Token</xf:name><xf:value value=\"tok\"/></xf:header>"
                      @"  <xf:header nodeset=\"k\"><xf:name>X-Key</xf:name><xf:value value=\".\"/></xf:header>"
                      @"  <xf:header combine=\"prepend\"><xf:name>x-key</xf:name><xf:value>zero</xf:value></xf:header>"
                      @"  <xf:header><xf:name>X-Multi</xf:name><xf:value>a</xf:value><xf:value>b</xf:value></xf:header>"
                      @"  <xf:header combine=\"replace\"><xf:name>X-Multi</xf:name><xf:value>c</xf:value></xf:header>"
                      @"</xf:submission>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:204 body:@"" forURL:@"http://example.test/h"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    NSDictionary *h = map.lastRequest.headers;
    XCTAssertEqualObjects(h[@"X-Token"], @"abc");
    XCTAssertEqualObjects(h[@"X-Key"], @"zero,one,two");
    XCTAssertEqualObjects(h[@"X-Multi"], @"c");
}

#pragma mark - P2

- (void)testSubmitControlIfGuardAndTriggerSilence // G-47
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><ok>no</ok><n>1</n></data></xf:instance>"
                      @"<xf:bind nodeset=\"n\" readonly=\"true()\"/>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/s\" method=\"post\" replace=\"none\"/>"
                      @"<xf:action id=\"done\" ev:event=\"xforms-submit-done\"/>"
                      @"<xf:setvalue ev:event=\"allow\" ref=\"ok\" value=\"'yes'\"/>"
                      extra:
                      @"<xf:submit id=\"sb\" submission=\"s\" if=\"ok = 'yes'\"><xf:label>Go</xf:label></xf:submit>"
                      @"<xf:trigger id=\"t\" ref=\"n\"><xf:label>T</xf:label><xf:action id=\"ro\" ev:event=\"xforms-readonly\"/></xf:trigger>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:204 body:@"" forURL:@"http://example.test/s"];
    p.model.transport = map;
    XFTriggerControl *submit = nil, *trigger = nil;
    for (XFControl *c in p.controls) {
        if ([c isKindOfClass:[XFSubmitControl class]]) submit = (XFTriggerControl *)c;
        else if ([c isKindOfClass:[XFTriggerControl class]]) trigger = (XFTriggerControl *)c;
    }
    XCTAssertTrue([submit isTrigger]);
    // triggers never get MIP events
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"ro"] invocationCount], (NSInteger)0);
    XCTAssertEqual(trigger.mipEvents.count, (NSUInteger)0);
    [p activateControl:submit];
    XCTAssertNil(map.lastRequest);
    [XFXMLEvents dispatch:p.model name:@"allow"];
    [p activateControl:submit];
    XCTAssertNotNil(map.lastRequest);
    XCTAssertTrue([[p actionWithIdentifier:@"done"] wasInvokedForEvent:@"xforms-submit-done"]);
}

- (void)testSubmissionSerializationOptions // G-58, G-59
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><a keep=\"1\" drop=\"2\">x &amp; y</a><b>hidden</b><t>old</t></data></xf:instance>"
                      @"<xf:bind nodeset=\"b\" relevant=\"false()\"/>"
                      @"<xf:bind nodeset=\"a/@drop\" relevant=\"false()\"/>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/x\" method=\"post\" replace=\"none\""
                      @"  mediatype=\"text/xml; action=urn:do-it\" cdata-section-elements=\"a\"/>"
                      @"<xf:submission id=\"none\" resource=\"http://example.test/n\" method=\"post\" serialization=\"none\" replace=\"none\"/>"
                      @"<xf:submission id=\"txt\" resource=\"http://example.test/t\" method=\"get\" replace=\"text\"/>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      @"<xf:send id=\"go-txt\" submission=\"txt\"/>"
                      @"<xf:action id=\"done\" ev:event=\"xforms-submit-done\"/>"
                      @"<xf:action id=\"err\" ev:event=\"xforms-submit-error\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFSubmission *none = [p.model submissionWithIdentifier:@"none"];
    XCTAssertFalse(none.validate);
    XCTAssertFalse(none.relevant);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:204 body:@"" forURL:@"http://example.test/x"];
    [map setStatus:200 body:@"plain" forURL:@"http://example.test/t"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    NSString *body = map.lastRequest.body;
    XCTAssertTrue([body containsString:@"<![CDATA[x & y]]>"], @"%@", body);
    XCTAssertFalse([body containsString:@"drop="], @"%@", body);
    XCTAssertTrue([body containsString:@"keep=\"1\""], @"%@", body);
    XCTAssertFalse([body containsString:@"hidden"], @"%@", body);
    XCTAssertEqualObjects(map.lastRequest.headers[@"SOAPAction"], @"urn:do-it");
    // replace="text" without targetref: no-op + submit-done (G-59)
    [self send:p identifier:@"go-txt"];
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"done"] invocationCount], (NSInteger)2);
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"err"] invocationCount], (NSInteger)0);
}

- (void)testJSONResponseReplacesInstanceAsXML // G-55
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance id=\"r\"><data xmlns=\"\"/></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/j\" method=\"get\" replace=\"instance\" instance=\"r\"/>"
                      @"<xf:send id=\"go\" submission=\"s\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    XFSubmissionResponse *resp = [[XFSubmissionResponse alloc] init];
    resp.statusCode = 200;
    resp.body = @"{\"name\":\"Ada\",\"tags\":[\"a\",\"b\"],\"n\":3,\"ok\":true,\"odd key\":1}";
    resp.mediaType = @"application/json; charset=utf-8";
    [map setResponse:resp forURL:@"http://example.test/j"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    NSXMLElement *root = [[p.model instanceWithIdentifier:@"r"] documentElement];
    XCTAssertEqualObjects([root localName], @"anonymous");
    XCTAssertEqualObjects([XFXML stringValueOfNode:[root elementsForName:@"name"].firstObject], @"Ada");
    XCTAssertEqual([root elementsForName:@"tags"].count, (NSUInteger)2);
    XCTAssertEqualObjects([XFXML stringValueOfNode:[root elementsForName:@"ok"].firstObject], @"true");
    XCTAssertEqualObjects([[[root elementsForName:@"n"].firstObject attributeForLocalName:@"type" URI:@"http://www.w3.org/2001/XMLSchema-instance"] stringValue], @"xsd:double");
    XCTAssertEqualObjects([[[root elementsForName:@"________"].firstObject attributeForLocalName:@"fullname" URI:@"http://www.agencexml.com/exml"] stringValue], @"odd key");
}

- (void)testJSONAndCSVSubmissionBodies // G-97
{
    // round trip through json2xml (G-55) and back
    NSString *src = @"{\"name\":\"Ada\",\"age\":36,\"ok\":true,\"tags\":[\"a\",\"b\"],\"addr\":{\"city\":\"Paris\"},\"none\":null,\"empty\":[]}";
    NSString *xml = [XFInstance xmlStringFromJSONData:[src dataUsingEncoding:NSUTF8StringEncoding] error:NULL];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL];
    NSString *json = [XFInstance jsonStringFromNode:[doc rootElement]];
    id parsed = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    XCTAssertEqualObjects(parsed[@"name"], @"Ada");
    XCTAssertEqualObjects(parsed[@"age"], @36);
    XCTAssertEqualObjects(parsed[@"ok"], @YES);
    XCTAssertEqualObjects(parsed[@"tags"], (@[ @"a", @"b" ]));
    XCTAssertEqualObjects(parsed[@"addr"], (@{ @"city": @"Paris" }));
    XCTAssertEqualObjects(parsed[@"empty"], @[]);
    XCTAssertEqualObjects(parsed[@"none"], [NSNull null]);
    // a plain instance submitted with mediatype="application/json"
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><rows xmlns=\"\"><row><a>1.5</a><b>x,y</b></row><row><a>2</a><b>z</b></row></rows></xf:instance>"
                      @"<xf:submission id=\"j\" resource=\"http://example.test/j\" method=\"post\" replace=\"none\" mediatype=\"application/json\"/>"
                      @"<xf:submission id=\"c\" resource=\"http://example.test/c\" method=\"post\" replace=\"none\" mediatype=\"text/csv\" separator=\"; ,\"/>"
                      @"<xf:send id=\"sj\" submission=\"j\"/><xf:send id=\"sc\" submission=\"c\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setXML:@"<ok/>" forURL:@"http://example.test/j"];
    [map setXML:@"<ok/>" forURL:@"http://example.test/c"];
    p.model.transport = map;
    [self send:p identifier:@"sj"];
    XCTAssertEqualObjects(map.lastRequest.mediaType, @"application/json");
    id body = [NSJSONSerialization JSONObjectWithData:[map.lastRequest.body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    XCTAssertEqualObjects(body, (@{ @"rows": @{ @"row": @[ @{ @"a": @"1.5", @"b": @"x,y" }, @{ @"a": @"2", @"b": @"z" } ] } }));
    [self send:p identifier:@"sc"];
    XCTAssertEqualObjects(map.lastRequest.body, @"a;b\n1,5;x,y\n2;z\n");
}

#pragma mark - Transport policy (redirects, cookies, auth)

- (XFSubmissionRequest *)postRequestTo:(NSString *)url
{
    XFSubmissionRequest *r = [[XFSubmissionRequest alloc] init];
    r.method = @"post";
    r.URLString = url;
    r.body = @"<x/>";
    r.mediaType = @"application/xml";
    return r;
}

- (void)testTransportRedirectRules
{
    // 302 on POST: browsers rewrite to GET and never replay the body
    XFScriptedHTTPTransport *t = [[XFScriptedHTTPTransport alloc] init];
    [t addResponse:302 headers:@{ @"Location": @"/moved" } body:nil];
    [t addResponse:200 headers:@{} body:@"ok"];
    XFSubmissionResponse *resp = [t performRequest:
        [self postRequestTo:@"http://one.test/start"] error:NULL];
    XCTAssertEqual(resp.statusCode, (NSInteger)200);
    XCTAssertEqual(t.hops.count, (NSUInteger)2);
    XCTAssertEqualObjects(t.hops[1].URLString, @"http://one.test/moved", @"relative Location resolves");
    XCTAssertEqualObjects([t.hops[1].method lowercaseString], @"get");
    XCTAssertNil(t.hops[1].body, @"no POST body replay through a redirect");

    // 307 preserves the method and the body
    t = [[XFScriptedHTTPTransport alloc] init];
    [t addResponse:307 headers:@{ @"Location": @"http://one.test/again" } body:nil];
    [t addResponse:200 headers:@{} body:@"ok"];
    resp = [t performRequest:[self postRequestTo:@"http://one.test/start"] error:NULL];
    XCTAssertEqualObjects([t.hops[1].method lowercaseString], @"post");
    XCTAssertEqualObjects(t.hops[1].body, @"<x/>");

    // the hop limit returns the final 3xx instead of looping forever
    t = [[XFScriptedHTTPTransport alloc] init];
    t.maxRedirects = 3;
    for (int i = 0; i < 6; i++) {
        [t addResponse:302 headers:@{ @"Location": @"/loop" } body:nil];
    }
    resp = [t performRequest:[self postRequestTo:@"http://one.test/start"] error:NULL];
    XCTAssertEqual(resp.statusCode, (NSInteger)302);
    XCTAssertEqual(t.hops.count, (NSUInteger)4);   // start + 3 hops
}

- (void)testTransportRedirectDropsAuthorizationCrossOrigin
{
    XFScriptedHTTPTransport *t = [[XFScriptedHTTPTransport alloc] init];
    [t addResponse:302 headers:@{ @"Location": @"http://other.test/target" } body:nil];
    [t addResponse:200 headers:@{} body:@"ok"];
    XFSubmissionRequest *req = [self postRequestTo:@"http://one.test/start"];
    req.headers = @{ @"Authorization": @"Bearer secret", @"X-Trace": @"1" };
    [t performRequest:req error:NULL];
    XCTAssertEqualObjects(t.hops[0].headers[@"Authorization"], @"Bearer secret");
    XCTAssertNil(t.hops[1].headers[@"Authorization"],
                 @"credentials never follow a cross-origin redirect");
    XCTAssertEqualObjects(t.hops[1].headers[@"X-Trace"], @"1", @"ordinary headers do");
}

- (void)testTransportCookieJar
{
    XFScriptedHTTPTransport *t = [[XFScriptedHTTPTransport alloc] init];
    [t addResponse:200 headers:@{ @"Set-Cookie": @"sid=abc123; Path=/" } body:@"login"];
    [t addResponse:200 headers:@{} body:@"data"];
    [t addResponse:200 headers:@{} body:@"other"];
    [t performRequest:[self postRequestTo:@"http://api.test/login"] error:NULL];
    [t performRequest:[self postRequestTo:@"http://api.test/data"] error:NULL];
    [t performRequest:[self postRequestTo:@"http://elsewhere.test/x"] error:NULL];
    XCTAssertNil(t.hops[0].headers[@"Cookie"]);
    XCTAssertEqualObjects(t.hops[1].headers[@"Cookie"], @"sid=abc123",
                          @"the jar returns the cookie to its host");
    XCTAssertNil(t.hops[2].headers[@"Cookie"], @"never to another host");

    // Secure cookies stay off plain http (a fresh host: api.test above
    // still holds sid)
    XFCookieJar *jar = t.cookieJar;
    [jar storeCookiesFromHeaders:@{ @"Set-Cookie": @"tok=s3cret; Secure" }
                          forURL:[NSURL URLWithString:@"https://secure.test/login"]];
    XCTAssertNil([jar cookieHeaderForURL:[NSURL URLWithString:@"http://secure.test/data"]]);
    XCTAssertEqualObjects([jar cookieHeaderForURL:[NSURL URLWithString:@"https://secure.test/data"]],
                          @"tok=s3cret");

    // Max-Age=0 deletes
    [jar storeCookiesFromHeaders:@{ @"Set-Cookie": @"tok=; Max-Age=0" }
                          forURL:[NSURL URLWithString:@"https://secure.test/logout"]];
    XCTAssertNil([jar cookieHeaderForURL:[NSURL URLWithString:@"https://secure.test/data"]]);
}

- (void)testProcessorDefaultTransportIsShared
{
    NSError *error = nil;
    XFProcessor *p = [self form:@"<xf:instance><data xmlns=\"\"><n>1</n></data></xf:instance>"
                          extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertNotNil(p.defaultTransport);
    XCTAssertEqual(p.defaultTransport, p.defaultTransport,
                   @"one transport (and one cookie jar) per document");
}

- (void)testTransportBasicAuthOneRetry
{
    XFScriptedHTTPTransport *t = [[XFScriptedHTTPTransport alloc] init];
    XFTestAuthProvider *auth = [[XFTestAuthProvider alloc] init];
    auth.user = @"Aladdin";
    auth.password = @"open sesame";
    t.auth = auth;
    [t addResponse:401 headers:@{ @"WWW-Authenticate": @"Basic realm=\"cave\"" } body:nil];
    [t addResponse:200 headers:@{} body:@"in"];
    XFSubmissionResponse *resp = [t performRequest:
        [self postRequestTo:@"http://one.test/protected"] error:NULL];
    XCTAssertEqual(resp.statusCode, (NSInteger)200);
    XCTAssertEqual(t.hops.count, (NSUInteger)2);
    XCTAssertNil(t.hops[0].headers[@"Authorization"], @"never preemptive by default");
    // RFC 2617's own Basic example pair
    XCTAssertEqualObjects(t.hops[1].headers[@"Authorization"],
                          @"Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==");
    XCTAssertEqualObjects(auth.lastSpace.realm, @"cave");

    // wrong credentials: ONE retry, then the 401 flows out (submit-error)
    t = [[XFScriptedHTTPTransport alloc] init];
    t.auth = auth;
    [t addResponse:401 headers:@{ @"WWW-Authenticate": @"Basic realm=\"cave\"" } body:nil];
    [t addResponse:401 headers:@{ @"WWW-Authenticate": @"Basic realm=\"cave\"" } body:nil];
    resp = [t performRequest:[self postRequestTo:@"http://one.test/protected"] error:NULL];
    XCTAssertEqual(resp.statusCode, (NSInteger)401);
    XCTAssertEqual(t.hops.count, (NSUInteger)2, @"exactly one retry");

    // no host credentials: no retry at all
    t = [[XFScriptedHTTPTransport alloc] init];
    [t addResponse:401 headers:@{ @"WWW-Authenticate": @"Basic realm=\"cave\"" } body:nil];
    resp = [t performRequest:[self postRequestTo:@"http://one.test/protected"] error:NULL];
    XCTAssertEqual(resp.statusCode, (NSInteger)401);
    XCTAssertEqual(t.hops.count, (NSUInteger)1);
}

- (void)testTransportDigestAuthRFC2617Vector
{
    XFScriptedHTTPTransport *t = [[XFScriptedHTTPTransport alloc] init];
    t.fixedCNonce = @"0a4f113b";
    XFTestAuthProvider *auth = [[XFTestAuthProvider alloc] init];
    auth.user = @"Mufasa";
    auth.password = @"Circle Of Life";
    t.auth = auth;
    [t addResponse:401 headers:@{ @"WWW-Authenticate":
        @"Digest realm=\"testrealm@host.com\", qop=\"auth,auth-int\", "
        @"nonce=\"dcd98b7102dd2f0e8b11d0f600bfb0c093\", "
        @"opaque=\"5ccc069c403ebaf9f0171e9517f40e41\"" } body:nil];
    [t addResponse:200 headers:@{} body:@"in"];
    XFSubmissionRequest *req = [[XFSubmissionRequest alloc] init];
    req.method = @"get";
    req.URLString = @"http://www.nowhere.org/dir/index.html";
    XFSubmissionResponse *resp = [t performRequest:req error:NULL];
    XCTAssertEqual(resp.statusCode, (NSInteger)200);
    NSString *authz = t.hops[1].headers[@"Authorization"];
    XCTAssertTrue([authz hasPrefix:@"Digest username=\"Mufasa\""], @"%@", authz);
    // the RFC's published response hash — the password itself never travels
    XCTAssertTrue([authz containsString:@"response=\"6629fae49393a05397450978507c4ef1\""], @"%@", authz);
    XCTAssertTrue([authz containsString:@"qop=auth"], @"%@", authz);
    XCTAssertTrue([authz containsString:@"nc=00000001"], @"%@", authz);
    XCTAssertFalse([authz containsString:@"Circle"], @"no password in the header");
}

- (void)testTransportPreemptiveBasicOnlyWhenAskedFor
{
    XFScriptedHTTPTransport *t = [[XFScriptedHTTPTransport alloc] init];
    XFTestAuthProvider *auth = [[XFTestAuthProvider alloc] init];
    auth.user = @"u";
    auth.password = @"p";
    t.auth = auth;
    [t addResponse:200 headers:@{} body:@"ok"];
    XFSubmissionRequest *req = [self postRequestTo:@"http://one.test/x"];
    req.preemptiveAuth = YES;
    [t performRequest:req error:NULL];
    XCTAssertTrue([t.hops[0].headers[@"Authorization"] hasPrefix:@"Basic "],
                  @"preemptive Basic when the author/host opted in");
}

- (void)testHeaderInjectingTransport
{
    XFMapSubmissionTransport *inner = [[XFMapSubmissionTransport alloc] init];
    [inner setStatus:200 body:@"ok" forURL:@"http://api.test/x"];
    XFHeaderInjectingTransport *wrap = [[XFHeaderInjectingTransport alloc] init];
    wrap.inner = inner;
    wrap.extraHeaders = @{ @"Authorization": @"Bearer host-session",
                           @"X-Injected": @"yes" };
    XFSubmissionRequest *req = [self postRequestTo:@"http://api.test/x"];
    req.headers = @{ @"Authorization": @"Bearer author-wins" };
    [wrap performRequest:req error:NULL];
    XCTAssertEqualObjects(inner.lastRequest.headers[@"Authorization"], @"Bearer author-wins",
                          @"the form author's header wins over the injected one");
    XCTAssertEqualObjects(inner.lastRequest.headers[@"X-Injected"], @"yes");
}

- (void)testSubmissionPreemptiveAuthenticationAttribute
{
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\"><n>1</n></data></xf:instance>"
        @"<xf:submission id=\"s\" resource=\"http://api.test/x\" method=\"post\""
        @"  replace=\"none\" xxf:preemptive-authentication=\"true\""
        @"  xmlns:xxf=\"http://orbeon.org/oxf/xml/xforms\"/>"
        @"<xf:send id=\"go\" submission=\"s\"/>"
                          extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:200 body:@"" forURL:@"http://api.test/x"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    XCTAssertTrue(map.lastRequest.preemptiveAuth);
}

- (void)testPreviewRequestMatchesSubmitWithoutSideEffects
{
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\"><q>xforms</q></data></xf:instance>"
        @"<xf:instance id=\"auth\"><auth xmlns=\"\"><token>t0k3n</token></auth></xf:instance>"
        @"<xf:submission id=\"s\" resource=\"http://api.test/search\" method=\"get\""
        @"  replace=\"none\">"
        @"  <xf:header combine=\"replace\"><xf:name>Authorization</xf:name>"
        @"    <xf:value value=\"concat('Bearer ', instance('auth')/token)\"/></xf:header>"
        @"</xf:submission>"
        @"<xf:send id=\"go\" submission=\"s\"/>"
                          extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFSubmission *sub = p.model.defaultSubmission;
    XFSubmissionRequest *preview = [sub previewRequest];
    XCTAssertEqualObjects(preview.method, @"get");
    XCTAssertEqualObjects(preview.URLString, @"http://api.test/search?q=xforms",
                          @"GET serializes into the query");
    XCTAssertEqualObjects(preview.headers[@"Authorization"], @"Bearer t0k3n",
                          @"xf:header evaluated from instance data");
    XCTAssertFalse(sub.pending, @"a preview never runs the submission");
    XCTAssertNil(sub.lastEventContext, @"no events, no state");

    // the live submit builds the same request
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:200 body:@"" forURL:@"http://api.test/search"];
    p.model.transport = map;
    [self send:p identifier:@"go"];
    XCTAssertEqualObjects(map.lastRequest.URLString, preview.URLString);
    XCTAssertEqualObjects(map.lastRequest.headers[@"Authorization"],
                          preview.headers[@"Authorization"]);
}

@end
