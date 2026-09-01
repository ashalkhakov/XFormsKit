/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* W3C XForms 1.1 test suite, chapter 11 (The XForms Submit Module) as
   XCTest assertions — see XFW3CTestCase.h for the approach and the
   spec-true policy. The chapter's real network endpoints are long gone;
   every case runs against the recording echo transport
   (`useEchoTransport`), which answers 200 with the request body echoed
   back and keeps each XFSubmissionRequest for the serialization
   assertions (URLs containing "invalid" still fail — the
   deliberate-bad-URL legs), or against the default dead transport when
   failure IS the expected behavior. Local file: actions (the
   replace="instance" data files) pass through to the real file. */
#import "XFW3CTestCase.h"

@interface XFW3CChapter11Tests : XFW3CTestCase
@end

@implementation XFW3CChapter11Tests

/// Body of the last request, "" when none.
- (NSString *)lastBody
{
    return self.lastRequest.body ?: @"";
}

- (XFSubmissionRequest *)submitAndGrab:(NSString *)label
{
    NSUInteger before = self.submittedRequests.count;
    [self activateTriggerLabeled:label];
    XCTAssertTrue(self.submittedRequests.count > before,
                  @"'%@' produced no request", label);
    return self.lastRequest;
}

#pragma mark - 11.1 the submission element

- (void)test_11_1_a_RefAttribute
{
    [self loadRequired:@"Chapt11/11.1/11.1.a.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit Make And Model"];
    XCTAssertTrue([r.body containsString:@"Acura"], @"%@", r.body);
    XCTAssertTrue([r.body containsString:@"Integra"], @"the subtree under ref goes too");
    XCTAssertFalse([r.body containsString:@"white"], @"only the ref subtree is serialized");
    r = [self submitAndGrab:@"Submit Color"];
    XCTAssertTrue([r.body containsString:@"white"]);
    XCTAssertFalse([r.body containsString:@"Acura"]);
}

- (void)test_11_1_b_BindAttribute
{
    [self loadRequired:@"Chapt11/11.1/11.1.b.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit"];
    XCTAssertTrue([r.body containsString:@"white"], @"%@", r.body);
    XCTAssertFalse([r.body containsString:@"Acura"]);
    XCTAssertFalse([r.body containsString:@"1994"]);
    XCTAssertFalse([r.body containsString:@"120"]);
}

- (void)test_11_1_c_ResourceAttribute
{
    [self loadRequired:@"Chapt11/11.1/11.1.c.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit Make And Model"];
    XCTAssertTrue([r.URLString containsString:@"xformstest.org"],
                  @"the resource attribute names the target: %@", r.URLString);
    XCTAssertTrue([r.body containsString:@"Acura"]);
    // the resource ELEMENT beats the (deliberately bad) resource attribute
    r = [self submitAndGrab:@"Submit Color"];
    XCTAssertTrue([r.URLString containsString:@"xformstest.org"],
                  @"the resource child element wins: %@", r.URLString);
    XCTAssertTrue([r.body containsString:@"white"]);
}

- (void)test_11_1_d_ActionAttribute
{
    [self loadRequired:@"Chapt11/11.1/11.1.d.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit"];
    XCTAssertTrue([r.body containsString:@"Subaru"], @"%@", r.body);
    XCTAssertTrue([r.body containsString:@"Impreza WRX STi"]);
    XCTAssertTrue([r.body containsString:@"2005"]);
}

- (void)test_11_1_e_ModeAttribute
{
    [self loadRequired:@"Chapt11/11.1/11.1.e.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit with Synchronous"];
    XCTAssertTrue([r.body containsString:@"white"], @"%@", r.body);
    [self activateTriggerLabeled:@"Submit with Asynchronous"];
    [[self submissionWithID:@"submitColorA"] waitUntilFinished:5];
    XCTAssertEqual(self.submittedRequests.count, (NSUInteger)2,
                   @"the asynchronous submission also reaches the transport");
    XCTAssertTrue([[self lastBody] containsString:@"white"]);
}

- (void)test_11_1_f_MethodAttribute
{
    [self loadRequired:@"Chapt11/11.1/11.1.f.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit by Post"];
    XCTAssertEqualObjects([r.method uppercaseString], @"POST");
    XCTAssertTrue([r.body containsString:@"Infiniti"]);
    r = [self submitAndGrab:@"Submit by Put"];
    XCTAssertEqualObjects([r.method uppercaseString], @"PUT");
    XCTAssertTrue([r.body containsString:@"G35x"]);
}

- (void)test_11_1_h_ValidateAttribute
{
    // age is xsd:positiveInteger with value "ten": validate="true" must
    // stop the submission with xforms-submit-error, validate="false"
    // must submit anyway
    [self loadRequired:@"Chapt11/11.1/11.1.h.xhtml"];
    [self useEchoTransport];
    [self activateTriggerLabeled:@"Submit (validate=true)"];
    XCTAssertTrue([self.messages containsObject:@"xforms-submit-error"], @"%@", self.messages);
    XCTAssertEqual(self.submittedRequests.count, (NSUInteger)0,
                   @"the invalid data never reaches the transport");
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit (validate=false)"];
    XCTAssertTrue([r.body containsString:@"ten"]);
}

