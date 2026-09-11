/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* W3C XForms 1.1 test suite, chapter 7 (XPath Expressions) — 62 cases.
   Function results assert on the outputs' rendered values; the
   digest/hmac vector forms encode PASS/FAIL as group relevance
   (self::node()[fn = 'vector']), asserted directly. Timezone-dependent
   expectations (local-date, now, adjust-dateTime-to-timezone) assert
   the lexical shape or a timezone-independent equivalence instead of a
   hardcoded local value. SPEC-TRUE. */
#import "XFW3CTestCase.h"

@interface XFW3CChapter07Tests : XFW3CTestCase
@end

@implementation XFW3CChapter07Tests

- (NSString *)outputValue:(NSUInteger)index
{
    XFControl *c = [self controlOfClass:[XFOutputControl class] index:index];
    return c.stringValue ?: @"";
}

- (NSString *)trimmedOutput:(NSUInteger)index
{
    return [[self outputValue:index] stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)assertOutputs:(NSArray<NSString *> *)expected
{
    for (NSUInteger i = 0; i < expected.count; i++) {
        XCTAssertEqualObjects([self trimmedOutput:i], expected[i],
                              @"output %lu: got '%@'", (unsigned long)i,
                              [self trimmedOutput:i]);
    }
}

/// The digest/hmac vector forms: every group labeled "PASS" must be
/// relevant (its self::node() predicate held) and every "FAIL" group
/// must not.
- (void)assertPassGroupsShown
{
    NSUInteger passes = 0, fails = 0;
    for (XFControl *c in [self allControls]) {
        if (![c isKindOfClass:[XFGroup class]] || c.label.length == 0) {
            continue;
        }
        // only the vector groups (ref="self::node()[fn = 'vector']") —
        // the instruction label also mentions "PASS". NB: messaging nil
        // returns a ZEROED NSRange (location 0 ≠ NSNotFound), so the
        // no-ref case needs its own check.
        NSString *ref = [[c.element attributeForName:@"ref"] stringValue];
        if (ref.length == 0
            || [ref rangeOfString:@"self::node()"].location == NSNotFound) {
            continue;
        }
        if ([c.label rangeOfString:@"PASS"].location != NSNotFound) {
            passes++;
            XCTAssertTrue(c.relevant, @"'%@' must be shown", c.label);
        } else if ([c.label rangeOfString:@"FAIL"].location != NSNotFound) {
            fails++;
            XCTAssertFalse(c.relevant, @"'%@' must be hidden", c.label);
        }
    }
    XCTAssertTrue(passes > 0 && passes == fails,
                  @"expected matched PASS/FAIL group pairs (%lu/%lu)",
                  (unsigned long)passes, (unsigned long)fails);
}

- (BOOL)value:(NSString *)value matchesPattern:(NSString *)pattern
{
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:pattern options:0 error:NULL];
    return [re numberOfMatchesInString:value options:0
                                 range:NSMakeRange(0, value.length)] == 1;
}

#pragma mark 7.2 evaluation context

- (void)test_7_2_a_OutermostBindingContext
{
    [self loadRequired:@"Chapt07/7.2/7.2.a.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFInputControl class] index:0] stringValue], @"Seth");
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFInputControl class] index:1] stringValue], @"Peters");
    XCTAssertEqualObjects([self trimmedOutput:0], @"speters@example.com");
}

- (void)test_7_2_b_NonOutermostBindingContext
{
    [self loadRequired:@"Chapt07/7.2/7.2.b.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFInputControl class] index:0] stringValue], @"Curtiss");
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFInputControl class] index:1] stringValue], @"Hewie");
    XCTAssertEqualObjects([self trimmedOutput:0], @"chewie@example.com");
}

- (void)test_7_2_c_ContextNodeWithinContextModel
{
    // no model attr → M1; model="M2" → M2; inside a group with model M3 → M3
    [self loadRequired:@"Chapt07/7.2/7.2.c.xhtml"];
    [self assertOutputs:@[ @"1", @"2", @"3" ]];
}

- (void)test_7_2_d_ComputedExpressionContextNode
{
    [self loadRequired:@"Chapt07/7.2/7.2.d.xhtml"];
    [self assertOutputs:@[ @"6", @"20", @"42" ]];
}

- (void)test_7_2_e_ContextSizeAndPosition
{
    // calculate="position() + last()" over three siblings → 4, 5, 6
    [self loadRequired:@"Chapt07/7.2/7.2.e.xhtml"];
    [self assertOutputs:@[ @"4", @"5", @"6" ]];
}

