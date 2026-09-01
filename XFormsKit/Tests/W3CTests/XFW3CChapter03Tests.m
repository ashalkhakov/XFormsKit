/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* W3C XForms 1.1 test suite, chapter 3 (Document Structure) — all 37
   cases as per-case assertions. Each test states in code what the
   form's instruction label asks a human to verify. Method names carry
   the case id (test_3_2_3_a = case 3.2.3.a). SPEC-TRUE: known engine
   gaps stay red (see docs/w3c-xctests.md). */
#import "XFW3CTestCase.h"

@interface XFW3CChapter03Tests : XFW3CTestCase
@end

@implementation XFW3CChapter03Tests


- (void)test_3_1_a_XFormsNamespace
{
    [self loadRequired:@"Chapt03/3.1/3.1.a.xhtml"];
    XFOutputControl *out = [self controlOfClass:[XFOutputControl class] index:0];
    XCTAssertEqualObjects(out.stringValue, @"Honda");
}

- (void)test_3_2_1_a_IDAttribute
{
    // "Every XForms element has an id attribute. You must not see any errors."
    [self loadRequired:@"Chapt03/3.2/3.2.1/3.2.1.a.xhtml"];
    XCTAssertEqualObjects(self.processor.models.firstObject.identifier, @"mymodel");
    XCTAssertEqual(self.messages.count, (NSUInteger)0);
}

- (void)test_3_2_1_b_ForeignAttributes
{
    [self loadRequired:@"Chapt03/3.2/3.2.1/3.2.1.b.xhtml"];
    XFOutputControl *out = [self controlOfClass:[XFOutputControl class] index:0];
    XCTAssertEqualObjects(out.stringValue, @"Mazda");
}

- (void)test_3_2_2_a_SrcAttribute
{
    // instance from src file; "input labeled 'Color:' containing 'red'"
    [self loadRequired:@"Chapt03/3.2/3.2.2/3.2.2.a.xhtml"];
    XFInputControl *input = [self controlOfClass:[XFInputControl class] index:0];
    XCTAssertEqualObjects(input.stringValue, @"red");
    // the label itself comes from label.txt via label/@src
    XCTAssertTrue([input.label rangeOfString:@"Color"].location != NSNotFound,
                  @"label/@src (label.txt) should yield 'Color:', got '%@'", input.label);
}

- (void)test_3_2_3_a_SingleNodeBindingRef
{
    [self loadRequired:@"Chapt03/3.2/3.2.3/3.2.3.a.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"120");
    // ref has no meaning when bind is present → bind_001 (/car/year)
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:1] stringValue], @"1994");
}

- (void)test_3_2_3_b_SingleNodeBindingModel
{
    [self loadRequired:@"Chapt03/3.2/3.2.3/3.2.3.b.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"Mercedes");
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:1] stringValue], @"Acura");
    // model has no meaning when bind is present → bind_002 in car2
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:2] stringValue], @"Acura");
}

