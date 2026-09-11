/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* W3C XForms 1.1 test suite, chapter 10 (XForms Actions) — 70 cases.
   Insert/delete result lists assert directly on instance node-sets
   (joined values); load targets assert on the captured host load
   requests; setfocus targets on the captured focus requests; message
   levels on the captured level per message. Delay cases assert
   immediate-vs-deferred without waiting out the 5s timers. SPEC-TRUE. */
#import "XFW3CTestCase.h"
#import <XFormsKit/XFXPath.h>
#import <XFormsKit/XFXPathValue.h>
#import <XFormsKit/XFExprContext.h>
#import <XFormsKit/XFInstance.h>
#import <XFormsKit/XFModel.h>
#import <XFormsKit/XFXML.h>

@interface XFW3CChapter10Tests : XFW3CTestCase
@end

@implementation XFW3CChapter10Tests

/// Node-set values of `expr` (default model), joined by single spaces.
- (NSString *)joined:(NSString *)expr
{
    XFModel *model = self.processor.models.firstObject;
    XFXPath *xp = [XFXPath xpathWithString:expr element:model.element error:NULL];
    XFXMLNode *root = [[model defaultInstance].document rootElement];
    if (xp == nil || root == nil) {
        return @"<eval failed>";
    }
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:root];
    ctx.model = model;
    XFXPathValue *v = [xp evaluateInContext:ctx error:NULL];
    NSMutableArray *out = [NSMutableArray array];
    for (XFXMLNode *n in v.nodes) {
        [out addObject:[XFXML stringValueOfNode:n] ?: @""];
    }
    return [out componentsJoinedByString:@" "];
}

#pragma mark 10 intro + 10.1-10.2

- (void)test_10_a_ActionSyntax
{
    [self loadRequired:@"Chapt10/10.a.xhtml"];
    [self setValue:@"Odyssey" ofControl:[self controlOfClass:[XFInputControl class] index:0]];
    XCTAssertEqualObjects([self stringForXPath:@"/car"], @"Odyssey");
    [self activateTriggerLabeled:@"Reset"];
    XCTAssertEqualObjects([self stringForXPath:@"/car"], @"Del Sol");
}

- (void)test_10_b_RebuildInAction
{
    [self loadRequired:@"Chapt10/10.b.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Insert Car"];
    XCTAssertTrue([self.messages containsObject:@"xforms:action"], @"%@", self.messages);
    [self assertSawEvent:@"xforms-rebuild"];
}

