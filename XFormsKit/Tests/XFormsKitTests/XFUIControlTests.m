#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFTriggerControl.h>
#import <XFormsKit/XFSubmitControl.h>
#import <XFormsKit/XFSecretControl.h>
#import <XFormsKit/XFTextareaControl.h>
#import <XFormsKit/XFSelectControl.h>
#import <XFormsKit/XFRangeControl.h>
#import <XFormsKit/XFLabelControl.h>
#import <XFormsKit/XFInputControl.h>
#import <XFormsKit/XFRepeat.h>
#import <XFormsKit/XFAbstractAction.h>
#import <XFormsKit/XFUploadControl.h>
#import <XFormsKit/XFNodeState.h>
#import <XFormsKit/XFXML.h>
#import <XFormsKit/XFDeferredUpdates.h>

@interface XFUIControlTests : XCTestCase
@end

@implementation XFUIControlTests

- (XFProcessor *)form:(NSString *)modelBody extra:(NSString *)extra error:(NSError **)error
{
    NSString *xml =
        [NSString stringWithFormat:
         @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
         @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
         @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
         @"  <xf:model id=\"m\">%@</xf:model>%@"
         @"</html>", modelBody, extra ?: @""];
    return [XFProcessor processorWithXMLString:xml error:error];
}

- (id)firstControlOfClass:(Class)cls in:(XFProcessor *)p
{
    for (XFControl *c in p.controls) {
        if ([c isKindOfClass:cls]) {
            return c;
        }
    }
    return nil;
}

- (void)testSecretAndTextarea
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><pw>secret</pw><bio>hi</bio></data></xf:instance>"
                      extra:
                      @"<xf:secret ref=\"pw\"><xf:label>PW</xf:label></xf:secret>"
                      @"<xf:textarea ref=\"bio\"><xf:label>Bio</xf:label></xf:textarea>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFSecretControl *secret = [self firstControlOfClass:[XFSecretControl class] in:p];
    XFTextareaControl *area = [self firstControlOfClass:[XFTextareaControl class] in:p];
    XCTAssertEqualObjects(secret.stringValue, @"secret");
    XCTAssertEqualObjects(area.stringValue, @"hi");
    XCTAssertTrue([p setValue:@"long text" ofControl:area error:&error]);
    XCTAssertEqualObjects(area.stringValue, @"long text");
}

- (void)testTriggerActivatesAction
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      extra:
                      @"<xf:trigger id=\"go\">"
                      @"  <xf:label>Go</xf:label>"
                      @"  <xf:setvalue ev:event=\"DOMActivate\" ref=\"n\" value=\"'Bob'\"/>"
                      @"</xf:trigger>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFTriggerControl *t = [self firstControlOfClass:[XFTriggerControl class] in:p];
    XCTAssertEqualObjects(t.label, @"Go");
    [p activateControl:t];
    NSXMLNode *n = [[[p.model defaultInstance] documentElement] elementsForName:@"n"].firstObject;
    XCTAssertEqualObjects([XFXML stringValueOfNode:n], @"Bob");
}

- (void)testSubmitSends
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"mem://x\" method=\"post\" replace=\"none\" serialization=\"none\"/>"
                      extra:
                      @"<xf:submit id=\"go\" submission=\"s\"><xf:label>Save</xf:label></xf:submit>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFSubmitControl *s = [self firstControlOfClass:[XFSubmitControl class] in:p];
    XCTAssertEqualObjects(s.submissionID, @"s");
    XFMapSubmissionTransport *map = [[XFMapSubmissionTransport alloc] init];
    [map setStatus:200 body:@"" forURL:@"mem://x"];
    p.model.transport = map;
    [s activate];
    XCTAssertEqualObjects(p.model.defaultSubmission.lastEventContext[@"resource-uri"], @"mem://x");
}

- (void)testSelect1StaticItems
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><color>red</color></data></xf:instance>"
                      extra:
                      @"<xf:select1 id=\"c\" ref=\"color\">"
                      @"  <xf:label>Color</xf:label>"
                      @"  <xf:item><xf:label>Red</xf:label><xf:value>red</xf:value></xf:item>"
                      @"  <xf:item><xf:label>Blue</xf:label><xf:value>blue</xf:value></xf:item>"
                      @"</xf:select1>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFSelectControl *sel = [self firstControlOfClass:[XFSelectControl class] in:p];
    XCTAssertFalse(sel.multiple);
    XCTAssertEqual(sel.items.count, (NSUInteger)2);
    XCTAssertTrue(sel.items[0].selected);
    XCTAssertTrue([sel selectValue:@"blue"]);
    XCTAssertEqualObjects(sel.stringValue, @"blue");
}