- (void)test_11_1_i_RelevantAttribute
{
    // dateOfPurchase is bound non-relevant: relevant="true" prunes it,
    // relevant="false" serializes it anyway
    [self loadRequired:@"Chapt11/11.1/11.1.i.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit (relevant=true)"];
    XCTAssertTrue([r.body containsString:@"Suzuki"], @"%@", r.body);
    XCTAssertTrue([r.body containsString:@"Hayabusa 1300"]);
    XCTAssertFalse([r.body containsString:@"2006-04-26"], @"non-relevant nodes are pruned");
    r = [self submitAndGrab:@"Submit (relevant=false)"];
    XCTAssertTrue([r.body containsString:@"2006-04-26"], @"relevant=false keeps them");
}

- (void)test_11_1_j_SerializationNone
{
    [self loadRequired:@"Chapt11/11.1/11.1.j.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit With Serialization"];
    XCTAssertFalse([r.URLString containsString:@"blue"],
                   @"serialization='none': no data in the URI: %@", r.URLString);
    XCTAssertFalse([r.body ?: @"" containsString:@"blue"], @"…and none in the body");
}

- (void)test_11_1_k_VersionAttribute
{
    // non-normative: both versions must simply submit
    [self loadRequired:@"Chapt11/11.1/11.1.k.xhtml"];
    [self useEchoTransport];
    [self submitAndGrab:@"Submit as 1.0"];
    [self submitAndGrab:@"Submit as 1.1"];
}

- (void)test_11_1_l_IndentAttribute
{
    // non-normative: both must submit; the data survives either way
    [self loadRequired:@"Chapt11/11.1/11.1.l.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit Without indent"];
    XCTAssertTrue([r.body containsString:@"Acura"]);
    r = [self submitAndGrab:@"Submit With indent"];
    XCTAssertTrue([r.body containsString:@"Acura"]);
}

- (void)test_11_1_m_MediatypeAttribute
{
    [self loadRequired:@"Chapt11/11.1/11.1.m.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit"];
    XCTAssertTrue([r.mediaType hasPrefix:@"application/xml"],
                  @"mediatype attribute sets the content type: %@", r.mediaType);
}

- (void)test_11_1_n_EncodingAttribute
{
    [self loadRequired:@"Chapt11/11.1/11.1.n.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit (UTF-8)"];
    XCTAssertTrue([r.body containsString:@"encoding=\"UTF-8\""], @"%@", r.body);
    r = [self submitAndGrab:@"Submit (ISO)"];
    XCTAssertTrue([r.body containsString:@"encoding=\"ISO-8859-1\""], @"%@", r.body);
}

- (void)test_11_1_o_OmitXMLDeclaration
{
    [self loadRequired:@"Chapt11/11.1/11.1.o.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit"];
    XCTAssertFalse([r.body containsString:@"<?xml"],
                   @"omit-xml-declaration drops the prolog: %@", r.body);
    XCTAssertTrue([r.body containsString:@"Acura"]);
}

- (void)test_11_1_p_StandaloneAttribute
{
    [self loadRequired:@"Chapt11/11.1/11.1.p.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit With Standalone true"];
    XCTAssertTrue([r.body containsString:@"standalone=\"yes\""]
                      || [r.body containsString:@"standalone=\"true\""], @"%@", r.body);
    r = [self submitAndGrab:@"Submit With Standalone false"];
    XCTAssertTrue([r.body containsString:@"standalone=\"no\""]
                      || [r.body containsString:@"standalone=\"false\""], @"%@", r.body);
    r = [self submitAndGrab:@"Submit Without Standalone"];
    XCTAssertFalse([r.body containsString:@"standalone"], @"%@", r.body);
}

- (void)test_11_1_q_CDATASectionElements
{
    [self loadRequired:@"Chapt11/11.1/11.1.q.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit (cdata=\"make\")"];
    // the instance text node is "Toyota\n        " — the CDATA section
    // legitimately keeps that whitespace, so accept it
    XCTAssertTrue([r.body containsString:@"<make><![CDATA[Toyota"], @"%@", r.body);
    XCTAssertTrue([r.body containsString:@"]]>"], @"%@", r.body);
    r = [self submitAndGrab:@"Submit (cdata=\"year\")"];
    XCTAssertTrue([r.body containsString:@"<year><![CDATA[2005]]></year>"], @"%@", r.body);
}

