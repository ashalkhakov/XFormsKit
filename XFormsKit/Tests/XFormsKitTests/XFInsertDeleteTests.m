#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFInsertAction.h>
#import <XFormsKit/XFDeleteAction.h>
#import <XFormsKit/XFToggleAction.h>
#import <XFormsKit/XFSetfocusAction.h>
#import <XFormsKit/XFSwitch.h>
#import <XFormsKit/XFRepeat.h>
#import <XFormsKit/XFXML.h>
#import <XFormsKit/XFBind.h>
#import <XFormsKit/XFNodeState.h>

@interface XFInsertDeleteTests : XCTestCase
@end

@implementation XFInsertDeleteTests

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

- (NSArray<NSXMLElement *> *)items:(XFProcessor *)p
{
    return [[[p.model defaultInstance] documentElement] elementsForName:@"item"];
}

- (void)testInsertClonesAfterLast
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <item>Ada</item>"
                      @"</data></xf:instance>"
                      @"<xf:insert id=\"ins\" ev:event=\"xforms-ready\" nodeset=\"item\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertEqual([self items:p].count, (NSUInteger)2);
    XCTAssertEqualObjects([XFXML stringValueOfNode:[self items:p].lastObject], @"Ada");
    XFInsertAction *ins = (XFInsertAction *)[p actionWithIdentifier:@"ins"];
    XCTAssertEqual(ins.lastInsertedNodes.count, (NSUInteger)1);
}

- (void)testInsertBeforeFirst
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <item>Ada</item><item>Bob</item>"
                      @"</data></xf:instance>"
                      @"<xf:insert ev:event=\"xforms-ready\" nodeset=\"item\" at=\"1\" position=\"before\" origin=\"item[2]\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSArray *items = [self items:p];
    XCTAssertEqual(items.count, (NSUInteger)3);
    XCTAssertEqualObjects([XFXML stringValueOfNode:items[0]], @"Bob");
}

- (void)testInsertIntoEmptyUsesContext
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <proto>X</proto>"
                      @"</data></xf:instance>"
                      @"<xf:insert ev:event=\"xforms-ready\" context=\"/data\" nodeset=\"item\" origin=\"proto\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLElement *root = [[p.model defaultInstance] documentElement];
    // nodeset "item" is empty, so the origin (proto) is cloned as a child of
    // the context node /data (XForms 1.1 10.3, XsltForms_insert). The clone
    // keeps its name, so there are now two proto elements and still no item.
    XCTAssertEqual([root elementsForName:@"proto"].count, (NSUInteger)2);
    XCTAssertEqual([root elementsForName:@"item"].count, (NSUInteger)0);
    XCTAssertEqualObjects([XFXML stringValueOfNode:[root elementsForName:@"proto"][1]], @"X");
    XCTAssertGreaterThanOrEqual([root children].count, (NSUInteger)2);
}

- (void)testInsertUpdatesRepeatIndex
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <item>Ada</item>"
                      @"</data></xf:instance>"
                      extra:
                      @"<xf:repeat id=\"r\" nodeset=\"item\">"
                      @"  <xf:output ref=\".\"><xf:label>N</xf:label></xf:output>"
                      @"</xf:repeat>"
                      @"<xf:insert ev:event=\"xforms-ready\" nodeset=\"item\" origin=\"item[1]\" position=\"after\" at=\"1\"/>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFRepeat *r = [p repeatWithIdentifier:@"r"];
    XCTAssertEqual(r.nodes.count, (NSUInteger)2);
    XCTAssertEqual(r.index, (NSUInteger)2);
}

- (void)testInsertEventHandler
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance id=\"i\"><data xmlns=\"\"><item>Ada</item></data></xf:instance>"
                      @"<xf:action id=\"onins\" ev:event=\"xforms-insert\" ev:observer=\"i\"/>"
                      @"<xf:insert ev:event=\"xforms-ready\" nodeset=\"item\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertTrue([[p actionWithIdentifier:@"onins"] wasInvokedForEvent:@"xforms-insert"]);
}

- (void)testDeleteAtIndex
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <item>Ada</item><item>Bob</item><item>Cid</item>"
                      @"</data></xf:instance>"
                      @"<xf:delete id=\"del\" ev:event=\"xforms-ready\" nodeset=\"item\" at=\"2\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSArray *items = [self items:p];
    XCTAssertEqual(items.count, (NSUInteger)2);
    XCTAssertEqualObjects([XFXML stringValueOfNode:items[0]], @"Ada");
    XCTAssertEqualObjects([XFXML stringValueOfNode:items[1]], @"Cid");
}

- (void)testDeleteWholeNodeset
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <item>Ada</item><item>Bob</item>"
                      @"</data></xf:instance>"
                      @"<xf:delete ev:event=\"xforms-ready\" nodeset=\"item\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertEqual([self items:p].count, (NSUInteger)0);
}