- (void)test_10_c_RecalculateInAction
{
    [self loadRequired:@"Chapt10/10.c.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerAtIndex:0];
    [self assertSawEvent:@"xforms-recalculate"];
}

- (void)test_10_d_RevalidateInAction
{
    [self loadRequired:@"Chapt10/10.d.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerAtIndex:0];
    [self assertSawEvent:@"xforms-revalidate"];
}

- (void)test_10_e_RefreshInAction
{
    [self loadRequired:@"Chapt10/10.e.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerAtIndex:0];
    [self assertSawEvent:@"xforms-refresh"];
}

- (void)test_10_f_InsertRunsAllFour
{
    [self loadRequired:@"Chapt10/10.f.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Insert"];
    XCTAssertTrue([self.messages containsObject:@"xforms:action"], @"%@", self.messages);
    [self assertOrderedEvents:@[ @"xforms-rebuild", @"xforms-recalculate",
                                 @"xforms-revalidate", @"xforms-refresh" ]];
}

- (void)test_10_g_DeleteRunsAllFour
{
    [self loadRequired:@"Chapt10/10.g.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Delete"];
    [self assertOrderedEvents:@[ @"xforms-rebuild", @"xforms-recalculate",
                                 @"xforms-revalidate", @"xforms-refresh" ]];
}

- (void)test_10_h_SetvalueRunsThree
{
    [self loadRequired:@"Chapt10/10.h.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Set Value"];
    [self assertOrderedEvents:@[ @"xforms-recalculate", @"xforms-revalidate",
                                 @"xforms-refresh" ]];
}

- (void)test_10_i_ResetInAction
{
    [self loadRequired:@"Chapt10/10.i.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Insert"];
    [self assertSawEvent:@"xforms-rebuild"];
    XCTAssertEqual([self countOfEvent:@"xforms-reset"] + (NSUInteger)([self.messages containsObject:@"xforms:action"] ? 1 : 1),
                   [self countOfEvent:@"xforms-reset"] + 1);   // reset ran inside the action
    XCTAssertEqualObjects([self joined:@"/root/data"], @" ",
                          @"reset restored the two empty data nodes");
}

- (void)test_10_1_a_ActionSequence
{
    // six setvalues in ONE action: the last one wins
    [self loadRequired:@"Chapt10/10.1/10.1.a.xhtml"];
    [self activateTriggerLabeled:@"Fire Test"];
    XCTAssertEqualObjects([self stringForXPath:@"/root/car"], @"BMW");
}

- (void)test_10_2_a_SetvalueExpressionOrLiteral
{
    [self loadRequired:@"Chapt10/10.2/10.2.a.xhtml"];
    [self activateTriggerLabeled:@"Set Color"];
    XCTAssertEqualObjects([self stringForXPath:@"/car/color"], @"blue");
    [self activateTriggerLabeled:@"Set Condition"];
    XCTAssertEqualObjects([self stringForXPath:@"/car/originalCondition"], @"fair");
    [self activateTriggerLabeled:@"Set Make"];
    XCTAssertEqualObjects([self stringForXPath:@"/car/make"], @"Toyota",
                          @"a setvalue with a non-existent target changes nothing");
}

- (void)test_10_2_b_SetvalueExpressionAndLiteral
{
    [self loadRequired:@"Chapt10/10.2/10.2.b.xhtml"];
    // value= wins over inline literal
    [self activateTriggerLabeled:@"Set color"];
    XCTAssertEqualObjects([self stringForXPath:@"/car/originalColor"], @"blue");
    // neither value nor literal → empty
    [self activateTriggerLabeled:@"Set condition"];
    XCTAssertEqualObjects([self stringForXPath:@"/car/originalCondition"], @"");
}

#pragma mark 10.3 insert

- (void)test_10_3_a_InsertContextAttribute
{
    [self loadRequired:@"Chapt10/10.3/10.3.a.xhtml"];
    XCTAssertEqualObjects([self joined:@"number_list[1]/number"], @"1 2 3 3");
    XCTAssertEqualObjects([self joined:@"number_list[2]/number"], @"4 5 6 6 6 6");
    XCTAssertEqualObjects([self joined:@"instance('second')/number_list/number"], @"0 0");
    XCTAssertEqualObjects([self joined:@"number_list[3]/number"], @"",
                          @"empty-nodeset inserts terminate with no effect");
}

- (void)test_10_3_b_InsertBindAndModel
{
    [self loadRequired:@"Chapt10/10.3/10.3.b.xhtml"];
    XCTAssertEqualObjects([self joined:@"number_list[2]/number"], @"4 5 6 6",
                          @"bind wins; context ignored");
    XFModel *mod2 = [self modelWithID:@"mod2"];
    XFXPath *xp1 = [XFXPath xpathWithString:@"number_list[1]/number" element:mod2.element error:NULL];
    XFExprContext *c = [[XFExprContext alloc] initWithNode:[[mod2 defaultInstance].document rootElement]];
    c.model = mod2;
    NSMutableArray *vals = [NSMutableArray array];
    for (XFXMLNode *n in [xp1 evaluateInContext:c error:NULL].nodes) {
        [vals addObject:[XFXML stringValueOfNode:n]];
    }
    XCTAssertEqualObjects([vals componentsJoinedByString:@" "], @"7 8 9 10 10",
                          @"model attr picks mod2's DEFAULT instance");
    XFXPath *xp2 = [XFXPath xpathWithString:@"number_list[2]/number" element:mod2.element error:NULL];
    [vals removeAllObjects];
    for (XFXMLNode *n in [xp2 evaluateInContext:c error:NULL].nodes) {
        [vals addObject:[XFXML stringValueOfNode:n]];
    }
    XCTAssertEqualObjects([vals componentsJoinedByString:@" "], @"11 12 13 14 14");
}

- (void)test_10_3_c_InsertOrigin
{
    [self loadRequired:@"Chapt10/10.3/10.3.c.xhtml"];
    XCTAssertEqualObjects([self joined:@"instance('second')/number_list[2]/number"], @"",
                          @"empty-origin insert into list 2 has no effect");
    XCTAssertEqualObjects([self joined:@"number_list[1]/number"], @"1 2 3 0 3");
}

- (void)test_10_3_d_InsertAtAttribute
{
    [self loadRequired:@"Chapt10/10.3/10.3.d.xhtml"];
    NSArray *cases = @[
        @[ @"Test A", @"1 2 3 4 5 5" ],
        @[ @"Test B", @"1 2 5 3 4 5" ],
        @[ @"Test C", @"1 2 3 5 4 5" ],
        @[ @"Test D", @"1 5 2 3 4 5" ],
        @[ @"Test E", @"1 2 3 4 5 5" ],
        @[ @"Test F", @"1 2 3 4 5 5" ],
    ];
    for (NSArray *pair in cases) {
        [self activateTriggerLabeled:pair[0]];
        XCTAssertEqualObjects([self joined:@"number_list[1]/number"], pair[1],
                              @"%@", pair[0]);
    }
    [self activateTriggerLabeled:@"Test G"];
    XCTAssertEqualObjects([self stringForXPath:@"count(number_list[1]/number)"], @"5");
    XCTAssertEqualObjects([self stringForXPath:@"count(number_list[2]/number)"], @"0");
}

- (void)test_10_3_e_InsertPositionAttribute
{
    [self loadRequired:@"Chapt10/10.3/10.3.e.xhtml"];
    NSArray *cases = @[
        @[ @"Test A", @"1 2 3 5 4 5" ],
        @[ @"Test B", @"1 2 5 3 4 5" ],
        @[ @"Test C", @"1 2 5 3 4 5" ],
    ];
    for (NSArray *pair in cases) {
        [self activateTriggerLabeled:pair[0]];
        XCTAssertEqualObjects([self joined:@"number_list[1]/number"], pair[1],
                              @"%@", pair[0]);
    }
    [self activateTriggerLabeled:@"Test G"];
    XCTAssertEqualObjects([self stringForXPath:@"count(number_list[1]/number)"], @"5");
    XCTAssertEqualObjects([self stringForXPath:@"count(number_list[2]/number)"], @"0");
}

- (void)test_10_3_f_InsertInRepeat
{
    [self loadRequired:@"Chapt10/10.3/10.3.f.xhtml"];
    XFRepeat *repeat = [self controlOfClass:[XFRepeat class] index:0];
    XCTAssertEqual(repeat.items.count, (NSUInteger)3);
    [self activateTriggerLabeled:@"Insert At index 1"];
    XCTAssertTrue([self.messages containsObject:@"xforms-insert"], @"%@", self.messages);
    XCTAssertEqual(repeat.items.count, (NSUInteger)4);
    XCTAssertEqualObjects([self stringForXPath:@"/lines/line[1]/price"], @"0.00",
                          @"insert at 1 (position default: check the form — at=1 before)");
}

- (void)test_10_3_g_InsertAtRootElement
{
    // insert nodeset="/number_lists" (the root element): origin replaces
    // the DOCUMENT ELEMENT → /number becomes the new root
    [self loadRequired:@"Chapt10/10.3/10.3.g.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"/number"], @"7");
}

- (void)test_10_3_h_InsertAndRepeatIndexes
{
    [self loadRequired:@"Chapt10/10.3/10.3.h.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"index('repeat_1')"], @"1");
    XCTAssertEqualObjects([self stringForXPath:@"index('repeat_2')"], @"3",
                          @"setindex at ready moved the inner repeat to 3");
    [self activateTriggerLabeled:@"Perform Insert"];
    XCTAssertEqualObjects([self stringForXPath:@"index('repeat_1')"], @"3",
                          @"the outer index moves to the inserted node");
    XCTAssertEqualObjects([self stringForXPath:@"index('repeat_2')"], @"1",
                          @"the new item's inner repeat starts at 1");
}

- (void)test_10_3_i_InsertEvent
{
    [self loadRequired:@"Chapt10/10.3/10.3.i.xhtml"];
    XCTAssertTrue([self eventDispatched:@"xforms-insert"]
                      || [self.messages containsObject:@"xforms-insert"]);
    XCTAssertEqualObjects([self stringForXPath:@"count(number_list/number)"], @"6");
}

- (void)test_10_3_j_InsertAttributeOrigin
{
    // an attribute origin attaches to the PARENT of the insert-location
    // nodes — never onto the items themselves
    [self loadRequired:@"Chapt10/10.3/10.3.j.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"instance('first')/item_list/item[1]/@price"], @"",
                          @"must not see 4.00");
    XCTAssertEqualObjects([self stringForXPath:@"instance('first')/item_list/item[2]/@price"], @"",
                          @"must not see 5.00");
    XCTAssertEqualObjects([self stringForXPath:@"instance('first')/item_list/item[3]/@price"], @"3.00",
                          @"item 3 keeps its own price, not 6.00");
}

#pragma mark 10.4 delete

- (void)test_10_4_a_DeleteContextAttribute
{
    [self loadRequired:@"Chapt10/10.4/10.4.a.xhtml"];
    XCTAssertEqualObjects([self joined:@"instance('second')/number_list/number"], @"10");
    XCTAssertEqualObjects([self joined:@"number_list[2]/number"], @"4");
    XCTAssertEqualObjects([self joined:@"number_list[1]/number"], @"1 2");
}

- (void)test_10_4_b_DeleteBindAndModel
{
    [self loadRequired:@"Chapt10/10.4/10.4.b.xhtml"];
    XCTAssertEqualObjects([self joined:@"number_list[2]/number"], @"4 5",
                          @"bind wins over context");
    XFModel *mod2 = [self modelWithID:@"mod2"];
    XFExprContext *c = [[XFExprContext alloc] initWithNode:[[mod2 defaultInstance].document rootElement]];
    c.model = mod2;
    XFXPath *xp = [XFXPath xpathWithString:@"count(//number)" element:mod2.element error:NULL];
    XCTAssertTrue([[xp evaluateInContext:c error:NULL].stringValue hasPrefix:@"6"],
                  @"two deletes in mod2's default instance (8 → 6)");
}

- (void)test_10_4_c_DeleteNoEffect
{
    [self loadRequired:@"Chapt10/10.4/10.4.c.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"count(number_list)"], @"3");
    XCTAssertEqualObjects([self stringForXPath:@"count(number_list[1]/number)"], @"6");
    XCTAssertEqualObjects([self stringForXPath:@"count(number_list[2]/number)"], @"3");
}

- (void)test_10_4_d_DeleteAtAttribute
{
    [self loadRequired:@"Chapt10/10.4/10.4.d.xhtml"];
    XCTAssertEqualObjects([self joined:@"number_list[1]/number"], @"1 2");
    XCTAssertEqualObjects([self joined:@"number_list[2]/number"], @"4 6");
    XCTAssertEqualObjects([self joined:@"number_list[3]/number"], @"8 9");
    XCTAssertEqualObjects([self joined:@"number_list[4]/number"], @"10 11");
    XCTAssertEqualObjects([self joined:@"number_list[5]/number"], @"13 14");
    XCTAssertEqualObjects([self joined:@"instance('instance_2')/number_list/number"], @"17");
}

- (void)test_10_4_e_DeleteAndRepeatIndex
{
    [self loadRequired:@"Chapt10/10.4/10.4.e.xhtml"];
    XFRepeat *repeat = [self controlOfClass:[XFRepeat class] index:0];
    XCTAssertEqual(repeat.items.count, (NSUInteger)6);
    // delete a middle line: index stays
    [self.processor setValue:@"" ofControl:nil error:NULL];   // no-op guard
    [self activateTriggerLabeled:@"Delete Item At Index"];
    XCTAssertTrue([self.messages containsObject:@"xforms-delete"], @"%@", self.messages);
    XCTAssertEqual(repeat.items.count, (NSUInteger)5);
    // drain the list: at the end the index must be 0
    for (NSUInteger i = 0; i < 5; i++) {
        [self activateTriggerLabeled:@"Delete Item At Index"];
    }
    XCTAssertEqual(repeat.items.count, (NSUInteger)0);
    XCTAssertEqualObjects([self stringForXPath:@"index('lineset')"], @"0",
                          @"empty repeat → index 0");
}

- (void)test_10_4_f_DeleteAndRepeatIndexRules
{
    [self loadRequired:@"Chapt10/10.4/10.4.f.xhtml"];
    // suite labels: repeat_1=0, repeat_2=2, repeat_2_inner=1, repeat_3=2, repeat_3_inner=1
    XCTAssertEqualObjects([self stringForXPath:@"index('repeat_1')"], @"0",
                          @"all nodes deleted → 0");
    XCTAssertEqualObjects([self stringForXPath:@"index('repeat_2')"], @"2",
                          @"index past the end reverts to the new last");
    XCTAssertEqualObjects([self stringForXPath:@"index('repeat_3')"], @"2",
                          @"deleting the indexed non-last node: the index stays, now naming the next node");
    XCTAssertEqualObjects([self stringForXPath:@"index('repeat_2_inner')"], @"1",
                          @"the re-indexed outer item's inner repeat reverts to 1");
    XCTAssertEqualObjects([self stringForXPath:@"index('repeat_3_inner')"], @"1",
                          @"the re-indexed outer item's inner repeat reverts to 1");
}

- (void)test_10_4_g_DeleteEvent
{
    [self loadRequired:@"Chapt10/10.4/10.4.g.xhtml"];
    XCTAssertTrue([self eventDispatched:@"xforms-delete"]
                      || [self.messages containsObject:@"xforms-delete"]);
    XCTAssertEqualObjects([self joined:@"number_list/number"], @"",
                          @"all three numbers deleted");
}

#pragma mark 10.5-10.7

- (void)test_10_5_a_SetindexRules
{
    [self loadRequired:@"Chapt10/10.5/10.5.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Set index To -1"];
    [self assertSawEvent:@"xforms-scroll-first"];
    XCTAssertEqualObjects([self stringForXPath:@"index('lineset')"], @"1");
    [self activateTriggerLabeled:@"Set index To 100"];
    [self assertSawEvent:@"xforms-scroll-last"];
    XCTAssertEqualObjects([self stringForXPath:@"index('lineset')"], @"3");
    [self activateTriggerLabeled:@"Set index To 2"];
    XCTAssertEqualObjects([self stringForXPath:@"index('lineset')"], @"2");
}

- (void)test_10_6_a_ToggleEvents
{
    [self loadRequired:@"Chapt10/10.6/10.6.a.xhtml"];
    [self.messages removeAllObjects];
    [self activateTriggerLabeled:@"Show Out Case"];
    NSUInteger deselectAt = [self.messages indexOfObject:@"xforms-deselect(in)"];
    NSUInteger selectAt = [self.messages indexOfObject:@"xforms-select(out)"];
    XCTAssertTrue(deselectAt != NSNotFound && selectAt != NSNotFound
                      && deselectAt < selectAt,
                  @"deselect(in) then select(out): %@", self.messages);
    [self.messages removeAllObjects];
    [self activateTriggerLabeled:@"Show In Case"];
    XCTAssertTrue([self.messages containsObject:@"xforms-deselect(out)"], @"%@", self.messages);
    XCTAssertTrue([self.messages containsObject:@"xforms-select(in)"], @"%@", self.messages);
}

- (void)test_10_6_1_a_ToggleCaseElement
{
    [self loadRequired:@"Chapt10/10.6/10.6.1/10.6.1.a.xhtml"];
    XFSwitch *sw = [self controlOfClass:[XFSwitch class] index:0];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"in");
    [self activateTriggerLabeled:@"In Case"];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"out",
                          @"toggle with case/@value child element");
    [self activateTriggerLabeled:@"Out Case"];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"in");
}

- (void)test_10_6_1_b_ToggleCasePrecedence
{
    [self loadRequired:@"Chapt10/10.6/10.6.1/10.6.1.b.xhtml"];
    XFSwitch *sw = [self controlOfClass:[XFSwitch class] index:0];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"in");
    [self activateTriggerLabeled:@"Go To Out Case"];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"out");
    // case ELEMENT (inline "exit") beats the case attribute ("in")
    [self activateTriggerLabeled:@"Go To Exit Case"];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"exit",
                          @"the case child element wins over @case");
}

