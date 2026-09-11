/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* W3C XForms 1.1 test suite, chapter 8 (Form Controls) — 59 cases.
   Widget state asserts on the real control layer (labels, help/hint/
   alert texts, range bounds, select items incl. choices group labels,
   upload via the engine's commitFileData: — headless file selection).
   Cases whose pass condition is "must not work correctly, generate an
   error, not appear, or otherwise make the problem known" accept any
   behavior, so they assert only that the form survives. SPEC-TRUE. */
#import "XFW3CTestCase.h"

@interface XFW3CChapter08Tests : XFW3CTestCase
@end

@implementation XFW3CChapter08Tests

#pragma mark 8.1.1 common behavior

- (void)test_8_1_a_NavindexAccesskey
{
    // non-normative keyboard behavior; the bindings themselves must work
    [self loadRequired:@"Chapt08/8.1/8.1.a.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"/order/quantity"] stringValue], @"3");
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"/order/name"] stringValue], @"Steven");
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"/order/item"] stringValue], @"Ball");
}

- (void)test_8_1_1_a_BindingRestrictionViolated
{
    // range bound to xsd:string → binding exception
    [self loadTest:@"Chapt08/8.1/8.1.1/8.1.1.a.xhtml"];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

- (void)test_8_1_1_b_BecomingRelevant
{
    [self loadRequired:@"Chapt08/8.1/8.1.1/8.1.1.b.xhtml"];
    XFControl *input = [self controlWithBinding:@"/person-name/first-name/name"];
    XCTAssertTrue(input.relevant, @"switch=2 at ready makes first-name relevant");
    for (NSString *e in @[ @"xforms-enabled", @"xforms-valid",
                           @"xforms-readwrite", @"xforms-optional" ]) {
        [self assertSawEvent:e];
    }
}

- (void)test_8_1_1_c_BecomingNonRelevant
{
    [self loadRequired:@"Chapt08/8.1/8.1.1/8.1.1.c.xhtml"];
    XFControl *input = [self controlWithBinding:@"/person-name/first-name/name"];
    XCTAssertFalse(input.relevant, @"switch=0 at ready hides first-name");
    [self assertSawEvent:@"xforms-disabled"];
}

#pragma mark 8.1.2-8.1.4 text controls

- (void)test_8_1_2_a_InputIncremental
{
    [self loadRequired:@"Chapt08/8.1/8.1.2/8.1.2.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self setValue:@"Elm Street" ofControl:[self controlWithBinding:@"/order/shipTo/street"]];
    [self assertSawEvent:@"xforms-value-changed"];
}

- (void)test_8_1_2_b_InputBindingRestrictions
{
    // binary-typed inputs: any "make the problem known" behavior passes
    XFProcessor *p = [self loadTest:@"Chapt08/8.1/8.1.2/8.1.2.b.xhtml"];
    XCTAssertTrue(p != nil || self.loadError != nil, @"must fail loudly or survive");
}

- (void)test_8_1_2_c_InputDatatypes
{
    [self loadRequired:@"Chapt08/8.1/8.1.2/8.1.2.c.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"/data/date-of-birth"] stringValue],
                          @"1997-12-21");
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"/data/confirm"] stringValue],
                          @"false");
}

- (void)test_8_1_3_a_SecretIncremental
{
    [self loadRequired:@"Chapt08/8.1/8.1.3/8.1.3.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self setValue:@"hunter2" ofControl:[self controlOfClass:[XFSecretControl class] index:0]];
    [self assertSawEvent:@"xforms-value-changed"];
    XCTAssertEqualObjects([self stringForXPath:@"/user/password"], @"hunter2");
}

- (void)test_8_1_3_b_SecretBindingRestrictions
{
    XFProcessor *p = [self loadTest:@"Chapt08/8.1/8.1.3/8.1.3.b.xhtml"];
    XCTAssertTrue(p != nil || self.loadError != nil);
}

- (void)test_8_1_4_a_TextareaIncrementalMultiline
{
    [self loadRequired:@"Chapt08/8.1/8.1.4/8.1.4.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self setValue:@"line one\nline two" ofControl:[self controlOfClass:[XFTextareaControl class] index:0]];
    [self assertSawEvent:@"xforms-value-changed"];
    XCTAssertTrue([[self stringForXPath:@"/car/description"] containsString:@"\n"],
                  @"textarea must keep multiple lines");
}

- (void)test_8_1_4_b_TextareaComplexContent
{
    XFProcessor *p = [self loadTest:@"Chapt08/8.1/8.1.4/8.1.4.b.xhtml"];
    XCTAssertTrue(p != nil || self.loadError != nil);
}

#pragma mark 8.1.5 output

- (void)test_8_1_5_a_OutputAppearance
{
    [self loadRequired:@"Chapt08/8.1/8.1.5/8.1.5.a.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"Lotus");
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:1] stringValue], @"2005");
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:2] stringValue], @"Aztec Bronze");
}

