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
#import <XFormsKit/XFXML.h>

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
                      @"  <xf:itemset nodeset=\"opt\">"
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
    XCTAssertEqualWithAccuracy(r.numericValue, 3, 0.01);
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

@end