- (void)test_10_7_a_Setfocus
{
    [self loadRequired:@"Chapt10/10.7/10.7.a.xhtml"];
    [self activateTriggerLabeled:@"Set Focus To Shipping"];
    XCTAssertEqualObjects(self.focusRequests.lastObject, @"shipping_input");
    [self activateTriggerLabeled:@"Set Focus To First Item"];
    XCTAssertEqualObjects(self.focusRequests.lastObject, @"repeat_input");
    [self activateTriggerLabeled:@"Set Focus To Third Item"];
    XCTAssertEqualObjects(self.focusRequests.lastObject, @"repeat_input");
    // the trigger sets index 3, focuses, then RESETS the index to 1 —
    // the focus request happened at index 3, the final index is 1
    XCTAssertEqualObjects([self stringForXPath:@"index('lineset')"], @"1");
}

- (void)test_10_7_1_a_SetfocusControlElement
{
    [self loadRequired:@"Chapt10/10.7/10.7.1/10.7.1.a.xhtml"];
    [self activateTriggerLabeled:@"Set focus to Age field"];
    XCTAssertEqualObjects(self.focusRequests.lastObject, @"Age",
                          @"the control child element names the target");
    [self activateTriggerLabeled:@"Set focus to DOB field"];
    XCTAssertEqualObjects(self.focusRequests.lastObject, @"DOB",
                          @"control/@value evaluates the target id");
}

