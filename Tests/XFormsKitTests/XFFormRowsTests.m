#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFFormRows.h>
#import <XFormsKit/XFSelectControl.h>
#import <XFormsKit/XFRepeat.h>

/// The flattening an iOS form is built from: host tree in, sections and
/// rows out. Runs on every platform — it names no view framework, which is
/// the point of keeping it separate from the cells.
@interface XFFormRowsTests : XCTestCase
@end

@implementation XFFormRowsTests

- (XFProcessor *)formWithBody:(NSString *)body
{
    NSString *xml = [NSString stringWithFormat:
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <head><xf:model><xf:instance><data xmlns=\"\">"
        @"    <name>Ada</name><agree>true</agree><colour>red</colour>"
        @"    <note>hi</note><many>a</many>"
        @"  </data></xf:instance></xf:model></head>"
        @"  <body>%@</body></html>", body];
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    return p;
}

- (NSArray<XFFormSection *> *)sectionsForBody:(NSString *)body
{
    return [XFFormRows sectionsForProcessor:[self formWithBody:body]];
}

- (void)testRepeatSectionTagsItsRowsAndClosesWithAnAddRow
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <head><xf:model><xf:instance><data xmlns=\"\">"
        @"    <item><name>one</name></item><item><name>two</name></item>"
        @"  </data></xf:instance></xf:model></head>"
        @"  <body><xf:repeat nodeset=\"item\"><xf:label>Items</xf:label>"
        @"    <xf:input ref=\"name\"><xf:label>Name</xf:label></xf:input>"
        @"  </xf:repeat></body></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSArray<XFFormSection *> *sections = [XFFormRows sectionsForProcessor:p];
    XCTAssertEqual(sections.count, (NSUInteger)1);
    XFFormSection *section = sections.firstObject;
    XCTAssertNotNil(section.repeat);
    XCTAssertEqual(section.rows.count, (NSUInteger)3);   // two items + add

    // each item's row knows which node a gesture on it would act on
    XCTAssertEqual(section.rows[0].repeatPosition, (NSUInteger)1);
    XCTAssertEqual(section.rows[1].repeatPosition, (NSUInteger)2);
    XCTAssertEqual(section.rows[0].repeat, section.repeat);

    XFFormRow *add = section.rows.lastObject;
    XCTAssertEqual(add.kind, XFFormRowKindRepeatAdd);
    XCTAssertEqual(add.repeat, section.repeat);
    // 0 because it stands for the repeat, not for any one item
    XCTAssertEqual(add.repeatPosition, (NSUInteger)0);
}

- (void)testRowsOutsideARepeatCarryNoRepeat
{
    NSArray<XFFormSection *> *sections = [self sectionsForBody:
        @"<xf:input ref=\"name\"><xf:label>Name</xf:label></xf:input>"];
    XFFormRow *row = sections.firstObject.rows.firstObject;
    XCTAssertNil(row.repeat);
    XCTAssertEqual(row.repeatPosition, (NSUInteger)0);
}

#pragma mark - prose with controls in it (inline flow)

- (void)testASentenceWithControlsBecomesOneFlowRow
{
    NSArray<XFFormSection *> *sections = [self sectionsForBody:
        @"<p>Hello <xf:output ref=\"name\"/>, pick a "
        @"<xf:trigger><xf:label>Colour</xf:label></xf:trigger> today</p>"];
    NSArray<XFFormRow *> *rows = sections.firstObject.rows;
    XCTAssertEqual(rows.count, (NSUInteger)1);
    XCTAssertEqual(rows.firstObject.kind, XFFormRowKindInlineFlow);
    // the whole run travels together, words and controls in order
    XCTAssertTrue(rows.firstObject.hostNodes.count >= 3);
}

- (void)testTwoControlsWithNoWordsStillFlow
{
    // the writers sample: two outputs and a trigger, joined by nothing
    // but non-breaking spaces
    NSArray<XFFormSection *> *sections = [self sectionsForBody:
        @"<p><xf:output ref=\"name\"/>\u00a0<xf:output ref=\"colour\"/>\u00a0"
        @"<xf:trigger><xf:label>Show</xf:label></xf:trigger></p>"];
    NSArray<XFFormRow *> *rows = sections.firstObject.rows;
    XCTAssertEqual(rows.count, (NSUInteger)1);
    XCTAssertEqual(rows.firstObject.kind, XFFormRowKindInlineFlow);
}

