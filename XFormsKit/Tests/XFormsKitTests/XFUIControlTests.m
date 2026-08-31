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

- (void)testInputModeHostAttributesAndUploadMediaTypes // G-41, G-46, G-63
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>x</n><d/><f/><t/></data></xf:instance>"
                      @"<xf:bind nodeset=\"f\" type=\"xsd:base64Binary\"/>"
                      extra:
                      @"<xf:input ref=\"n\" inputmode=\"upperCase\" navindex=\"2\" accesskey=\"n\" placeholder=\"Name\"><xf:label>N</xf:label>"
                      @"  <xf:help href=\"help.html\">H</xf:help></xf:input>"
                      @"<xf:input ref=\"d\" inputmode=\"digits\"><xf:label>D</xf:label></xf:input>"
                      @"<xf:textarea ref=\"t\" rows=\"6\" cols=\"40\"><xf:label>T</xf:label></xf:textarea>"
                      @"<xf:upload ref=\"f\" mediatype=\"image/*\"><xf:label>F</xf:label>"
                      @"  <xf:action id=\"up-done\" ev:event=\"xforms-upload-done\"/>"
                      @"  <xf:action id=\"up-err\" ev:event=\"xforms-upload-error\"/></xf:upload>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSArray<XFInputControl *> *ins = p.inputControls;
    XCTAssertEqual(ins[0].navindex, (NSInteger)2);
    XCTAssertEqualObjects(ins[0].accesskey, @"n");
    XCTAssertEqualObjects(ins[0].placeholder, @"Name");
    XCTAssertEqualObjects(ins[0].helpHref, @"help.html");
    XCTAssertTrue([p setValue:@"ada" ofControl:ins[0] error:NULL]);
    XCTAssertEqualObjects(ins[0].stringValue, @"ADA");
    XCTAssertTrue([p setValue:@"a1b2" ofControl:ins[1] error:NULL]);
    XCTAssertEqualObjects(ins[1].stringValue, @"12");
    XFControl *ta = nil; XFUploadControl *up = nil;
    for (XFControl *c in p.controls) {
        if ([c isKindOfClass:[XFTextareaControl class]]) ta = c;
        if ([c isKindOfClass:[XFUploadControl class]]) up = (XFUploadControl *)c;
    }
    XCTAssertEqual(ta.rows, (NSInteger)6);
    XCTAssertEqual(ta.cols, (NSInteger)40);
    XCTAssertEqualObjects(up.acceptedMediaTypes, @[ @"image/*" ]);
    XCTAssertTrue([up acceptsMediaType:@"image/png"]);
    XCTAssertFalse([up acceptsMediaType:@"application/pdf"]);
    NSData *bytes = [@"XYZ" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse([up commitFileData:bytes fileName:@"a.pdf" mediaType:@"application/pdf" error:NULL]);
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"up-err"] invocationCount], (NSInteger)1);
    XCTAssertTrue([up commitFileData:bytes fileName:@"a.png" mediaType:@"image/png" error:&error], @"%@", error);
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"up-done"] invocationCount], (NSInteger)1);
}

- (void)testRichTextConverterRoundTrip // rich textarea (TinyMCE sample)
{
    // fonts need the AppKit backend
    [NSApplication sharedApplication];
    NSArray<NSString *> *stable = @[
        @"<p>Paragraph <em>number one</em></p>",
        @"<h1>Title</h1><p>Body with <strong><em>both</em></strong> and <u>lines</u><br/>second line</p>",
        @"<ul><li>one</li><li><strong>two</strong></li></ul><p>after</p>",
        @"<ol><li>first</li><li>second</li></ol>",
        @"<p>a &amp; b &lt; c</p>",
        @"",
    ];
    for (NSString *html in stable) {
        NSAttributedString *rich = [XFRichText attributedStringFromHTML:html baseFont:nil];
        XCTAssertEqualObjects([XFRichText htmlFromAttributedString:rich], html);
    }
    // canonicalisation: b→strong, i→em, div→p, bare fragments wrapped
    NSDictionary *canonical = @{
        @"<div>A <b>bold</b> and <i>ital</i></div>": @"<p>A <strong>bold</strong> and <em>ital</em></p>",
        @"Hello <strong>World</strong>!": @"<p>Hello <strong>World</strong>!</p>",
        @"just text": @"<p>just text</p>",
    };
    for (NSString *html in canonical) {
        NSAttributedString *rich = [XFRichText attributedStringFromHTML:html baseFont:nil];
        XCTAssertEqualObjects([XFRichText htmlFromAttributedString:rich], canonical[html]);
    }
    // not well-formed → plain text, fully escaped on the way back
    NSAttributedString *broken = [XFRichText attributedStringFromHTML:@"<p>broken <em>markup</p>" baseFont:nil];
    XCTAssertEqualObjects([broken string], @"<p>broken <em>markup</p>");
    XCTAssertEqualObjects([XFRichText htmlFromAttributedString:broken],
                          @"<p>&lt;p&gt;broken &lt;em&gt;markup&lt;/p&gt;</p>");
    // display text: bullets / numbering / line separator
    NSAttributedString *list = [XFRichText attributedStringFromHTML:@"<ol><li>a</li><li>b</li></ol>" baseFont:nil];
    XCTAssertEqualObjects([list string], @"1. a\n2. b");
    NSAttributedString *br = [XFRichText attributedStringFromHTML:@"<p>a<br/>b</p>" baseFont:nil];
    XCTAssertEqualObjects([br string], ([NSString stringWithFormat:@"a%Cb", (unichar)0x2028]));
    // markers drive the serialisation (font-independent)
    NSRange r;
    NSAttributedString *bold = [XFRichText attributedStringFromHTML:@"<p><strong>x</strong></p>" baseFont:nil];
    XCTAssertTrue([[bold attribute:XFRichBoldAttributeName atIndex:0 effectiveRange:&r] boolValue]);
}