- (void)testSelectMultipleAndItemset
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <picked>a</picked>"
                      @"  <opt><n>A</n><v>a</v></opt>"
                      @"  <opt><n>B</n><v>b</v></opt>"
                      @"</data></xf:instance>"
                      extra:
                      @"<xf:select id=\"s\" ref=\"picked\">"
                      @"  <xf:label>P</xf:label>"
                      @"  <xf:itemset nodeset=\"../opt\">"
                      @"    <xf:label ref=\"n\"/>"
                      @"    <xf:value ref=\"v\"/>"
                      @"  </xf:itemset>"
                      @"</xf:select>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFSelectControl *sel = [self firstControlOfClass:[XFSelectControl class] in:p];
    XCTAssertTrue(sel.multiple);
    XCTAssertEqual(sel.items.count, (NSUInteger)2);
    XCTAssertEqualObjects(sel.items[0].label, @"A");
    XCTAssertTrue(sel.items[0].selected);
    XCTAssertTrue([sel toggleValue:@"b"]);
    XCTAssertTrue([sel.selectedValues containsObject:@"a"]);
    XCTAssertTrue([sel.selectedValues containsObject:@"b"]);
}

- (void)testChoicesGroupsAndCopy
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <choice/>"
                      @"  <colors>"
                      @"    <color><n>Red</n><hex>ff0000</hex></color>"
                      @"    <color><n>Blue</n><hex>0000ff</hex></color>"
                      @"  </colors>"
                      @"</data></xf:instance>"
                      extra:
                      @"<xf:select1 ref=\"choice\">"
                      @"  <xf:label>C</xf:label>"
                      @"  <xf:choices>"
                      @"    <xf:label>Primaries</xf:label>"
                      @"    <xf:itemset nodeset=\"../colors/color\">"
                      @"      <xf:label ref=\"n\"/>"
                      @"      <xf:copy ref=\".\"/>"
                      @"    </xf:itemset>"
                      @"  </xf:choices>"
                      @"  <xf:item><xf:label>None</xf:label><xf:value></xf:value></xf:item>"
                      @"</xf:select1>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFSelectControl *sel = [self firstControlOfClass:[XFSelectControl class] in:p];
    XCTAssertEqual(sel.items.count, (NSUInteger)3);
    XCTAssertEqualObjects(sel.items[0].groupLabel, @"Primaries");
    XCTAssertEqualObjects(sel.items[0].label, @"Red");
    XCTAssertTrue(sel.items[0].usesCopy);
    XCTAssertTrue([sel selectItem:sel.items[0]]);
    NSXMLElement *bound = (NSXMLElement *)sel.boundNode;
    XCTAssertEqual(bound.childCount, (NSUInteger)1);
    XCTAssertEqualObjects([bound.children[0] localName], @"color");
    XCTAssertTrue(sel.items[0].selected);
}

- (void)testRangeCommit
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>3</n></data></xf:instance>"
                      extra:
                      @"<xf:range id=\"r\" ref=\"n\" start=\"0\" end=\"10\" step=\"1\">"
                      @"  <xf:label>N</xf:label>"
                      @"</xf:range>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFRangeControl *r = [self firstControlOfClass:[XFRangeControl class] in:p];
    XCTAssertEqual(r.start, 0);
    XCTAssertEqual(r.end, 10);
    XCTAssertEqualWithAccuracy(r.numericValue, 3.0, 0.01);
    XCTAssertTrue([r commitNumericValue:8 error:&error]);
    XCTAssertEqualObjects(r.stringValue, @"8");
}