- (void)testALoneControlInABlockKeepsItsOwnRow
{
    // a single field is not a sentence: on a phone it wants a label and a
    // row of its own, which is what every other form gets
    NSArray<XFFormSection *> *sections = [self sectionsForBody:
        @"<p><xf:input ref=\"name\"><xf:label>Name</xf:label></xf:input></p>"];
    NSArray<XFFormRow *> *rows = sections.firstObject.rows;
    XCTAssertEqual(rows.count, (NSUInteger)1);
    XCTAssertEqual(rows.firstObject.kind, XFFormRowKindTextField);
}

- (void)testProseWithNoControlsIsStillMarkup
{
    NSArray<XFFormSection *> *sections = [self sectionsForBody:
        @"<p>Just a paragraph of words.</p>"];
    XCTAssertEqual(sections.firstObject.rows.firstObject.kind, XFFormRowKindMarkup);
}

/// A block-level control among the words does not spoil the line: the
/// sentence flows and the block follows, as a browser lays it out. This
/// is the writers sample, whose <p> ends with the empty group a subform
/// is embedded into.
- (void)testABlockControlAfterASentenceIsSplitOff
{
    NSArray<XFFormSection *> *sections = [self sectionsForBody:
        @"<p><xf:output ref=\"name\"/>\u00a0"
        @"<xf:trigger><xf:label>Show</xf:label></xf:trigger>"
        @"<xf:group id=\"subform\"><xf:label>Books</xf:label>"
        @"  <xf:output ref=\"colour\"><xf:label>Inside</xf:label></xf:output>"
        @"</xf:group></p>"];
    NSMutableArray<NSNumber *> *kinds = [NSMutableArray array];
    for (XFFormSection *section in sections) {
        for (XFFormRow *row in section.rows) {
            [kinds addObject:@(row.kind)];
        }
    }
    XCTAssertTrue([kinds.firstObject isEqual:@(XFFormRowKindInlineFlow)],
                  @"the sentence flows first: %@", kinds);
    XCTAssertTrue(kinds.count > 1, @"and the group still contributes its own rows");
}

- (void)testADialogIsNotLaidOutInTheForm
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <head><xf:model><xf:instance><data xmlns=\"\"><n>Ada</n></data>"
        @"  </xf:instance></xf:model></head>"
        @"  <body>"
        @"    <xf:input ref=\"n\"><xf:label>Name</xf:label></xf:input>"
        @"    <xf:dialog id=\"d\"><xf:label>A dialog</xf:label>"
        @"      <xf:output ref=\"n\"><xf:label>Inside</xf:label></xf:output>"
        @"    </xf:dialog>"
        @"  </body></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (XFFormSection *section in [XFFormRows sectionsForProcessor:p]) {
        for (XFFormRow *row in section.rows) {
            if (row.label.length) { [labels addObject:row.label]; }
        }
    }
    // the dialog is hidden until xf:show and then PRESENTED; its content
    // must not sit in the form, or it shows permanently and twice over
    XCTAssertTrue([labels containsObject:@"Name"], @"%@", labels);
    XCTAssertFalse([labels containsObject:@"Inside"], @"dialog content leaked: %@", labels);
    XCTAssertFalse([labels containsObject:@"A dialog"], @"%@", labels);
}

- (void)testMarkupRowsCarryTheirRepeatItemsContext
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <head><xf:model><xf:instance><colors xmlns=\"\">"
        @"    <color code=\"#FF0000\"/><color code=\"#0000FF\"/>"
        @"  </colors></xf:instance></xf:model></head>"
        @"  <body><xf:repeat nodeset=\"color\"><p>flag</p></xf:repeat></body></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSMutableArray<XFFormRow *> *markup = [NSMutableArray array];
    for (XFFormSection *section in [XFFormRows sectionsForProcessor:p]) {
        for (XFFormRow *row in section.rows) {
            if (row.kind == XFFormRowKindMarkup) { [markup addObject:row]; }
        }
    }
    XCTAssertEqual(markup.count, (NSUInteger)2);
    // each item's markup points at that item's node, which is what its
    // AVTs and xf:output children evaluate against
    XCTAssertNotNil(markup[0].contextNode);
    XCTAssertNotEqual(markup[0].contextNode, markup[1].contextNode);
}

- (void)testNoteRowCarriesHintMarkup
{
    NSArray<XFFormSection *> *sections = [self sectionsForBody:
        @"<xf:input ref=\"name\"><xf:label>Name</xf:label>"
        @"  <xf:hint>Enter your <b>full</b> name</xf:hint></xf:input>"];
    XFFormRow *note = sections.firstObject.rows.lastObject;
    XCTAssertEqual(note.kind, XFFormRowKindNote);
    XCTAssertEqualObjects(note.note, @"Enter your full name");
    XCTAssertEqualObjects(note.noteMarkup, @"Enter your <b>full</b> name");
}