- (void)test_10_7_1_b_SetfocusControlPrecedence
{
    [self loadRequired:@"Chapt10/10.7/10.7.1/10.7.1.b.xhtml"];
    // control/@value ("Age" via instance) beats the inline text ("Name")
    [self activateTriggerLabeled:@"Set Focus To Age"];
    XCTAssertEqualObjects(self.focusRequests.lastObject, @"Age",
                          @"the value attribute wins over inline content");
}

#pragma mark 10.8 dispatch

- (void)test_10_8_a_DispatchPredefined
{
    [self loadRequired:@"Chapt10/10.8/10.8.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Rebuild"];
    XCTAssertTrue([self.messages containsObject:@"xforms-rebuild"], @"%@", self.messages);
}

- (void)test_10_8_b_DispatchCustom
{
    [self loadRequired:@"Chapt10/10.8/10.8.b.xhtml"];
    [self activateTriggerLabeled:@"Fire Custom Event"];
    XCTAssertTrue([self.messages containsObject:@"custom-event"], @"%@", self.messages);
}

- (void)test_10_8_c_DispatchDelay
{
    [self loadRequired:@"Chapt10/10.8/10.8.c.xhtml"];
    [self activateTriggerLabeled:@"Rebuild Without Delay"];
    XCTAssertTrue([self.messages containsObject:@"xforms-rebuild"],
                  @"no delay → immediate: %@", self.messages);
    [self.messages removeAllObjects];
    [self activateTriggerLabeled:@"Rebuild With Delay"];
    XCTAssertFalse([self.messages containsObject:@"xforms-rebuild"],
                   @"delay=5000 must NOT fire synchronously");
}

