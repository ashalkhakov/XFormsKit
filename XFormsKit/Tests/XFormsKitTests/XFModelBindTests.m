#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFDeferredUpdates.h>
#import <XFormsKit/XFNodeState.h>
#import <XFormsKit/XFAbstractAction.h>
#import <XFormsKit/XFInsertAction.h>
#import <XFormsKit/XFBind.h>
#import <XFormsKit/XFNodeState.h>
#import <XFormsKit/XFXML.h>
#import <XFormsKit/XFBinding.h>
#import <XFormsKit/XFSelectControl.h>
#import <XFormsKit/XFErrors.h>

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
    // the type name is stored resolved against the bind's namespaces (G-57)
    XCTAssertEqualObjects([XFNodeState existingStateOnNode:bind.nodes.firstObject].typeName,
                          @"{http://www.w3.org/2002/xforms}integer");
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

#pragma mark - G-21 bind="id", G-22 model="id"

- (void)testBindAttributeOnControlSetvalueAndInsert // G-21
{
    NSError *error = nil;
    XFProcessor *p = [self processor:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n><item k=\"1\">a</item><item>b</item><item k=\"1\">c</item></data></xf:instance>"
                      @"<xf:bind id=\"outer\" nodeset=\".\"><xf:bind id=\"bn\" nodeset=\"n\"/></xf:bind>"
                      @"<xf:bind id=\"bk\" nodeset=\"item[@k='1']\"/>"
                      @"<xf:setvalue ev:event=\"xforms-ready\" bind=\"bn\" value=\"'Bob'\"/>"
                      @"<xf:insert ev:event=\"xforms-ready\" bind=\"bk\" position=\"after\"/>"
                      extra:
                      @"<xf:input id=\"in\" bind=\"bn\"><xf:label>N</xf:label></xf:input>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFControl *input = p.inputControls.firstObject;
    XCTAssertEqualObjects(input.binding.bindID, @"bn");
    XCTAssertEqualObjects(input.stringValue, @"Bob");
    // the insert used the bind's node list: the clone of the LAST bound
    // node (c) sits after it, not after the last <item> in document order
    NSXMLElement *root = [[p defaultInstance] documentElement];
    NSArray *items = [root elementsForName:@"item"];
    XCTAssertEqual(items.count, (NSUInteger)4);
    XCTAssertEqualObjects([XFXML stringValueOfNode:items[3]], @"c");
    XCTAssertEqualObjects([[(NSXMLElement *)items[3] attributeForName:@"k"] stringValue], @"1");
    XCTAssertTrue([p setValue:@"Cy" ofControl:input error:&error], @"%@", error);
    XCTAssertEqualObjects([XFXML stringValueOfNode:[root elementsForName:@"n"].firstObject], @"Cy");
}

- (void)testUnknownBindIsAnError // G-21
{
    NSError *error = nil;
    XFProcessor *p = [self processor:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      extra:@"<xf:output bind=\"nope\"/>"
                        error:&error];
    // the control exists but its refresh reports the missing bind
    XCTAssertNotNil(p);
    XCTAssertFalse([p refresh:&error]);
    XCTAssertEqual(error.code, (NSInteger)XFErrorBinding);
}

- (void)testModelAttributeSelectsModelForControlsActionsAndItemsets // G-22
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"  <xf:model id=\"m1\"><xf:instance><d xmlns=\"\"><n>one</n></d></xf:instance>"
        @"    <xf:setvalue ev:event=\"poke\" model=\"m2\" ref=\"n\" value=\"'changed'\"/>"
        @"  </xf:model>"
        @"  <xf:model id=\"m2\"><xf:instance><d xmlns=\"\"><n>two</n><opt>x</opt><opt>y</opt></d></xf:instance>"
        @"    <xf:bind id=\"b2\" nodeset=\"n\" readonly=\"true()\"/>"
        @"  </xf:model>"
        @"  <xf:output id=\"o1\" ref=\"n\"/>"
        @"  <xf:output id=\"o2\" model=\"m2\" ref=\"n\"/>"
        @"  <xf:output id=\"o3\" bind=\"b2\"/>"
        @"  <xf:select1 ref=\"n\"><xf:label>S</xf:label>"
        @"    <xf:itemset model=\"m2\" nodeset=\"opt\"><xf:label ref=\".\"/><xf:value ref=\".\"/></xf:itemset>"
        @"  </xf:select1>"
        @"</html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSArray<XFOutputControl *> *outs = p.outputControls;
    XCTAssertEqual(outs.count, (NSUInteger)3);
    XCTAssertEqualObjects(outs[0].stringValue, @"one");
    XCTAssertEqualObjects(outs[1].stringValue, @"two");
    XCTAssertEqualObjects(outs[2].stringValue, @"two");
    XCTAssertTrue(outs[2].readonly);
    XFSelectControl *sel = nil;
    for (XFControl *c in p.controls) {
        if ([c isKindOfClass:[XFSelectControl class]]) { sel = (XFSelectControl *)c; }
    }
    XCTAssertEqual(sel.items.count, (NSUInteger)2);
    XCTAssertEqualObjects(sel.items[1].value, @"y");
    // setvalue model="m2" writes m2's node; m2 is the model that gets
    // recalculated / refreshed
    [XFXMLEvents dispatch:p.model name:@"poke"];
    XCTAssertEqualObjects(outs[1].stringValue, @"changed");
    XCTAssertEqualObjects(outs[2].stringValue, @"changed");
    XCTAssertEqualObjects(outs[0].stringValue, @"one");
    XCTAssertEqualObjects([XFXML stringValueOfNode:[[[p.models[1] defaultInstance] documentElement] elementsForName:@"n"].firstObject], @"changed");
}