- (void)test_11_1_r_ReplaceInstance
{
    // replace="instance" from a LOCAL data file (the dead transport
    // passes file: URLs through): instance2 is replaced, instance1 not
    [self loadRequired:@"Chapt11/11.1/11.1.r.xhtml"];
    [self activateTriggerLabeled:@"Replace Instance"];
    XCTAssertEqualObjects([self stringForXPath:@"/car/carOwner"], @"Henry",
                          @"the first instance is untouched");
    XCTAssertEqualObjects([self stringForXPath:@"instance('instance2')/carOwner"], @"Janel");
    XCTAssertEqualObjects([self stringForXPath:@"instance('instance2')/make"], @"Saturn");
    XCTAssertEqualObjects([self stringForXPath:@"instance('instance2')/color"], @"red");
}

- (void)test_11_1_s1_InstanceAttribute
{
    [self loadRequired:@"Chapt11/11.1/11.1.s1.xhtml"];
    [self activateTriggerLabeled:@"Replace Instance 2"];
    XCTAssertTrue([[self stringForXPath:@"instance('instance_2')"]
                      containsString:@"This is the response data."],
                  @"only the named instance is replaced");
    XCTAssertTrue([[self stringForXPath:@"instance('instance_1')"]
                      containsString:@"instance 1"], @"instance 1 unchanged");
    XCTAssertTrue([[self stringForXPath:@"instance('instance_3')"]
                      containsString:@"instance 3"], @"instance 3 unchanged");
}

- (void)test_11_1_s2_InvalidInstanceAttribute
{
    [self loadRequired:@"Chapt11/11.1/11.1.s2.xhtml"];
    [self activateTriggerLabeled:@"Invalid Instance"];
    [self assertSawEvent:@"xforms-binding-exception"];
}

- (void)test_11_1_t_TargetrefAttribute
{
    [self loadRequired:@"Chapt11/11.1/11.1.t.xhtml"];
    [self activateTriggerLabeled:@"Replace Instance"];
    XCTAssertEqualObjects([self stringForXPath:@"instance('instance2')/carOwner"], @"Janel");
    XCTAssertEqualObjects([self stringForXPath:@"instance('instance2')/make"], @"Saturn");
    XCTAssertEqualObjects([self stringForXPath:@"instance('instance2')/color"], @"red");
}

- (void)test_11_1_u_SeparatorAttribute
{
    [self loadRequired:@"Chapt11/11.1/11.1.u.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Separate With '&'"];
    XCTAssertTrue([r.body containsString:@"carOwner=Greg&make=Toyota&color=Silver"],
                  @"default separator is '&': %@", r.body);
    r = [self submitAndGrab:@"Separate With ';'"];
    XCTAssertTrue([r.body containsString:@"carOwner=Greg;make=Toyota;color=Silver"],
                  @"separator=';': %@", r.body);
}

- (void)test_11_1_v_IncludeNamespacePrefixes
{
    [self loadRequired:@"Chapt11/11.1/11.1.v.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit"];
    XCTAssertTrue([r.body containsString:@"my:car"], @"%@", r.body);
    XCTAssertTrue([r.body containsString:@"xmlns:my"], @"the listed prefix is declared");
    XCTAssertFalse([r.body containsString:@"xmlns:xhtml"], @"unlisted prefixes are excluded");
    XCTAssertFalse([r.body containsString:@"xmlns:xforms"], @"unlisted prefixes are excluded");
}

#pragma mark - 11.2 the xforms-submit event

- (void)test_11_2_a_OneConcurrentSubmitPerSubmission
{
    [self loadRequired:@"Chapt11/11.2/11.2.a.xhtml"];
    [self useEchoTransport];
    [self activateTriggerLabeled:@"Submit Twice"];
    XCTAssertFalse([self.messages containsObject:@"xforms-submit-error"],
                   @"two sequential submits must both succeed: %@", self.messages);
    XCTAssertTrue([self.messages containsObject:@"xforms-submit-done"], @"%@", self.messages);
}

- (void)test_11_2_b_NonRelevantNodesNotSerialized
{
    [self loadRequired:@"Chapt11/11.2/11.2.b.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Show"];
    XCTAssertTrue([r.body containsString:@"test1"], @"%@", r.body);
    XCTAssertTrue([r.body containsString:@"test2"]);
    XCTAssertFalse([r.body containsString:@"test3"], @"non-relevant nodes are pruned");
    XCTAssertFalse([r.body containsString:@"test4"]);
}

- (void)test_11_2_c_EmptyInstanceDataNoData
{
    // ref="data" selects nothing → xforms-submit-error, error-type "no-data"
    [self loadRequired:@"Chapt11/11.2/11.2.c.xhtml"];
    [self useEchoTransport];
    [self activateTriggerLabeled:@"Submit Now"];
    XCTAssertTrue([self.messages.description containsString:@"xforms-submit-error"],
                  @"%@", self.messages);
    XCTAssertEqualObjects([self stringForXPath:@"instance('error_holder')/error_name"],
                          @"no-data");
}