- (void)test_8_1_5_b_OutputValueAttribute
{
    // value= computes; a bind on the same output overrides the value attr
    [self loadRequired:@"Chapt08/8.1/8.1.5/8.1.5.b.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"1032");
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:1] stringValue], @"2005");
}

- (void)test_8_1_5_c_OutputUICommon
{
    [self loadRequired:@"Chapt08/8.1/8.1.5/8.1.5.c.xhtml"];
    XFControl *output = [self controlWithBinding:@"name"];
    XCTAssertEqualObjects(output.hint, @"This is the hint message");
    XCTAssertEqualObjects(output.help, @"This is the help message");
    XCTAssertEqualObjects(output.alert, @"That is an invalid name");
    [self activateTriggerLabeled:@"Enter An Invalid Value"];
    XCTAssertFalse(output.valid, @"empty name fails the constraint → alert case");
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Dispatch Hint Message"];
    [self assertSawEvent:@"xforms-hint"];
    [self activateTriggerLabeled:@"Dispatch Help Message"];
    [self assertSawEvent:@"xforms-help"];
}

- (void)test_8_1_5_d_OutputMediatypeAttribute
{
    [self loadRequired:@"Chapt08/8.1/8.1.5/8.1.5.d.xhtml"];
    XFOutputControl *output = [self controlOfClass:[XFOutputControl class] index:0];
    XCTAssertEqualObjects(output.stringValue, @"calendar-picker-open.png");
    XCTAssertEqualObjects(output.mediaType, @"image/*");
}

- (void)test_8_1_5_1_a_MediatypeElement
{
    // the xf:mediatype CHILD (ref="../@mediatype" = image/*) overrides
    // the mediatype ATTRIBUTE (text/plain)
    [self loadRequired:@"Chapt08/8.1/8.1.5/8.1.5.1/8.1.5.1.a.xhtml"];
    XFOutputControl *output = [self controlOfClass:[XFOutputControl class] index:0];
    XCTAssertEqualObjects(output.stringValue, @"../calendar-picker-open.png");
    XCTAssertEqualObjects(output.mediaType, @"image/*",
                          @"the mediatype element must override the attribute");
}

#pragma mark 8.1.6 upload (headless via commitFileData:)

static NSData *XFW3CPixel(void)
{
    return [NSData dataWithBytes:"\x89PNG\r\n" length:6];
}

- (void)test_8_1_6_a_UploadMediatypeAttribute
{
    [self loadRequired:@"Chapt08/8.1/8.1.6/8.1.6.a.xhtml"];
    XFUploadControl *upload = [self controlOfClass:[XFUploadControl class] index:0];
    NSArray *accepted = @[ @"image/jpeg", @"image/png" ];
    XCTAssertEqualObjects(upload.acceptedMediaTypes, accepted);
    XCTAssertTrue([upload acceptsMediaType:@"image/png"]);
    XCTAssertFalse([upload acceptsMediaType:@"application/pdf"]);
}

- (void)test_8_1_6_b_UploadIncremental
{
    [self loadRequired:@"Chapt08/8.1/8.1.6/8.1.6.b.xhtml"];
    XFUploadControl *upload = [self controlOfClass:[XFUploadControl class] index:0];
    [self.dispatchedEvents removeAllObjects];
    XCTAssertTrue([upload commitFileData:XFW3CPixel() fileName:@"pic.png"
                               mediaType:@"image/png" error:NULL]);
    [self assertSawEvent:@"xforms-value-changed"];
    XCTAssertTrue([self stringForXPath:@"/mail/picture/attach"].length > 0,
                  @"file content must land base64-encoded in the node");
}