- (void)test_7_2_f_NamespaceDeclarationsInScope
{
    [self loadRequired:@"Chapt07/7.2/7.2.f.xhtml"];
    XFControl *input = [self controlOfClass:[XFInputControl class] index:0];
    XCTAssertEqualObjects([input.stringValue stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]], @"Mazda");
    XCTAssertTrue(input.readonly, @"the ex:-prefixed bind must reach the node");
}

#pragma mark 7.4-7.5

- (void)test_7_4_6_a_BindingExamples
{
    [self loadRequired:@"Chapt07/7.4/7.4.6/7.4.6.a.xhtml"];
    for (NSUInteger i = 0; i < 3; i++) {
        XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFInputControl class] index:i] stringValue],
                              @"John", @"input %lu", (unsigned long)i);
    }
}

- (void)test_7_5_a_MIPErrorComputeException
{
    [self loadTest:@"Chapt07/7.5/7.5.a.xhtml"];
    [self assertMessageOrFatal:@"xforms-compute-exception"];
}

- (void)test_7_5_b_BindingErrorBindingException
{
    [self loadTest:@"Chapt07/7.5/7.5.b.xhtml"];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

#pragma mark 7.6 boolean functions

- (void)test_7_6_1_a_BooleanFromString
{
    [self loadRequired:@"Chapt07/7.6/7.6.1/7.6.1.a.xhtml"];
    [self assertOutputs:@[ @"true", @"true", @"true",
                           @"false", @"false", @"false", @"false" ]];
}

- (void)test_7_6_2_a_IsCardNumber
{
    [self loadRequired:@"Chapt07/7.6/7.6.2/7.6.2.a.xhtml"];
    [self assertOutputs:@[ @"true", @"true", @"true",
                           @"false", @"false", @"false" ]];
}

#pragma mark 7.7 number functions

- (void)test_7_7_1_a_Avg
{
    [self loadRequired:@"Chapt07/7.7/7.7.1/7.7.1.a.xhtml"];
    XCTAssertEqualObjects([self trimmedOutput:0], @"4");
}

- (void)test_7_7_1_b_AvgNegative
{
    [self loadRequired:@"Chapt07/7.7/7.7.1/7.7.1.b.xhtml"];
    [self assertOutputs:@[ @"NaN", @"NaN" ]];
}

- (void)test_7_7_2_a_Min
{
    [self loadRequired:@"Chapt07/7.7/7.7.2/7.7.2.a.xhtml"];
    XCTAssertEqualObjects([self trimmedOutput:0], @"2");
}

- (void)test_7_7_2_b_MinNegative
{
    [self loadRequired:@"Chapt07/7.7/7.7.2/7.7.2.b.xhtml"];
    [self assertOutputs:@[ @"NaN", @"NaN" ]];
}

- (void)test_7_7_3_a_Max
{
    [self loadRequired:@"Chapt07/7.7/7.7.3/7.7.3.a.xhtml"];
    XCTAssertEqualObjects([self trimmedOutput:0], @"6");
}

- (void)test_7_7_3_b_MaxNegative
{
    [self loadRequired:@"Chapt07/7.7/7.7.3/7.7.3.b.xhtml"];
    [self assertOutputs:@[ @"NaN", @"NaN" ]];
}

- (void)test_7_7_4_a_CountNonEmpty
{
    [self loadRequired:@"Chapt07/7.7/7.7.4/7.7.4.a.xhtml"];
    [self assertOutputs:@[ @"2", @"0" ]];
}

- (void)test_7_7_5_a_Index
{
    [self loadRequired:@"Chapt07/7.7/7.7.5/7.7.5.a.xhtml"];
    XCTAssertEqualObjects([self trimmedOutput:0], @"1");
}

- (void)test_7_7_5_b_IndexNegative
{
    [self loadRequired:@"Chapt07/7.7/7.7.5/7.7.5.b.xhtml"];
    XCTAssertEqualObjects([self trimmedOutput:0], @"NaN");
}

- (void)test_7_7_6_a_Power
{
    [self loadRequired:@"Chapt07/7.7/7.7.6/7.7.6.a.xhtml"];
    [self assertOutputs:@[ @"8", @"NaN" ]];
}

- (void)test_7_7_7_a_Random
{
    [self loadRequired:@"Chapt07/7.7/7.7.7/7.7.7.a.xhtml"];
    for (NSUInteger i = 0; i < 3; i++) {
        NSString *v = [self trimmedOutput:i];
        double d = [v doubleValue];
        XCTAssertTrue(v.length > 0 && d >= 0.0 && d < 1.0,
                      @"random() output %lu out of [0,1): '%@'", (unsigned long)i, v);
    }
}

- (void)test_7_7_8_a_Compare
{
    [self loadRequired:@"Chapt07/7.7/7.7.8/7.7.8.a.xhtml"];
    [self assertOutputs:@[ @"-1", @"0", @"1" ]];
}

#pragma mark 7.8 string/crypto functions

- (void)test_7_8_1_a_If
{
    [self loadRequired:@"Chapt07/7.8/7.8.1/7.8.1.a.xhtml"];
    [self assertOutputs:@[ @"Yes", @"Unsafe" ]];
}

- (void)test_7_8_2_a_PropertyVersion
{
    [self loadRequired:@"Chapt07/7.8/7.8.2/7.8.2.a.xhtml"];
    XCTAssertEqualObjects([self trimmedOutput:0], @"1.1");
}

- (void)test_7_8_2_b_PropertyConformanceLevel
{
    [self loadRequired:@"Chapt07/7.8/7.8.2/7.8.2.b.xhtml"];
    NSString *v = [self trimmedOutput:0];
    XCTAssertTrue([v isEqualToString:@"basic"] || [v isEqualToString:@"full"]
                      || [v hasPrefix:@"http"],
                  @"conformance-level must be basic/full/a URI: '%@'", v);
}

- (void)test_7_8_2_c_PropertyInvalidNCName
{
    [self loadTest:@"Chapt07/7.8/7.8.2/7.8.2.c.xhtml"];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
    if (self.processor) {
        XCTAssertEqualObjects([self trimmedOutput:0], @"");
    }
}

- (void)test_7_8_2_d_PropertyQNameNotNCName
{
    // "You must see no value for the Invalid Property output."
    [self loadRequired:@"Chapt07/7.8/7.8.2/7.8.2.d.xhtml"];
    XCTAssertEqualObjects([self trimmedOutput:0], @"");
}

- (void)test_7_8_3_a_DigestSHA1MD5SHA256
{
    [self loadRequired:@"Chapt07/7.8/7.8.3/7.8.3.a.xhtml"];
    [self assertPassGroupsShown];
}

- (void)test_7_8_3_b_DigestSHA384SHA512
{
    [self loadRequired:@"Chapt07/7.8/7.8.3/7.8.3.b.xhtml"];
    [self assertPassGroupsShown];
}

- (void)test_7_8_3_c_DigestInvalidNCName
{
    [self loadTest:@"Chapt07/7.8/7.8.3/7.8.3.c.xhtml"];
    [self assertMessageOrFatal:@"xforms-compute-exception"];
}

- (void)test_7_8_3_d_DigestQNameNotNCName
{
    [self loadTest:@"Chapt07/7.8/7.8.3/7.8.3.d.xhtml"];
    [self assertMessageOrFatal:@"xforms-compute-exception"];
}

- (void)test_7_8_3_e_DigestInvalidEncoding
{
    [self loadTest:@"Chapt07/7.8/7.8.3/7.8.3.e.xhtml"];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

- (void)test_7_8_3_f_DigestDefaultBase64
{
    [self loadRequired:@"Chapt07/7.8/7.8.3/7.8.3.f.xhtml"];
    [self assertPassGroupsShown];
}

- (void)test_7_8_4_a_HmacSHA1MD5SHA256
{
    [self loadRequired:@"Chapt07/7.8/7.8.4/7.8.4.a.xhtml"];
    [self assertPassGroupsShown];
}

- (void)test_7_8_4_b_HmacSHA384SHA512
{
    [self loadRequired:@"Chapt07/7.8/7.8.4/7.8.4.b.xhtml"];
    [self assertPassGroupsShown];
}

- (void)test_7_8_4_c_HmacInvalidNCName
{
    [self loadTest:@"Chapt07/7.8/7.8.4/7.8.4.c.xhtml"];
    [self assertMessageOrFatal:@"xforms-compute-exception"];
}

- (void)test_7_8_4_d_HmacQNameNotNCName
{
    [self loadTest:@"Chapt07/7.8/7.8.4/7.8.4.d.xhtml"];
    [self assertMessageOrFatal:@"xforms-compute-exception"];
}

- (void)test_7_8_4_e_HmacInvalidEncoding
{
    [self loadTest:@"Chapt07/7.8/7.8.4/7.8.4.e.xhtml"];
    [self assertMessageOrFatal:@"xforms-compute-exception"];
}

- (void)test_7_8_4_f_HmacDefaultBase64
{
    [self loadRequired:@"Chapt07/7.8/7.8.4/7.8.4.f.xhtml"];
    [self assertPassGroupsShown];
}

#pragma mark 7.9 date/time functions

- (void)test_7_9_1_a_LocalDate
{
    [self loadRequired:@"Chapt07/7.9/7.9.1/7.9.1.a.xhtml"];
    XCTAssertTrue([self value:[self trimmedOutput:0] matchesPattern:
        @"^\\d{4}-\\d{2}-\\d{2}(Z|[+-]\\d{2}:\\d{2})?$"],
        @"local-date(): '%@'", [self trimmedOutput:0]);
}

- (void)test_7_9_2_a_LocalDateTime
{
    [self loadRequired:@"Chapt07/7.9/7.9.2/7.9.2.a.xhtml"];
    XCTAssertTrue([self value:[self trimmedOutput:0] matchesPattern:
        @"^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?(Z|[+-]\\d{2}:\\d{2})?$"],
        @"local-dateTime(): '%@'", [self trimmedOutput:0]);
}

- (void)test_7_9_3_a_Now
{
    [self loadRequired:@"Chapt07/7.9/7.9.3/7.9.3.a.xhtml"];
    XCTAssertTrue([self value:[self trimmedOutput:0] matchesPattern:
        @"^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?(Z|[+-]\\d{2}:\\d{2})$"],
        @"now(): '%@'", [self trimmedOutput:0]);
}

- (void)test_7_9_4_a_DaysFromDate
{
    [self loadRequired:@"Chapt07/7.9/7.9.4/7.9.4.a.xhtml"];
    [self assertOutputs:@[ @"11688", @"-1" ]];
}

- (void)test_7_9_4_b_DaysFromDateIgnoresTime
{
    [self loadRequired:@"Chapt07/7.9/7.9.4/7.9.4.b.xhtml"];
    XCTAssertEqualObjects([self trimmedOutput:0], @"4");
}

- (void)test_7_9_4_c_DaysFromDateNegative
{
    [self loadRequired:@"Chapt07/7.9/7.9.4/7.9.4.c.xhtml"];
    XCTAssertEqualObjects([self trimmedOutput:0], @"NaN");
}

- (void)test_7_9_5_a_DaysToDate
{
    [self loadRequired:@"Chapt07/7.9/7.9.5/7.9.5.a.xhtml"];
    [self assertOutputs:@[ @"2002-01-01", @"1969-12-31" ]];
}

- (void)test_7_9_6_a_SecondsFromDateTime
{
    [self loadRequired:@"Chapt07/7.9/7.9.6/7.9.6.a.xhtml"];
    NSString *year = [self trimmedOutput:0];
    XCTAssertTrue([year isEqualToString:@"31536000"] || [year isEqualToString:@"3.1536E7"],
                  @"one year of seconds: '%@'", year);
    XCTAssertEqualObjects([self trimmedOutput:1], @"0.001");
    XCTAssertEqualObjects([self trimmedOutput:2], @"NaN");
}

- (void)test_7_9_7_a_SecondsToDateTime
{
    [self loadRequired:@"Chapt07/7.9/7.9.7/7.9.7.a.xhtml"];
    XCTAssertEqualObjects([self trimmedOutput:0], @"1970-01-01T00:00:00Z");
}

- (void)test_7_9_8_a_AdjustDateTimeToTimezone
{
    [self loadRequired:@"Chapt07/7.9/7.9.8/7.9.8.a.xhtml"];
    // Test 2's expected value is local-timezone-dependent; assert the
    // timezone-independent truth instead: adjusting must preserve the
    // instant, and the result must carry an explicit offset.
    XCTAssertEqualObjects([self stringForXPath:
        @"seconds-from-dateTime(adjust-dateTime-to-timezone('2007-10-02T21:26:43Z'))"
        @" = seconds-from-dateTime('2007-10-02T21:26:43Z')"], @"true");
    XCTAssertTrue([self value:[self trimmedOutput:1] matchesPattern:
        @"^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?(Z|[+-]\\d{2}:\\d{2})$"],
        @"adjusted dateTime: '%@'", [self trimmedOutput:1]);
}

- (void)test_7_9_9_a_Seconds
{
    [self loadRequired:@"Chapt07/7.9/7.9.9/7.9.9.a.xhtml"];
    XCTAssertEqualObjects([self trimmedOutput:0], @"0");
    XCTAssertEqualObjects([self trimmedOutput:1], @"297001.5");
    XCTAssertEqualObjects([self trimmedOutput:2], @"NaN");
}

- (void)test_7_9_10_a_Months
{
    [self loadRequired:@"Chapt07/7.9/7.9.10/7.9.10.a.xhtml"];
    XCTAssertEqualObjects([self trimmedOutput:0], @"14");
    XCTAssertEqualObjects([self trimmedOutput:1], @"-19");
    XCTAssertEqualObjects([self trimmedOutput:2], @"NaN");
}

#pragma mark 7.10 node-set functions

- (void)test_7_10_1_a_Instance
{
    // instance('orderform') picks by id; instance() = the default instance
    [self loadRequired:@"Chapt07/7.10/7.10.1/7.10.1.a.xhtml"];
    [self assertOutputs:@[ @"John", @"George" ]];
}

- (void)test_7_10_2_a_Current1
{
    [self loadRequired:@"Chapt07/7.10/7.10.2/7.10.2.a.xhtml"];
    XCTAssertEqualObjects([self trimmedOutput:0], @"8023.451");
}

- (void)test_7_10_2_b_Current2
{
    [self loadRequired:@"Chapt07/7.10/7.10.2/7.10.2.b.xhtml"];
    [self assertOutputs:@[ @"Jan", @"Feb", @"Mar" ]];
}

- (void)test_7_10_3_a_IdFunction
{
    [self loadRequired:@"Chapt07/7.10/7.10.3/7.10.3.a.xhtml"];
    [self assertOutputs:@[ @"Node-A", @"Node-B", @"Node-C" ]];
    XCTAssertFalse([self valueRendered:@"Node-D"]);
    XCTAssertFalse([self valueRendered:@"Node-F"]);
}

- (void)test_7_10_3_b_IdFunctionScoped
{
    // id('a b c', /root/level_1a): only Node-A lives under level_1a
    [self loadRequired:@"Chapt07/7.10/7.10.3/7.10.3.b.xhtml"];
    XCTAssertEqualObjects([self trimmedOutput:0], @"Node-A");
    XCTAssertFalse([self valueRendered:@"Node-B"]);
    XCTAssertFalse([self valueRendered:@"Node-C"]);
}

- (void)test_7_10_3_c_IdFunctionXsiType
{
    // the ID-ness comes from xsi:type="xsd:ID" on the CONTENT
    [self loadRequired:@"Chapt07/7.10/7.10.3/7.10.3.c.xhtml"];
    [self assertOutputs:@[ @"Node-A", @"Node-B", @"Node-C" ]];
}

- (void)test_7_10_4_a_Context
{
    [self loadRequired:@"Chapt07/7.10/7.10.4/7.10.4.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"/fruitRoot/bad-fruit"], @"Unknown");
    // the triggers' labels are computed (label ref="."): item 1 = apple
    XFControl *first = [self controlOfClass:[XFTriggerControl class] index:0];
    XCTAssertNotNil(first);
    XCTAssertEqualObjects(first.label, @"apple", @"label ref='.' must compute");
    // setvalue value="context()" inside the repeat item: the in-scope
    // context is that item's fruit node
    [self activateTrigger:first];
    XCTAssertEqualObjects([self stringForXPath:@"/fruitRoot/bad-fruit"], @"apple");
}

#pragma mark 7.11-7.12

- (void)test_7_11_1_a_Choose
{
    // 3 dogs vs 4 cats → the cats nodeset
    [self loadRequired:@"Chapt07/7.11/7.11.1/7.11.1.a.xhtml"];
    [self assertOutputs:@[ @"Garfield", @"Heathcliff", @"Felix", @"Tom" ]];
    XCTAssertFalse([self valueRendered:@"Benji"]);
}

- (void)test_7_11_2_a_EventInsertedNodes
{
    [self loadRequired:@"Chapt07/7.11/7.11.2/7.11.2.a.xhtml"];
    [self activateTriggerLabeled:@"Insert A Date"];
    NSString *v = [self stringForXPath:@"/descriptions/insert_description"
                                 model:[self modelWithID:@"description_catcher"]];
    // "the XPath expression '/Dates/date' or '2006-01-01'"
    XCTAssertTrue([v isEqualToString:@"2006-01-01"] || [v isEqualToString:@"/Dates/date"],
                  @"event('inserted-nodes'): '%@'", v);
}

- (void)test_7_12_a_InvalidFunctionsAttribute
{
    [self loadTest:@"Chapt07/7.12/7.12.a.xhtml"];
    [self assertMessageOrFatal:@"xforms-compute-exception"];
}

@end
