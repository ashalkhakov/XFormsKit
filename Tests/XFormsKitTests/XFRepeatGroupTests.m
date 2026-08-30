#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFGroup.h>
#import <XFormsKit/XFRepeat.h>
#import <XFormsKit/XFSetindexAction.h>
#import <XFormsKit/XFXML.h>
#import <math.h>

@interface XFRepeatGroupTests : XCTestCase
@end

@implementation XFRepeatGroupTests

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

- (void)testGroupShiftsContext
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <item><name>Ada</name></item>"
                      @"</data></xf:instance>"
                      extra:
                      @"<xf:group id=\"g\" ref=\"item\">"
                      @"  <xf:output id=\"o\" ref=\"name\"><xf:label>N</xf:label></xf:output>"
                      @"</xf:group>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertEqual(p.groups.count, (NSUInteger)1);
    XFGroup *g = p.groups.firstObject;
    XCTAssertTrue(g.relevant);
    XCTAssertEqual(g.children.count, (NSUInteger)1);
    XFOutputControl *out = (XFOutputControl *)g.children.firstObject;
    XCTAssertEqualObjects(out.stringValue, @"Ada");
}

- (void)testGroupWithoutBindingStaysRelevant
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      extra:
                      @"<xf:group id=\"g\">"
                      @"  <xf:output ref=\"n\"><xf:label>N</xf:label></xf:output>"
                      @"</xf:group>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertTrue(p.groups.firstObject.relevant);
    XCTAssertEqualObjects(p.outputControls.firstObject.stringValue, @"Ada");
}

- (void)testGroupNonRelevantWhenMissingNode
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      extra:
                      @"<xf:group id=\"g\" ref=\"missing\">"
                      @"  <xf:output ref=\"n\"><xf:label>N</xf:label></xf:output>"
                      @"</xf:group>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertFalse(p.groups.firstObject.relevant);
}

- (void)testRepeatBuildsItemsAndIndex
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <item><name>Ada</name></item>"
                      @"  <item><name>Bob</name></item>"
                      @"  <item><name>Cid</name></item>"
                      @"</data></xf:instance>"
                      extra:
                      @"<xf:repeat id=\"r\" nodeset=\"item\">"
                      @"  <xf:output ref=\"name\"><xf:label>N</xf:label></xf:output>"
                      @"</xf:repeat>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFRepeat *r = [p repeatWithIdentifier:@"r"];
    XCTAssertNotNil(r);
    XCTAssertEqual(r.nodes.count, (NSUInteger)3);
    XCTAssertEqual(r.items.count, (NSUInteger)3);
    XCTAssertEqual(r.index, (NSUInteger)1);
    XCTAssertEqualObjects([(XFOutputControl *)r.items[0].controls.firstObject stringValue], @"Ada");
    XCTAssertEqualObjects([(XFOutputControl *)r.items[1].controls.firstObject stringValue], @"Bob");
    XCTAssertEqualObjects([(XFOutputControl *)r.items[2].controls.firstObject stringValue], @"Cid");
    XCTAssertTrue(r.items[0].selected);
    XCTAssertFalse(r.items[1].selected);
}

- (void)testRepeatStartIndex
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <item><name>Ada</name></item>"
                      @"  <item><name>Bob</name></item>"
                      @"</data></xf:instance>"
                      extra:
                      @"<xf:repeat id=\"r\" nodeset=\"item\" startindex=\"2\">"
                      @"  <xf:output ref=\"name\"><xf:label>N</xf:label></xf:output>"
                      @"</xf:repeat>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFRepeat *r = [p repeatWithIdentifier:@"r"];
    XCTAssertEqual(r.index, (NSUInteger)2);
    XCTAssertTrue(r.items[1].selected);
}

- (void)testEmptyRepeatIndexIsZero
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"></data></xf:instance>"
                      extra:
                      @"<xf:repeat id=\"r\" nodeset=\"item\">"
                      @"  <xf:output ref=\"name\"><xf:label>N</xf:label></xf:output>"
                      @"</xf:repeat>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFRepeat *r = [p repeatWithIdentifier:@"r"];
    XCTAssertEqual(r.nodes.count, (NSUInteger)0);
    XCTAssertEqual(r.index, (NSUInteger)0);
    XCTAssertFalse(r.relevant);
}

- (void)testIndexFunctionAndSetindex
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <item><name>Ada</name></item>"
                      @"  <item><name>Bob</name></item>"
                      @"  <item><name>Cid</name></item>"
                      @"</data></xf:instance>"
                      extra:
                      @"<xf:repeat id=\"r\" nodeset=\"item\">"
                      @"  <xf:output ref=\"name\"><xf:label>N</xf:label></xf:output>"
                      @"</xf:repeat>"
                      @"<xf:output id=\"idx\" value=\"index('r')\"><xf:label>I</xf:label></xf:output>"
                      @"<xf:setindex id=\"go\" ev:event=\"xforms-ready\" repeat=\"r\" index=\"2\"/>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFRepeat *r = [p repeatWithIdentifier:@"r"];
    XCTAssertEqual(r.index, (NSUInteger)2);
    XCTAssertTrue([[p actionWithIdentifier:@"go"] wasInvokedForEvent:@"xforms-ready"]);
    XCTAssertEqualObjects(p.outputControls.lastObject.stringValue, @"2");
}

- (void)testSetindexClampsAndScrolls
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <item><name>Ada</name></item>"
                      @"  <item><name>Bob</name></item>"
                      @"</data></xf:instance>"
                      @"<xf:action id=\"first\" ev:event=\"xforms-scroll-first\" ev:observer=\"r\"/>"
                      @"<xf:action id=\"last\" ev:event=\"xforms-scroll-last\" ev:observer=\"r\"/>"
                      extra:
                      @"<xf:repeat id=\"r\" nodeset=\"item\">"
                      @"  <xf:output ref=\"name\"><xf:label>N</xf:label></xf:output>"
                      @"</xf:repeat>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFRepeat *r = [p repeatWithIdentifier:@"r"];
    [r setIndex:99];
    XCTAssertEqual(r.index, (NSUInteger)2);
    XCTAssertTrue([[p actionWithIdentifier:@"last"] wasInvokedForEvent:@"xforms-scroll-last"]);
    [r setIndex:0];
    XCTAssertEqual(r.index, (NSUInteger)1);
    XCTAssertTrue([[p actionWithIdentifier:@"first"] wasInvokedForEvent:@"xforms-scroll-first"]);
}

- (void)testRepeatRefAttribute
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <item>one</item><item>two</item>"
                      @"</data></xf:instance>"
                      extra:
                      @"<xf:repeat id=\"r\" ref=\"item\">"
                      @"  <xf:output ref=\".\"><xf:label>N</xf:label></xf:output>"
                      @"</xf:repeat>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFRepeat *r = [p repeatWithIdentifier:@"r"];
    XCTAssertEqual(r.items.count, (NSUInteger)2);
    XCTAssertEqualObjects([(XFOutputControl *)r.items[1].controls.firstObject stringValue], @"two");
}

@end