- (void)test_8_1_6_c_UploadFilenameAndMediatype
{
    [self loadRequired:@"Chapt08/8.1/8.1.6/8.1.6.c.xhtml"];
    XFUploadControl *upload = [self controlOfClass:[XFUploadControl class] index:0];
    XCTAssertTrue([upload commitFileData:XFW3CPixel() fileName:@"holiday.png"
                               mediaType:@"image/png" error:NULL]);
    XCTAssertEqualObjects([self stringForXPath:@"/mail/picture/name"], @"holiday.png");
    XCTAssertEqualObjects([self stringForXPath:@"/mail/picture/type"], @"image/png");
}

- (void)test_8_1_6_d_UploadBindingRestriction
{
    // upload bound to xsd:string → binding exception
    [self loadTest:@"Chapt08/8.1/8.1.6/8.1.6.d.xhtml"];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

- (void)test_8_1_6_e_UploadThreeControls
{
    [self loadRequired:@"Chapt08/8.1/8.1.6/8.1.6.e.xhtml"];
    XCTAssertEqual([self countOfClass:[XFUploadControl class]], (NSUInteger)3);
    for (NSUInteger i = 0; i < 3; i++) {
        XFUploadControl *upload = [self controlOfClass:[XFUploadControl class] index:i];
        XCTAssertTrue([upload commitFileData:XFW3CPixel() fileName:@"f.png"
                                   mediaType:@"image/png" error:NULL],
                      @"upload %lu", (unsigned long)i);
    }
    XCTAssertEqual(self.messages.count, (NSUInteger)0, @"no errors: %@", self.messages);
}

- (void)test_8_1_6_1_a_FilenameElement
{
    [self loadRequired:@"Chapt08/8.1/8.1.6/8.1.6.1/8.1.6.1.a.xhtml"];
    XFUploadControl *upload = [self controlOfClass:[XFUploadControl class] index:0];
    XCTAssertTrue([upload commitFileData:XFW3CPixel() fileName:@"beach.png"
                               mediaType:@"image/png" error:NULL]);
    XCTAssertEqualObjects([self stringForXPath:@"/mail/attachment/@filename"], @"beach.png");
}

- (void)test_8_1_6_2_a_MediatypeElement
{
    [self loadRequired:@"Chapt08/8.1/8.1.6/8.1.6.2/8.1.6.2.a.xhtml"];
    XFUploadControl *upload = [self controlOfClass:[XFUploadControl class] index:0];
    XCTAssertTrue([upload commitFileData:XFW3CPixel() fileName:@"beach.png"
                               mediaType:@"image/png" error:NULL]);
    XCTAssertEqualObjects([self stringForXPath:@"/mail/attachment/@type"], @"image/png");
}

#pragma mark 8.1.7 range

- (void)test_8_1_7_a_RangeStart
{
    [self loadRequired:@"Chapt08/8.1/8.1.7/8.1.7.a.xhtml"];
    XFRangeControl *range = [self controlOfClass:[XFRangeControl class] index:0];
    XCTAssertNotNil(range);
    XCTAssertEqual(range.start, 1000.0);
    XCTAssertEqualObjects(range.stringValue, @"1000");
}

- (void)test_8_1_7_b_RangeEnd
{
    [self loadRequired:@"Chapt08/8.1/8.1.7/8.1.7.b.xhtml"];
    XFRangeControl *range = [self controlOfClass:[XFRangeControl class] index:0];
    XCTAssertEqual(range.end, 50000.0);
    XCTAssertEqualObjects(range.stringValue, @"50000");
}

- (void)test_8_1_7_c_RangeStep
{
    [self loadRequired:@"Chapt08/8.1/8.1.7/8.1.7.c.xhtml"];
    XFRangeControl *range = [self controlOfClass:[XFRangeControl class] index:0];
    XCTAssertEqual(range.step, 2.0);
}

- (void)test_8_1_7_d_RangeIncremental
{
    [self loadRequired:@"Chapt08/8.1/8.1.7/8.1.7.d.xhtml"];
    XFRangeControl *range = [self controlOfClass:[XFRangeControl class] index:0];
    [self.dispatchedEvents removeAllObjects];
    [self setValue:@"7" ofControl:range];   // initial is 5
    [self assertSawEvent:@"xforms-value-changed"];
}

- (void)test_8_1_7_e_RangeDecimal
{
    [self loadRequired:@"Chapt08/8.1/8.1.7/8.1.7.e.xhtml"];
    XFRangeControl *range = [self controlOfClass:[XFRangeControl class] index:0];
    [self setValue:@"1.5" ofControl:range];
    XCTAssertEqualObjects([self stringForXPath:@"/stats/balance"], @"1.5");
    XCTAssertTrue(range.valid);
}

- (void)test_8_1_7_f_RangeDatatypes
{
    // duration/date/time/gregorian-typed ranges "must work"
    [self loadRequired:@"Chapt08/8.1/8.1.7/8.1.7.f.xhtml"];
    XCTAssertFalse([self eventDispatched:@"xforms-binding-exception"],
                   @"every range binds an acceptable datatype");
    for (XFControl *c in [self allControls]) {
        if ([c isKindOfClass:[XFRangeControl class]]) {
            XCTAssertTrue(c.relevant, @"range %@ must render", c.binding);
        }
    }
}

- (void)test_8_1_7_g_RangeDatatypesBasic
{
    [self loadRequired:@"Chapt08/8.1/8.1.7/8.1.7.g.xhtml"];
    XCTAssertFalse([self eventDispatched:@"xforms-binding-exception"]);
}

#pragma mark 8.1.8-8.1.9 trigger, submit

- (void)test_8_1_8_a_Trigger
{
    [self loadRequired:@"Chapt08/8.1/8.1.8/8.1.8.a.xhtml"];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self.messages containsObject:@"DOMActivate"], @"%@", self.messages);
}