- (void)testModelWithoutInstanceGetsSynthesisedData // G-28
{
    NSError *error = nil;
    XFProcessor *p = [self processor:
                      @"<xf:setvalue ev:event=\"xforms-ready\" ref=\"name\" value=\"'Ada'\"/>"
                      extra:
                      @"<xf:input ref=\"name\"><xf:label>N</xf:label></xf:input>"
                      @"<xf:input ref=\"name\"><xf:label>Again</xf:label></xf:input>"
                      @"<xf:output ref=\"age\"/>"
                      @"<xf:output ref=\"a/b\"/>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertEqual(p.model.instances.count, (NSUInteger)1);
    XCTAssertEqualObjects(p.model.instances.firstObject.identifier, @"instance-default");
    NSXMLElement *root = [[p defaultInstance] documentElement];
    XCTAssertEqualObjects([root name], @"data");
    XCTAssertEqual([root elementsForName:@"name"].count, (NSUInteger)1);
    XCTAssertEqual([root elementsForName:@"age"].count, (NSUInteger)1);
    XCTAssertEqual([root elementsForName:@"a"].count, (NSUInteger)0);
    XCTAssertEqualObjects(p.inputControls.firstObject.stringValue, @"Ada");
    XCTAssertEqualObjects(p.inputControls[1].stringValue, @"Ada");
}

- (void)testInstanceResourceReadonlyAndForeignData // G-55
{
    NSString *csv = [XFInstance xmlStringFromCSV:@"name,age\n\"Ada, B\",36\nBob,40\n" separator:@"," header:YES];
    XCTAssertTrue([csv containsString:@"<exml:anonymous><name>Ada, B</name><age>36</age></exml:anonymous>"], @"%@", csv);
    NSString *json = [XFInstance xmlStringFromJSONData:[@"[1,2]" dataUsingEncoding:NSUTF8StringEncoding] error:NULL];
    XCTAssertTrue([json containsString:@"<exml:anonymous exsi:maxOccurs=\"unbounded\" xsi:type=\"xsd:double\">1</exml:anonymous>"], @"%@", json);

    NSError *error = nil;
    XFProcessor *p = [self processor:
                      @"<xf:instance><data xmlns=\"\"><n/></data></xf:instance>"
                      @"<xf:instance id=\"ro\" readonly=\"true\"><d xmlns=\"\"><v>x</v></d></xf:instance>"
                      @"<xf:instance id=\"res\" resource=\"file:///nonexistent/xfk.xml\" mediatype=\"text/csv; header=present; separator=%3B\"/>"
                      @"<xf:bind nodeset=\"instance('ro')/v\" required=\"true()\" constraint=\"false()\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFInstance *ro = [p.model instanceWithIdentifier:@"ro"];
    XCTAssertTrue(ro.readonly);
    // readonly instances are not validated: no state from the bind's MIPs
    XCTAssertTrue([XFNodeState existingStateOnNode:[[ro documentElement] elementsForName:@"v"].firstObject].valid);
    XFInstance *res = [p.model instanceWithIdentifier:@"res"];
    XCTAssertEqualObjects(res.src, @"file:///nonexistent/xfk.xml");
    XCTAssertEqualObjects(res.mediatype, @"text/csv");
    XCTAssertTrue(res.csvHeader);
    XCTAssertEqualObjects(res.csvSeparator, @";");
}

- (void)testInlineSchemaTypesAndBindTypeResolution // G-56, G-57
{
    [[[XFXMLEvents sharedEvents] exceptionMessages] removeAllObjects];
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" xmlns:my=\"urn:my\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">"
        @"<head><xf:model id=\"m\" schema=\"#sch missing.xsd\">"
        @"  <xs:schema id=\"sch\" targetNamespace=\"urn:my\" xmlns=\"urn:my\">"
        @"    <xs:simpleType name=\"color\"><xs:restriction base=\"xs:string\"><xs:enumeration value=\"red\"/><xs:enumeration value=\"blue\"/></xs:restriction></xs:simpleType>"
        @"    <xs:simpleType name=\"short\"><xs:restriction base=\"xs:string\"><xs:maxLength value=\"3\"/></xs:restriction></xs:simpleType>"
        @"    <xs:simpleType name=\"money\"><xs:restriction base=\"xs:decimal\"><xs:fractionDigits value=\"2\"/><xs:minExclusive value=\"0\"/></xs:restriction></xs:simpleType>"
        @"    <xs:simpleType name=\"colors\"><xs:list itemType=\"color\"/></xs:simpleType>"
        @"  </xs:schema>"
        @"  <xf:instance><data xmlns=\"\"><c>green</c><s>abcd</s><price>1</price><total/><cs>red blue</cs><typed xsi:type=\"xs:string\">x</typed></data></xf:instance>"
        @"  <xf:bind nodeset=\"c\" type=\"my:color\"/>"
        @"  <xf:bind nodeset=\"s\" type=\"my:short\"/>"
        @"  <xf:bind nodeset=\"price\" type=\"my:money\"/>"
        @"  <xf:bind nodeset=\"total\" type=\"my:money\" calculate=\"../price * 2\"/>"
        @"  <xf:bind nodeset=\"cs\" type=\"my:colors\"/>"
        @"  <xf:bind nodeset=\"typed\" type=\"xs:integer\"/>"
        @"  <xf:action id=\"link\" ev:event=\"xforms-link-exception\" xmlns:ev=\"http://www.w3.org/2001/xml-events\"/>"
        @"</xf:model></head><body/></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLElement *root = [[p defaultInstance] documentElement];
    XFNodeState *(^state)(NSString *) = ^XFNodeState *(NSString *name) {
        return [XFNodeState existingStateOnNode:[root elementsForName:name].firstObject];
    };
    XCTAssertFalse(state(@"c").valid);      // not in the enumeration
    XCTAssertFalse(state(@"s").valid);      // maxLength 3
    XCTAssertTrue(state(@"price").valid);
    XCTAssertTrue(state(@"cs").valid);      // list of colors
    XCTAssertEqualObjects(state(@"c").typeName, @"{urn:my}color");
    // calculate result normalised to the type's fractionDigits (G-57)
    XCTAssertEqualObjects([XFXML stringValueOfNode:[root elementsForName:@"total"].firstObject], @"2.00");
    // xsi:type on a bind-typed node is a binding exception; missing schema a link exception
    BOOL bindingEx = NO;
    for (NSString *m in [[XFXMLEvents sharedEvents] exceptionMessages]) {
        if ([m containsString:@"xsi:type"]) bindingEx = YES;
    }
    XCTAssertTrue(bindingEx);
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"link"] invocationCount], (NSInteger)1);
}

