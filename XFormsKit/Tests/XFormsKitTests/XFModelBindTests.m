#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFBind.h>
#import <XFormsKit/XFNodeState.h>
#import <XFormsKit/XFXML.h>

@interface XFModelBindTests : XCTestCase
@end

@implementation XFModelBindTests

- (XFProcessor *)processor:(NSString *)innerModel extra:(NSString *)extra error:(NSError **)error
{
    NSString *xml =
        [NSString stringWithFormat:
         @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
         @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
         @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
         @"  <xf:model id=\"m\">%@</xf:model>%@"
         @"</html>", innerModel, extra ?: @""];
    return [XFProcessor processorWithXMLString:xml error:error];
}

- (void)testBindSelectsNodesAndAppliesType
{
    NSError *error = nil;
    XFProcessor *p = [self processor:
                      @"<xf:instance><data xmlns=\"\"><n>3</n><m>4</m></data></xf:instance>"
                      @"<xf:bind id=\"bn\" ref=\"n\" type=\"xf:integer\"/>"
                                          extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFBind *bind = [p.model bindWithIdentifier:@"bn"];
    XCTAssertEqual(bind.nodes.count, (NSUInteger)1);
    XCTAssertEqualObjects([XFXML stringValueOfNode:bind.nodes.firstObject], @"3");
    XCTAssertEqualObjects([XFNodeState existingStateOnNode:bind.nodes.firstObject].typeName, @"xf:integer");
}

- (void)testCalculateRunsDuringConstruct
{
    NSError *error = nil;
    XFProcessor *p = [self processor:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <price>10</price><qty>3</qty><total/>"
                      @"</data></xf:instance>"
                      @"<xf:bind ref=\"total\" calculate=\"../price * ../qty\"/>"
                                          extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLNode *total = [[[p.model defaultInstance] documentElement] elementsForName:@"total"].firstObject;
    XCTAssertEqualObjects([XFXML stringValueOfNode:total], @"30");
    XFNodeState *state = [XFNodeState existingStateOnNode:total];
    XCTAssertTrue(state.readonly, @"calculate implies readonly");
}

- (void)testAddChangeThenRecalculateUpdatesDependants
{
    NSError *error = nil;
    XFProcessor *p = [self processor:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <price>10</price><qty>3</qty><total/>"
                      @"</data></xf:instance>"
                      @"<xf:bind ref=\"total\" calculate=\"../price * ../qty\"/>"
                                          extra:
                      @"<xf:input ref=\"price\"><xf:label>P</xf:label></xf:input>"
                      @"<xf:output ref=\"total\"><xf:label>T</xf:label></xf:output>"
                                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertEqualObjects(p.outputControls.firstObject.stringValue, @"30");

    BOOL ok = [p setValue:@"4" ofControl:p.inputControls.firstObject error:&error];
    XCTAssertTrue(ok, @"%@", error);
    XCTAssertEqualObjects(p.outputControls.firstObject.stringValue, @"12");
}

- (void)testRelevantRequiredConstraintOnRevalidate
{
    NSError *error = nil;
    XFProcessor *p = [self processor:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <flag>true</flag><name></name>"
                      @"</data></xf:instance>"
                      @"<xf:bind ref=\"name\" relevant=\"../flag = 'true'\" required=\"true()\" constraint=\". != ''\"/>"
                                          extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLNode *name = [[[p.model defaultInstance] documentElement] elementsForName:@"name"].firstObject;
    XFNodeState *state = [XFNodeState existingStateOnNode:name];
    XCTAssertTrue(state.relevant);
    XCTAssertTrue(state.required);
    XCTAssertFalse(state.valid, @"empty required node is invalid");
    XCTAssertFalse(state.constraint);
}

- (void)testNestedBindUsesParentContext
{
    NSError *error = nil;
    XFProcessor *p = [self processor:
                      @"<xf:instance><data xmlns=\"\">"
                      @"  <item><a>2</a><b>5</b><sum/></item>"
                      @"</data></xf:instance>"
                      @"<xf:bind nodeset=\"item\">"
                      @"  <xf:bind ref=\"sum\" calculate=\"../a + ../b\"/>"
                      @"</xf:bind>"
                                          extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLNode *sum = [[[[[p.model defaultInstance] documentElement] elementsForName:@"item"] firstObject]
                      elementsForName:@"sum"].firstObject;
    XCTAssertEqualObjects([XFXML stringValueOfNode:sum], @"7");
}

- (void)testNodesChangedWalksAncestors
{
    NSError *error = nil;
    XFProcessor *p = [self processor:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                                          extra:@"<xf:input ref=\"n\"><xf:label>N</xf:label></xf:input>"
                                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    [p.model.nodesChanged removeAllObjects];
    [p setValue:@"Bob" ofControl:p.inputControls.firstObject error:&error];
    XCTAssertGreaterThan(p.model.nodesChanged.count, (NSUInteger)0);
    BOOL sawN = NO;
    for (NSXMLNode *n in p.model.nodesChanged) {
        if ([[n name] isEqualToString:@"n"]) {
            sawN = YES;
        }
    }
    XCTAssertTrue(sawN);
}

@end