// Hints and alerts on the form (XSLTForms icones.css: hint icon always,
// alert icon only while .xforms-invalid; minimal hint = title/placeholder).
- (void)testValidationBadgesAndMinimalHintPlaceholder
{
    [NSApplication sharedApplication];
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\"><age>5</age><name/></data></xf:instance>"
        @"<xf:bind nodeset=\"age\" constraint=\". &gt;= 18\"/>"
        extra:
        @"<xf:input ref=\"age\"><xf:label>Age</xf:label>"
        @"<xf:hint>18 or more</xf:hint>"
        @"<xf:alert>You must be at least 18</xf:alert></xf:input>"
        @"<xf:input ref=\"name\"><xf:label>Name</xf:label>"
        @"<xf:hint appearance=\"minimal\">Your full name</xf:hint></xf:input>"
        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFInputControl *age = [self firstControlOfClass:[XFInputControl class] in:p];
    XCTAssertFalse(age.valid);
    XCTAssertFalse(age.hintMinimal);
    XFFormView *fv = [[XFFormView alloc] initWithProcessor:p];

    NSView * (^badgeWithTip)(NSString *) = ^NSView *(NSString *tip) {
        for (NSView *v in [fv subviews]) {
            if ([NSStringFromClass([v class]) isEqualToString:@"XFBadgeView"]
                && [[v valueForKey:@"text"] isEqualToString:tip]) {
                return v;
            }
        }
        return nil;
    };
    // age is invalid: visible hint badge and visible alert badge
    NSView *hintBadge = badgeWithTip(@"18 or more");
    NSView *alertBadge = badgeWithTip(@"You must be at least 18");
    XCTAssertNotNil(hintBadge);
    XCTAssertNotNil(alertBadge);
    XCTAssertFalse([hintBadge isHidden]);
    XCTAssertFalse([alertBadge isHidden]);

    // the minimal hint becomes the name field's placeholder, not a badge
    XCTAssertNil(badgeWithTip(@"Your full name"));
    BOOL foundPlaceholder = NO;
    for (NSView *v in [fv subviews]) {
        if ([v isKindOfClass:[NSTextField class]] && [(NSTextField *)v isEditable]
            && [[(NSTextFieldCell *)[(NSTextField *)v cell] placeholderString]
                   isEqualToString:@"Your full name"]) {
            foundPlaceholder = YES;
        }
    }
    XCTAssertTrue(foundPlaceholder, @"minimal hint must map to placeholderString");

    // fixing the value hides the alert badge but keeps the hint badge
    XCTAssertTrue([p setValue:@"21" ofControl:age error:&error], @"%@", error);
    [fv reloadFromProcessor];
    XCTAssertTrue(age.valid);
    hintBadge = badgeWithTip(@"18 or more");
    alertBadge = badgeWithTip(@"You must be at least 18");
    XCTAssertNotNil(hintBadge);
    XCTAssertFalse([hintBadge isHidden]);
    XCTAssertNotNil(alertBadge, @"the slot stays reserved while an xf:alert exists");
    XCTAssertTrue([alertBadge isHidden]);
}

// Attribute value templates (avtparser.xsl / XsltForms_avt): {expr}
// segments concatenated with literals, {{ }} escapes, unmatched braces
// staying literal, and repeat-style contexts (position()).
- (void)testAVTTemplates
{
    XCTAssertFalse([XFAVT stringIsTemplate:@"plain"]);
    XCTAssertFalse([XFAVT stringIsTemplate:@"esc {{only}} here"]);
    XCTAssertFalse([XFAVT stringIsTemplate:@"open { but never closed"]);
    XCTAssertTrue([XFAVT stringIsTemplate:@"a{1 + 1}b"]);

    NSError *error = nil;
    XFAVT *avt = [XFAVT avtWithString:@"x{1 + 1}y{{z}}{'q'}" element:nil error:&error];
    XCTAssertNotNil(avt, @"%@", error);
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:nil];
    XCTAssertEqualObjects([avt evaluateInContext:ctx error:NULL], @"x2y{z}q");

    // a string literal inside the expression may hold quotes and braces
    avt = [XFAVT avtWithString:@"fill:{concat('#', 'AB', \"'\")}" element:nil error:&error];
    XCTAssertNotNil(avt, @"%@", error);
    XCTAssertEqualObjects([avt evaluateInContext:ctx error:NULL], @"fill:#AB'");

    // an expression that does not compile refuses the whole template
    XCTAssertNil([XFAVT avtWithString:@"{1 +}" element:nil error:&error]);
    XCTAssertNotNil(error);

    // context: node values and position()
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:
        @"<r><i>7</i><i>9</i></r>" options:0 error:NULL];
    NSArray *items = [[doc rootElement] children];
    XFExprContext *itemCtx = [[[XFExprContext alloc] initWithNode:[doc rootElement]]
        cloneWithNode:items[1] position:2 nodeList:items];
    XCTAssertEqualObjects([XFAVT resolveString:@"v{.}p{position()}" element:nil
                                     inContext:itemCtx], @"v9p2");
}