- (void)testDeleteUpdatesRepeat
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <item>Ada</item><item>Bob</item>"
                      @"</data></xf:instance>"
                      extra:
                      @"<xf:repeat id=\"r\" nodeset=\"item\">"
                      @"  <xf:output ref=\".\"><xf:label>N</xf:label></xf:output>"
                      @"</xf:repeat>"
                      @"<xf:delete ev:event=\"xforms-ready\" nodeset=\"item\" at=\"1\"/>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFRepeat *r = [p repeatWithIdentifier:@"r"];
    XCTAssertEqual(r.nodes.count, (NSUInteger)1);
    XCTAssertEqualObjects([XFXML stringValueOfNode:r.nodes.firstObject], @"Bob");
}

- (void)testToggleSelectsCase
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      extra:
                      @"<xf:switch id=\"s\">"
                      @"  <xf:case id=\"one\" selected=\"true\">"
                      @"    <xf:output ref=\"n\"><xf:label>A</xf:label></xf:output>"
                      @"  </xf:case>"
                      @"  <xf:case id=\"two\">"
                      @"    <xf:output value=\"'B'\"><xf:label>B</xf:label></xf:output>"
                      @"  </xf:case>"
                      @"</xf:switch>"
                      @"<xf:toggle id=\"go\" ev:event=\"xforms-ready\" case=\"two\"/>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFSwitch *sw = nil;
    for (XFControl *c in p.controls) {
        if ([c isKindOfClass:[XFSwitch class]]) {
            sw = (XFSwitch *)c;
        }
    }
    XCTAssertNotNil(sw);
    XCTAssertEqualObjects(sw.selectedCase.identifier, @"two");
    XCTAssertTrue(sw.selectedCase.selected);
    XCTAssertFalse(sw.cases.firstObject.selected);
    XFToggleAction *tog = (XFToggleAction *)[p actionWithIdentifier:@"go"];
    XCTAssertEqualObjects(tog.lastCaseID, @"two");
}

- (void)testSetfocusDispatches
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      extra:
                      @"<xf:input id=\"in\" ref=\"n\"><xf:label>N</xf:label></xf:input>"
                      @"<xf:setfocus id=\"go\" ev:event=\"xforms-ready\" control=\"in\"/>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFSetfocusAction *sf = (XFSetfocusAction *)[p actionWithIdentifier:@"go"];
    XCTAssertNotNil(sf.lastFocused);
    XCTAssertTrue([sf.lastFocused isKindOfClass:[XFInputControl class]]);
    XCTAssertTrue([(XFControl *)sf.lastFocused focused]);
}

- (void)testInsertIntoEmptyNodesetGoesBeforeFirstChild
{
    // XsltForms_insert: empty nodeset + context -> the clone becomes the
    // FIRST child of the context node, not the last (G-13)
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <a/><b/><proto>X</proto>"
                      @"</data></xf:instance>"
                      @"<xf:insert ev:event=\"xforms-ready\" context=\"/data\" nodeset=\"item\" origin=\"proto\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLElement *root = [[p.model defaultInstance] documentElement];
    NSMutableArray *names = [NSMutableArray array];
    for (NSXMLNode *c in [root children]) {
        if ([c kind] == NSXMLElementKind) {
            [names addObject:[c name]];
        }
    }
    XCTAssertEqualObjects(names, (@[@"proto", @"a", @"b", @"proto"]));
}

- (void)testInsertAtNaNAppendsAfterLast
{
    // XForms 1.1 10.3 / XsltForms_insert: a non-numeric `at` means the
    // insert location is the last node of the nodeset (G-13)
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <item>Ada</item><item>Bob</item><item>Cid</item>"
                      @"</data></xf:instance>"
                      @"<xf:insert ev:event=\"xforms-ready\" nodeset=\"item\" at=\"'x'\" position=\"after\" origin=\"item[1]\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSArray *items = [self items:p];
    XCTAssertEqual(items.count, (NSUInteger)4);
    XCTAssertEqualObjects([XFXML stringValueOfNode:items[3]], @"Ada");
    XCTAssertEqualObjects([XFXML stringValueOfNode:items[2]], @"Cid");
}

- (void)testDeleteDisposesBindNodes
{
    // XsltForms_delete -> XsltForms_bind.disposeNode: deleted nodes leave
    // the bind's node list and MIP caches so later recalculations do not
    // touch detached nodes (G-16)
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <item>Ada</item><item>Bob</item>"
                      @"</data></xf:instance>"
                      @"<xf:bind id=\"b\" nodeset=\"item\" readonly=\"count(../item) = 1\"/>"
                      @"<xf:delete ev:event=\"xforms-ready\" nodeset=\"item\" at=\"1\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFBind *bind = [p.model bindWithIdentifier:@"b"];
    XCTAssertNotNil(bind);
    XCTAssertEqual([self items:p].count, (NSUInteger)1);
    XCTAssertEqual(bind.nodes.count, (NSUInteger)1);
    XCTAssertEqual([bind.nodes.firstObject parent], [[p.model defaultInstance] documentElement]);
    XCTAssertTrue([XFNodeState stateOnNode:[self items:p].firstObject].readonly);
}

@end