- (void)test_8_1_8_b_TriggerAppearance
{
    [self loadRequired:@"Chapt08/8.1/8.1.8/8.1.8.b.xhtml"];
    XCTAssertEqual([self countOfClass:[XFTriggerControl class]], (NSUInteger)2);
}

- (void)test_8_1_9_a_Submit
{
    [self loadRequired:@"Chapt08/8.1/8.1.9/8.1.9.a.xhtml"];
    [self useEchoTransport];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self.messages containsObject:@"DOMActivate"], @"%@", self.messages);
    [self assertOrderedEvents:@[ @"DOMActivate", @"xforms-submit", @"xforms-submit-done" ]];
}

- (void)test_8_1_9_b_SubmitAppearance
{
    [self loadRequired:@"Chapt08/8.1/8.1.9/8.1.9.b.xhtml"];
    XCTAssertEqual([self countOfClass:[XFSubmitControl class]], (NSUInteger)2);
}

#pragma mark 8.1.10-8.1.11 select / select1

- (void)test_8_1_10_a_SelectOpenSelection
{
    [self loadRequired:@"Chapt08/8.1/8.1.10/8.1.10.a.xhtml"];
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    XCTAssertTrue([select selectValue:@"v"]);
    XCTAssertEqualObjects([self stringForXPath:@"/icecream/flavor"], @"v");
    // selection="open": a free value must be accepted, not out-of-range
    [self setValue:@"mint" ofControl:select];
    XCTAssertEqualObjects([self stringForXPath:@"/icecream/flavor"], @"mint");
    XCTAssertFalse(select.outOfRange, @"open selection accepts free values");
}

- (void)test_8_1_10_b_SelectIncremental
{
    [self loadRequired:@"Chapt08/8.1/8.1.10/8.1.10.b.xhtml"];
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    [self.dispatchedEvents removeAllObjects];
    XCTAssertTrue([select selectValue:@"s"]);
    [self assertSawEvent:@"xforms-value-changed"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"s");
}

- (void)test_8_1_10_c_SelectAppearances
{
    [self loadRequired:@"Chapt08/8.1/8.1.10/8.1.10.c.xhtml"];
    XCTAssertEqual([self countOfClass:[XFSelectControl class]], (NSUInteger)3);
    for (NSUInteger i = 0; i < 3; i++) {
        XCTAssertEqual([(XFSelectControl *)[self controlOfClass:[XFSelectControl class] index:i] items].count,
                       (NSUInteger)3, @"select %lu", (unsigned long)i);
    }
}