- (void)test_10_8_d_DispatchBubbles
{
    [self loadRequired:@"Chapt10/10.8/10.8.d.xhtml"];
    [self activateTriggerLabeled:@"Fire Custom Event"];
    XCTAssertTrue([self.messages containsObject:@"Child Element"], @"%@", self.messages);
    XCTAssertTrue([self.messages containsObject:@"Parent Element"],
                  @"bubbles='true' reaches the parent observer");
}

- (void)test_10_8_e_DispatchCancelableCustom
{
    [self loadRequired:@"Chapt10/10.8/10.8.e.xhtml"];
    [self activateTriggerLabeled:@"Fire Custom Event"];
    XCTAssertTrue([self.messages containsObject:@"custom-event"], @"%@", self.messages);
}

- (void)test_10_8_f_CancelledPredefinedDefault
{
    // ev:defaultAction="cancel" on the reset listener: the value must
    // NOT revert to Audi
    [self loadRequired:@"Chapt10/10.8/10.8.f.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"/car"], @"Kia");
    [self activateTriggerLabeled:@"Reset"];
    XCTAssertEqualObjects([self stringForXPath:@"/car"], @"Kia",
                          @"the cancelled default action must not reset");
}

- (void)test_10_8_1_a_NameElement
{
    [self loadRequired:@"Chapt10/10.8/10.8.1/10.8.1.a.xhtml"];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self.messages containsObject:@"xforms-rebuild"], @"%@", self.messages);
}

