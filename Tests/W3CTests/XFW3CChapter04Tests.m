/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* W3C XForms 1.1 test suite, chapter 4 (Processing Model) — 67 cases.
   Event observations come from the ms68 trace sink (installed before
   load, so construction-time dispatches are seen) plus the message
   handler for post-load messages. SPEC-TRUE: engine gaps stay red.
   4.5.3.a is absent upstream (no file to test); 4.8.1.a/b exercise the
   scripting DOM API, which this host does not provide — their tests
   assert only that the forms load (the JS legs are n/a, not failures). */
#import "XFW3CTestCase.h"

@interface XFW3CChapter04Tests : XFW3CTestCase
@end

@implementation XFW3CChapter04Tests


#pragma mark 4.2 initialization

- (void)test_4_2_1_a_ModelConstructPerModel
{
    [self loadRequired:@"Chapt04/4.2/4.2.1/4.2.1.a.xhtml"];
    XCTAssertEqual([self countOfEvent:@"xforms-model-construct"], (NSUInteger)2,
                   @"one xforms-model-construct per model: %@", self.dispatchedEvents);
}

- (void)test_4_2_1_b1_SchemasLoaded
{
    [self loadRequired:@"Chapt04/4.2/4.2.1/4.2.1.b1.xhtml"];
    XCTAssertFalse([self eventDispatched:@"xforms-link-exception"],
                   @"both schemas are valid — no link exception");
    XCTAssertFalse([self.messages containsObject:@"xforms-link-exception"]);
}

- (void)test_4_2_1_b2_InvalidSchemaLinkException
{
    [self loadTest:@"Chapt04/4.2/4.2.1/4.2.1.b2.xhtml"];
    [self assertMessageOrFatal:@"xforms-link-exception"];
}

- (void)test_4_2_1_c1_ExternalInitialInstance
{
    [self loadRequired:@"Chapt04/4.2/4.2.1/4.2.1.c1.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"14");
}

- (void)test_4_2_1_c2_InlineWinsOverResource
{
    // XForms 1.1: inline content takes precedence over @resource
    [self loadRequired:@"Chapt04/4.2/4.2.1/4.2.1.c2.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"100");
}

- (void)test_4_2_1_c3_InvalidExternalSource
{
    [self loadTest:@"Chapt04/4.2/4.2.1/4.2.1.c3.xhtml"];
    [self assertMessageOrFatal:@"xforms-link-exception"];
}

- (void)test_4_2_1_d_ConstructDonePerModel
{
    [self loadRequired:@"Chapt04/4.2/4.2.1/4.2.1.d.xhtml"];
    XCTAssertEqual([self countOfEvent:@"xforms-model-construct-done"], (NSUInteger)2,
                   @"one construct-done per model: %@", self.dispatchedEvents);
}

- (void)test_4_2_2_a_ConstructThenConstructDone
{
    [self loadRequired:@"Chapt04/4.2/4.2.2/4.2.2.a.xhtml"];
    [self assertSawEvent:@"xforms-model-construct"];
    [self assertSawEvent:@"xforms-model-construct-done"];
    [self assertOrderedEvents:@[ @"xforms-model-construct",
                                 @"xforms-model-construct-done" ]];
}

- (void)test_4_2_2_b_MissingNodeBehavesNonRelevant
{
    // /car does not exist in the external data (<automobile>Mitsubishi…)
    [self loadRequired:@"Chapt04/4.2/4.2.2/4.2.2.b.xhtml"];
    XCTAssertFalse([self valueRendered:@"Mitsubishi"],
                   @"the unbound output must behave non-relevant");
}

- (void)test_4_2_2_c1_LazyInstanceFromTyping
{
    // no instance anywhere; typing must lazily create <instanceData><car>
    [self loadRequired:@"Chapt04/4.2/4.2.2/4.2.2.c1.xhtml"];
    XFInputControl *input = [self controlOfClass:[XFInputControl class] index:0];
    XCTAssertNotNil(input);
    [self setValue:@"Civic" ofControl:input];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue],
                          @"car=Civic",
                          @"lazy instance creation (4.2.2 step 1) must back the input");
}