- (void)testStandaloneLabelLiteralAndBinding
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><title>Hello</title></data></xf:instance>"
                      extra:
                      @"<xf:label id=\"lit\">Welcome</xf:label>"
                      @"<xf:label id=\"ref\" ref=\"title\"/>"
                      @"<xf:label id=\"val\" value=\"concat('Hi ', title)\"/>"
                      @"<xf:input id=\"n\" ref=\"title\"><xf:label>Name</xf:label></xf:input>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);

    NSMutableArray *labels = [NSMutableArray array];
    for (XFControl *c in p.controls) {
        if ([c isKindOfClass:[XFLabelControl class]]) {
            [labels addObject:c];
        }
    }
    XCTAssertEqual(labels.count, (NSUInteger)3);
    XFLabelControl *lit = labels[0];
    XFLabelControl *ref = labels[1];
    XFLabelControl *val = labels[2];
    XCTAssertEqualObjects(lit.stringValue, @"Welcome");
    XCTAssertEqualObjects(ref.stringValue, @"Hello");
    XCTAssertEqualObjects(val.stringValue, @"Hi Hello");

    XFInputControl *input = [self firstControlOfClass:[XFInputControl class] in:p];
    XCTAssertEqualObjects(input.label, @"Name");
}

- (void)testDateInputFromBindType
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <d>2020-01-15</d>"
                      @"  <t>08:30:00</t>"
                      @"  <dt>2020-01-15T08:30:00</dt>"
                      @"</data></xf:instance>"
                      @"<xf:bind nodeset=\"d\" type=\"xsd:date\"/>"
                      @"<xf:bind nodeset=\"t\" type=\"xsd:time\"/>"
                      @"<xf:bind nodeset=\"dt\" type=\"xsd:dateTime\"/>"
                      extra:
                      @"<xf:input id=\"d\" ref=\"d\"><xf:label>D</xf:label></xf:input>"
                      @"<xf:input id=\"t\" ref=\"t\"><xf:label>T</xf:label></xf:input>"
                      @"<xf:input id=\"dt\" ref=\"dt\"><xf:label>DT</xf:label></xf:input>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSArray *inputs = p.inputControls;
    XCTAssertEqual(inputs.count, (NSUInteger)3);
    XFInputControl *date = inputs[0];
    XFInputControl *time = inputs[1];
    XFInputControl *dateTime = inputs[2];
    XCTAssertEqual(date.resolvedDateType, XFDateTypeDate);
    XCTAssertEqual(time.resolvedDateType, XFDateTypeTime);
    XCTAssertEqual(dateTime.resolvedDateType, XFDateTypeDateTime);
    XCTAssertNotNil(date.dateValue);
    XCTAssertEqualObjects([XFInputControl formatDate:date.dateValue type:XFDateTypeDate], @"2020-01-15");
    XCTAssertTrue([date commitDateValue:date.dateValue error:&error]);
    XCTAssertEqualObjects(date.stringValue, @"2020-01-15");

    NSDate *next = [XFInputControl parseDateString:@"2021-12-31" type:XFDateTypeDate];
    XCTAssertTrue([date commitDateValue:next error:&error]);
    XCTAssertEqualObjects(date.stringValue, @"2021-12-31");
}

- (void)testDateInputFromAppearance
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><d>2019-06-01</d></data></xf:instance>"
                      extra:
                      @"<xf:input id=\"d\" ref=\"d\" appearance=\"date\"><xf:label>D</xf:label></xf:input>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFInputControl *date = [self firstControlOfClass:[XFInputControl class] in:p];
    XCTAssertEqual(date.resolvedDateType, XFDateTypeDate);
}

- (void)testDateParseAndFormatRoundTrip
{
    NSDate *date = [XFInputControl parseDateString:@"2024-03-09" type:XFDateTypeDate];
    XCTAssertNotNil(date);
    XCTAssertEqualObjects([XFInputControl formatDate:date type:XFDateTypeDate], @"2024-03-09");
    NSDate *time = [XFInputControl parseDateString:@"13:05:09" type:XFDateTypeTime];
    XCTAssertEqualObjects([XFInputControl formatDate:time type:XFDateTypeTime], @"13:05:09");
    NSDate *dt = [XFInputControl parseDateString:@"2024-03-09T13:05:09" type:XFDateTypeDateTime];
    XCTAssertEqualObjects([XFInputControl formatDate:dt type:XFDateTypeDateTime], @"2024-03-09T13:05:09");
    XCTAssertEqual([XFInputControl dateTypeFromTypeName:@"xs:date"], XFDateTypeDate);
    XCTAssertEqual([XFInputControl dateTypeFromTypeName:@"xsd:dateTime"], XFDateTypeDateTime);
    XCTAssertEqual([XFInputControl dateTypeFromTypeName:@"time"], XFDateTypeTime);
}