// SVG parsing primitives: path data (arcs included), transform-list
// order, colors, style declarations, unit lengths.
- (void)testSVGParsingPrimitives
{
    [NSApplication sharedApplication];
    // a unit square, closed
    NSBezierPath *square = [XFSVGDocument bezierPathWithSVGPathData:@"M 0 0 L 10 0 L 10 10 L 0 10 Z"];
    XCTAssertNotNil(square);
    NSRect b = [square bounds];
    XCTAssertEqualWithAccuracy(NSWidth(b), 10.0, 0.001);
    XCTAssertEqualWithAccuracy(NSHeight(b), 10.0, 0.001);

    // quarter-circle arc from (100,0) to (0,100) sweeping through (~70.7,~70.7)
    NSBezierPath *arc = [XFSVGDocument bezierPathWithSVGPathData:@"M 100 0 A 100 100 0 0 1 0 100"];
    NSRect ab = [arc bounds];
    XCTAssertTrue(NSMaxX(ab) > 99 && NSMaxY(ab) > 99, @"%@", NSStringFromRect(ab));
    XCTAssertEqualWithAccuracy([arc currentPoint].x, 0.0, 0.01);
    XCTAssertEqualWithAccuracy([arc currentPoint].y, 100.0, 0.01);

    // relative commands and implicit linetos after moveto
    NSBezierPath *rel = [XFSVGDocument bezierPathWithSVGPathData:@"m 5 5 10 0 l 0 10"];
    XCTAssertEqualWithAccuracy([rel currentPoint].x, 15.0, 0.001);
    XCTAssertEqualWithAccuracy([rel currentPoint].y, 15.0, 0.001);

    // transform lists apply left to right with the rightmost hitting the
    // point first: translate(10,0) rotate(90) maps (1,0) to (10,1)
    NSAffineTransform *t = [XFSVGDocument transformWithSVGString:@"translate(10,0) rotate(90)"];
    NSPoint p = [t transformPoint:NSMakePoint(1, 0)];
    XCTAssertEqualWithAccuracy(p.x, 10.0, 0.001);
    XCTAssertEqualWithAccuracy(p.y, 1.0, 0.001);

    NSColor *hex = [[XFSVGDocument colorWithSVGString:@"#0685C6"]
        colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    XCTAssertEqualWithAccuracy([hex redComponent], 0x06 / 255.0, 0.005);
    XCTAssertEqualWithAccuracy([hex blueComponent], 0xC6 / 255.0, 0.005);
    XCTAssertNotNil([XFSVGDocument colorWithSVGString:@"#ab0"]);
    XCTAssertNotNil([XFSVGDocument colorWithSVGString:@"black"]);
    XCTAssertNil([XFSVGDocument colorWithSVGString:@"none"]);
    XCTAssertNotNil([XFSVGDocument colorWithSVGString:@"url(#pattern)"],
                    @"paint servers degrade to a neutral wash, not to nothing");

    NSDictionary *style = [XFSVGDocument declarationsWithSVGStyle:
        @"fill:{#404040}; stroke : black ;stroke-width:1;"];
    XCTAssertEqualObjects(style[@"stroke"], @"black");
    XCTAssertEqualObjects(style[@"stroke-width"], @"1");

    XCTAssertEqualWithAccuracy([XFSVGDocument lengthWithSVGString:@"4.1mm" fallback:0],
                               4.1 * 96.0 / 25.4, 0.01);
    XCTAssertEqualWithAccuracy([XFSVGDocument lengthWithSVGString:@"12" fallback:0], 12.0, 0.001);
    XCTAssertEqualWithAccuracy([XFSVGDocument lengthWithSVGString:nil fallback:7], 7.0, 0.001);
}

// The render tree over the host DOM: AVTs resolved per repeat item
// (position() included), text gathered from xf:output, sizes from the
// svg element — the piechart/flags shape of dynamic SVG.
- (void)testSVGRenderTreeWithRepeatAndAVT
{
    [NSApplication sharedApplication];
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\">"
        @"<item name=\"A\" code=\"#101010\">4</item>"
        @"<item name=\"B\" code=\"#202020\">6</item>"
        @"</data></xf:instance>"
        extra:
        @"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"100\">"
        @"<xf:repeat nodeset=\"item\">"
        @"<rect x=\"0\" y=\"{position() * 20}\" width=\"{. * 10}\" height=\"10\" fill=\"{@code}\"/>"
        @"<text x=\"5\" y=\"{position() * 20}\"><xf:output value=\"concat(@name, ': ', .)\"/></text>"
        @"</xf:repeat>"
        @"</svg>"
        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFFormView *fv = [[XFFormView alloc] initWithProcessor:p];
    XFSVGView *svg = nil;
    for (NSView *sub in [fv subviews]) {
        if ([sub isKindOfClass:[XFSVGView class]]) {
            svg = (XFSVGView *)sub;
        }
    }
    XCTAssertNotNil(svg, @"the placeholder era is over");
    XCTAssertEqualWithAccuracy([svg frame].size.width, 200.0, 0.001);
    XCTAssertEqualWithAccuracy([svg frame].size.height, 100.0, 0.001);

    XFSVGNode *root = svg.svgDocument.root;
    NSMutableArray *rects = [NSMutableArray array];
    NSMutableArray *texts = [NSMutableArray array];
    for (XFSVGNode *child in root.children) {
        if ([child.tag isEqualToString:@"rect"]) {
            [rects addObject:child];
        } else if ([child.tag isEqualToString:@"text"]) {
            [texts addObject:child];
        }
    }
    XCTAssertEqual(rects.count, (NSUInteger)2, @"one per repeat item");
    XCTAssertEqualObjects(((XFSVGNode *)rects[0]).attributes[@"fill"], @"#101010");
    XCTAssertEqualObjects(((XFSVGNode *)rects[1]).attributes[@"fill"], @"#202020");
    XCTAssertEqualObjects(((XFSVGNode *)rects[0]).attributes[@"y"], @"20", @"position() carries");
    XCTAssertEqualObjects(((XFSVGNode *)rects[1]).attributes[@"y"], @"40");
    XCTAssertEqualObjects(((XFSVGNode *)rects[1]).attributes[@"width"], @"60");
    XCTAssertEqual(texts.count, (NSUInteger)2);
    XCTAssertEqualObjects(((XFSVGNode *)texts[0]).text, @"A: 4", @"output values gathered");
    XCTAssertEqualObjects(((XFSVGNode *)texts[1]).text, @"B: 6");

    // refresh keeps the tree live: change a value, rebuild, re-read
    NSXMLElement *data = [[p defaultInstance] documentElement];
    NSXMLElement *first = (NSXMLElement *)[data childAtIndex:0];
    [first setStringValue:@"9"];
    [svg rebuild];
    for (XFSVGNode *child in svg.svgDocument.root.children) {
        if ([child.tag isEqualToString:@"rect"]) {
            XCTAssertEqualObjects(child.attributes[@"width"], @"90");
            break;
        }
    }
}

// Paint servers (linearGradient / radialGradient / pattern), defs / use,
// and the render-tree hit testing the designer's overlay picks through.
- (void)testSVGPaintServersUseAndHitTesting
{
    [NSApplication sharedApplication];
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\"><v>1</v></data></xf:instance>"
        extra:
        @"<svg xmlns=\"http://www.w3.org/2000/svg\""
        @"     xmlns:xlink=\"http://www.w3.org/1999/xlink\""
        @"     width=\"200\" height=\"200\">"
        @"<defs>"
        @"<linearGradient id=\"grad\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"0\">"
        @"<stop offset=\"0\" stop-color=\"#FF0000\"/>"
        @"<stop offset=\"100%\" stop-color=\"#0000FF\" stop-opacity=\"0.5\"/>"
        @"</linearGradient>"
        @"<pattern id=\"pat\" x=\"0\" y=\"0\" width=\"10\" height=\"10\" patternUnits=\"userSpaceOnUse\">"
        @"<rect x=\"0\" y=\"0\" width=\"5\" height=\"10\" fill=\"#CCCCCC\"/>"
        @"</pattern>"
        @"<circle id=\"proto\" cx=\"5\" cy=\"5\" r=\"5\" fill=\"green\"/>"
        @"</defs>"
        @"<rect id=\"gr\" x=\"10\" y=\"10\" width=\"60\" height=\"30\" fill=\"url(#grad)\"/>"
        @"<rect id=\"pr\" x=\"10\" y=\"60\" width=\"60\" height=\"30\" fill=\"url(#pat)\"/>"
        @"<use xlink:href=\"#proto\" x=\"120\" y=\"120\"/>"
        @"<g transform=\"translate(100,10)\"><rect id=\"tr\" x=\"0\" y=\"0\" width=\"20\" height=\"20\" fill=\"black\"/></g>"
        @"</svg>"
        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFFormView *fv = [[XFFormView alloc] initWithProcessor:p];
    XFSVGView *svg = nil;
    for (NSView *sub in [fv subviews]) {
        if ([sub isKindOfClass:[XFSVGView class]]) {
            svg = (XFSVGView *)sub;
        }
    }
    XCTAssertNotNil(svg);
    XFSVGDocument *doc = svg.svgDocument;

    // definitions registered, not painted in place
    XCTAssertNotNil([doc nodeForIdentifier:@"grad"]);
    XCTAssertNotNil([doc nodeForIdentifier:@"pat"]);
    XCTAssertNotNil([doc nodeForIdentifier:@"proto"]);
    for (XFSVGNode *child in doc.root.children) {
        XCTAssertFalse([child.tag isEqualToString:@"defs"]);
        XCTAssertFalse([child.tag isEqualToString:@"lineargradient"]);
    }
    XCTAssertEqual([[doc nodeForIdentifier:@"grad"] children].count, (NSUInteger)2,
                   @"gradient keeps its stops");

    // hit testing: shape centers land on their host elements
    NSXMLElement * (^byID)(NSString *) = ^NSXMLElement *(NSString *ident) {
        return [XFXML elementWithID:ident inNode:p.hostDocument];
    };
    XCTAssertEqual([[doc nodeAtPoint:NSMakePoint(40, 25)] element], byID(@"gr"));
    XCTAssertEqual([[doc nodeAtPoint:NSMakePoint(40, 75)] element], byID(@"pr"));
    // a transformed shape hits through its group's translate
    XCTAssertEqual([[doc nodeAtPoint:NSMakePoint(110, 20)] element], byID(@"tr"));
    // content reached through <use> reports the use element
    XFSVGNode *used = [doc nodeAtPoint:NSMakePoint(125, 125)];
    XCTAssertNotNil(used);
    XCTAssertEqualObjects(used.tag, @"use");
    // empty space hits nothing
    XCTAssertNil([doc nodeAtPoint:NSMakePoint(195, 195)]);

    // frames: the transformed rect reports its translated rectangle
    NSRect tr = [doc frameOfElement:byID(@"tr")];
    XCTAssertEqualWithAccuracy(NSMinX(tr), 100.0, 0.5);
    XCTAssertEqualWithAccuracy(NSMinY(tr), 10.0, 0.5);
    XCTAssertEqualWithAccuracy(NSWidth(tr), 20.0, 0.5);
    // and the form view bridges both lookups
    NSPoint inForm = [fv convertPoint:NSMakePoint(40, 25) fromView:svg];
    XCTAssertEqual([fv svgElementAtPoint:inForm], byID(@"gr"));
    XCTAssertFalse(NSIsEmptyRect([fv layoutFrameOfSVGElement:byID(@"gr")]));

    // the draw paths run headless (gradient, pattern tiling, use)
    NSImage *image = [[NSImage alloc] initWithSize:doc.size];
    [image lockFocus];
    [doc drawInRect:NSMakeRect(0, 0, doc.size.width, doc.size.height)];
    [image unlockFocus];

    // SVG shapes reorder among SVG parents (paint order), but an xf
    // control never moves INTO svg markup through the zone bypass
    NSUndoManager *undo = [[NSUndoManager alloc] init];
    [undo setGroupsByEvent:NO];
    XFHostEdit *edit = [XFHostEdit editWithProcessor:p undoManager:undo];
    NSXMLElement *gr = byID(@"gr");
    NSXMLElement *svgRoot = (NSXMLElement *)[gr parent];
    [undo beginUndoGrouping];
    XCTAssertTrue([edit moveElement:gr underParent:svgRoot atIndex:-1]);
    [undo endUndoGrouping];
    XCTAssertEqual([svgRoot childAtIndex:[svgRoot childCount] - 1], gr);
    [undo undo];
}

// Relative instance/@src (and friends) resolve DURING processor
// construction, so the base URL must ride into the string constructor —
// setting .baseURL afterwards is too late (the select-from-file bug:
// both apps built from strings and patched baseURL post-hoc, leaving
// every file-loaded itemset empty).
- (void)testRelativeSrcResolvesAgainstBaseURL
{
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"xfsrc-%d", getpid()]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"<codes xmlns=\"\"><code>alpha</code><code>beta</code></codes>"
        writeToFile:[dir stringByAppendingPathComponent:@"codes.xml"]
        atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"<head><xf:model>"
        @"<xf:instance src=\"codes.xml\"/>"
        @"</xf:model></head>"
        @"<body><xf:output ref=\"/codes/code[1]\"/></body></html>";
    NSURL *base = [NSURL fileURLWithPath:
        [dir stringByAppendingPathComponent:@"form.xhtml"]];
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml baseURL:base error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertEqualObjects([[[p defaultInstance] documentElement] localName], @"codes",
                          @"the relative src loaded against the base URL");
    XFControl *output = [self firstControlOfClass:[XFOutputControl class] in:p];
    XCTAssertEqualObjects(output.stringValue, @"alpha");
}