- (void)testPlainNoteRowHasNoMarkup
{
    NSArray<XFFormSection *> *sections = [self sectionsForBody:
        @"<xf:input ref=\"name\"><xf:label>Name</xf:label>"
        @"  <xf:hint>Plain hint</xf:hint></xf:input>"];
    XFFormRow *note = sections.firstObject.rows.lastObject;
    XCTAssertEqualObjects(note.note, @"Plain hint");
    XCTAssertNil(note.noteMarkup);
}

- (void)testEachControlKindPicksItsRow
{
    NSArray<XFFormSection *> *sections = [self sectionsForBody:
        @"<xf:input ref=\"name\"><xf:label>Name</xf:label></xf:input>"
        @"<xf:secret ref=\"name\"><xf:label>PW</xf:label></xf:secret>"
        @"<xf:textarea ref=\"note\"><xf:label>Note</xf:label></xf:textarea>"
        @"<xf:input ref=\"agree\"><xf:label>Agree</xf:label></xf:input>"
        @"<xf:output ref=\"name\"><xf:label>Shown</xf:label></xf:output>"
        @"<xf:trigger><xf:label>Go</xf:label></xf:trigger>"
        @"<xf:range ref=\"name\" start=\"0\" end=\"10\"><xf:label>R</xf:label></xf:range>"
        @"<xf:upload ref=\"name\"><xf:label>File</xf:label></xf:upload>"];
    XCTAssertEqual(sections.count, (NSUInteger)1, @"nothing is grouped, so one section");
    NSArray<XFFormRow *> *rows = sections[0].rows;
    NSArray *expected = @[ @(XFFormRowKindTextField), @(XFFormRowKindTextField),
                           @(XFFormRowKindTextView), @(XFFormRowKindSwitch),
                           @(XFFormRowKindValue), @(XFFormRowKindButton),
                           @(XFFormRowKindSlider), @(XFFormRowKindUpload) ];
    XCTAssertEqual(rows.count, expected.count);
    for (NSUInteger i = 0; i < MIN(rows.count, expected.count); i++) {
        XCTAssertEqual((NSInteger)rows[i].kind, [expected[i] integerValue],
                       @"row %lu (%@)", (unsigned long)i, rows[i].label);
    }
}

- (void)testSelectPicksSegmentedOrCheckRowsByItemCount
{
    NSString *(^select)(NSUInteger) = ^NSString *(NSUInteger count) {
        NSMutableString *items = [NSMutableString string];
        for (NSUInteger i = 0; i < count; i++) {
            [items appendFormat:@"<xf:item><xf:label>i%lu</xf:label>"
                                 "<xf:value>v%lu</xf:value></xf:item>",
                                (unsigned long)i, (unsigned long)i];
        }
        return [NSString stringWithFormat:
            @"<xf:select1 ref=\"colour\" appearance=\"full\">"
             "<xf:label>Colour</xf:label>%@</xf:select1>", items];
    };

    // few items: one segmented row
    NSArray<XFFormRow *> *few = [self sectionsForBody:select(3)][0].rows;
    XCTAssertEqual(few.count, (NSUInteger)1);
    XCTAssertEqual((NSInteger)few[0].kind, (NSInteger)XFFormRowKindSegmented);

    // many: one check row each, so the list scrolls instead of overflowing
    NSArray<XFFormRow *> *many = [self sectionsForBody:select(8)][0].rows;
    XCTAssertEqual(many.count, (NSUInteger)8);
    for (NSUInteger i = 0; i < many.count; i++) {
        XCTAssertEqual((NSInteger)many[i].kind, (NSInteger)XFFormRowKindCheck);
        XCTAssertEqual(many[i].itemIndex, i);
    }
    XCTAssertEqualObjects(many[0].label, @"Colour", @"the caption shows once");
    XCTAssertNil(many[1].label);

    // minimal appearance stays a value + picker row whatever the count
    NSArray<XFFormRow *> *minimal = [self sectionsForBody:
        @"<xf:select1 ref=\"colour\" appearance=\"minimal\">"
         "<xf:label>C</xf:label>"
         "<xf:item><xf:label>Red</xf:label><xf:value>red</xf:value></xf:item>"
         "</xf:select1>"][0].rows;
    XCTAssertEqual((NSInteger)minimal[0].kind, (NSInteger)XFFormRowKindSelector);
}