- (void)testUploadEncodesBase64AndFilename
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <file/><name/><type/>"
                      @"</data></xf:instance>"
                      @"<xf:bind ref=\"file\" type=\"xsd:base64Binary\"/>"
                      extra:
                      @"<xf:upload ref=\"file\">"
                      @"  <xf:label>File</xf:label>"
                      @"  <xf:filename ref=\"../name\"/>"
                      @"  <xf:mediatype ref=\"../type\"/>"
                      @"</xf:upload>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFUploadControl *up = [self firstControlOfClass:[XFUploadControl class] in:p];
    XCTAssertNotNil(up);
    NSData *bytes = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([up commitFileData:bytes fileName:@"hello.txt" mediaType:@"text/plain" error:&error], @"%@", error);
    XCTAssertEqualObjects(up.stringValue, [bytes base64EncodedStringWithOptions:0]);
    NSXMLElement *root = [[p.model defaultInstance] documentElement];
    XCTAssertEqualObjects([XFXML stringValueOfNode:[root elementsForName:@"name"].firstObject], @"hello.txt");
    XCTAssertEqualObjects([XFXML stringValueOfNode:[root elementsForName:@"type"].firstObject], @"text/plain");
    XFNodeState *st = [XFNodeState existingStateOnNode:up.boundNode];
    XCTAssertEqualObjects(st.fileName, @"hello.txt");
    XCTAssertEqual(st.fileData.length, bytes.length);
}

- (void)testHintHelpAlertAndMIPEvents
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n></n></data></xf:instance>"
                      @"<xf:bind ref=\"n\" required=\"true()\" constraint=\"string-length(.) &gt; 1\"/>"
                      extra:
                      @"<xf:input id=\"n\" ref=\"n\">"
                      @"  <xf:label>N</xf:label>"
                      @"  <xf:hint>A hint</xf:hint>"
                      @"  <xf:help>Help text</xf:help>"
                      @"  <xf:alert>Need two chars</xf:alert>"
                      @"</xf:input>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFInputControl *input = [self firstControlOfClass:[XFInputControl class] in:p];
    XCTAssertEqualObjects(input.hint, @"A hint");
    XCTAssertEqualObjects(input.help, @"Help text");
    XCTAssertEqualObjects(input.alert, @"Need two chars");
    XCTAssertTrue(input.required);
    XCTAssertFalse(input.valid);
    XCTAssertTrue([input.mipEvents containsObject:@"xforms-required"]);
    XCTAssertTrue([input.mipEvents containsObject:@"xforms-invalid"]);
    NSUInteger before = [XFDeferredUpdates sharedUpdates].messages.count;
    [input showHelp];
    XCTAssertGreaterThan([XFDeferredUpdates sharedUpdates].messages.count, before);
    XCTAssertTrue([p setValue:@"ab" ofControl:input error:&error], @"%@", error);
    XCTAssertTrue(input.valid);
    XCTAssertTrue([input.mipEvents containsObject:@"xforms-valid"]);
}