- (void)test_11_2_d_RequiredEmptyValidationError
{
    [self loadRequired:@"Chapt11/11.2/11.2.d.xhtml"];
    [self useEchoTransport];
    [self activateTriggerLabeled:@"Submit Here"];
    XCTAssertTrue([self.messages containsObject:@"xforms-submit-error"], @"%@", self.messages);
    XCTAssertEqualObjects([self stringForXPath:@"instance('error_holder')/error_name"],
                          @"validation-error");
}

- (void)test_11_2_e_InvalidDataValidationError
{
    [self loadRequired:@"Chapt11/11.2/11.2.e.xhtml"];
    [self useEchoTransport];
    [self activateTriggerLabeled:@"Submit Here"];
    XCTAssertTrue([self.messages containsObject:@"xforms-submit-error"], @"%@", self.messages);
    XCTAssertEqualObjects([self stringForXPath:@"instance('error_holder')/error_name"],
                          @"validation-error");
}

#pragma mark - 11.3 xforms-submit-serialize

- (void)test_11_3_a_SubmitSerializeEvent
{
    [self loadRequired:@"Chapt11/11.3/11.3.a.xhtml"];
    [self useEchoTransport];
    [self activateTriggerLabeled:@"Submit Now"];
    XCTAssertTrue([self.messages containsObject:@"xforms-submit-serialize"]
                      || [self eventDispatched:@"xforms-submit-serialize"],
                  @"%@", self.messages);
    XCTAssertTrue([[self lastBody] containsString:@"Toyota"]);
    XCTAssertTrue([[self lastBody] containsString:@"Prius"]);
}

- (void)test_11_3_b_SubmissionBodyProperty
{
    // setvalue on event('submission-body') replaces the serialization
    [self loadRequired:@"Chapt11/11.3/11.3.b.xhtml"];
    [self useEchoTransport];
    [self activateTriggerLabeled:@"Submit Now"];
    XCTAssertTrue([[self lastBody] containsString:@"<data>MyNewData</data>"],
                  @"%@", [self lastBody]);
    XCTAssertFalse([[self lastBody] containsString:@"Toyota"]);
    XCTAssertFalse([[self lastBody] containsString:@"Prius"]);
}

#pragma mark - 11.4 xforms-submit-done

- (void)test_11_4_a_SubmitDoneEvent
{
    [self loadRequired:@"Chapt11/11.4/11.4.a.xhtml"];
    [self useEchoTransport];
    [self activateTriggerLabeled:@"Submit Now"];
    XCTAssertTrue([self.messages containsObject:@"xforms-submit-done"], @"%@", self.messages);
}

- (void)test_11_4_b_SubmitDoneContextInfo
{
    [self loadRequired:@"Chapt11/11.4/11.4.b.xhtml"];
    [self useEchoTransport];
    [self activateTriggerLabeled:@"Submit Now"];
    XCTAssertEqualObjects([self stringForXPath:@"instance('event_catcher')/return_code"],
                          @"200", @"event('response-status-code')");
}

#pragma mark - 11.5 xforms-submit-error

- (void)test_11_5_a_SubmitErrorEvent
{
    // the deliberately-unreachable URL (dead transport: every non-file
    // URL fails) must produce xforms-submit-error
    [self loadRequired:@"Chapt11/11.5/11.5.a.xhtml"];
    [self activateTriggerLabeled:@"Submit Now"];
    XCTAssertTrue([self.messages containsObject:@"xforms-submit-error"], @"%@", self.messages);
}

- (void)test_11_5_b_SubmitErrorContextInfo
{
    [self loadRequired:@"Chapt11/11.5/11.5.b.xhtml"];
    [self activateTriggerLabeled:@"Submit To Bad URL"];
    XCTAssertEqualObjects([self stringForXPath:@"instance('error_catcher')/error_name"],
                          @"resource-error");
    XCTAssertEqualObjects([self stringForXPath:@"instance('error_catcher')/error_info"],
                          @"http://invaliduri.com8565/inval1d",
                          @"event('resource-uri') names the failed URL");
}

#pragma mark - 11.6.1 the resource element

- (void)test_11_6_1_a_ResourceElement
{
    [self loadRequired:@"Chapt11/11.6/11.6.1/11.6.1.a.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit (@resource)"];
    XCTAssertTrue([r.URLString containsString:@"xformstest.org"],
                  @"@resource beats @action: %@", r.URLString);
    r = [self submitAndGrab:@"Submit (resource element)"];
    XCTAssertTrue([r.URLString containsString:@"xformstest.org"],
                  @"the resource element beats @resource: %@", r.URLString);
}

- (void)test_11_6_1_b_ResourceElementValueAttribute
{
    [self loadRequired:@"Chapt11/11.6/11.6.1/11.6.1.b.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit"];
    XCTAssertTrue([r.URLString containsString:@"xformstest.org"],
                  @"resource/@value evaluates the URL: %@", r.URLString);
}