// Garbage in a typed date node must parse to nil, never to a wild
// NSDate — GNUstep's Gregorian conversion effectively never returns for
// year 0, hanging the layout (W3C suite 5.2.1.a, "non-empty-content").
- (void)testDateParsingRejectsGarbage
{
    XCTAssertNil([XFInputControl parseDateString:@"non-empty-content"
                                            type:XFDateTypeDate]);
    XCTAssertNil([XFInputControl parseDateString:@"0000-00-00"
                                            type:XFDateTypeDate]);
    XCTAssertNil([XFInputControl parseDateString:@"2026-13-40"
                                            type:XFDateTypeDate]);
    XCTAssertNotNil([XFInputControl parseDateString:@"2026-08-31"
                                               type:XFDateTypeDate]);
}

// Host-registered XPath extension functions (the native stand-in for
// XSLTForms' page-JavaScript fallback): consulted after the built-ins.
- (void)testHostRegisteredXPathFunctions
{
    NSError *error = nil;
    [XFXPath registerHostFunctionNamed:@"xfx-test-fn"
                             evaluator:^XFXPathValue *(XFExprContext *ctx,
                                                       NSArray *args,
                                                       NSError **err) {
        (void)ctx;
        (void)err;
        double bias = args.count ? [(XFXPathValue *)args.firstObject numberValue] : 0;
        return [XFXPathValue number:40 + bias];
    }];
    XFXPath *xp = [XFXPath xpathWithString:@"xfx-test-fn(2) + 1" element:nil error:&error];
    XCTAssertNotNil(xp, @"%@", error);
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:nil];
    XCTAssertEqualWithAccuracy([[xp evaluateInContext:ctx error:&error] numberValue],
                               43.0, 0.001);

    // built-ins are consulted first — a host "sum" cannot shadow XPath's
    [XFXPath registerHostFunctionNamed:@"true"
                             evaluator:^XFXPathValue *(XFExprContext *c,
                                                       NSArray *a, NSError **e) {
        (void)c; (void)a; (void)e;
        return [XFXPathValue boolean:NO];
    }];
    xp = [XFXPath xpathWithString:@"true()" element:nil error:&error];
    XCTAssertTrue([[xp evaluateInContext:ctx error:&error] booleanValue]);
    [XFXPath unregisterHostFunctionNamed:@"true"];

    // unregistering restores the not-found behavior
    [XFXPath unregisterHostFunctionNamed:@"xfx-test-fn"];
    xp = [XFXPath xpathWithString:@"xfx-test-fn(2)" element:nil error:&error];
    XCTAssertNotNil(xp, @"unknown functions still compile (late binding)");
    error = nil;
    XCTAssertNil([xp evaluateInContext:ctx error:&error]);
}