- (void)testOutputImageMediatype
{
    NSError *error = nil;
    NSString *b64 = @"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
    XFProcessor *p = [self form:
                      [NSString stringWithFormat:
                       @"<xf:instance><data xmlns=\"\"><img>%@</img></data></xf:instance>", b64]
                      extra:
                      @"<xf:output ref=\"img\" mediatype=\"image/png\"><xf:label>Pic</xf:label></xf:output>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFOutputControl *out = [self firstControlOfClass:[XFOutputControl class] in:p];
    XCTAssertTrue(out.displaysImage);
    XCTAssertFalse(out.displaysHTML);
    XCTAssertGreaterThan(out.imageData.length, (NSUInteger)0);
}

- (void)testSelectChangeRecalculatesDependentMIPs
{
    // Samples/readonly.xhtml: name is readonly while lock = 'true'. Picking
    // "No" in the select1 must run the deferred-update cycle so the bind on
    // name is recalculated and the input becomes writable.
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><lock>true</lock><name>Ada</name></data></xf:instance>"
                      @"<xf:bind nodeset=\"name\" readonly=\"../lock = 'true'\"/>"
                      extra:
                      @"<xf:select1 id=\"s\" ref=\"lock\">"
                      @"  <xf:item><xf:label>Yes</xf:label><xf:value>true</xf:value></xf:item>"
                      @"  <xf:item><xf:label>No</xf:label><xf:value>false</xf:value></xf:item>"
                      @"</xf:select1>"
                      @"<xf:input id=\"n\" ref=\"name\"><xf:label>Name</xf:label></xf:input>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFSelectControl *sel = [self firstControlOfClass:[XFSelectControl class] in:p];
    XFInputControl *name = [self firstControlOfClass:[XFInputControl class] in:p];
    XCTAssertTrue(name.readonly);

    XCTAssertTrue([sel selectValue:@"false"]);
    [p controlDidChangeValue:sel];
    XCTAssertEqualObjects([XFXML stringValueOfNode:sel.boundNode], @"false");
    XCTAssertFalse(name.readonly, @"readonly MIP must be recalculated after the select change");

    XCTAssertTrue([sel selectValue:@"true"]);
    [p controlDidChangeValue:sel];
    XCTAssertTrue(name.readonly);
}

- (void)testLabelsAreBoundAndFollowTheInstance // G-23
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><lbl>First</lbl><n>Ada</n><g>Grp</g><o>x</o></data></xf:instance>"
                      @"<xf:setvalue ev:event=\"poke\" ref=\"lbl\" value=\"'Given'\"/>"
                      @"<xf:setvalue ev:event=\"poke\" ref=\"n\" value=\"'Bob'\"/>"
                      @"<xf:setvalue ev:event=\"poke\" ref=\"g\" value=\"'Group'\"/>"
                      extra:
                      @"<xf:input id=\"i1\" ref=\"n\"><xf:label ref=\"../lbl\"/></xf:input>"
                      @"<xf:input id=\"i2\" ref=\"n\"><xf:label>Name (<b><xf:output ref=\".\"/></b>)</xf:label></xf:input>"
                      @"<xf:output id=\"o1\" value=\"'v'\"><xf:label value=\"concat('L', n)\"/></xf:output>"
                      @"<xf:select1 ref=\"o\"><xf:label>S</xf:label>"
                      @"  <xf:choices><xf:label ref=\"../g\"/><xf:item><xf:label>X</xf:label><xf:value>x</xf:value></xf:item></xf:choices>"
                      @"</xf:select1>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSArray<XFInputControl *> *ins = p.inputControls;
    XCTAssertEqualObjects(ins[0].label, @"First");
    XCTAssertEqualObjects(ins[1].label, @"Name (Ada)");
    XCTAssertEqualObjects(p.outputControls.firstObject.label, @"LAda");
    XFSelectControl *sel = nil;
    for (XFControl *c in p.controls) {
        if ([c isKindOfClass:[XFSelectControl class]]) { sel = (XFSelectControl *)c; }
    }
    XCTAssertEqualObjects(sel.items.firstObject.groupLabel, @"Grp");
    [XFXMLEvents dispatch:p.model name:@"poke"];
    XCTAssertEqualObjects(ins[0].label, @"Given");
    XCTAssertEqualObjects(ins[1].label, @"Name (Bob)");
    XCTAssertEqualObjects(p.outputControls.firstObject.label, @"LBob");
    XCTAssertEqualObjects(sel.items.firstObject.groupLabel, @"Group");
}

