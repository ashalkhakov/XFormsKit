/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* W3C XForms 1.1 test suite, appendix H (Complete Examples —
   non-normative) as XCTest assertions — see XFW3CTestCase.h for the
   approach and the spec-true policy. H.1 is the bilingual payment form
   (switch/case, item-level xforms-select messages, an external schema
   via the model's @schema); H.2 the hierarchical bookmark editor
   (instance @resource, nested repeats, index()-driven insert/delete);
   H.3 the espresso survey hosted in an SVG document (the manifest links
   h.3.svg, absent upstream — h.3.xhtml carries the same document). */
#import "XFW3CTestCase.h"

@interface XFW3CAppendixHTests : XFW3CTestCase
@end

@implementation XFW3CAppendixHTests

- (void)test_h_1_XFormsInXHTML
{
    [self loadRequired:@"Appendix/H/h.1.xhtml"];
    [self useEchoTransport];
    XCTAssertEqualObjects([self stringForXPath:@"/my:payment/@as"], @"credit");
    XFSwitch *sw = [self controlOfClass:[XFSwitch class] index:0];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"fr",
                          @"the first case is selected initially");

    // the French select1 shows the credit selection; my:cc is
    // relevant+required while @as='credit'
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    XCTAssertTrue([select.selectedValues containsObject:@"credit"]);
    XFInputControl *cc = [self controlOfClass:[XFInputControl class] index:0];
    XCTAssertTrue(cc.relevant);
    XCTAssertTrue(cc.required);

    [self activateTriggerLabeled:@"English"];
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"en");

    // selecting Cash fires the item's xforms-select message
    XFSelectControl *enSelect = [self controlOfClass:[XFSelectControl class] index:0];
    XCTAssertTrue([enSelect selectValue:@"cash"]);
    XCTAssertTrue([[self.messages componentsJoinedByString:@"\n"]
                      containsString:@"Please do not mail cash"],
                  @"%@", self.messages);
}

- (void)test_h_2_HierarchicalBookmarks
{
    // instance @resource loads bookmarks.xml; nested repeats edit it
    [self loadRequired:@"Appendix/H/h.2.xhtml"];
    [self useEchoTransport];
    XCTAssertEqualObjects([self stringForXPath:@"count(section)"], @"3");
    XCTAssertEqualObjects([self stringForXPath:@"section[1]/@name"], @"main");
    XCTAssertEqualObjects([self stringForXPath:@"count(section[2]/bookmark)"], @"3");

    // insert a bookmark into the current (first) section
    [self activateTriggerLabeled:@"Insert bookmark"];
    XCTAssertEqualObjects([self stringForXPath:@"count(section[1]/bookmark)"], @"2",
                          @"a clone of the current bookmark is inserted");
    [self activateTriggerLabeled:@"Delete bookmark"];
    XCTAssertEqualObjects([self stringForXPath:@"count(section[1]/bookmark)"], @"1");

    // insert/delete a whole section
    [self activateTriggerLabeled:@"Insert section"];
    XCTAssertEqualObjects([self stringForXPath:@"count(section)"], @"4");
    [self activateTriggerLabeled:@"Delete section"];
    XCTAssertEqualObjects([self stringForXPath:@"count(section)"], @"3");

    // Save posts the whole bookmarks document
    [self activateTriggerLabeled:@"Save"];
    NSString *body = self.lastRequest.body ?: @"";
    XCTAssertTrue([body containsString:@"bookmarks"], @"%@", body);
    XCTAssertTrue([body containsString:@"Main page"]);
}

- (void)test_h_3_SurveyInSVG
{
    // an SVG host document: the model lives in svg/defs, the controls in
    // foreignObject islands
    [self loadTest:@"Appendix/H/h.3.xhtml"];
    XCTAssertNotNil(self.processor, @"the SVG-hosted form must load: %@", self.loadError);
    if (self.processor == nil) {
        return;
    }
    XCTAssertEqualObjects([self stringForXPath:@"/s:survey/s:drink"], @"none");
    XCTAssertNotNil([self controlOfClass:[XFSelectControl class] index:0],
                    @"the select1 inside foreignObject builds");
    XCTAssertNotNil([self controlOfClass:[XFRangeControl class] index:0],
                    @"the range inside foreignObject builds");
}

@end