// The drag-reorder command: one undoable move preserving element
// identity, with the same-parent index arithmetic and the zone guards.
- (void)testHostEditMove
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"<head><xf:model id=\"m\">"
        @"<xf:instance><data xmlns=\"\"><one/><two/><three/></data></xf:instance>"
        @"</xf:model></head>"
        @"<body>"
        @"<xf:input id=\"a\" ref=\"one\"><xf:label>A</xf:label></xf:input>"
        @"<xf:input id=\"b\" ref=\"two\"><xf:label>B</xf:label></xf:input>"
        @"<xf:group id=\"g\"><xf:label>G</xf:label>"
        @"<xf:input id=\"c\" ref=\"three\"><xf:label>C</xf:label></xf:input>"
        @"</xf:group>"
        @"</body></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLElement * (^byID)(NSString *) = ^NSXMLElement *(NSString *ident) {
        return [XFXML elementWithID:ident inNode:p.hostDocument];
    };
    NSXMLElement *a = byID(@"a"), *b = byID(@"b"), *g = byID(@"g");
    NSXMLElement *body = (NSXMLElement *)[a parent];
    NSArray * (^order)(NSXMLElement *) = ^NSArray *(NSXMLElement *parent) {
        NSMutableArray *ids = [NSMutableArray array];
        for (NSXMLNode *c in [parent children]) {
            if ([c kind] == NSXMLElementKind) {
                [ids addObject:[[(NSXMLElement *)c attributeForName:@"id"] stringValue] ?: @"?"];
            }
        }
        return ids;
    };
    NSUndoManager *undo = [[NSUndoManager alloc] init];
    [undo setGroupsByEvent:NO];
    XFHostEdit *edit = [XFHostEdit editWithProcessor:p undoManager:undo];
    NSUInteger controls = p.controls.count;

    // append within the same parent (index arithmetic across the detach)
    [undo beginUndoGrouping];
    XCTAssertTrue([edit moveElement:a underParent:body atIndex:-1]);
    [undo endUndoGrouping];
    XCTAssertEqualObjects(order(body), (@[ @"b", @"g", @"a" ]));
    XCTAssertEqual(p.controls.count, controls);
    XCTAssertNotNil([p controlForElement:a], @"the moved element stays attached");

    // back up before b (same parent, moving toward the front)
    [undo beginUndoGrouping];
    XCTAssertTrue([edit moveElement:a underParent:body atIndex:(NSInteger)[b index]]);
    [undo endUndoGrouping];
    XCTAssertEqualObjects(order(body), (@[ @"a", @"b", @"g" ]));

    // across parents: into the group
    [undo beginUndoGrouping];
    XCTAssertTrue([edit moveElement:b underParent:g atIndex:-1]);
    [undo endUndoGrouping];
    XCTAssertEqualObjects(order(body), (@[ @"a", @"g" ]));
    XCTAssertEqualObjects(order(g), (@[ @"?", @"c", @"b" ]));   // "?" = the label
    XCTAssertNotNil([p controlForElement:b]);

    // refusals change nothing: into itself / its own subtree, a zone that
    // rejects the kind, and dropping right where it already is
    XCTAssertFalse([edit moveElement:g underParent:g atIndex:-1]);
    XCTAssertFalse([edit moveElement:g underParent:(NSXMLElement *)[byID(@"c") parent] atIndex:0]);
    XCTAssertFalse([edit moveElement:a underParent:(NSXMLElement *)p.model.element atIndex:-1]);
    XCTAssertFalse([edit moveElement:a underParent:body atIndex:(NSInteger)[a index]]);
    XCTAssertEqualObjects(order(body), (@[ @"a", @"g" ]));

    // the undo chain walks every move back
    [undo undo];
    XCTAssertEqualObjects(order(body), (@[ @"a", @"b", @"g" ]));
    XCTAssertEqualObjects(order(g), (@[ @"?", @"c" ]));
    [undo undo];
    XCTAssertEqualObjects(order(body), (@[ @"b", @"g", @"a" ]));
    [undo undo];
    XCTAssertEqualObjects(order(body), (@[ @"a", @"b", @"g" ]));
    XCTAssertEqual(p.controls.count, controls);

    // and the moved-again layout still resolves for the form view
    [NSApplication sharedApplication];
    XFFormView *fv = [[XFFormView alloc] initWithProcessor:p];
    XCTAssertFalse(NSIsEmptyRect([fv layoutFrameOfControl:[p controlForElement:a]]));
}

// The design-support introspection the designer's overlay draws from:
// layoutFrameOfControl / controlAtPoint on XFFormView.
- (void)testFormViewDesignIntrospection
{
    [NSApplication sharedApplication];
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\"><name>Ada</name><city/><ghost/></data></xf:instance>"
        @"<xf:bind nodeset=\"ghost\" relevant=\"false()\"/>"
        extra:
        @"<xf:input ref=\"name\"><xf:label>Name</xf:label></xf:input>"
        @"<xf:group><xf:label>Address</xf:label>"
        @"<xf:input ref=\"city\"><xf:label>City</xf:label></xf:input></xf:group>"
        @"<xf:input ref=\"ghost\"><xf:label>Ghost</xf:label></xf:input>"
        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFFormView *fv = [[XFFormView alloc] initWithProcessor:p];

    XFControl * (^byRef)(NSString *) = ^XFControl *(NSString *ref) {
        for (NSXMLElement *e in [XFXML elementsWithLocalName:@"input"
                                                namespaceURI:@"http://www.w3.org/2002/xforms"
                                                      inNode:p.hostDocument]) {
            if ([[[e attributeForName:@"ref"] stringValue] isEqualToString:ref]) {
                return [p controlForElement:e];
            }
        }
        return nil;
    };
    XFControl *name = byRef(@"name");
    XFControl *city = byRef(@"city");
    XFControl *ghost = byRef(@"ghost");
    XFGroup *group = [self firstControlOfClass:[XFGroup class] in:p];
    XCTAssertNotNil(name);
    XCTAssertNotNil(city);
    XCTAssertNotNil(group);

    // laid-out controls report a frame; the hit test finds them by it
    NSRect nameRect = [fv layoutFrameOfControl:name];
    XCTAssertFalse(NSIsEmptyRect(nameRect));
    XCTAssertEqual([fv controlAtPoint:NSMakePoint(NSMidX(nameRect), NSMidY(nameRect))], name);

    // the group's box encloses its child, and the child wins the hit test
    NSRect groupRect = [fv layoutFrameOfControl:group];
    NSRect cityRect = [fv layoutFrameOfControl:city];
    XCTAssertFalse(NSIsEmptyRect(groupRect));
    XCTAssertFalse(NSIsEmptyRect(cityRect));
    XCTAssertTrue(NSContainsRect(groupRect, cityRect));
    XCTAssertEqual([fv controlAtPoint:NSMakePoint(NSMidX(cityRect), NSMidY(cityRect))], city);
    // the box's title strip holds no widget — the group itself answers
    XCTAssertEqual([fv controlAtPoint:NSMakePoint(NSMinX(groupRect) + 2, NSMinY(groupRect) + 2)], group);

    // a non-relevant control is not laid out: no frame, never hit
    XCTAssertNotNil(ghost);
    XCTAssertTrue(NSIsEmptyRect([fv layoutFrameOfControl:ghost]));
    // empty margin space hits nothing
    XCTAssertNil([fv controlAtPoint:NSMakePoint(0.5, 0.5)]);
}

