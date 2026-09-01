/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* W3C XForms 1.1 test suite, chapter 9 (Container Form Controls) — 21
   cases. Switch state asserts on selectedCase and on what the deep walk
   renders (the walk enters only the selected case, so "you must NOT see
   X" is `!valueRendered:X`); repeat cases assert item counts and
   per-item values through the real repeat machinery. SPEC-TRUE. */
#import "XFW3CTestCase.h"

@interface XFW3CChapter09Tests : XFW3CTestCase
@end

@implementation XFW3CChapter09Tests

- (NSUInteger)renderedCountOf:(NSString *)value
{
    NSUInteger n = 0;
    for (NSString *v in [self renderedValues]) {
        if ([v isEqualToString:value]) {
            n++;
        }
    }
    return n;
}

#pragma mark 9.1 group

- (void)test_9_1_1_a1_GroupPrecedence
{
    // a non-relevant group hides its children whatever their own binds
    // say; a relevant group still hides a child whose own bind is false
    [self loadRequired:@"Chapt09/9.1/9.1.1/9.1.1.a1.xhtml"];
    // the CONTAINER carries the non-relevance for Street (a hidden group
    // hides its subtree); City's own bind hides it directly
    XFControl *group1 = [self controlWithBinding:@"group1"];
    XFControl *city = [self controlWithBinding:@"input2"];
    XCTAssertFalse(group1.relevant, @"group1 (relevant=false) hides its content");
    XCTAssertFalse(city.relevant, @"input2's own bind (relevant=false) hides City");
}

- (void)test_9_1_1_a2_GroupInsideCase
{
    [self loadRequired:@"Chapt09/9.1/9.1.1/9.1.1.a2.xhtml"];
    XFSwitch *sw = [self controlOfClass:[XFSwitch class] index:0];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"in");
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Show Out Case"];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"out");
    [self assertSawEvent:@"xforms-deselect"];
    [self assertSawEvent:@"xforms-select"];
    [self activateTriggerLabeled:@"Show In Case"];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"in");
}

- (void)test_9_1_1_b_GroupLabels
{
    // exact label match — the instruction label also QUOTES the group
    // names, so a substring search would find the wrong group
    [self loadRequired:@"Chapt09/9.1/9.1.1/9.1.1.b.xhtml"];
    XFGroup *shipping = nil, *date = nil;
    for (XFControl *c in [self allControls]) {
        if ([c isKindOfClass:[XFGroup class]]) {
            if ([c.label isEqualToString:@"Shipping Address"]) {
                shipping = (XFGroup *)c;
            } else if ([c.label isEqualToString:@"Shipping Date"]) {
                date = (XFGroup *)c;
            }
        }
    }
    XCTAssertTrue([shipping isKindOfClass:[XFGroup class]]);
    XCTAssertTrue([date isKindOfClass:[XFGroup class]]);
    XCTAssertTrue(shipping.children.count >= 2, @"Street + City inputs: %@", shipping.children);
    XCTAssertTrue(date.children.count >= 2, @"Day + Month inputs: %@", date.children);
}

- (void)test_9_1_1_c_FocusToGroup
{
    // headless focus: the normative core is that setfocus on a group
    // dispatches xforms-focus (the host then focuses the first control)
    [self loadRequired:@"Chapt09/9.1/9.1.1/9.1.1.c.xhtml"];
    [self.dispatchedEvents removeAllObjects];
    [self activateTriggerLabeled:@"Set Focus To Group 2"];
    [self assertSawEvent:@"xforms-focus"];
}

#pragma mark 9.2 switch / case

- (void)test_9_2_1_a1_SwitchToggle
{
    [self loadRequired:@"Chapt09/9.2/9.2.1/9.2.1.a1.xhtml"];
    XFSwitch *sw = [self controlOfClass:[XFSwitch class] index:0];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"in", @"selected='true'");
    [self activateTriggerLabeled:@"Case In"];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"out");
    [self activateTriggerLabeled:@"Case Out"];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"in");
}

