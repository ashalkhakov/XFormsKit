/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* W3C XForms 1.1 test suite, chapter 6 (Model Item Properties) — 11
   cases, asserted on real control/model state (readonly, relevant,
   validity, calculate results) through the same paths a user's edits
   take. SPEC-TRUE. */
#import "XFW3CTestCase.h"

@interface XFW3CChapter06Tests : XFW3CTestCase
@end

@implementation XFW3CChapter06Tests

- (XFControl *)inputBoundTo:(NSString *)binding
{
    XFControl *c = [self controlWithBinding:binding];
    XCTAssertNotNil(c, @"no control bound to %@", binding);
    return c;
}

- (void)test_6_1_1_a_TypeProperty
{
    [self loadRequired:@"Chapt06/6.1/6.1.1/6.1.1.a.xhtml"];
    [self activateTriggerLabeled:@"Check Month"];
    XFControl *month = [self inputBoundTo:@"month_bind"];
    XCTAssertEqualObjects([self stringForXPath:@"/person/month"], @"--04");
    XCTAssertTrue(month.valid, @"--04 is a valid gMonth (bind/@type)");
    [self activateTriggerLabeled:@"Check Year"];
    XFControl *year = [self inputBoundTo:@"/person/year"];
    XCTAssertTrue(year.valid, @"1999 is a valid gYear (xsi:type)");
}

- (void)test_6_1_2_a_ReadonlyProperty
{
    [self loadRequired:@"Chapt06/6.1/6.1.2/6.1.2.a.xhtml"];
    XFControl *first = [self inputBoundTo:@"/person-name/first-name"];
    XFControl *last = [self inputBoundTo:@"/person-name/last-name"];
    XCTAssertEqualObjects(first.stringValue, @"Roland");
    XCTAssertEqualObjects(last.stringValue, @"Orlando");
    XCTAssertTrue(first.readonly);
    XCTAssertFalse(last.readonly);
    // a readonly node must not take a user edit
    [self.processor setValue:@"Hacked" ofControl:first error:NULL];
    XCTAssertEqualObjects([self stringForXPath:@"/person-name/first-name"], @"Roland",
                          @"readonly node must not change on user edit");
    [self.processor setValue:@"Lando" ofControl:last error:NULL];
    XCTAssertEqualObjects([self stringForXPath:@"/person-name/last-name"], @"Lando");
}

- (void)test_6_1_2_b_ReadonlyInheritance
{
    // an ancestor's readonly=true wins over the child's own false()
    [self loadRequired:@"Chapt06/6.1/6.1.2/6.1.2.b.xhtml"];
    XCTAssertTrue([(XFControl *)[self inputBoundTo:@"/person-name/first-name"] readonly]);
    XCTAssertTrue([(XFControl *)[self inputBoundTo:@"/person-name/last-name"] readonly],
                  @"readonly inherits TRUE from the ancestor bind despite false()");
}

- (void)test_6_1_3_a_RequiredBlocksSubmission
{
    [self loadRequired:@"Chapt06/6.1/6.1.3/6.1.3.a.xhtml"];
    [self useEchoTransport];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerAtIndex:0];   // the submit; first-name is empty
    XCTAssertTrue([self eventDispatched:@"xforms-submit-error"],
                  @"empty required node must block submission: %@", self.dispatchedEvents);
    XCTAssertFalse([self eventDispatched:@"xforms-submit-done"]);
    // fill the required node — submission must now go through
    [self setValue:@"Ada" ofControl:[self inputBoundTo:@"/person-name/first-name"]];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self eventDispatched:@"xforms-submit-done"],
                  @"filled required node must submit: %@", self.dispatchedEvents);
}

- (void)test_6_1_4_a_RelevantInheritance
{
    [self loadRequired:@"Chapt06/6.1/6.1.4/6.1.4.a.xhtml"];
    XCTAssertFalse([(XFControl *)[self inputBoundTo:@"/person-name/first-name/title"] relevant],
                   @"children of a non-relevant node inherit non-relevance");
    XCTAssertFalse([(XFControl *)[self inputBoundTo:@"/person-name/first-name/name"] relevant]);
    XCTAssertTrue([(XFControl *)[self inputBoundTo:@"/person-name/last-name"] relevant]);
}