// The designer's command layer: insert / delete / attribute / support-child
// edits notify the processor in place and undo losslessly (element identity
// survives the round trip).
- (void)testHostEditCommands
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"<head><xf:model id=\"m\">"
        @"<xf:instance><data xmlns=\"\"><name>Ada</name><age>7</age></data></xf:instance>"
        @"</xf:model></head>"
        @"<body><xf:input id=\"taken-1\" ref=\"name\"><xf:label>Name</xf:label></xf:input></body>"
        @"</html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLElement *body = [XFXML childElementWithLocalName:@"body"
                                             namespaceURI:XFXHTMLNamespaceURI
                                                ofElement:[p.hostDocument rootElement]];
    XCTAssertNotNil(body);
    NSXMLElement *modelEl = (NSXMLElement *)p.model.element;

    NSUndoManager *undo = [[NSUndoManager alloc] init];
    [undo setGroupsByEvent:NO];
    XFHostEdit *edit = [XFHostEdit editWithProcessor:p undoManager:undo];
    __block NSUInteger changes = 0;
    edit.changedHandler = ^(NSXMLElement *e) { (void)e; changes++; };

    // insertion zones
    XCTAssertTrue([[XFHostEdit insertableNamesUnderParent:body] containsObject:@"input"]);
    NSArray *modelNames = [XFHostEdit insertableNamesUnderParent:modelEl];
    XCTAssertEqualObjects([modelNames subarrayWithRange:NSMakeRange(0, 3)],
                          (@[ @"instance", @"bind", @"submission" ]));
    XCTAssertTrue([modelNames containsObject:@"action"]);   // model event handlers
    XCTAssertFalse([XFHostEdit canInsertElementNamed:@"input" underParent:modelEl]);
    NSXMLElement *data = (NSXMLElement *)[[p.defaultInstance.document rootElement] copy];
    XCTAssertEqual([XFHostEdit insertableNamesUnderParent:data].count, (NSUInteger)0);

    // unique ids skip taken ones
    XCTAssertEqualObjects([edit uniqueIdentifierWithPrefix:@"taken"], @"taken-2");

    // insert an input under the body
    NSUInteger before = p.controls.count;
    [undo beginUndoGrouping];
    NSXMLElement *input = [edit insertElementNamed:@"input" underParent:body atIndex:-1 error:&error];
    [undo endUndoGrouping];
    XCTAssertNotNil(input, @"%@", error);
    XCTAssertEqual(p.controls.count, before + 1);
    XCTAssertNotNil([p controlForElement:input]);
    XCTAssertEqualObjects([[input attributeForName:@"id"] stringValue], @"input-1");
    XCTAssertEqualObjects([edit supportChildText:@"label" onElement:input], @"Input");
    XCTAssertEqual(changes, (NSUInteger)1);

    // attribute edit + undo
    [undo beginUndoGrouping];
    [edit setAttribute:@"ref" value:@"age" onElement:input];
    [undo endUndoGrouping];
    XCTAssertEqualObjects([[input attributeForName:@"ref"] stringValue], @"age");
    [undo undo];
    XCTAssertNil([input attributeForName:@"ref"]);
    [undo redo];
    XCTAssertEqualObjects([[input attributeForName:@"ref"] stringValue], @"age");

    // support child edit + undo
    [undo beginUndoGrouping];
    [edit setSupportChild:@"hint" text:@"Years" onElement:input];
    [undo endUndoGrouping];
    XCTAssertEqualObjects([edit supportChildText:@"hint" onElement:input], @"Years");
    [undo undo];
    XCTAssertNil([edit supportChildText:@"hint" onElement:input]);

    // rich support child: inline markup + xf:output (XForms 1.1 label
    // content), read back as XML, flattened text still available, undo
    // restores the plain text version
    [undo beginUndoGrouping];
    [edit setSupportChild:@"hint" text:@"Years" onElement:input];
    [undo endUndoGrouping];
    NSError *richErr = nil;
    XCTAssertFalse([edit setSupportChild:@"hint" contentXML:@"<broken"
                               onElement:input error:&richErr]);
    XCTAssertNotNil(richErr);
    XCTAssertEqualObjects([edit supportChildText:@"hint" onElement:input], @"Years");
    [undo beginUndoGrouping];
    XCTAssertTrue([edit setSupportChild:@"hint"
                             contentXML:@"Age in <strong>years</strong>: <xf:output value=\"'7'\"/>"
                              onElement:input error:&error], @"%@", error);
    [undo endUndoGrouping];
    NSString *hintXML = [edit supportChildXML:@"hint" onElement:input];
    XCTAssertTrue([hintXML containsString:@"Age in <strong>years</strong>: "], @"%@", hintXML);
    XCTAssertTrue([hintXML containsString:@"output"], @"%@", hintXML);
    XCTAssertFalse([hintXML containsString:@"xmlns"], @"%@", hintXML);
    XCTAssertTrue([XFHostXMLString(p.hostDocument, 0) containsString:@"<strong>years</strong>"]);
    [undo undo];
    XCTAssertEqualObjects([edit supportChildText:@"hint" onElement:input], @"Years");
    XCTAssertEqualObjects([edit supportChildXML:@"hint" onElement:input], @"Years");
    // a rich label lands as the FIRST child even when created fresh
    [undo beginUndoGrouping];
    [edit setSupportChild:@"hint" text:nil onElement:input];
    [edit setSupportChild:@"label" text:nil onElement:input];
    XCTAssertTrue([edit setSupportChild:@"label" contentXML:@"<em>Nom</em>"
                              onElement:input error:&error], @"%@", error);
    [undo endUndoGrouping];
    XCTAssertEqualObjects([(NSXMLElement *)[input childAtIndex:0] localName], @"label");
    XCTAssertEqualObjects([edit supportChildText:@"label" onElement:input], @"Nom");
    [undo beginUndoGrouping];
    [edit setSupportChild:@"label" text:@"Input" onElement:input];
    [undo endUndoGrouping];

    // delete + undo brings back the SAME element at the same place
    NSInteger index = (NSInteger)[input index];
    [undo beginUndoGrouping];
    [edit deleteElement:input];
    [undo endUndoGrouping];
    XCTAssertEqual(p.controls.count, before);
    XCTAssertNil([p controlForElement:input]);
    [undo undo];
    XCTAssertEqual(p.controls.count, before + 1);
    XCTAssertEqual((NSInteger)[input index], index);
    XCTAssertNotNil([p controlForElement:input]);
    XCTAssertEqual([input parent], body);

    // a bind inserted under the model reaches the model
    [undo beginUndoGrouping];
    NSXMLElement *bind = [edit insertElementNamed:@"bind" underParent:modelEl atIndex:-1 error:&error];
    [undo endUndoGrouping];
    XCTAssertNotNil(bind, @"%@", error);
    [undo beginUndoGrouping];
    [edit setAttribute:@"nodeset" value:@"age" onElement:bind];
    [edit setAttribute:@"required" value:@"true()" onElement:bind];
    [undo endUndoGrouping];
    XCTAssertTrue([XFHostXMLString(p.hostDocument, 0) containsString:@"required=\"true()\""]);

    // instance-data replacement re-adopts the instance; undo restores it
    NSXMLElement *instanceEl = [XFXML childElementWithLocalName:@"instance"
                                                   namespaceURI:XFXFormsNamespaceURI
                                                      ofElement:modelEl];
    XCTAssertNotNil(instanceEl);
    NSError *bad = nil;
    XCTAssertFalse([edit setContentXML:@"<broken" onElement:instanceEl error:&bad]);
    XCTAssertNotNil(bad);
    [undo beginUndoGrouping];
    XCTAssertTrue([edit setContentXML:@"<data xmlns=\"\"><name>Zed</name><city/></data>"
                            onElement:instanceEl error:&error], @"%@", error);
    [undo endUndoGrouping];
    NSXMLElement *root = [[p defaultInstance] documentElement];
    XCTAssertEqualObjects([[root childAtIndex:0] stringValue], @"Zed");
    XCTAssertEqual([root childCount], (NSUInteger)2);
    [undo undo];
    root = [[p defaultInstance] documentElement];
    XCTAssertEqualObjects([[root childAtIndex:0] stringValue], @"Ada");
}