- (void)test_3_2_3_c_SingleNodeBindingBind
{
    [self loadRequired:@"Chapt03/3.2/3.2.3/3.2.3.c.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"silver");
}

- (void)test_3_2_3_d_BindOverridesRefAndModel
{
    [self loadRequired:@"Chapt03/3.2/3.2.3/3.2.3.d.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"silver");
}

- (void)test_3_2_3_e_InvalidBindIDREF
{
    [self loadTest:@"Chapt03/3.2/3.2.3/3.2.3.e.xhtml"];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

- (void)test_3_2_3_f_InvalidModelIDREF
{
    [self loadTest:@"Chapt03/3.2/3.2.3/3.2.3.f.xhtml"];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

- (void)test_3_2_3_g_FirstNodeRule
{
    [self loadRequired:@"Chapt03/3.2/3.2.3/3.2.3.g.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"Mercedes");
}

- (void)test_3_2_4_a_NodesetAndBindOverride
{
    // itemset's bind (valid) overrides its nodeset (deliberately bogus)
    [self loadRequired:@"Chapt03/3.2/3.2.4/3.2.4.a.xhtml"];
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    XCTAssertNotNil(select);
    XCTAssertEqual(select.items.count, (NSUInteger)5, @"items: %@", select.items);
    XCTAssertEqualObjects(select.items.firstObject.label, @"Audi");
    XCTAssertTrue([select selectValue:@"Audi"]);
    XCTAssertEqualObjects([self stringForXPath:@"/carsAvailable/carOrder"], @"Audi");
}

- (void)test_3_2_4_b_ItemsetModelAttribute
{
    // select binds in model "order", itemset pulls from "carsForSale"
    [self loadRequired:@"Chapt03/3.2/3.2.4/3.2.4.b.xhtml"];
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    XCTAssertEqual(select.items.count, (NSUInteger)5, @"items: %@", select.items);
    XCTAssertTrue([select selectValue:@"BMW"]);
    XCTAssertEqualObjects([self stringForXPath:@"/carOrder"
                                         model:[self modelWithID:@"order"]], @"BMW");
}

- (void)test_3_2_4_c_ItemsetBindAttribute
{
    [self loadRequired:@"Chapt03/3.2/3.2.4/3.2.4.c.xhtml"];
    XFSelectControl *select = [self controlOfClass:[XFSelectControl class] index:0];
    XCTAssertEqual(select.items.count, (NSUInteger)5, @"items: %@", select.items);
    XCTAssertTrue([select selectValue:@"Porsche"]);
    XCTAssertEqualObjects([self stringForXPath:@"/carsAvailable/carOrder"], @"Porsche");
}

- (void)test_3_2_4_d_BindOverridesModelAttribute
{
    [self loadRequired:@"Chapt03/3.2/3.2.4/3.2.4.d.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"BMW");
}

- (void)test_3_2_4_e_ItemsetInvalidModelIDREF
{
    [self loadTest:@"Chapt03/3.2/3.2.4/3.2.4.e.xhtml"];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

- (void)test_3_2_4_f_ItemsetInvalidBindIDREF
{
    [self loadTest:@"Chapt03/3.2/3.2.4/3.2.4.f.xhtml"];
    [self assertMessageOrFatal:@"xforms-binding-exception"];
}

- (void)test_3_3_a_IgnoreForeignAttributes
{
    [self loadRequired:@"Chapt03/3.3/3.3.a.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"Mazda");
}

- (void)test_3_3_1_a1_FiftyModels
{
    [self loadRequired:@"Chapt03/3.3/3.3.1/3.3.1.a1.xhtml"];
    XCTAssertEqual(self.processor.models.count, (NSUInteger)50);
    XCTAssertEqual(self.messages.count, (NSUInteger)0);
}

- (void)test_3_3_1_a2_NoModels
{
    // "This page creates 0 models. You must not receive any errors."
    // KNOWN GAP: the engine refuses a host document without xf:model;
    // XForms 1.1 lazy authoring must keep this form alive.
    XFProcessor *p = [self loadTest:@"Chapt03/3.3/3.3.1/3.3.1.a2.xhtml"];
    XCTAssertNotNil(p, @"a modelless document must load (lazy authoring): %@",
                    [self.loadError localizedDescription]);
    XCTAssertEqual(self.messages.count, (NSUInteger)0);
}

- (void)test_3_3_1_b_InvalidFunction
{
    // functions="invalid" → xforms-compute-exception (or fatal)
    [self loadTest:@"Chapt03/3.3/3.3.1/3.3.1.b.xhtml"];
    [self assertMessageOrFatal:@"xforms-compute-exception"];
}

- (void)test_3_3_1_c1_ValidSchema
{
    [self loadRequired:@"Chapt03/3.3/3.3.1/3.3.1.c1.xhtml"];
    XCTAssertEqual(self.messages.count, (NSUInteger)0,
                   @"no xforms-link-exception expected: %@", self.messages);
}

- (void)test_3_3_1_c2_InvalidSchema
{
    [self loadTest:@"Chapt03/3.3/3.3.1/3.3.1.c2.xhtml"];
    [self assertMessageOrFatal:@"xforms-link-exception"];
}

- (void)test_3_3_1_d1_VersionAttribute
{
    [self loadRequired:@"Chapt03/3.3/3.3.1/3.3.1.d1.xhtml"];
    XCTAssertFalse([self.messages containsObject:@"xforms-version-exception"],
                   @"version='1.0 1.1' is supported — no exception expected");
}

- (void)test_3_3_1_d2_VersionNegative1
{
    [self loadTest:@"Chapt03/3.3/3.3.1/3.3.1.d2.xhtml"];
    [self assertMessageOrFatal:@"xforms-version-exception"];
}

- (void)test_3_3_1_d3_VersionNegative2
{
    [self loadTest:@"Chapt03/3.3/3.3.1/3.3.1.d3.xhtml"];
    [self assertMessageOrFatal:@"xforms-version-exception"];
}

- (void)test_3_3_2_a_ModelWithNoInstance
{
    [self loadRequired:@"Chapt03/3.3/3.3.2/3.3.2.a.xhtml"];
    XCTAssertEqual(self.messages.count, (NSUInteger)0);
}

- (void)test_3_3_2_b_InlineDataWinsOverResource
{
    // inline content is used when @src is absent, even with @resource
    [self loadRequired:@"Chapt03/3.3/3.3.2/3.3.2.b.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"Wendy");
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:1] stringValue], @"20");
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:2] stringValue], @"college");
}

- (void)test_3_3_2_c_ResourceAttribute
{
    [self loadRequired:@"Chapt03/3.3/3.3.2/3.3.2.c.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"James");
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:1] stringValue], @"18");
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:2] stringValue], @"high school");
}