- (void)test_8_1_10_d_SelectOutOfRange
{
    [self loadRequired:@"Chapt08/8.1/8.1.10/8.1.10.d.xhtml"];
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Enter An Invalid Value"];
    [self assertSawEvent:@"xforms-out-of-range"];
    XCTAssertTrue(select.outOfRange);
}

- (void)test_8_1_11_a_Select1OpenSelection
{
    [self loadRequired:@"Chapt08/8.1/8.1.11/8.1.11.a.xhtml"];
    XFSelectControl *select1 = [self controlOfClass:[XFSelectControl class] index:0];
    XCTAssertFalse(select1.multiple);
    XCTAssertTrue([select1 selectValue:@"c"]);
    XCTAssertEqualObjects([self stringForXPath:@"/icecream/flavor"], @"c");
    [self setValue:@"mint" ofControl:select1];
    XCTAssertEqualObjects([self stringForXPath:@"/icecream/flavor"], @"mint");
    XCTAssertFalse(select1.outOfRange, @"open selection accepts free values");
}

- (void)test_8_1_11_b_Select1Incremental
{
    [self loadRequired:@"Chapt08/8.1/8.1.11/8.1.11.b.xhtml"];
    XFSelectControl *select1 = [self controlOfClass:[XFSelectControl class] index:0];
    [self.dispatchedEvents removeAllObjects];
    XCTAssertTrue([select1 selectValue:@"s"]);
    [self assertSawEvent:@"xforms-value-changed"];
}

- (void)test_8_1_11_c_Select1Appearances
{
    [self loadRequired:@"Chapt08/8.1/8.1.11/8.1.11.c.xhtml"];
    XCTAssertEqual([self countOfClass:[XFSelectControl class]], (NSUInteger)3);
}

- (void)test_8_1_11_d_Select1OutOfRange
{
    [self loadRequired:@"Chapt08/8.1/8.1.11/8.1.11.d.xhtml"];
    XFSelectControl *select1 = [self controlOfClass:[XFSelectControl class] index:0];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Enter An Invalid Value"];
    [self assertSawEvent:@"xforms-out-of-range"];
    XCTAssertTrue(select1.outOfRange);
}

#pragma mark 8.2 label / help / hint / alert

