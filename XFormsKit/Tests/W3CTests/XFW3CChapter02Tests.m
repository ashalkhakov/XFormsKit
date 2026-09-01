/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* W3C XForms 1.1 test suite, chapter 2 (Introduction to XForms) as
   XCTest assertions — see XFW3CTestCase.h for the approach and the
   spec-true policy. The chapter's four worked examples exercise the
   whole stack end to end: binding, namespaced instances, MIPs from
   binds and an inline schema, and two independent models on one page.
   Submissions run against the recording echo transport.

   Chapter 1 ("Differences between XForms 1.1 and 1.0") defines NO forms
   of its own — its manifest's 43 cases are all cross-references into
   chapters 3, 5, 7, 8, 10 and 11, each already asserted by that
   chapter's class — so there is no XFW3CChapter01Tests. */
#import "XFW3CTestCase.h"

@interface XFW3CChapter02Tests : XFW3CTestCase
@end

@implementation XFW3CChapter02Tests

- (void)test_2_1_a_IntroductoryExample
{
    [self loadRequired:@"Chapt02/2.1.a.xhtml"];
    [self useEchoTransport];
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    XCTAssertNotNil(select);
    XCTAssertEqual(select.items.count, (NSUInteger)2);
    XCTAssertEqualObjects([(XFItem *)select.items.firstObject value], @"cash");
    XCTAssertEqualObjects([self stringForXPath:@"/ecommerce/method"], @"cc",
                          @"initial payment method");
    XCTAssertEqual([self countOfClass:[XFInputControl class]], (NSUInteger)2);

    [self setValue:@"1234 5678" ofControl:[self controlOfClass:[XFInputControl class] index:0]];
    [self setValue:@"2005-12" ofControl:[self controlOfClass:[XFInputControl class] index:1]];
    XCTAssertTrue([select selectValue:@"cash"]);
    [self activateTriggerLabeled:@"Submit Now"];
    NSString *body = self.lastRequest.body ?: @"";
    XCTAssertTrue([body containsString:@"cash"], @"%@", body);
    XCTAssertTrue([body containsString:@"1234 5678"]);
    XCTAssertTrue([body containsString:@"2005-12"]);
}

- (void)test_2_2_a_EncapsulationOfInstanceData
{
    // the same form over a NAMESPACED instance (my:payment with @method)
    [self loadRequired:@"Chapt02/2.2.a.xhtml"];
    [self useEchoTransport];
    XCTAssertEqualObjects([self stringForXPath:@"/my:payment/@method"], @"cc");
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    XCTAssertNotNil(select.boundNode, @"select1 ref='@method' binds the attribute");
    XFInputControl *number = [self controlOfClass:[XFInputControl class] index:0];
    XFInputControl *expiry = [self controlOfClass:[XFInputControl class] index:1];
    XCTAssertNotNil(number.boundNode, @"ref='my:number' resolves in the my: namespace");
    XCTAssertNotNil(expiry.boundNode, @"absolute /my:payment/my:expiry resolves");

    [self setValue:@"4111" ofControl:number];
    [self setValue:@"2006-01" ofControl:expiry];
    [self activateTriggerLabeled:@"Submit Now"];
    NSString *body = self.lastRequest.body ?: @"";
    XCTAssertTrue([body containsString:@"4111"], @"%@", body);
    XCTAssertTrue([body containsString:@"2006-01"]);
    XCTAssertTrue([body containsString:@"cc"]);
}

- (void)test_2_3_a_ValueConstraints
{
    // binds make number/expiry relevant+required only while @method='cc';
    // an inline xsd:schema types number as a 14-18 digit pattern
    [self loadRequired:@"Chapt02/2.3.a.xhtml"];
    [self useEchoTransport];
    XFInputControl *number = [self controlOfClass:[XFInputControl class] index:0];
    XFInputControl *expiry = [self controlOfClass:[XFInputControl class] index:1];
    XCTAssertTrue(number.relevant, @"credit selected initially");
    XCTAssertTrue(expiry.relevant);

    // empty required fields: the submission must refuse
    [self activateTriggerLabeled:@"Submit Now"];
    XCTAssertEqual(self.submittedRequests.count, (NSUInteger)0,
                   @"required-but-empty data must not submit");

    [self setValue:@"12345678901234" ofControl:number];
    [self setValue:@"1998-12" ofControl:expiry];
    [self activateTriggerLabeled:@"Submit Now"];
    XCTAssertEqual(self.submittedRequests.count, (NSUInteger)1,
                   @"valid data submits");
    NSString *body = self.lastRequest.body ?: @"";
    XCTAssertTrue([body containsString:@"12345678901234"], @"%@", body);
    XCTAssertTrue([body containsString:@"1998-12"]);

    // the schema pattern (\d{14,18}): a 2-digit number is invalid
    [self setValue:@"12" ofControl:number];
    [self activateTriggerLabeled:@"Submit Now"];
    XCTAssertEqual(self.submittedRequests.count, (NSUInteger)1,
                   @"the schema pattern must block the submission");

    // cash: the credit fields lose relevance
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    XCTAssertTrue([select selectValue:@"cash"]);
    XCTAssertFalse(number.relevant, @"cash deselects the credit fields");
    XCTAssertFalse(expiry.relevant);
}

- (void)test_2_4_a_MultipleForms
{
    // two independent models on one page; each submit serializes ONLY
    // its own model's data
    [self loadRequired:@"Chapt02/2.4.a.xhtml"];
    [self useEchoTransport];
    XCTAssertNotNil([self modelWithID:@"pay"]);
    XCTAssertNotNil([self modelWithID:@"poll"]);
    XCTAssertEqualObjects([self stringForXPath:@"/hlp:helpmodel/hlp:helpful"
                                         model:[self modelWithID:@"poll"]], @"3");

    // the poll: four options, submit Form 2 carries only the poll data
    XFSelectControl *poll = [self controlOfClass:[XFSelectControl class] index:1];
    XCTAssertEqual(poll.items.count, (NSUInteger)4);
    XCTAssertTrue([poll selectValue:@"1"]);
    [self activateTriggerLabeled:@"Submit Form 2"];
    NSString *body = self.lastRequest.body ?: @"";
    XCTAssertTrue([body containsString:@"helpful"], @"%@", body);
    XCTAssertTrue([body containsString:@">1<"]);
    XCTAssertFalse([body containsString:@"payment"], @"only the poll model's data");

    // the payment form: fill valid data, submit Form 1 carries only it
    [self setValue:@"12345678901234" ofControl:[self controlOfClass:[XFInputControl class] index:0]];
    [self setValue:@"1998-12" ofControl:[self controlOfClass:[XFInputControl class] index:1]];
    NSUInteger before = self.submittedRequests.count;
    [self activateTriggerLabeled:@"Submit Form 1"];
    XCTAssertEqual(self.submittedRequests.count, before + 1, @"the payment form submits");
    body = self.lastRequest.body ?: @"";
    XCTAssertTrue([body containsString:@"12345678901234"], @"%@", body);
    XCTAssertFalse([body containsString:@"helpful"], @"only the payment model's data");
}

@end