- (void)test_4_2_2_c2_LazySlashRefBindingException
{
    // ref="/car" is an illegal QName-path for automatic instance construction
    [self loadTest:@"Chapt04/4.2/4.2.2/4.2.2.c2.xhtml"];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

- (void)test_4_2_3_a_ConstructDoneThenReady
{
    [self loadRequired:@"Chapt04/4.2/4.2.3/4.2.3.a.xhtml"];
    [self assertSawEvent:@"xforms-model-construct-done"];
    [self assertSawEvent:@"xforms-ready"];
    [self assertOrderedEvents:@[ @"xforms-model-construct-done", @"xforms-ready" ]];
}

- (void)test_4_2_4_a_SubmitSideOfModelDestruct
{
    // The destruct-after-replace-all leg needs a navigating host; the
    // checkable core offline: DOMActivate ran (tested=true) and
    // xforms-submit dispatched.
    [self loadRequired:@"Chapt04/4.2/4.2.4/4.2.4.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerAtIndex:0];
    XCTAssertEqualObjects([self stringForXPath:@"/data/tested"], @"true");
    XCTAssertTrue([self eventDispatched:@"xforms-submit"], @"%@", self.dispatchedEvents);
}

#pragma mark 4.3 model events

- (void)test_4_3_1_a_Rebuild
{
    [self loadRequired:@"Chapt04/4.3/4.3.1/4.3.1.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Rebuild"];
    [self assertSawEvent:@"xforms-rebuild"];
}

- (void)test_4_3_2_a_Recalculate
{
    [self loadRequired:@"Chapt04/4.3/4.3.2/4.3.2.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Recalculate"];
    [self assertSawEvent:@"xforms-recalculate"];
}

- (void)test_4_3_3_a_Revalidate
{
    // setvalue at xforms-ready → the value-change sequence revalidates
    [self loadRequired:@"Chapt04/4.3/4.3.3/4.3.3.a.xhtml"];
    [self assertSawEvent:@"xforms-revalidate"];
    XCTAssertEqualObjects([self stringForXPath:@"/car/color"], @"blue");
}

- (void)test_4_3_4_a_Refresh
{
    [self loadRequired:@"Chapt04/4.3/4.3.4/4.3.4.a.xhtml"];
    [self assertSawEvent:@"xforms-refresh"];
}

- (void)test_4_3_5_a_ResetRunsAllFive
{
    [self loadRequired:@"Chapt04/4.3/4.3.5/4.3.5.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Reset"];
    for (NSString *e in @[ @"xforms-reset", @"xforms-rebuild", @"xforms-recalculate",
                           @"xforms-revalidate", @"xforms-refresh" ]) {
        [self assertSawEvent:e];
    }
    [self assertOrderedEvents:@[ @"xforms-reset", @"xforms-rebuild",
                                 @"xforms-recalculate", @"xforms-revalidate",
                                 @"xforms-refresh" ]];
}

- (void)test_4_3_6_a_PreviousAndNext
{
    [self loadRequired:@"Chapt04/4.3/4.3.6/4.3.6.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Previous"];
    [self assertSawEvent:@"xforms-previous"];
    [self activateTriggerLabeled:@"Next"];
    [self assertSawEvent:@"xforms-next"];
}

- (void)test_4_3_6_b_NavindexFormLoads
{
    // Non-normative keyboard navigation — the headless-checkable core:
    // the form loads and the two hidden_bind inputs are non-relevant.
    [self loadRequired:@"Chapt04/4.3/4.3.6/4.3.6.b.xhtml"];
    NSUInteger hidden = 0;
    for (XFControl *c in [self allControls]) {
        if ([c isKindOfClass:[XFInputControl class]] && !c.relevant) {
            hidden++;
        }
    }
    XCTAssertEqual(hidden, (NSUInteger)2, @"the two hidden_bind inputs");
}

- (void)test_4_3_7_a_Focus
{
    [self loadRequired:@"Chapt04/4.3/4.3.7/4.3.7.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Set Focus"];
    [self assertSawEvent:@"xforms-focus"];
}

- (void)test_4_3_8_a_HelpAndHint
{
    [self loadRequired:@"Chapt04/4.3/4.3.8/4.3.8.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Dispatch Help"];
    [self assertSawEvent:@"xforms-help"];
    [self activateTriggerLabeled:@"Dispatch Hint"];
    [self assertSawEvent:@"xforms-hint"];
}

#pragma mark 4.4 notification events

- (void)test_4_4_1_a_InsertEventContext
{
    [self loadRequired:@"Chapt04/4.4/4.4.1/4.4.1.a.xhtml"];
    [self activateTriggerLabeled:@"Insert A Date"];
    XCTAssertTrue([self.messages containsObject:@"xforms-insert"], @"%@", self.messages);
    XFModel *catcher = [self modelWithID:@"description_catcher"];
    XCTAssertEqualObjects([self stringForXPath:@"/descriptions/insert_description" model:catcher], @"before");
    XCTAssertEqualObjects([self stringForXPath:@"/descriptions/new_value" model:catcher], @"2006-01-01");
}

- (void)test_4_4_2_a_DeleteEventContext
{
    [self loadRequired:@"Chapt04/4.4/4.4.2/4.4.2.a.xhtml"];
    [self activateTriggerLabeled:@"Delete A Date"];
    XCTAssertTrue([self.messages containsObject:@"xforms-delete"], @"%@", self.messages);
    XFModel *catcher = [self modelWithID:@"description_catcher"];
    XCTAssertEqualObjects([self stringForXPath:@"/descriptions/delete_description" model:catcher], @"1");
    XCTAssertEqualObjects([self stringForXPath:@"/descriptions/new_value" model:catcher], @"2006-12-25");
}

- (void)test_4_4_3_a_ValueChanged
{
    [self loadRequired:@"Chapt04/4.4/4.4.3/4.4.3.a.xhtml"];
    [self assertSawEvent:@"xforms-value-changed"];
    XCTAssertEqualObjects([self stringForXPath:@"/car/make"], @"Toyota");
}

- (void)test_4_4_4_a_Valid
{
    [self loadRequired:@"Chapt04/4.4/4.4.4/4.4.4.a.xhtml"];
    [self assertSawEvent:@"xforms-valid"];
}

- (void)test_4_4_5_a_Invalid
{
    [self loadRequired:@"Chapt04/4.4/4.4.5/4.4.5.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Enter Invalid Value"];
    [self assertSawEvent:@"xforms-invalid"];
}

- (void)test_4_4_6_a_Readonly
{
    [self loadRequired:@"Chapt04/4.4/4.4.6/4.4.6.a.xhtml"];
    [self assertSawEvent:@"xforms-readonly"];
}

- (void)test_4_4_7_a_Readwrite
{
    [self loadRequired:@"Chapt04/4.4/4.4.7/4.4.7.a.xhtml"];
    [self assertSawEvent:@"xforms-readwrite"];
}

- (void)test_4_4_8_a_Required
{
    [self loadRequired:@"Chapt04/4.4/4.4.8/4.4.8.a.xhtml"];
    [self assertSawEvent:@"xforms-required"];
}

- (void)test_4_4_9_a_Optional
{
    [self loadRequired:@"Chapt04/4.4/4.4.9/4.4.9.a.xhtml"];
    [self assertSawEvent:@"xforms-optional"];
}

- (void)test_4_4_10_a_Enabled
{
    [self loadRequired:@"Chapt04/4.4/4.4.10/4.4.10.a.xhtml"];
    [self assertSawEvent:@"xforms-enabled"];
}

- (void)test_4_4_11_a_Disabled
{
    [self loadRequired:@"Chapt04/4.4/4.4.11/4.4.11.a.xhtml"];
    [self assertSawEvent:@"xforms-disabled"];
}

- (void)test_4_4_12_a_DOMActivate
{
    [self loadRequired:@"Chapt04/4.4/4.4.12/4.4.12.a.xhtml"];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self.messages containsObject:@"DOMActivate"], @"%@", self.messages);
}