// The AST's structure/rendering API (the designer's picker is built on
// it): kinds, canonical source, precedence-preserving parentheses, and
// subexpression replacement by structure path.
- (void)testXPathStructureAndRendering
{
    NSError *error = nil;
    XFXPath *calc = [XFXPath xpathWithString:@"../in - ../out" error:&error];
    XCTAssertNotNil(calc, @"%@", error);
    NSDictionary *s = [calc structure];
    XCTAssertEqualObjects(s[@"kind"], @"binary");
    XCTAssertEqualObjects(s[@"op"], @"-");
    NSArray *children = s[@"children"];
    XCTAssertEqual(children.count, (NSUInteger)2);
    XCTAssertEqualObjects(children[0][@"kind"], @"location");
    XCTAssertEqualObjects(children[0][@"source"], @"../in");
    XCTAssertEqualObjects([calc canonicalSource], @"../in - ../out");
    // splice: edit the left path only
    XCTAssertEqualObjects([calc sourceReplacingNodeAtPath:@[ @0 ] with:@"../balance"],
                          @"../balance - ../out");
    XCTAssertNil([calc sourceReplacingNodeAtPath:@[ @7 ] with:@"x"]);

    // parentheses survive where the grammar needs them; associativity too
    XFXPath *parens = [XFXPath xpathWithString:@"(a + b) * c" error:&error];
    XCTAssertEqualObjects([parens canonicalSource], @"(a + b) * c");
    XFXPath *assoc = [XFXPath xpathWithString:@"a - (b - c)" error:&error];
    XCTAssertEqualObjects([assoc canonicalSource], @"a - (b - c)");

    // location paths: steps carry axis/test, predicates re-render
    XFXPath *loc = [XFXPath xpathWithString:@"instance('m')/order/item[@sku='x']/price"
                                      error:&error];
    XCTAssertNotNil(loc, @"%@", error);
    NSDictionary *ls = [loc structure];
    XCTAssertEqualObjects(ls[@"kind"], @"path");
    NSArray *lc = ls[@"children"];
    // predicate-free filters collapse: the path's head IS the function
    XCTAssertEqualObjects(lc[0][@"kind"], @"function");
    XCTAssertEqualObjects(lc[0][@"name"], @"instance");
    XCTAssertEqualObjects(lc[1][@"kind"], @"location");
    NSArray *steps = lc[1][@"children"];
    XCTAssertEqual(steps.count, (NSUInteger)3);
    XCTAssertEqualObjects(steps[1][@"axis"], @"child");
    XCTAssertEqualObjects(steps[1][@"test"], @"item");
    XCTAssertEqualObjects([loc canonicalSource],
                          @"instance('m')/order/item[@sku = 'x']/price");

    // functions and shorthands
    XFXPath *fn = [XFXPath xpathWithString:@"concat(../a, 'x', \"it's\")" error:&error];
    XCTAssertEqualObjects([fn canonicalSource], @"concat(../a, 'x', \"it's\")");

    // highlight tokens: engine-lexed spans with semantic classification
    NSString *expr = @"instance('m')/a[position() mod 2 = 0] | $v/child::b";
    NSArray *tokens = [XFXPath highlightTokensForString:expr];
    NSMutableDictionary *byText = [NSMutableDictionary dictionary];
    for (NSDictionary *token in tokens) {
        NSRange r = [token[@"range"] rangeValue];
        XCTAssertTrue(NSMaxRange(r) <= expr.length);
        byText[[expr substringWithRange:r]] = token[@"kind"];
    }
    XCTAssertEqualObjects(byText[@"instance"], @"function");
    XCTAssertEqualObjects(byText[@"'m'"], @"string");
    XCTAssertEqualObjects(byText[@"position"], @"function");
    XCTAssertEqualObjects(byText[@"mod"], @"operator");
    XCTAssertEqualObjects(byText[@"2"], @"number");
    XCTAssertEqualObjects(byText[@"|"], @"operator");
    XCTAssertEqualObjects(byText[@"v"], @"variable");
    XCTAssertEqualObjects(byText[@"child"], @"axis");
    XCTAssertEqualObjects(byText[@"b"], @"name");
    // '*' is a name test at operand position, multiplication after one
    NSArray *star1 = [XFXPath highlightTokensForString:@"a * b"];
    XCTAssertEqualObjects(star1[1][@"kind"], @"operator");
    NSArray *star2 = [XFXPath highlightTokensForString:@"child::*"];
    XCTAssertEqualObjects([star2 lastObject][@"kind"], @"name");
    // half-typed expressions still tokenize (no parse required)
    XCTAssertTrue([XFXPath highlightTokensForString:@"concat('a"].count > 0);
}

// Itemset authoring: insertable under selects with a compilable starter,
// and the child-attribute command (label/@ref, value/@ref) round-trips.
- (void)testItemsetAuthoring
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"<head><xf:model id=\"m\">"
        @"<xf:instance><data xmlns=\"\"><color>red</color>"
        @"<option>red</option><option>blue</option></data></xf:instance>"
        @"</xf:model></head>"
        @"<body><xf:select1 id=\"s\" ref=\"color\"><xf:label>Color</xf:label>"
        @"<xf:item><xf:label>None</xf:label><xf:value/></xf:item>"
        @"</xf:select1></body>"
        @"</html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLElement *select = nil;
    for (XFControl *c in p.controls) {
        if ([[c.element localName] isEqualToString:@"select1"]) {
            select = c.element;
        }
    }
    XCTAssertNotNil(select);
    XCTAssertTrue([[XFHostEdit insertableNamesUnderParent:select] containsObject:@"itemset"]);

    NSUndoManager *undo = [[NSUndoManager alloc] init];
    [undo setGroupsByEvent:NO];
    XFHostEdit *edit = [XFHostEdit editWithProcessor:p undoManager:undo];
    [undo beginUndoGrouping];
    NSXMLElement *itemset = [edit insertElementNamed:@"itemset" underParent:select
                                             atIndex:-1 error:&error];
    [undo endUndoGrouping];
    XCTAssertNotNil(itemset, @"%@", error);
    XCTAssertEqualObjects([[itemset attributeForName:@"nodeset"] stringValue], @".");
    XCTAssertEqualObjects([edit supportChildAttribute:@"ref" child:@"label"
                                            onElement:itemset], @".");

    [undo beginUndoGrouping];
    [edit setAttribute:@"nodeset" value:@"../option" onElement:itemset];
    [edit setSupportChildAttribute:@"ref" child:@"value" value:@"." onElement:itemset];
    [edit setSupportChildAttribute:@"ref" child:@"label" value:@"." onElement:itemset];
    [undo endUndoGrouping];
    XCTAssertTrue([XFHostXMLString(p.hostDocument, 0) containsString:@"nodeset=\"../option\""]);
    // the select's items now include the two option nodes
    XFSelectControl *sc = (XFSelectControl *)[p controlForElement:select];
    XCTAssertGreaterThanOrEqual((NSInteger)sc.items.count, 3);

    [undo undo];
    XCTAssertEqualObjects([edit supportChildAttribute:@"ref" child:@"label"
                                            onElement:itemset], @".");
    [undo undo];
    XCTAssertNil([itemset parent]);
}