- (void)testDuplicateSchemaNamespaceAndXsiTypeNil // G-82, G-83
{
    [[[XFXMLEvents sharedEvents] exceptionMessages] removeAllObjects];
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">"
        @"<head><xf:model id=\"m\">"
        @"  <xs:schema targetNamespace=\"urn:dup\"><xs:simpleType name=\"a\"><xs:restriction base=\"xs:string\"/></xs:simpleType></xs:schema>"
        @"  <xs:schema targetNamespace=\"urn:dup\"><xs:simpleType name=\"b\"><xs:restriction base=\"xs:string\"/></xs:simpleType></xs:schema>"
        @"  <xf:instance><data xmlns=\"\">"
        @"    <n xsi:type=\"xs:integer\">12</n><bad xsi:type=\"xs:integer\">zz</bad>"
        @"    <nil xsi:nil=\"true\"/><notnil xsi:nil=\"true\">x</notnil>"
        @"    <bn xsi:nil=\"true\">3</bn>"
        @"  </data></xf:instance>"
        @"  <xf:bind nodeset=\"bn\" type=\"xs:integer\"/>"
        @"  <xf:action id=\"link\" ev:event=\"xforms-link-exception\" xmlns:ev=\"http://www.w3.org/2001/xml-events\"/>"
        @"</xf:model></head><body/></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"link"] invocationCount], (NSInteger)1);
    BOOL dup = NO;
    for (NSString *m in [[XFXMLEvents sharedEvents] exceptionMessages]) {
        if ([m containsString:@"More than one schema"]) dup = YES;
    }
    XCTAssertTrue(dup);
    NSXMLElement *root = [[p defaultInstance] documentElement];
    BOOL (^valid)(NSString *) = ^BOOL(NSString *name) {
        XFNodeState *st = [XFNodeState existingStateOnNode:[root elementsForName:name].firstObject];
        return st == nil || st.valid;
    };
    XCTAssertTrue(valid(@"n"));
    XCTAssertFalse(valid(@"bad"));      // unbound, typed by xsi:type
    XCTAssertTrue(valid(@"nil"));
    XCTAssertTrue(valid(@"notnil"));    // unbound: validate_ else-branch ignores xsi:nil
    XCTAssertFalse(valid(@"bn"));       // bound + nil: only empty is valid
}

@end