- (void)test_4_4_13_a_DOMFocusIn
{
    [self loadRequired:@"Chapt04/4.4/4.4.13/4.4.13.a.xhtml"];
    [self assertSawEvent:@"DOMFocusIn"];
}

- (void)test_4_4_14_a_DOMFocusOut
{
    [self loadRequired:@"Chapt04/4.4/4.4.14/4.4.14.a.xhtml"];
    [self assertSawEvent:@"DOMFocusOut"];
}

- (void)test_4_4_15_a_SelectAndDeselect
{
    [self loadRequired:@"Chapt04/4.4/4.4.15/4.4.15.a.xhtml"];
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    XCTAssertNotNil(select);
    [self.dispatchedEvents removeAllObjects];
    XCTAssertTrue([select selectValue:@"sub"]);
    [self assertSawEvent:@"xforms-select"];
    [self.dispatchedEvents removeAllObjects];
    XCTAssertTrue([select toggleValue:@"sub"]);   // deselect Subaru
    [self assertSawEvent:@"xforms-deselect"];
}

- (void)test_4_4_16_a_InRange
{
    [self loadRequired:@"Chapt04/4.4/4.4.16/4.4.16.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"In Range"];
    [self assertSawEvent:@"xforms-in-range"];
}

- (void)test_4_4_17_a_OutOfRange
{
    [self loadRequired:@"Chapt04/4.4/4.4.17/4.4.17.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Out Of Range"];
    [self assertSawEvent:@"xforms-out-of-range"];
}

- (void)test_4_4_18_a_ScrollFirstAndLast
{
    [self loadRequired:@"Chapt04/4.4/4.4.18/4.4.18.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Scroll First"];
    [self assertSawEvent:@"xforms-scroll-first"];
    [self activateTriggerLabeled:@"Scroll Last"];
    [self assertSawEvent:@"xforms-scroll-last"];
}

#pragma mark 4.5 exception events

- (void)test_4_5_1_a1_InvalidModelAttribute
{
    [self loadTest:@"Chapt04/4.5/4.5.1/4.5.1.a1.xhtml"];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

- (void)test_4_5_1_a2_InvalidBindAttribute
{
    [self loadTest:@"Chapt04/4.5/4.5.1/4.5.1.a2.xhtml"];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

- (void)test_4_5_1_a3_InvalidSubmissionAttribute
{
    XFProcessor *p = [self loadTest:@"Chapt04/4.5/4.5.1/4.5.1.a3.xhtml"];
    if (p == nil) {
        return;
    }
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerAtIndex:0];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

- (void)test_4_5_1_a4_InvalidInstanceOfSubmission
{
    XFProcessor *p = [self loadTest:@"Chapt04/4.5/4.5.1/4.5.1.a4.xhtml"];
    if (p == nil) {
        return;
    }
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerAtIndex:0];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

- (void)test_4_5_1_a5_IllegalBindingExpression
{
    [self loadTest:@"Chapt04/4.5/4.5.1/4.5.1.a5.xhtml"];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

- (void)test_4_5_2_a_ComputeException
{
    // The exception EVENT must dispatch (halting afterwards is fine; a
    // silent load failure is not — nothing was dispatched).
    [self loadTest:@"Chapt04/4.5/4.5.2/4.5.2.a.xhtml"];
    XCTAssertTrue([self eventDispatched:@"xforms-compute-exception"]
                      || [self.messages containsObject:@"xforms-compute-exception"],
                  @"a non-compiling calculate must dispatch xforms-compute-exception; events: %@",
                  self.dispatchedEvents);
    XCTAssertFalse([self valueRendered:@"Hello world!"], @"processing must halt");
}

// 4.5.3.a (xforms-version-exception): the manifest links a file that is
// absent upstream — nothing to test. Version negatives run as 3.3.1.d2/d3.

- (void)test_4_5_4_a_LinkExceptionHalts
{
    [self loadTest:@"Chapt04/4.5/4.5.4/4.5.4.a.xhtml"];
    XCTAssertTrue([self eventDispatched:@"xforms-link-exception"]
                      || [self.messages containsObject:@"xforms-link-exception"]
                      || self.processor == nil,
                  @"failed instance link must raise xforms-link-exception");
    XCTAssertFalse([self valueRendered:@"Hello world!"], @"processing must halt");
}

- (void)test_4_5_5_a_OutputError
{
    [self loadRequired:@"Chapt04/4.5/4.5.5/4.5.5.a.xhtml"];
    [self assertSawEvent:@"xforms-output-error"];
}

#pragma mark 4.6 event sequencing

- (void)test_4_6_1_a1_ValueChangeSequenceTextControls
{
    [self loadRequired:@"Chapt04/4.6/4.6.1/4.6.1.a1.xhtml"];
    XFInputControl *input = [self controlOfClass:[XFInputControl class] index:0];
    [self.dispatchedEvents removeAllObjects];
    [self setValue:@"test" ofControl:input];
    [self assertOrderedEvents:@[ @"xforms-recalculate", @"xforms-revalidate",
                                 @"xforms-refresh" ]];
}

- (void)test_4_6_1_a2_ValueChangeSequenceRange
{
    [self loadRequired:@"Chapt04/4.6/4.6.1/4.6.1.a2.xhtml"];
    XFRangeControl *range = [self controlOfClass:[XFRangeControl class] index:0];
    XCTAssertNotNil(range);
    [self.dispatchedEvents removeAllObjects];
    [self setValue:@"26000" ofControl:range];   // initial is 25000 — must differ
    [self assertOrderedEvents:@[ @"xforms-recalculate", @"xforms-revalidate",
                                 @"xforms-refresh" ]];
}

- (void)test_4_6_1_b1_CommitSequenceTextControls
{
    // non-incremental: the commit path runs the same model sequence
    [self loadRequired:@"Chapt04/4.6/4.6.1/4.6.1.b1.xhtml"];
    XFInputControl *input = [self controlOfClass:[XFInputControl class] index:0];
    [self.dispatchedEvents removeAllObjects];
    [self setValue:@"test" ofControl:input];
    [self assertOrderedEvents:@[ @"xforms-recalculate", @"xforms-revalidate",
                                 @"xforms-refresh" ]];
}

- (void)test_4_6_1_b2_CommitSequenceRange
{
    [self loadRequired:@"Chapt04/4.6/4.6.1/4.6.1.b2.xhtml"];
    XFRangeControl *range = [self controlOfClass:[XFRangeControl class] index:0];
    XCTAssertNotNil(range);
    [self.dispatchedEvents removeAllObjects];
    [self setValue:@"26000" ofControl:range];   // initial is 25000 — must differ
    [self assertOrderedEvents:@[ @"xforms-recalculate", @"xforms-revalidate",
                                 @"xforms-refresh" ]];
}

- (void)test_4_6_3_a_SelectSequenceIncremental
{
    [self loadRequired:@"Chapt04/4.6/4.6.3/4.6.3.a.xhtml"];
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    [self.dispatchedEvents removeAllObjects];
    XCTAssertTrue([select selectValue:@"acu"]);
    [self assertSawEvent:@"xforms-select"];
    [self assertOrderedEvents:@[ @"xforms-select", @"xforms-recalculate",
                                 @"xforms-revalidate", @"xforms-refresh" ]];
}

- (void)test_4_6_3_b_SelectSequenceNonIncremental
{
    [self loadRequired:@"Chapt04/4.6/4.6.3/4.6.3.b.xhtml"];
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    [self.dispatchedEvents removeAllObjects];
    XCTAssertTrue([select selectValue:@"acu"]);
    [self assertSawEvent:@"xforms-select"];
}

- (void)test_4_6_3_c_SelectDeselectOnChange
{
    [self loadRequired:@"Chapt04/4.6/4.6.3/4.6.3.c.xhtml"];
    XFSelectControl *select1 = [self controlOfClass:[XFSelectControl class] index:1];
    XCTAssertNotNil(select1);
    XCTAssertTrue([select1 selectValue:@"acu"]);
    [self.dispatchedEvents removeAllObjects];
    XCTAssertTrue([select1 selectValue:@"hon"]);
    // switching a select1 deselects the old value and selects the new
    [self assertSawEvent:@"xforms-deselect"];
    [self assertSawEvent:@"xforms-select"];
}

- (void)test_4_6_4_a_TriggerSequence
{
    [self loadRequired:@"Chapt04/4.6/4.6.4/4.6.4.a.xhtml"];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self.messages containsObject:@"DOMActivate"], @"%@", self.messages);
}

- (void)test_4_6_5_a_SubmitSequence
{
    [self loadRequired:@"Chapt04/4.6/4.6.5/4.6.5.a.xhtml"];
    [self useEchoTransport];   // submission1 succeeds; "invaliduri" fails
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Submit 1"];
    XCTAssertTrue([self.messages containsObject:@"DOMActivate"], @"%@", self.messages);
    [self assertOrderedEvents:@[ @"DOMActivate", @"xforms-submit",
                                 @"xforms-submit-done" ]];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Submit 2"];
    [self assertOrderedEvents:@[ @"DOMActivate", @"xforms-submit",
                                 @"xforms-submit-error" ]];
}

#pragma mark 4.7 IDREF resolution

- (void)test_4_7_a_InvalidIDRefsNoEffect
{
    [self loadRequired:@"Chapt04/4.7/4.7.a.xhtml"];
    XCTAssertEqual(self.messages.count, (NSUInteger)0,
                   @"invalid IDREFs on actions terminate silently: %@", self.messages);
}

- (void)test_4_7_b_SubmitNotDispatchedForInvalidIDREF
{
    [self loadRequired:@"Chapt04/4.7/4.7.b.xhtml"];
    [self activateTriggerAtIndex:0];
    XCTAssertFalse([self.messages containsObject:@"xforms-submit"],
                   @"no xforms-submit for an invalid submission IDREF");
}

- (void)test_4_7_c_IndexOfUnknownRepeatIsNaN
{
    [self loadRequired:@"Chapt04/4.7/4.7.c.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"NaN");
}

- (void)test_4_7_d_InstanceMissingNodeEmpty
{
    [self loadRequired:@"Chapt04/4.7/4.7.d.xhtml"];
    XFOutputControl *out = [self controlOfClass:[XFOutputControl class] index:0];
    XCTAssertTrue(out == nil || !out.relevant || out.stringValue.length == 0,
                  @"no value must show: '%@'", out.stringValue);
}

- (void)test_4_7_e1_NullBindSearch
{
    [self loadTest:@"Chapt04/4.7/4.7.e1.xhtml"];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

- (void)test_4_7_e2_NullModelSearch
{
    [self loadTest:@"Chapt04/4.7/4.7.e2.xhtml"];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

- (void)test_4_7_e3_NullInstanceSearchOnSubmission
{
    XFProcessor *p = [self loadTest:@"Chapt04/4.7/4.7.e3.xhtml"];
    if (p == nil) {
        return;
    }
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerAtIndex:0];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

#pragma mark 4.8 DOM API (non-normative; no scripting host here)

- (void)test_4_8_1_a_GetInstanceDocumentFormLoads
{
    // The JS leg (getInstanceDocument) is n/a without a scripting host;
    // the form itself must still load and expose the instance.
    [self loadRequired:@"Chapt04/4.8/4.8.1/4.8.1.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"/car/color"], @"blue");
}

- (void)test_4_8_1_b_GetInstanceDocumentInvalidFormLoads
{
    [self loadRequired:@"Chapt04/4.8/4.8.1/4.8.1.b.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"/car/color"], @"blue");
}

@end
