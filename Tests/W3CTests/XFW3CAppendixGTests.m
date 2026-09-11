/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* W3C XForms 1.1 test suite, appendix G (Complete XForms 1.1 CSS —
   non-normative) as XCTest assertions — see XFW3CTestCase.h for the
   approach and the spec-true policy. The appendix's observable is CSS
   styling of MIP states; headless, the tests assert the underlying MIP
   state on the real controls — the state the pseudo-classes select on —
   plus the index/interaction behavior the styling is meant to show. */
#import "XFW3CTestCase.h"

@interface XFW3CAppendixGTests : XFW3CTestCase
@end

@implementation XFW3CAppendixGTests

- (void)test_g_1_a_EnabledDisabledPseudoClasses
{
    [self loadRequired:@"Appendix/G/G.1/g.1.a.xhtml"];
    XFInputControl *make = [self controlOfClass:[XFInputControl class] index:0];
    XCTAssertTrue(make.relevant, @":enabled — relevant = true()");
    // the non-relevant control is invisible to the relevant-only walk;
    // its bound node carries the state
    XCTAssertEqualObjects([self stringForXPath:@"/car/model"], @"Civic");
    XCTAssertEqual([self countOfClass:[XFInputControl class]], (NSUInteger)2);
    XFInputControl *model = [self controlOfClass:[XFInputControl class] index:1];
    XCTAssertFalse(model.relevant, @":disabled — relevant = false()");
}

- (void)test_g_1_b_RequiredOptionalPseudoClasses
{
    [self loadRequired:@"Appendix/G/G.1/g.1.b.xhtml"];
    XFOutputControl *make = [self controlOfClass:[XFOutputControl class] index:0];
    XFOutputControl *model = [self controlOfClass:[XFOutputControl class] index:1];
    XCTAssertTrue(make.required, @":required");
    XCTAssertFalse(model.required, @":optional");
}

- (void)test_g_1_c_ValidInvalidPseudoClasses
{
    [self loadRequired:@"Appendix/G/G.1/g.1.c.xhtml"];
    XFOutputControl *oil = [self controlOfClass:[XFOutputControl class] index:0];
    XFOutputControl *tire = [self controlOfClass:[XFOutputControl class] index:1];
    XCTAssertTrue(oil.valid, @"'true' is a valid xsd:boolean");
    XCTAssertFalse(tire.valid, @"'not yet' is not");
}

- (void)test_g_1_d_ReadOnlyReadWritePseudoClasses
{
    [self loadRequired:@"Appendix/G/G.1/g.1.d.xhtml"];
    XFOutputControl *oil = [self controlOfClass:[XFOutputControl class] index:0];
    XFOutputControl *tire = [self controlOfClass:[XFOutputControl class] index:1];
    XCTAssertTrue(oil.readonly, @":read-only");
    XCTAssertFalse(tire.readonly, @":read-write");
}

- (void)test_g_1_e_InRangeOutOfRangePseudoClasses
{
    // year 2000 lies inside [1975,2010]; horsepower -100 outside [0,2000]
    [self loadRequired:@"Appendix/G/G.1/g.1.e.xhtml"];
    XFRangeControl *year = [self controlOfClass:[XFRangeControl class] index:0];
    XFRangeControl *hp = [self controlOfClass:[XFRangeControl class] index:1];
    XCTAssertNotNil(year);
    XCTAssertNotNil(hp);
    XCTAssertEqualObjects([self stringForXPath:@"/car/horsepower"], @"-100");
    // the state behind :out-of-range is announced by the range events
    XCTAssertTrue([self eventDispatched:@"xforms-out-of-range"],
                  @"the out-of-range value must be flagged");
}

- (void)test_g_2_a_ValuePseudoElement
{
    [self loadRequired:@"Appendix/G/G.2/g.2.a.xhtml"];
    XFInputControl *year = [self controlOfClass:[XFInputControl class] index:0];
    XCTAssertEqualObjects(year.stringValue, @"2000",
                          @"::value styles the rendered value part");
}

- (void)test_g_2_b_RepeatItemPseudoElement
{
    [self loadRequired:@"Appendix/G/G.2/g.2.b.xhtml"];
    XFRepeat *repeat = [self controlOfClass:[XFRepeat class] index:0];
    XCTAssertEqual(repeat.items.count, (NSUInteger)3);
    XCTAssertTrue([self valueRendered:@"Honda"]);
    XCTAssertTrue([self valueRendered:@"Toyota"]);
    XCTAssertTrue([self valueRendered:@"Acura"]);
}

- (void)test_g_2_c_RepeatIndexPseudoElement
{
    [self loadRequired:@"Appendix/G/G.2/g.2.c.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"index('repeat1')"], @"1");
    [self activateTriggerLabeled:@"Set Index to 2"];
    XCTAssertEqualObjects([self stringForXPath:@"index('repeat1')"], @"2");
    [self activateTriggerLabeled:@"Set Index to 3"];
    XCTAssertEqualObjects([self stringForXPath:@"index('repeat1')"], @"3");
    [self activateTriggerLabeled:@"Set Index to 1"];
    XCTAssertEqualObjects([self stringForXPath:@"index('repeat1')"], @"1");
}

- (void)test_g_2_d_RepeatIndexPrecedence
{
    // same interaction as g.2.c — the precedence is a styling matter;
    // the selected item is the one the index names
    [self loadRequired:@"Appendix/G/G.2/g.2.d.xhtml"];
    XFRepeat *repeat = [self controlOfClass:[XFRepeat class] index:0];
    XCTAssertEqual(repeat.items.count, (NSUInteger)3);
    [self activateTriggerLabeled:@"Set Index to 2"];
    XCTAssertEqualObjects([self stringForXPath:@"index('repeat1')"], @"2");
    XCTAssertTrue([(XFRepeatItem *)repeat.items[1] selected],
                  @"the indexed item is the selected one");
    XCTAssertFalse([(XFRepeatItem *)repeat.items[0] selected]);
}

- (void)test_g_3_NamespaceExample
{
    [self loadRequired:@"Appendix/G/G.3/g.3.xhtml"];
    XFRepeat *repeat = [self controlOfClass:[XFRepeat class] index:0];
    XCTAssertEqual(repeat.items.count, (NSUInteger)3);
    XCTAssertTrue([self valueRendered:@"Honda"]);
}

@end
