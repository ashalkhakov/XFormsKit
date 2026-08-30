#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFDeferredUpdates.h>
#import <XFormsKit/XFNodeState.h>
#import <XFormsKit/XFAbstractAction.h>
#import <XFormsKit/XFInsertAction.h>
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
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    // Inside an action the change list holds the node and its ancestors
    // (XsltForms_model.addChange); it is emptied once the deferred update
    // cycle has refreshed the UI (XsltForms_globals.refresh) — G-01.
    [du openAction:@"test"];
    XFControl *input = p.inputControls.firstObject;
    XCTAssertTrue([input commitStringValue:@"Bob" error:&error]);
    [p.model addChange:input.boundNode];
    NSMutableSet *names = [NSMutableSet set];
    for (NSXMLNode *n in p.model.nodesChanged) {
        [names addObject:[n name]];
    }
    XCTAssertTrue([names containsObject:@"n"]);
    XCTAssertTrue([names containsObject:@"data"]);
    XCTAssertTrue([du.changedModels containsObject:p.model]);
    [du closeAction:@"test"];
    XCTAssertEqual(p.model.nodesChanged.count, (NSUInteger)0);
    XCTAssertEqual(du.changedModels.count, (NSUInteger)0);
    XCTAssertFalse(p.model.rebuilded);
}

- (void)testMIPsOnExistingNodesRecalculateAfterInsert // G-01
{
    NSError *error = nil;
    XFProcessor *p = [self processor:
                      @"<xf:instance><data xmlns=\"\"><item>a</item></data></xf:instance>"
                      @"<xf:bind nodeset=\"item\" required=\"count(../item) > 1\" relevant=\"count(../item) &lt; 3\"/>"
                      @"<xf:insert id=\"ins\" nodeset=\"item\" position=\"after\"/>"
                                          extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLElement *root = [[p.model defaultInstance] documentElement];
    NSXMLNode *first = [root elementsForName:@"item"].firstObject;
    XCTAssertFalse([XFNodeState existingStateOnNode:first].required);

    XFAbstractAction *insert = [p actionWithIdentifier:@"ins"];
    [insert runWithContextNode:root event:nil];
    XCTAssertEqual([root elementsForName:@"item"].count, (NSUInteger)2);
    // the MIP of the pre-existing first item depends on count(../item): it
    // must have been re-evaluated in the same rebuild cycle
    XCTAssertTrue([XFNodeState existingStateOnNode:first].required,
                  @"required MIP on the existing node must be recalculated after insert");
    XCTAssertTrue([XFNodeState existingStateOnNode:first].relevant);

    [insert runWithContextNode:root event:nil];
    XCTAssertEqual([root elementsForName:@"item"].count, (NSUInteger)3);
    XCTAssertFalse([XFNodeState existingStateOnNode:first].relevant);
    XCTAssertEqual(p.model.nodesChanged.count, (NSUInteger)0);
}

- (void)testRelevanceInheritanceIsReversible // G-02
{
    NSError *error = nil;
    XFProcessor *p = [self processor:
                      @"<xf:instance><data xmlns=\"\"><on>true</on><grp><leaf>x</leaf></grp></data></xf:instance>"
                      @"<xf:bind nodeset=\"grp\" relevant=\"../on = 'true'\" readonly=\"../on != 'true'\"/>"
                                          extra:@"<xf:input id=\"i\" ref=\"on\"><xf:label>on</xf:label></xf:input>"
                                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLElement *root = [[p.model defaultInstance] documentElement];
    NSXMLNode *leaf = [[root elementsForName:@"grp"].firstObject elementsForName:@"leaf"].firstObject;
    XFNodeState *(^st)(void) = ^{ return [XFNodeState existingStateOnNode:leaf]; };
    XCTAssertTrue(st() == nil || st().relevant);

    XFControl *input = p.inputControls.firstObject;
    XCTAssertTrue([p setValue:@"false" ofControl:input error:&error]);
    XCTAssertNotNil(st());
    XCTAssertFalse(st().relevant, @"unbound descendant inherits non-relevance");
    XCTAssertTrue(st().readonly, @"unbound descendant inherits readonly");

    XCTAssertTrue([p setValue:@"true" ofControl:input error:&error]);
    XCTAssertTrue(st().relevant, @"unbound descendant must become relevant again");
    XCTAssertFalse(st().readonly, @"unbound descendant must become writable again");
}

@end