- (void)test_9_2_1_a2_SwitchReceivesEvents
{
    // the bound switch turns readonly with its node; the event bubbles
    // to the enclosing group's message handler
    [self loadRequired:@"Chapt09/9.2/9.2.1/9.2.1.a2.xhtml"];
    XFSelectControl *select1 = [self controlOfClass:[XFSelectControl class] index:0];
    [self.dispatchedEvents removeAllObjects];
    XCTAssertTrue([select1 selectValue:@"yes"]);
    [self assertSawEvent:@"xforms-readonly"];
    XCTAssertTrue(select1.readonly, @"haveCar='yes' makes the node readonly");
}

- (void)test_9_2_1_b_SwitchExample
{
    [self loadRequired:@"Chapt09/9.2/9.2.1/9.2.1.b.xhtml"];
    XFSwitch *sw = [self controlOfClass:[XFSwitch class] index:0];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"in");
    XCTAssertNotNil([self controlOfClass:[XFInputControl class] index:0]);
    [self activateTriggerLabeled:@"Send Name"];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"out");
    XCTAssertTrue([self valueRendered:@"Bill"], @"the Hello output shows the name");
    [self activateTriggerLabeled:@"Edit"];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"in");
}

- (void)test_9_2_2_a_FirstCaseAutoSelected
{
    [self loadRequired:@"Chapt09/9.2/9.2.2/9.2.2.a.xhtml"];
    XCTAssertTrue([self valueRendered:@"Janel"]);
    XCTAssertFalse([self valueRendered:@"Blue"], @"the unselected case must not show");
}

- (void)test_9_2_2_b_SelectedAttribute
{
    [self loadRequired:@"Chapt09/9.2/9.2.2/9.2.2.b.xhtml"];
    XCTAssertTrue([self valueRendered:@"Blue"], @"selected='true' picks the second case");
    XCTAssertFalse([self valueRendered:@"Janel"]);
}

- (void)test_9_2_2_c_MultipleSelectedAttributes
{
    // several selected='true' → the FIRST wins
    [self loadRequired:@"Chapt09/9.2/9.2.2/9.2.2.c.xhtml"];
    XCTAssertTrue([self valueRendered:@"Janel"]);
    XCTAssertFalse([self valueRendered:@"Blue"]);
}

#pragma mark 9.3 repeat

- (void)test_9_3_1_a_Repeat
{
    [self loadRequired:@"Chapt09/9.3/9.3.1/9.3.1.a.xhtml"];
    for (NSString *v in @[ @"windshield wipers", @"tires", @"exhaust", @"air freshener" ]) {
        XCTAssertTrue([self valueRendered:v], @"'%@' must render", v);
    }
}

- (void)test_9_3_1_b_StartIndex
{
    [self loadRequired:@"Chapt09/9.3/9.3.1/9.3.1.b.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue],
                          @"3", @"startindex=3 → index('myrepeat') = 3");
}

- (void)test_9_3_1_c_NumberAttribute
{
    // non-normative presentation hint ("you MAY see only one")
    [self loadRequired:@"Chapt09/9.3/9.3.1/9.3.1.c.xhtml"];
    XFRepeat *repeat = [self controlOfClass:[XFRepeat class] index:0];
    XCTAssertTrue(repeat.items.count == 4 || repeat.items.count == 1,
                  @"all nodes bound (or windowed to number=1): %lu",
                  (unsigned long)repeat.items.count);
    XCTAssertEqual(self.messages.count, (NSUInteger)0);
}

- (void)test_9_3_1_d_UnrolledRepeat
{
    // the rolled repeat and the hand-unrolled copy must agree
    [self loadRequired:@"Chapt09/9.3/9.3.1/9.3.1.d.xhtml"];
    for (NSString *v in @[ @"windshield wipers", @"tires", @"exhaust", @"air freshener" ]) {
        XCTAssertEqual([self renderedCountOf:v], (NSUInteger)2, @"'%@' in both lists", v);
    }
}