#pragma mark - 11.7.1 the method element

- (void)test_11_7_1_a_MethodElement
{
    [self loadRequired:@"Chapt11/11.7/11.7.1/11.7.1.a.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit With Method"];
    XCTAssertEqualObjects([r.method uppercaseString], @"POST",
                          @"method/@value evaluates to 'post', beating the inline 'other'");
}

#pragma mark - 11.8 the header element

- (void)test_11_8_a_HeaderElement
{
    [self loadRequired:@"Chapt11/11.8/11.8.a.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit Now"];
    XCTAssertEqualObjects(r.headers[@"myHeader1"], @"myValue1", @"%@", r.headers);
    XCTAssertEqualObjects(r.headers[@"myHeader2"], @"myValue2");
}

- (void)test_11_8_b_HeaderNodesetAttribute
{
    // one header element iterated over three nodes: the combined
    // myHeader value carries all three node values
    [self loadRequired:@"Chapt11/11.8/11.8.b.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit Now"];
    NSString *combined = r.headers[@"myHeader"] ?: @"";
    XCTAssertTrue([combined containsString:@"one"], @"%@", r.headers);
    XCTAssertTrue([combined containsString:@"two"]);
    XCTAssertTrue([combined containsString:@"three"]);
}

- (void)test_11_8_c_DuplicateHeaderNames
{
    // the suite's chosen interpretation: duplicate names combine into
    // ONE header, values in document/iteration order
    [self loadRequired:@"Chapt11/11.8/11.8.c.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit Now"];
    XCTAssertEqualObjects(r.headers[@"myHeader"],
                          @"myValue1,myValue2,myValue1,myValue2,myValue3,myValue4,myValue4",
                          @"%@", r.headers);
}

- (void)test_11_8_1_a_NameElementValueAttribute
{
    [self loadRequired:@"Chapt11/11.8/11.8.1/11.8.1.a.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit Now"];
    XCTAssertEqualObjects(r.headers[@"myHeader"], @"myValue1",
                          @"name/@value beats the inline text: %@", r.headers);
    XCTAssertNil(r.headers[@"wrongData"]);
}

- (void)test_11_8_1_b_NameElementEmptyValue
{
    [self loadRequired:@"Chapt11/11.8/11.8.1/11.8.1.b.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit Now"];
    XCTAssertFalse([[r.headers.allValues componentsJoinedByString:@","]
                       containsString:@"myValue"],
                   @"an empty header name drops the header: %@", r.headers);
}

- (void)test_11_8_2_a_ValueElementValueAttribute
{
    [self loadRequired:@"Chapt11/11.8/11.8.2/11.8.2.a.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit Now"];
    XCTAssertEqualObjects(r.headers[@"myHeader"], @"three",
                          @"value/@value beats the inline text: %@", r.headers);
}

#pragma mark - 11.9 submission options (methods)

- (void)assertMethod:(NSString *)verb form:(NSString *)relPath label:(NSString *)label
{
    [self loadRequired:relPath];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:label];
    XCTAssertEqualObjects([r.method uppercaseString], verb, @"%@", relPath);
}

- (void)test_11_9_a_HTTPPost
{
    [self assertMethod:@"POST" form:@"Chapt11/11.9/11.9.a.xhtml" label:@"Post Data"];
}

- (void)test_11_9_b_HTTPGet
{
    [self assertMethod:@"GET" form:@"Chapt11/11.9/11.9.b.xhtml" label:@"Get Data"];
}

- (void)test_11_9_c_HTTPPut
{
    [self assertMethod:@"PUT" form:@"Chapt11/11.9/11.9.c.xhtml" label:@"Put Data"];
}

- (void)test_11_9_d_HTTPMultipartPost
{
    [self assertMethod:@"POST" form:@"Chapt11/11.9/11.9.d.xhtml" label:@"Post Data"];
}

- (void)test_11_9_e_HTTPFormDataPost
{
    [self assertMethod:@"POST" form:@"Chapt11/11.9/11.9.e.xhtml" label:@"Post Data"];
}

- (void)test_11_9_f_HTTPUrlencodedPost
{
    [self assertMethod:@"POST" form:@"Chapt11/11.9/11.9.f.xhtml" label:@"Post Data"];
}

- (void)test_11_9_g_HTTPSPost
{
    [self assertMethod:@"POST" form:@"Chapt11/11.9/11.9.g.xhtml" label:@"Post Data"];
}

- (void)test_11_9_h_HTTPSGet
{
    [self assertMethod:@"GET" form:@"Chapt11/11.9/11.9.h.xhtml" label:@"Get Data"];
}

- (void)test_11_9_i_HTTPSPut
{
    [self assertMethod:@"PUT" form:@"Chapt11/11.9/11.9.i.xhtml" label:@"Put Data"];
}

- (void)test_11_9_j_HTTPSMultipartPost
{
    [self assertMethod:@"POST" form:@"Chapt11/11.9/11.9.j.xhtml" label:@"Post Data"];
}