- (void)testTopLevelGroupsBecomeSectionsAndNestedOnesIndent
{
    NSArray<XFFormSection *> *sections = [self sectionsForBody:
        @"<xf:input ref=\"name\"><xf:label>Loose</xf:label></xf:input>"
        @"<xf:group><xf:label>Details</xf:label>"
        @"  <xf:input ref=\"note\"><xf:label>Note</xf:label></xf:input>"
        @"  <xf:group><xf:label>Deeper</xf:label>"
        @"    <xf:input ref=\"colour\"><xf:label>Colour</xf:label></xf:input>"
        @"  </xf:group>"
        @"</xf:group>"];
    XCTAssertEqual(sections.count, (NSUInteger)2);
    XCTAssertNil(sections[0].title, @"what sits outside a group leads, untitled");
    XCTAssertEqualObjects(sections[0].rows[0].label, @"Loose");

    XCTAssertEqualObjects(sections[1].title, @"Details");
    XCTAssertEqual(sections[1].rows.count, (NSUInteger)2);
    XCTAssertEqualObjects(sections[1].rows[0].label, @"Note");
    // the nested group has nowhere to go in a two-level table: it flattens,
    // and carries the depth an indent is drawn from
    XCTAssertEqualObjects(sections[1].rows[1].label, @"Colour");
    XCTAssertGreaterThan(sections[1].rows[1].depth, sections[1].rows[0].depth);
}

/// Sections come out in document order. Rows outside a group used to be
/// collected and prepended in one lump, which put anything after a group
/// above it.
- (void)testSectionsKeepDocumentOrder
{
    NSArray<XFFormSection *> *sections = [self sectionsForBody:
        @"<xf:input ref=\"name\"><xf:label>Before</xf:label></xf:input>"
        @"<xf:group><xf:label>Middle</xf:label>"
        @"  <xf:input ref=\"note\"><xf:label>Inside</xf:label></xf:input>"
        @"</xf:group>"
        @"<xf:trigger><xf:label>After</xf:label></xf:trigger>"];
    XCTAssertEqual(sections.count, (NSUInteger)3);
    XCTAssertEqualObjects(sections[0].rows[0].label, @"Before");
    XCTAssertEqualObjects(sections[1].title, @"Middle");
    XCTAssertEqualObjects(sections[2].rows[0].label, @"After");
}

- (void)testNonRelevantControlsTakeNoRow
{
    NSArray<XFFormSection *> *sections = [self sectionsForBody:
        @"<xf:input ref=\"name\"><xf:label>Shown</xf:label></xf:input>"
        @"<xf:group ref=\"nothing\"><xf:label>Gone</xf:label>"
        @"  <xf:input ref=\"note\"><xf:label>Hidden</xf:label></xf:input>"
        @"</xf:group>"];
    for (XFFormSection *section in sections) {
        for (XFFormRow *row in section.rows) {
            XCTAssertNotEqualObjects(row.label, @"Hidden");
        }
    }
}

/// The host tree keeps inter-element whitespace deliberately. It must not
/// become rows, or every pair of controls gets an empty cell between them.
- (void)testWhitespaceBetweenControlsIsNotARow
{
    NSArray<XFFormSection *> *sections = [self sectionsForBody:
        @"  <xf:input ref=\"name\"><xf:label>One</xf:label></xf:input>\n"
        @"  <xf:input ref=\"note\"><xf:label>Two</xf:label></xf:input>\n"];
    NSArray<XFFormRow *> *rows = sections[0].rows;
    XCTAssertEqual(rows.count, (NSUInteger)2);
    XCTAssertEqualObjects(rows[0].label, @"One");
    XCTAssertEqualObjects(rows[1].label, @"Two");
}

- (void)testHostMarkupGathersIntoRuns
{
    NSArray<XFFormSection *> *sections = [self sectionsForBody:
        @"<p>Some prose <b>and more</b> of it.</p>"
        @"<xf:input ref=\"name\"><xf:label>Name</xf:label></xf:input>"
        @"<p>Trailing prose.</p>"];
    NSArray<XFFormRow *> *rows = sections[0].rows;
    XCTAssertEqual(rows.count, (NSUInteger)3, @"markup, control, markup");
    XCTAssertEqual((NSInteger)rows[0].kind, (NSInteger)XFFormRowKindMarkup);
    XCTAssertGreaterThan(rows[0].hostNodes.count, (NSUInteger)0);
    XCTAssertEqual((NSInteger)rows[1].kind, (NSInteger)XFFormRowKindTextField);
    XCTAssertEqual((NSInteger)rows[2].kind, (NSInteger)XFFormRowKindMarkup);
}

@end