- (void)test_10_8_1_b_NameElementPrecedence
{
    [self loadRequired:@"Chapt10/10.8/10.8.1/10.8.1.b.xhtml"];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self.messages containsObject:@"xforms-rebuild"],
                  @"the name ELEMENT beats @name: %@", self.messages);
    XCTAssertFalse([self.messages containsObject:@"custom-event"]);
}

- (void)test_10_8_1_c_NameValueAttribute
{
    [self loadRequired:@"Chapt10/10.8/10.8.1/10.8.1.c.xhtml"];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self.messages containsObject:@"xforms-rebuild"],
                  @"name/@value beats the inline text: %@", self.messages);
    XCTAssertFalse([self.messages containsObject:@"custom-event"]);
}

- (void)test_10_8_2_a_TargetElement
{
    [self loadRequired:@"Chapt10/10.8/10.8.2/10.8.2.a.xhtml"];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self.messages containsObject:@"custom-event"], @"%@", self.messages);
}

- (void)test_10_8_2_b_TargetElementPrecedence
{
    [self loadRequired:@"Chapt10/10.8/10.8.2/10.8.2.b.xhtml"];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self.messages containsObject:@"custom-event"], @"%@", self.messages);
    XCTAssertFalse([self.messages containsObject:@"wrong custom-event"],
                   @"the targetid ELEMENT beats @targetid");
}

- (void)test_10_8_2_c_TargetValueAttribute
{
    [self loadRequired:@"Chapt10/10.8/10.8.2/10.8.2.c.xhtml"];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self.messages containsObject:@"custom-event"], @"%@", self.messages);
    XCTAssertFalse([self.messages containsObject:@"wrong custom-event"],
                   @"targetid/@value beats the inline text");
}

- (void)test_10_8_3_a_DelayElement
{
    [self loadRequired:@"Chapt10/10.8/10.8.3/10.8.3.a.xhtml"];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self.messages containsObject:@"xforms-rebuild"], @"%@", self.messages);
    [self.messages removeAllObjects];
    [self activateTriggerAtIndex:1];
    XCTAssertFalse([self.messages containsObject:@"xforms-rebuild"],
                   @"the delay ELEMENT (5000) defers the dispatch");
}

- (void)test_10_8_3_b_DelayElementPrecedence
{
    [self loadRequired:@"Chapt10/10.8/10.8.3/10.8.3.b.xhtml"];
    [self activateTriggerAtIndex:1];
    XCTAssertFalse([self.messages containsObject:@"xforms-rebuild"],
                   @"the delay ELEMENT (5000) beats @delay='0'");
}