- (void)testSetfocusMovesFocusRepeatIndexAndDispatchesFocusEvents // G-24
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>a</n><item>1</item><item>2</item></data></xf:instance>"
                      @"<xf:setfocus ev:event=\"go1\" control=\"in\"/>"
                      @"<xf:setfocus ev:event=\"go2\"><xf:control value=\"'top'\"/></xf:setfocus>"
                      extra:
                      @"<xf:input id=\"top\" ref=\"n\"><xf:label>N</xf:label>"
                      @"  <xf:action id=\"top-in\" ev:event=\"DOMFocusIn\"/>"
                      @"</xf:input>"
                      @"<xf:repeat id=\"r\" nodeset=\"item\">"
                      @"  <xf:input id=\"in\" ref=\".\"><xf:label>I</xf:label>"
                      @"    <xf:action id=\"in-in\" ev:event=\"DOMFocusIn\"/>"
                      @"    <xf:action id=\"in-out\" ev:event=\"DOMFocusOut\"/>"
                      @"  </xf:input>"
                      @"</xf:repeat>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFRepeat *r = p.repeats.firstObject;
    XCTAssertEqual(r.index, (NSUInteger)1);
    __block XFControl *requested = nil;
    p.focusRequestHandler = ^(XFControl *c) { requested = c; };

    // focus the input of the second item directly (as a widget would)
    XFControl *second = r.items[1].controls.firstObject;
    [p focusControl:second fromUI:YES];
    XCTAssertEqual(p.focusedControl, second);
    XCTAssertTrue(second.focused);
    XCTAssertEqual(r.index, (NSUInteger)2);
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"in-in"] invocationCount], (NSInteger)1);
    XCTAssertNil(requested);

    // xf:setfocus → xforms-focus → focus: previous control gets DOMFocusOut
    [XFXMLEvents dispatch:p.model name:@"go2"];
    XCTAssertEqual(p.focusedControl, p.inputControls.firstObject);
    XCTAssertEqual(requested, p.inputControls.firstObject);
    XCTAssertFalse(second.focused);
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"in-out"] invocationCount], (NSInteger)1);
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"top-in"] invocationCount], (NSInteger)1);

    // an output never takes the focus
    [p blurFocusedControl];
    XCTAssertNil(p.focusedControl);
}

- (void)testSelectRangeEventsItemTargetsAndRelevantItemset // G-25
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><v>a</v><opt>a</opt><opt>b</opt><opt>hidden</opt><show>true</show></data></xf:instance>"
                      @"<xf:bind nodeset=\"opt[. = 'hidden']\" relevant=\"../show = 'true'\"/>"
                      @"<xf:setvalue ev:event=\"bogus\" ref=\"v\" value=\"'zzz'\"/>"
                      @"<xf:setvalue ev:event=\"fix\" ref=\"v\" value=\"'b'\"/>"
                      @"<xf:setvalue ev:event=\"hide\" ref=\"show\" value=\"'false'\"/>"
                      extra:
                      @"<xf:select1 id=\"s\" ref=\"v\"><xf:label>S</xf:label>"
                      @"  <xf:action id=\"oor\" ev:event=\"xforms-out-of-range\"/>"
                      @"  <xf:action id=\"inr\" ev:event=\"xforms-in-range\"/>"
                      @"  <xf:item id=\"ia\"><xf:label>A</xf:label><xf:value>a</xf:value>"
                      @"    <xf:action id=\"a-desel\" ev:event=\"xforms-deselect\"/></xf:item>"
                      @"  <xf:item id=\"ib\"><xf:label>B</xf:label><xf:value>b</xf:value>"
                      @"    <xf:action id=\"b-sel\" ev:event=\"xforms-select\"/></xf:item>"
                      @"  <xf:itemset nodeset=\"../opt\"><xf:label ref=\".\"/><xf:value ref=\".\"/></xf:itemset>"
                      @"</xf:select1>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFSelectControl *sel = nil;
    for (XFControl *c in p.controls) {
        if ([c isKindOfClass:[XFSelectControl class]]) { sel = (XFSelectControl *)c; }
    }
    XCTAssertEqual(sel.items.count, (NSUInteger)5, @"items=%@", [sel.items valueForKey:@"value"]);
    XCTAssertFalse(sel.outOfRange);

    [XFXMLEvents dispatch:p.model name:@"bogus"];
    XCTAssertTrue(sel.outOfRange);
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"oor"] invocationCount], (NSInteger)1);
    [XFXMLEvents dispatch:p.model name:@"fix"];
    XCTAssertFalse(sel.outOfRange);
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"inr"] invocationCount], (NSInteger)1);

    // UI selection: xforms-select on the picked xf:item, xforms-deselect on
    // the previous one (handlers sit on the items, not on the select)
    XCTAssertTrue([sel selectValue:@"a"]);
    [p controlDidChangeValue:sel];
    XCTAssertTrue([sel selectValue:@"b"]);
    [p controlDidChangeValue:sel];
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"b-sel"] invocationCount], (NSInteger)1);
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"a-desel"] invocationCount], (NSInteger)1);

    // itemset drops non-relevant nodes
    [XFXMLEvents dispatch:p.model name:@"hide"];
    XCTAssertEqual(sel.items.count, (NSUInteger)4);
}

@end