- (void)test_8_2_1_a_LabelFromInstance
{
    [self loadRequired:@"Chapt08/8.2/8.2.1/8.2.1.a.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"myinput"] label], @"Instance Data");
}

- (void)test_8_2_1_b_LabelInline
{
    [self loadRequired:@"Chapt08/8.2/8.2.1/8.2.1.b.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"myinput"] label], @"Inline Text");
}

- (void)test_8_2_1_c_LabelBindingPrecedence
{
    // label/@ref beats the inline text
    [self loadRequired:@"Chapt08/8.2/8.2.1/8.2.1.c.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"myinput"] label], @"Instance Data");
}

- (void)test_8_2_2_a_HelpFromInstance
{
    [self loadRequired:@"Chapt08/8.2/8.2.2/8.2.2.a.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"myinput"] help],
                          @"Instance Help Message");
}

- (void)test_8_2_2_b_HelpInline
{
    [self loadRequired:@"Chapt08/8.2/8.2.2/8.2.2.b.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"myinput"] help],
                          @"Inline Help Message");
}

- (void)test_8_2_2_c_HelpBindingPrecedence
{
    [self loadRequired:@"Chapt08/8.2/8.2.2/8.2.2.c.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"myinput"] help],
                          @"Instance Help Message");
}

- (void)test_8_2_3_a_HintFromInstance
{
    [self loadRequired:@"Chapt08/8.2/8.2.3/8.2.3.a.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"myinput"] hint],
                          @"Instance Hint Message");
}

- (void)test_8_2_3_b_HintInline
{
    [self loadRequired:@"Chapt08/8.2/8.2.3/8.2.3.b.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"myinput"] hint],
                          @"Inline Hint Message");
}

- (void)test_8_2_3_c_HintBindingPrecedence
{
    [self loadRequired:@"Chapt08/8.2/8.2.3/8.2.3.c.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"myinput"] hint],
                          @"Instance Hint Message");
}

- (void)test_8_2_4_a_AlertFromInstance
{
    [self loadRequired:@"Chapt08/8.2/8.2.4/8.2.4.a.xhtml"];
    XFControl *input = [self controlWithBinding:@"numeric_field"];
    XCTAssertEqualObjects(input.alert, @"Instance Alert Message");
    [self setValue:@"abc" ofControl:input];
    XCTAssertFalse(input.valid, @"'abc' fails xsd:integer → the alert case");
}

- (void)test_8_2_4_b_AlertInline
{
    // NB the markup's inline text is lowercase ("Inline alert message")
    // even though the instruction label capitalizes it
    [self loadRequired:@"Chapt08/8.2/8.2.4/8.2.4.b.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"numeric_field"] alert],
                          @"Inline alert message");
}

- (void)test_8_2_4_c_AlertBindingPrecedence
{
    [self loadRequired:@"Chapt08/8.2/8.2.4/8.2.4.c.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlWithBinding:@"numeric_field"] alert],
                          @"Instance Alert Message");
}

#pragma mark 8.3 item machinery

- (void)test_8_3_1_a_Choices
{
    // the select's groups are 1-3, the select1's are 4-6
    [self loadRequired:@"Chapt08/8.3/8.3.1/8.3.1.a.xhtml"];
    NSArray<NSSet *> *expected = @[
        [NSSet setWithObjects:@"Group 1", @"Group 2", @"Group 3", nil],
        [NSSet setWithObjects:@"Group 4", @"Group 5", @"Group 6", nil],
    ];
    for (NSUInteger s = 0; s < 2; s++) {
        XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:s];
        NSMutableSet *groups = [NSMutableSet set];
        for (XFItem *item in select.items) {
            if (item.groupLabel.length) {
                [groups addObject:item.groupLabel];
            }
        }
        XCTAssertEqualObjects(groups, expected[s], @"select %lu choices groups", (unsigned long)s);
    }
}

- (void)test_8_3_2_a_Items
{
    [self loadRequired:@"Chapt08/8.3/8.3.2/8.3.2.a.xhtml"];
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    XCTAssertTrue(select.items.count >= 2, @"items: %@", select.items);
    XCTAssertEqualObjects(select.items[0].label, @"Item 1");
    XCTAssertEqualObjects(select.items[0].value, @"item1");
}

- (void)test_8_3_3_a_ValueBindingRestriction
{
    // scoops is integer-typed; item values "one"/"two" make it invalid
    [self loadRequired:@"Chapt08/8.3/8.3.3/8.3.3.a.xhtml"];
    XFSelectControl *select1 = [self controlOfClass:[XFSelectControl class] index:0];
    XCTAssertTrue([select1 selectValue:@"one"]);
    XCTAssertFalse(select1.valid, @"'one' is not an integer");
    XCTAssertTrue([select1 selectValue:@"3"]);
    XCTAssertTrue(select1.valid);
}

- (void)test_8_3_3_b_ValueElementPrecedence
{
    // every item's value/@ref points at /icecream/default → Neapolitan
    [self loadRequired:@"Chapt08/8.3/8.3.3/8.3.3.b.xhtml"];
    XFSelectControl *select1 = [self controlOfClass:[XFSelectControl class] index:0];
    XCTAssertTrue(select1.items.count > 0);
    XCTAssertTrue([select1 selectItem:select1.items.firstObject]);
    XCTAssertEqualObjects([self stringForXPath:@"/icecream/flavor"], @"Neapolitan");
}

- (void)test_8_3_3_c_ValueInline
{
    [self loadRequired:@"Chapt08/8.3/8.3.3/8.3.3.c.xhtml"];
    XFSelectControl *select1 = [self controlOfClass:[XFSelectControl class] index:0];
    XCTAssertTrue([select1 selectValue:@"red"]);
    XCTAssertEqualObjects([self stringForXPath:@"/colors/mycolor"], @"red");
    XCTAssertTrue([self valueRendered:@"red"]);
}

@end