- (void)test_3_3_2_d_InvalidResourceLink
{
    [self loadTest:@"Chapt03/3.3/3.3.2/3.3.2.d.xhtml"];
    [self assertMessageOrFatal:@"xforms-link-exception"];
}

- (void)test_3_3_2_e_InlineAndResource
{
    [self loadRequired:@"Chapt03/3.3/3.3.2/3.3.2.e.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"Wendy");
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:1] stringValue], @"20");
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:2] stringValue], @"college");
}

- (void)test_3_3_2_f_SrcNonNormativePrecedence
{
    // Non-normative, and the form's instructions are CONDITIONAL ("if
    // your processor is set to override inline content…"). XForms 1.1
    // makes inline win (4.2.1.c2), so model1 may show inline (Wendy) or
    // the src override (Suzie) — but must be one set, consistently.
    // model2 has no inline: the data MUST come from a linking attribute.
    [self loadRequired:@"Chapt03/3.3/3.3.2/3.3.2.f.xhtml"];
    NSArray *inline_ = @[ @"Wendy", @"20", @"college" ];
    NSArray *src = @[ @"Suzie", @"7", @"elementary school" ];
    NSArray *resource = @[ @"James", @"18", @"high school" ];
    NSMutableArray *model1 = [NSMutableArray array], *model2 = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; i++) {
        [model1 addObject:[(XFControl *)[self controlOfClass:[XFOutputControl class] index:i] stringValue] ?: @""];
        [model2 addObject:[(XFControl *)[self controlOfClass:[XFOutputControl class] index:i + 3] stringValue] ?: @""];
    }
    XCTAssertTrue([model1 isEqualToArray:inline_] || [model1 isEqualToArray:src],
                  @"model1 must show the inline or the src data whole: %@", model1);
    XCTAssertTrue([model2 isEqualToArray:src] || [model2 isEqualToArray:resource],
                  @"model2 must load one linked source whole: %@", model2);
}

- (void)test_3_3_2_g_TwoTopLevelNodes
{
    [self loadTest:@"Chapt03/3.3/3.3.2/3.3.2.g.xhtml"];
    [self assertMessageOrFatal:@"xforms-link-exception"];
}

- (void)test_3_3_2_h_ExceptionCarriesResourceURI
{
    XFProcessor *p = [self loadTest:@"Chapt03/3.3/3.3.2/3.3.2.h.xhtml"];
    if (p == nil) {
        return;   // "or a fatal error"
    }
    // the exception fires at construct, before the host's message
    // handler exists — the dispatched event is the evidence
    [self assertSawEvent:@"xforms-link-exception"];
    // event('resource-uri') was copied into model2's /msg
    NSString *uri = [self stringForXPath:@"/msg" model:[self modelWithID:@"model2"]];
    XCTAssertTrue(uri.length > 0, @"resource-uri must reach the handler");
}

- (void)test_3_3_4_a_BindNodeset
{
    [self loadRequired:@"Chapt03/3.3/3.3.4/3.3.4.a.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"suzuka blue");
}

- (void)test_3_3_4_b_NestedBindCalculate
{
    // inner bind (no nodeset) calculates avg(../prices/price) → 2000
    [self loadRequired:@"Chapt03/3.3/3.3.4/3.3.4.b.xhtml"];
    NSString *v = [(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue];
    XCTAssertTrue([v hasPrefix:@"2000"], @"average should be 2000, got '%@'", v);
}

- (void)test_3_4_1_a_ExtensionElement
{
    [self loadRequired:@"Chapt03/3.4/3.4.1/3.4.1.a.xhtml"];
    XCTAssertEqualObjects([(XFControl *)[self controlOfClass:[XFOutputControl class] index:0] stringValue], @"blue");
}

@end