- (void)test_11_9_k_HTTPSFormDataPost
{
    [self assertMethod:@"POST" form:@"Chapt11/11.9/11.9.k.xhtml" label:@"Post Data"];
}

- (void)test_11_9_l_HTTPSUrlencodedPost
{
    [self assertMethod:@"POST" form:@"Chapt11/11.9/11.9.l.xhtml" label:@"Post Data"];
}

- (void)test_11_9_m_MailtoPost
{
    // non-normative: the mailto URI must reach the submission layer
    [self loadRequired:@"Chapt11/11.9/11.9.m.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Post Data"];
    XCTAssertTrue([r.URLString hasPrefix:@"mailto:"], @"%@", r.URLString);
}

- (void)test_11_9_n_FileGet
{
    // file: get against the local data file (non-normative)
    [self loadRequired:@"Chapt11/11.9/11.9.n.xhtml"];
    [self activateTriggerLabeled:@"Get Data"];
    XCTAssertTrue([self.messages.description containsString:@"submit-error"] == NO,
                  @"file get must not error: %@", self.messages);
    XCTAssertTrue([self eventDispatched:@"xforms-submit-done"],
                  @"the local file loads as the response");
}

- (void)test_11_9_o_FilePut
{
    // file: put (non-normative) — through the echo transport so the
    // suite directory is never written
    [self loadRequired:@"Chapt11/11.9/11.9.o.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Put Data"];
    XCTAssertEqualObjects([r.method uppercaseString], @"PUT");
    XCTAssertTrue([r.URLString containsString:@"11.9.o.data.xml"], @"%@", r.URLString);
}

- (void)test_11_9_p_MailtoUrlencodedPost
{
    [self loadRequired:@"Chapt11/11.9/11.9.p.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Post Data"];
    XCTAssertTrue([r.URLString hasPrefix:@"mailto:"], @"%@", r.URLString);
}

- (void)test_11_9_q_MailtoFormDataPost
{
    [self loadRequired:@"Chapt11/11.9/11.9.q.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Post Data"];
    XCTAssertTrue([r.URLString hasPrefix:@"mailto:"], @"%@", r.URLString);
}

- (void)test_11_9_r_MailtoUrlencodedPost2
{
    [self loadRequired:@"Chapt11/11.9/11.9.r.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Post Data"];
    XCTAssertTrue([r.URLString hasPrefix:@"mailto:"], @"%@", r.URLString);
}

- (void)test_11_9_1_a_GetMethod
{
    // get: the data travels in the request URI, not the body
    [self loadRequired:@"Chapt11/11.9/11.9.1/11.9.1.a.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Use Get Method"];
    XCTAssertTrue([r.URLString containsString:@"blue"], @"%@", r.URLString);
    XCTAssertFalse([r.body ?: @"" containsString:@"blue"], @"no body on get");
}

- (void)test_11_9_2_a_PostMethod
{
    [self loadRequired:@"Chapt11/11.9/11.9.2/11.9.2.a.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Use Post Method"];
    XCTAssertTrue([r.body containsString:@"blue"], @"%@", r.body);
}

- (void)test_11_9_2_b_MultipartPostMethod
{
    [self loadRequired:@"Chapt11/11.9/11.9.2/11.9.2.b.xhtml"];
    [self useEchoTransport];
    [self activateTriggerLabeled:@"Use Multipart-Post Method"];
    XFSubmissionRequest *r = self.lastRequest;
    XCTAssertNotNil(r, @"multipart-post must submit");
    NSString *body = r.body ?: [[NSString alloc] initWithData:r.bodyData ?: [NSData data]
                                                     encoding:NSUTF8StringEncoding];
    XCTAssertTrue([body containsString:@"blue"], @"%@", body);
}

- (void)test_11_9_2_c_FormDataPostMethod
{
    [self loadRequired:@"Chapt11/11.9/11.9.2/11.9.2.c.xhtml"];
    [self useEchoTransport];
    [self activateTriggerLabeled:@"Use Form-Data-Post Method"];
    XFSubmissionRequest *r = self.lastRequest;
    XCTAssertNotNil(r, @"form-data-post must submit");
    NSString *body = r.body ?: [[NSString alloc] initWithData:r.bodyData ?: [NSData data]
                                                     encoding:NSUTF8StringEncoding];
    XCTAssertTrue([body containsString:@"blue"], @"%@", body);
}

- (void)test_11_9_2_d_UrlencodedPostMethod
{
    [self loadRequired:@"Chapt11/11.9/11.9.2/11.9.2.d.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Use Urlencoded-Post Method"];
    XCTAssertTrue([r.body containsString:@"blue"], @"%@", r.body);
}

- (void)test_11_9_3_a_PutMethod
{
    [self loadRequired:@"Chapt11/11.9/11.9.3/11.9.3.a.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Use Put Method"];
    XCTAssertEqualObjects([r.method uppercaseString], @"PUT");
    XCTAssertTrue([r.body containsString:@"blue"], @"%@", r.body);
}