- (void)test_9_3_1_e_RepeatInsertRemove
{
    [self loadRequired:@"Chapt09/9.3/9.3.1/9.3.1.e.xhtml"];
    XFRepeat *repeat = [self controlOfClass:[XFRepeat class] index:0];
    XCTAssertEqual(repeat.items.count, (NSUInteger)3);
    XCTAssertTrue([self valueRendered:@"32.25"]);
    [self activateTriggerLabeled:@"Insert New Item"];
    XCTAssertEqual(repeat.items.count, (NSUInteger)4, @"insert adds a line");
    XCTAssertTrue([self valueRendered:@"0.00"], @"the new line's price is 0.00");
    [self activateTriggerLabeled:@"Remove Current Item"];
    XCTAssertEqual(repeat.items.count, (NSUInteger)3, @"remove deletes the line");
}

- (void)test_9_3_1_f_SwitchWithinRepeat
{
    // each repeat item carries its OWN switch state
    [self loadRequired:@"Chapt09/9.3/9.3.1/9.3.1.f.xhtml"];
    XCTAssertEqual([self renderedCountOf:@"You are in the In case"], (NSUInteger)3);
    [self activateTriggerLabeled:@"Go To Out Case"];   // the first one
    XCTAssertEqual([self renderedCountOf:@"You are in the Out case"], (NSUInteger)1,
                   @"only the toggled item switches");
    XCTAssertEqual([self renderedCountOf:@"You are in the In case"], (NSUInteger)2,
                   @"the other two stay");
    [self activateTriggerLabeled:@"Go To In Case"];
    XCTAssertEqual([self renderedCountOf:@"You are in the In case"], (NSUInteger)3);
}

- (void)test_9_3_4_a_SwitchInsideRepeat
{
    [self loadRequired:@"Chapt09/9.3/9.3.4/9.3.4.a.xhtml"];
    [self activateTriggerLabeled:@"Show Out Case"];
    XCTAssertNotNil([self controlWithLabelContaining:@"Show In Case"],
                    @"the Out case's trigger replaces the In case's");
    [self activateTriggerLabeled:@"Show In Case"];
    XCTAssertNotNil([self controlWithLabelContaining:@"Show Out Case"]);
}

- (void)test_9_3_5_a_RepeatAttributes
{
    // repeat-nodeset/-bind ATTRIBUTES are non-normative ("if supported");
    // part 3 is a plain repeat and must always work
    [self loadRequired:@"Chapt09/9.3/9.3.5/9.3.5.a.xhtml"];
    for (NSString *v in @[ @"windshield wipers", @"tires", @"exhaust", @"air freshener" ]) {
        XCTAssertTrue([self renderedCountOf:v] >= 1, @"'%@' (plain repeat, part 3)", v);
    }
}

- (void)test_9_3_6_a_ItemsetWithCopy
{
    [self loadRequired:@"Chapt09/9.3/9.3.6/9.3.6.a.xhtml"];
    for (NSUInteger s = 0; s < 2; s++) {
        XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:s];
        XCTAssertEqual(select.items.count, (NSUInteger)3, @"select %lu", (unsigned long)s);
        XCTAssertEqualObjects(select.items.firstObject.label, @"Vanilla");
        XCTAssertTrue(select.items.firstObject.usesCopy || select.usesCopy,
                      @"itemset uses xf:copy");
    }
}

- (void)test_9_3_7_a_CopyElement
{
    [self loadRequired:@"Chapt09/9.3/9.3.7/9.3.7.a.xhtml"];
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    XFOutputControl *output = [self controlOfClass:[XFOutputControl class] index:0];
    XCTAssertFalse(output.relevant, @"no flavor selected yet → no output");
    XCTAssertTrue([select selectItem:select.items.firstObject]);
    XCTAssertEqualObjects([self stringForXPath:@"/icecream/order/flavor"
                                         model:[self modelWithID:@"cone"]], @"vanilla",
                          @"copy inserts the flavor subtree");
    XCTAssertTrue(output.relevant);
    XCTAssertTrue([select toggleItem:select.items.firstObject]);   // deselect
    XCTAssertFalse(output.relevant, @"deselect removes the copied subtree");
}

- (void)test_9_3_7_b_CopyBindingException
{
    // copy into an attribute node cannot work → binding exception on select
    XFProcessor *p = [self loadTest:@"Chapt09/9.3/9.3.7/9.3.7.b.xhtml"];
    if (p == nil) {
        return;
    }
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    if (select.items.count) {
        [select selectItem:select.items.firstObject];
    }
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

@end