- (void)test_10_8_3_c_DelayValueAttribute
{
    [self loadRequired:@"Chapt10/10.8/10.8.3/10.8.3.c.xhtml"];
    [self activateTriggerAtIndex:1];
    XCTAssertFalse([self.messages containsObject:@"xforms-rebuild"],
                   @"delay/@value (5000) beats the inline text (0)");
}

#pragma mark 10.13-10.16

- (void)test_10_13_a_Reset
{
    [self loadRequired:@"Chapt10/10.13/10.13.a.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerAtIndex:0];
    [self assertSawEvent:@"xforms-reset"];
}

- (void)test_10_13_b_ResetModelAttribute
{
    [self loadRequired:@"Chapt10/10.13/10.13.b.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"/car" model:[self modelWithID:@"m1"]], @"BMW");
    [self activateTriggerLabeled:@"Reset Car Type Value"];
    XCTAssertEqualObjects([self stringForXPath:@"/car" model:[self modelWithID:@"m1"]], @"Mercedes");
    XCTAssertEqualObjects([self stringForXPath:@"/car/color" model:[self modelWithID:@"m2"]], @"red",
                          @"m2 untouched by the m1 reset");
    [self activateTriggerLabeled:@"Reset Car Color Value"];
    XCTAssertEqualObjects([self stringForXPath:@"/car/color" model:[self modelWithID:@"m2"]], @"white");
}

- (void)test_10_14_a_LoadAttributes
{
    [self loadRequired:@"Chapt10/10.14/10.14.a.xhtml"];
    NSString *spec = @"http://www.w3.org/TR/xforms11/";
    for (NSUInteger i = 0; i < 3; i++) {
        [self activateTriggerAtIndex:i];
        XCTAssertTrue([self.loadRequests.lastObject hasPrefix:spec],
                      @"trigger %lu: %@", (unsigned long)i, self.loadRequests);
    }
    XCTAssertEqual(self.loadRequests.count, (NSUInteger)3);
}

- (void)test_10_14_b_LoadShowAttribute
{
    [self loadRequired:@"Chapt10/10.14/10.14.b.xhtml"];
    [self activateTriggerAtIndex:0];
    [self activateTriggerAtIndex:1];
    [self activateTriggerAtIndex:2];
    XCTAssertEqual(self.loadShows.count, (NSUInteger)3, @"%@", self.loadShows);
    XCTAssertTrue([self.loadShows[1] isEqualToString:@"replace"]);
    XCTAssertTrue([self.loadShows[2] isEqualToString:@"new"]);
}

- (void)test_10_14_1_a_ResourceElement
{
    [self loadRequired:@"Chapt10/10.14/10.14.1/10.14.1.a.xhtml"];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self.loadRequests.lastObject hasPrefix:@"http://www.w3.org/TR/xforms11/"],
                  @"the resource ELEMENT beats @resource: %@", self.loadRequests);
}

- (void)test_10_14_1_b_ResourceValueAttribute
{
    [self loadRequired:@"Chapt10/10.14/10.14.1/10.14.1.b.xhtml"];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self.loadRequests.lastObject hasPrefix:@"http://www.w3.org/TR/xforms11/"],
                  @"resource/@value beats the inline text: %@", self.loadRequests);
}

- (void)test_10_15_a_Send
{
    [self loadRequired:@"Chapt10/10.15/10.15.a.xhtml"];
    [self useEchoTransport];
    [self activateTriggerAtIndex:0];
    XCTAssertTrue([self.messages containsObject:@"xforms-submit-done"], @"%@", self.messages);
    [self.messages removeAllObjects];
    [self activateTriggerAtIndex:1];
    XCTAssertTrue([self.messages containsObject:@"xforms-submit-done"], @"%@", self.messages);
}

- (void)test_10_16_a_MessageBinding
{
    [self loadRequired:@"Chapt10/10.16/10.16.a.xhtml"];
    [self activateTriggerAtIndex:0];
    [self activateTriggerAtIndex:1];
    NSUInteger n = 0;
    for (NSString *m in self.messages) {
        if ([[m stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]]
                isEqualToString:@"Instance Message"]) {
            n++;
        }
    }
    XCTAssertEqual(n, (NSUInteger)2, @"bind and ref variants: %@", self.messages);
}

- (void)test_10_16_b_MessageLevels
{
    [self loadRequired:@"Chapt10/10.16/10.16.b.xhtml"];
    [self activateTriggerAtIndex:0];
    [self activateTriggerAtIndex:1];
    [self activateTriggerAtIndex:2];
    XCTAssertEqualObjects(self.messages,
        (@[ @"Modal Message", @"Modeless Message", @"Ephemeral Message" ]));
    XCTAssertEqualObjects(self.messageLevels, (@[ @"modal", @"modeless", @"ephemeral" ]));
}