- (void)test_11_9_3_b_PutToLocalFile
{
    // non-normative — via the echo transport so no file is written
    [self loadRequired:@"Chapt11/11.9/11.9.3/11.9.3.b.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Use Put Method"];
    XCTAssertEqualObjects([r.method uppercaseString], @"PUT");
    XCTAssertTrue([r.URLString containsString:@"myfile.txt"], @"%@", r.URLString);
    XCTAssertTrue([r.body containsString:@"blue"], @"%@", r.body);
}

- (void)test_11_9_4_a_DeleteMethod
{
    // delete serializes to the URI like get
    [self loadRequired:@"Chapt11/11.9/11.9.4/11.9.4.a.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Use Delete Method"];
    XCTAssertEqualObjects([r.method uppercaseString], @"DELETE");
    XCTAssertTrue([r.URLString containsString:@"blue"], @"%@", r.URLString);
    XCTAssertFalse([r.body ?: @"" containsString:@"blue"]);
}

- (void)test_11_9_4_b_DeleteLocalFile
{
    // non-normative; the deletion itself needs a writable host — the
    // covered leg is the DELETE request reaching the transport
    [self loadRequired:@"Chapt11/11.9/11.9.4/11.9.4.b.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit"];
    XCTAssertEqualObjects([r.method uppercaseString], @"DELETE");
    XCTAssertTrue([r.URLString containsString:@"deleteme.txt"], @"%@", r.URLString);
}

- (void)test_11_9_5_a_SerializationApplicationXML
{
    [self loadRequired:@"Chapt11/11.9/11.9.5/11.9.5.a.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit Data"];
    XCTAssertTrue([r.mediaType hasPrefix:@"application/xml"], @"%@", r.mediaType);
    XCTAssertTrue([r.body containsString:@"Henry"], @"%@", r.body);
    XCTAssertTrue([r.body containsString:@"Acura"]);
    XCTAssertTrue([r.body containsString:@"white"]);
}

- (void)test_11_9_6_a_SerializationMultipartRelated
{
    [self loadRequired:@"Chapt11/11.9/11.9.6/11.9.6.a.xhtml"];
    [self useEchoTransport];
    [self activateTriggerLabeled:@"Submit Data"];
    XFSubmissionRequest *r = self.lastRequest;
    XCTAssertNotNil(r, @"multipart-post must submit");
    XCTAssertTrue([r.mediaType hasPrefix:@"multipart/related"], @"%@", r.mediaType);
    NSString *body = r.body ?: [[NSString alloc] initWithData:r.bodyData ?: [NSData data]
                                                     encoding:NSUTF8StringEncoding];
    XCTAssertTrue([body containsString:@"Henry"], @"%@", body);
}

- (void)test_11_9_7_a_SerializationMultipartFormData
{
    [self loadRequired:@"Chapt11/11.9/11.9.7/11.9.7.a.xhtml"];
    [self useEchoTransport];
    [self activateTriggerLabeled:@"Submit Data"];
    XFSubmissionRequest *r = self.lastRequest;
    XCTAssertNotNil(r, @"form-data-post must submit");
    XCTAssertTrue([r.mediaType hasPrefix:@"multipart/form-data"], @"%@", r.mediaType);
    NSString *body = r.body ?: [[NSString alloc] initWithData:r.bodyData ?: [NSData data]
                                                     encoding:NSUTF8StringEncoding];
    XCTAssertTrue([body containsString:@"Henry"], @"%@", body);
}

- (void)test_11_9_8_a_SerializationUrlencoded
{
    [self loadRequired:@"Chapt11/11.9/11.9.8/11.9.8.a.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit Data"];
    XCTAssertTrue([r.mediaType hasPrefix:@"application/x-www-form-urlencoded"],
                  @"%@", r.mediaType);
    XCTAssertTrue([r.body containsString:@"Ren%C3%A9"],
                  @"UTF-8 percent-encoding of é: %@", r.body);
}

#pragma mark - 11.10 replacing data with the submission response

- (void)test_11_10_a_InvalidTargetref
{
    [self loadRequired:@"Chapt11/11.10/11.10.a.xhtml"];
    [self activateTriggerLabeled:@"Replace Instance"];
    XCTAssertTrue([self.messages containsObject:@"xforms-submit-error"], @"%@", self.messages);
    XFModel *catcher = [self modelWithID:@"catcher"];
    XCTAssertEqualObjects([self stringForXPath:@"/eventdata" model:catcher], @"target-error");
    XCTAssertEqualObjects([self stringForXPath:@"instance('instance2')/carOwner"], @"Thomas",
                          @"the target instance is untouched on error");
}