// Action authoring: insertion zones offer the action module, inserts get
// an ev:event starter, attribute edits recompile the handler, delete
// unhooks it (the listener would otherwise keep firing).
- (void)testActionAuthoring
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"<head><xf:model id=\"m\">"
        @"<xf:instance><data xmlns=\"\"><name>Ada</name></data></xf:instance>"
        @"</xf:model></head>"
        @"<body><xf:trigger id=\"t\"><xf:label>Go</xf:label></xf:trigger></body>"
        @"</html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLElement *trigger = nil;
    for (XFControl *c in p.controls) {
        if ([[c.element localName] isEqualToString:@"trigger"]) {
            trigger = c.element;
        }
    }
    XCTAssertNotNil(trigger);

    NSUndoManager *undo = [[NSUndoManager alloc] init];
    [undo setGroupsByEvent:NO];
    XFHostEdit *edit = [XFHostEdit editWithProcessor:p undoManager:undo];

    // zones: the action module hangs off controls, models, submissions,
    // and nests inside xf:action — never inside instance data
    XCTAssertTrue([[XFHostEdit insertableNamesUnderParent:trigger] containsObject:@"setvalue"]);
    NSXMLElement *modelEl = (NSXMLElement *)p.model.element;
    XCTAssertTrue([[XFHostEdit insertableNamesUnderParent:modelEl] containsObject:@"action"]);
    NSXMLElement *data = (NSXMLElement *)[[p.defaultInstance.document rootElement] copy];
    XCTAssertFalse([XFHostEdit canInsertElementNamed:@"setvalue" underParent:data]);

    // insert under the trigger: ev:event starter + live compilation
    NSUInteger actionsBefore = p.actions.count;
    [undo beginUndoGrouping];
    NSXMLElement *setvalue = [edit insertElementNamed:@"setvalue" underParent:trigger
                                              atIndex:-1 error:&error];
    [undo endUndoGrouping];
    XCTAssertNotNil(setvalue, @"%@", error);
    XCTAssertEqualObjects([[setvalue attributeForName:@"ev:event"] stringValue], @"DOMActivate");
    XCTAssertEqual(p.actions.count, actionsBefore + 1);
    [undo beginUndoGrouping];
    [edit setAttribute:@"ref" value:@"name" onElement:setvalue];
    [edit setAttribute:@"value" value:@"'Zed'" onElement:setvalue];
    [undo endUndoGrouping];
    XCTAssertEqual(p.actions.count, actionsBefore + 1);   // recompiled, not duplicated

    // the handler actually fires: activating the trigger sets the node
    XFTriggerControl *triggerControl = (XFTriggerControl *)[p controlForElement:trigger];
    [triggerControl activate];
    XCTAssertEqualObjects([[[p defaultInstance] documentElement] stringValue], @"Zed");

    // inline content command: message-style mixed content on the element
    [undo beginUndoGrouping];
    NSXMLElement *message = [edit insertElementNamed:@"message" underParent:trigger
                                             atIndex:-1 error:&error];
    XCTAssertNotNil(message, @"%@", error);
    XCTAssertTrue([edit setInlineContentXML:@"Saved <strong>OK</strong>"
                                  onElement:message error:&error], @"%@", error);
    [undo endUndoGrouping];
    XCTAssertTrue([[edit inlineContentXMLOfElement:message] containsString:@"<strong>OK</strong>"]);
    [undo undo];
    XCTAssertNil([message parent]);

    // delete unhooks the compiled handler and its listener
    [undo beginUndoGrouping];
    [edit deleteElement:setvalue];
    [undo endUndoGrouping];
    XCTAssertEqual(p.actions.count, actionsBefore);
    [[[p defaultInstance] documentElement] setStringValue:@"Ada"];
    [triggerControl activate];
    XCTAssertEqualObjects([[[p defaultInstance] documentElement] stringValue], @"Ada");

    // ev:observer redirects a handler to listen elsewhere (XML Events
    // attribute module): a setvalue living under the MODEL but observing
    // the trigger fires when the trigger activates — authored live, so
    // the attribute change must reinstall the listener on the new observer.
    // (ref="." — the earlier setStringValue on the root ate the <name>
    // child, so the root itself is the only stable target left.)
    [undo beginUndoGrouping];
    NSXMLElement *remote = [edit insertElementNamed:@"setvalue" underParent:modelEl
                                            atIndex:-1 error:&error];
    XCTAssertNotNil(remote, @"%@", error);
    [edit setAttribute:@"ref" value:@"." onElement:remote];
    [edit setAttribute:@"value" value:@"'Observed'" onElement:remote];
    [edit setAttribute:@"ev:event" value:@"DOMActivate" onElement:remote];
    [edit setAttribute:@"ev:observer" value:@"t" onElement:remote];
    [undo endUndoGrouping];
    [triggerControl activate];
    XCTAssertEqualObjects([[[p defaultInstance] documentElement] stringValue], @"Observed");
    [undo beginUndoGrouping];
    [edit deleteElement:remote];
    [undo endUndoGrouping];
    XCTAssertEqual(p.actions.count, actionsBefore);
    [[[p defaultInstance] documentElement] setStringValue:@"Ada"];
    [triggerControl activate];
    XCTAssertEqualObjects([[[p defaultInstance] documentElement] stringValue], @"Ada");
}

// The node picker's step builder: relative paths with ../, positional
// predicates only where needed, attributes, and the below-root tail for
// instance('id')/… expressions.
- (void)testXPathStepBuilding
{
    NSString *xml =
        @"<order xmlns=\"\">"
        @"<customer><name>Ada</name><city>Kyzylorda</city></customer>"
        @"<line qty=\"2\"><sku>A-1</sku></line>"
        @"<line qty=\"5\"><sku>B-2</sku></line>"
        @"</order>";
    NSError *error = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:&error];
    XCTAssertNotNil(doc, @"%@", error);
    NSXMLElement *order = [doc rootElement];
    NSXMLElement *customer = (NSXMLElement *)[order childAtIndex:0];
    NSXMLElement *name = (NSXMLElement *)[customer childAtIndex:0];
    NSXMLElement *line2 = (NSXMLElement *)[order childAtIndex:2];
    NSXMLElement *sku2 = (NSXMLElement *)[line2 childAtIndex:0];
    NSXMLNode *qty2 = [line2 attributeForName:@"qty"];

    XCTAssertEqualObjects([XFHostEdit pathFromNode:order toNode:order], @".");
    XCTAssertEqualObjects([XFHostEdit pathFromNode:order toNode:name], @"customer/name");
    XCTAssertEqualObjects([XFHostEdit pathFromNode:order toNode:sku2], @"line[2]/sku");
    XCTAssertEqualObjects([XFHostEdit pathFromNode:name toNode:sku2], @"../../line[2]/sku");
    XCTAssertEqualObjects([XFHostEdit pathFromNode:customer toNode:qty2], @"../line[2]/@qty");
    XCTAssertEqualObjects([XFHostEdit pathFromNode:sku2 toNode:customer], @"../../customer");
    XCTAssertEqualObjects([XFHostEdit stepsBelowRootToNode:order], @"");
    XCTAssertEqualObjects([XFHostEdit stepsBelowRootToNode:sku2], @"line[2]/sku");
    // a node from another document has no relative path
    NSXMLDocument *other = [[NSXMLDocument alloc] initWithXMLString:@"<x/>" options:0 error:NULL];
    XCTAssertNil([XFHostEdit pathFromNode:order toNode:[other rootElement]]);
}

@end