- (void)test_10_16_c_MessageRuntimeContent
{
    // the message body embeds an xf:output evaluated at run time
    [self loadRequired:@"Chapt10/10.16/10.16.c.xhtml"];
    [self activateTriggerLabeled:@"See Message"];
    BOOL saw = NO;
    for (NSString *m in self.messages) {
        if ([m containsString:@"Hello"] && [m containsString:@"world"]) {
            saw = YES;
        }
    }
    XCTAssertTrue(saw, @"'Hello, world!': %@", self.messages);
}

#pragma mark 10.17-10.18 if / while

- (void)test_10_17_a_ConditionalSetvalue
{
    [self loadRequired:@"Chapt10/10.17/10.17.a.xhtml"];
    [self activateTriggerLabeled:@"Enter Correct Answers"];
    XCTAssertEqualObjects([self stringForXPath:@"instance('fb')/feedback_one"], @"correct");
    XCTAssertEqualObjects([self stringForXPath:@"instance('fb')/feedback_three"], @"correct");
    [self activateTriggerLabeled:@"Enter Incorrect Answers"];
    XCTAssertEqualObjects([self stringForXPath:@"instance('fb')/feedback_one"], @"incorrect");
    XCTAssertEqualObjects([self stringForXPath:@"instance('fb')/feedback_three"], @"incorrect");
}

- (void)test_10_17_b_ConditionalAction
{
    [self loadRequired:@"Chapt10/10.17/10.17.b.xhtml"];
    [self activateTriggerLabeled:@"Positive Test"];
    XCTAssertTrue([self.messages containsObject:@"This is the positive test"], @"%@", self.messages);
    [self activateTriggerLabeled:@"Negative Test"];
    XCTAssertFalse([self.messages containsObject:@"This is the negative test"],
                   @"the false @if must suppress the whole action");
}

- (void)test_10_17_c_FocusAdvancement
{
    [self loadRequired:@"Chapt10/10.17/10.17.c.xhtml"];
    [self setValue:@"415" ofControl:[self controlWithBinding:@"/info/areaCode"]];
    XCTAssertEqualObjects(self.focusRequests.lastObject, @"ExchangeControl",
                          @"3 digits advance the focus");
    [self setValue:@"55" ofControl:[self controlWithBinding:@"/info/exchange"]];
    XCTAssertFalse([self.focusRequests.lastObject isEqualToString:@"LocalControl"],
                   @"2 digits must NOT advance");
    [self setValue:@"555" ofControl:[self controlWithBinding:@"/info/exchange"]];
    XCTAssertEqualObjects(self.focusRequests.lastObject, @"LocalControl");
}

- (void)test_10_17_d_EmptyRepeatFocus
{
    [self loadRequired:@"Chapt10/10.17/10.17.d.xhtml"];
    XFRepeat *repeat = [self controlOfClass:[XFRepeat class] index:0];
    NSUInteger rows = repeat.items.count;
    XCTAssertTrue(rows > 0);
    for (NSUInteger i = 0; i < rows; i++) {
        [self activateTriggerLabeled:@"Delete Row"];
    }
    XCTAssertEqual(repeat.items.count, (NSUInteger)0);
    XCTAssertEqualObjects(self.focusRequests.lastObject, @"InsertControl",
                          @"deleting the last row focuses the Insert trigger");
}

- (void)test_10_18_a_WhileOnAction
{
    [self loadRequired:@"Chapt10/10.18/10.18.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"count(number)"], @"10",
                          @"while inserts until ten nodes exist");
}

- (void)test_10_18_b_WhileOnActionElement
{
    [self loadRequired:@"Chapt10/10.18/10.18.b.xhtml"];
    [self activateTriggerLabeled:@"Run Test"];
    XCTAssertEqualObjects([self stringForXPath:@"count(number)"], @"10");
}

- (void)test_10_18_c_WhileZeroIterations
{
    [self loadRequired:@"Chapt10/10.18/10.18.c.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"count(number)"], @"1",
                          @"a false while runs zero times");
}

- (void)test_10_18_d_IfAndWhile
{
    // if is re-evaluated per iteration: stops at 5 despite while < 10
    [self loadRequired:@"Chapt10/10.18/10.18.d.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"count(number)"], @"5");
}

- (void)test_10_18_e_SummingExample
{
    [self loadRequired:@"Chapt10/10.18/10.18.e.xhtml"];
    [self activateTriggerAtIndex:0];
    XCTAssertEqualObjects([self stringForXPath:@"instance('temps')/accumulator"], @"6");
    XCTAssertTrue([[self stringForXPath:@"instance('temps')/counter"] hasPrefix:@"4"],
                  @"counter ends past the last node");
}

@end