- (void)test_6_1_4_b_RelevantProperty
{
    [self loadRequired:@"Chapt06/6.1/6.1.4/6.1.4.b.xhtml"];
    XFControl *discount = [self inputBoundTo:@"/order/item/discount"];
    [self activateTriggerLabeled:@"Enter 1500"];
    XCTAssertTrue(discount.relevant, @"amount 1500 > 1000 shows the discount");
    XCTAssertEqualObjects(discount.stringValue, @"100");
    [self activateTriggerLabeled:@"Enter 250"];
    XCTAssertFalse(discount.relevant, @"amount 250 hides the discount");
}

- (void)test_6_1_4_c_RelevantInheritanceScopes
{
    [self loadRequired:@"Chapt06/6.1/6.1.4/6.1.4.c.xhtml"];
    XCTAssertTrue([(XFControl *)[self inputBoundTo:@"personA/value"] relevant]);
    XCTAssertTrue([(XFControl *)[self inputBoundTo:@"personA/favcolor"] relevant]);
    XCTAssertTrue([(XFControl *)[self inputBoundTo:@"personB/value"] relevant]);
    XCTAssertFalse([(XFControl *)[self inputBoundTo:@"personB/favcolor"] relevant]);
    XCTAssertFalse([(XFControl *)[self inputBoundTo:@"personC/value"] relevant]);
    XCTAssertFalse([(XFControl *)[self inputBoundTo:@"personC/favcolor"] relevant]);
}

- (void)test_6_1_5_a_CalculateProperty
{
    [self loadRequired:@"Chapt06/6.1/6.1.5/6.1.5.a.xhtml"];
    XFControl *discount = [self inputBoundTo:@"/order/item/discount"];
    [self activateTriggerLabeled:@"Enter 1500"];
    XCTAssertEqualObjects(discount.stringValue, @"750");
    XCTAssertTrue(discount.relevant);
    [self activateTriggerLabeled:@"Enter 2000"];
    XCTAssertEqualObjects(discount.stringValue, @"1000");
    [self activateTriggerLabeled:@"Enter 250"];
    XCTAssertFalse(discount.relevant, @"amount 250 hides the discount output");
}

- (void)test_6_1_6_a_ConstraintProperty
{
    [self loadRequired:@"Chapt06/6.1/6.1.6/6.1.6.a.xhtml"];
    XFControl *to = [self inputBoundTo:@"/range/to"];
    [self activateTriggerLabeled:@"Valid Value"];
    XCTAssertTrue(to.valid, @"25 > 10 satisfies the constraint");
    [self activateTriggerLabeled:@"Invalid Value"];
    XCTAssertFalse(to.valid, @"5 > 10 fails the constraint");
}

- (void)test_6_1_7_a_P3PTypeProperty
{
    // p3ptype is host metadata (auto-fill hinting): the form must load,
    // bind, edit and submit normally with it present.
    [self loadRequired:@"Chapt06/6.1/6.1.7/6.1.7.a.xhtml"];
    [self useEchoTransport];
    [self setValue:@"Ada" ofControl:[self inputBoundTo:@"/person-name/first-name"]];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self eventDispatched:@"xforms-submit-done"], @"%@", self.dispatchedEvents);
}

- (void)test_6_2_1_a_InlineSchemaAtomicType
{
    // xsd:schema inline in the model: nonEmptyString (minLength 1)
    [self loadRequired:@"Chapt06/6.2/6.2.1/6.2.1.a.xhtml"];
    XFControl *name = [self inputBoundTo:@"/first-name"];
    [self activateTriggerLabeled:@"Use Empty String"];
    XCTAssertFalse(name.valid, @"empty fails minLength=1");
    [self activateTriggerLabeled:@"Use Joe"];
    XCTAssertTrue(name.valid);
}

@end