- (void)test_11_10_b_TargetrefReceivingText
{
    [self loadRequired:@"Chapt11/11.10/11.10.b.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"instance('instance2')/carOwner"], @"Thomas");
    [self activateTriggerLabeled:@"Replace Instance"];
    XCTAssertEqualObjects([self stringForXPath:@"instance('instance2')/carOwner"], @"Janel",
                          @"replace='text' fills the targetref node");
}

- (void)test_11_10_c_TargetrefReceivingInstance
{
    [self loadRequired:@"Chapt11/11.10/11.10.c.xhtml"];
    [self activateTriggerLabeled:@"Replace Instance"];
    XCTAssertEqualObjects([self stringForXPath:@"/car/carOwner"], @"Henry",
                          @"the first instance is untouched");
    XCTAssertEqualObjects([self stringForXPath:@"instance('instance2')/carOwner"], @"Janel");
    XCTAssertEqualObjects([self stringForXPath:@"instance('instance2')/make"], @"Saturn");
    XCTAssertEqualObjects([self stringForXPath:@"instance('instance2')/color"], @"red");
}

#pragma mark - 11.11 integration with SOAP

- (void)test_11_11_1_a_SOAPEnvelope
{
    [self loadRequired:@"Chapt11/11.11/11.11.1/11.11.1.a.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit SOAP"];
    XCTAssertTrue([r.body containsString:@"soap:Envelope"], @"%@", r.body);
    XCTAssertTrue([r.body containsString:@"This is the message"]);
}

- (void)test_11_11_2_a_IndicatingSOAPSubmission
{
    [self loadRequired:@"Chapt11/11.11/11.11.2/11.11.2.a.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit SOAP"];
    XCTAssertTrue([r.mediaType hasPrefix:@"application/soap+xml"], @"%@", r.mediaType);
}

- (void)test_11_11_3_a_SOAPGetAcceptHeader
{
    // SOAP + get: the mediatype travels as the Accept header
    [self loadRequired:@"Chapt11/11.11/11.11.3/11.11.3.a.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit SOAP"];
    NSString *accept = r.headers[@"Accept"] ?: @"";
    XCTAssertTrue([accept hasPrefix:@"application/soap+xml"], @"%@", r.headers);
    XCTAssertTrue([accept containsString:@"ASCII"], @"the charset rides along: %@", accept);
}

- (void)test_11_11_3_b_SOAPPostContentType
{
    [self loadRequired:@"Chapt11/11.11/11.11.3/11.11.3.b.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit SOAP"];
    XCTAssertTrue([r.mediaType hasPrefix:@"application/soap+xml"], @"%@", r.mediaType);
}

- (void)test_11_11_3_c_SOAPActionParameter
{
    // an action= parameter in the mediatype becomes the SOAPAction
    // header and the content type falls back to text/xml
    [self loadRequired:@"Chapt11/11.11/11.11.3/11.11.3.c.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit SOAP"];
    XCTAssertTrue([r.mediaType hasPrefix:@"text/xml"], @"%@", r.mediaType);
    XCTAssertEqualObjects(r.headers[@"SOAPAction"], @"http://www.google.com", @"%@", r.headers);
}

- (void)test_11_11_3_d_SOAPGetEncodingAttribute
{
    [self loadRequired:@"Chapt11/11.11/11.11.3/11.11.3.d.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit SOAP"];
    NSString *accept = r.headers[@"Accept"] ?: @"";
    XCTAssertTrue([accept hasPrefix:@"application/soap+xml"], @"%@", r.headers);
    XCTAssertTrue([accept containsString:@"UTF-8"], @"%@", accept);
}

- (void)test_11_11_3_e_SOAPPostEncodingAttribute
{
    [self loadRequired:@"Chapt11/11.11/11.11.3/11.11.3.e.xhtml"];
    [self useEchoTransport];
    XFSubmissionRequest *r = [self submitAndGrab:@"Submit SOAP"];
    XCTAssertTrue([r.mediaType hasPrefix:@"application/soap+xml"], @"%@", r.mediaType);
    XCTAssertTrue([r.mediaType containsString:@"UTF-8"], @"%@", r.mediaType);
}

- (void)test_11_11_4_a_SOAPErrorResponse
{
    // the "disconnect your network" leg: the dead transport IS the
    // unreachable network — the submission must fail with submit-error
    [self loadRequired:@"Chapt11/11.11/11.11.4/11.11.4.a.xhtml"];
    [self activateTriggerLabeled:@"Submit SOAP"];
    XCTAssertTrue([self.messages containsObject:@"xforms-submit-error"], @"%@", self.messages);
}

- (void)test_11_11_4_b_SOAPSuccessResponse
{
    [self loadRequired:@"Chapt11/11.11/11.11.4/11.11.4.b.xhtml"];
    [self useEchoTransport];
    [self activateTriggerLabeled:@"Submit SOAP"];
    XCTAssertTrue([self.messages containsObject:@"xforms-submit-done"], @"%@", self.messages);
}

@end
