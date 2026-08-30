#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFAbstractAction.h>
#import <XFormsKit/XFSetvalueAction.h>
#import <XFormsKit/XFMessageAction.h>
#import <XFormsKit/XFDeferredUpdates.h>
#import <XFormsKit/XFXML.h>

@interface XFActionTests : XCTestCase
@end

@implementation XFActionTests

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

- (void)testSetvalueOnReadyWritesInstance
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      @"<xf:setvalue id=\"sv\" ev:event=\"xforms-ready\" ref=\"n\" value=\"'Bob'\"/>"
                          extra:@"<xf:output ref=\"n\"><xf:label>N</xf:label></xf:output>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertTrue([[p actionWithIdentifier:@"sv"] wasInvokedForEvent:@"xforms-ready"]);
    XCTAssertEqualObjects(p.outputControls.firstObject.stringValue, @"Bob");
}

- (void)testActionGroupRunsChildSetvalues
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><a/><b/></data></xf:instance>"
                      @"<xf:action id=\"grp\" ev:event=\"xforms-ready\">"
                      @"  <xf:setvalue ref=\"a\" value=\"'1'\"/>"
                      @"  <xf:setvalue ref=\"b\" value=\"'2'\"/>"
                      @"</xf:action>"
                          extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFAction *grp = (XFAction *)[p actionWithIdentifier:@"grp"];
    XCTAssertEqual(grp.children.count, (NSUInteger)2);
    NSXMLElement *root = [[p.model defaultInstance] documentElement];
    XCTAssertEqualObjects([XFXML stringValueOfNode:[root elementsForName:@"a"].firstObject], @"1");
    XCTAssertEqualObjects([XFXML stringValueOfNode:[root elementsForName:@"b"].firstObject], @"2");
}

- (void)testIfSkipsSetvalue
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      @"<xf:setvalue ev:event=\"xforms-ready\" ref=\"n\" value=\"'X'\" if=\"false()\"/>"
                          extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLNode *n = [[[p.model defaultInstance] documentElement] elementsForName:@"n"].firstObject;
    XCTAssertEqualObjects([XFXML stringValueOfNode:n], @"Ada");
}

- (void)testWhileIncrements
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>0</n></data></xf:instance>"
                      @"<xf:setvalue ev:event=\"xforms-ready\" ref=\"n\" while=\"number(n) &lt; 3\" value=\". + 1\"/>"
                          extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLNode *n = [[[p.model defaultInstance] documentElement] elementsForName:@"n"].firstObject;
    XCTAssertEqualObjects([XFXML stringValueOfNode:n], @"3");
}

- (void)testSetvalueLiteralContent
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n/></data></xf:instance>"
                      @"<xf:setvalue ev:event=\"xforms-ready\" ref=\"n\">hello</xf:setvalue>"
                          extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLNode *n = [[[p.model defaultInstance] documentElement] elementsForName:@"n"].firstObject;
    XCTAssertEqualObjects([XFXML stringValueOfNode:n], @"hello");
}

- (void)testMessageRecordsText
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      @"<xf:message id=\"msg\" ev:event=\"xforms-ready\" ref=\"n\"/>"
                          extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFMessageAction *msg = (XFMessageAction *)[p actionWithIdentifier:@"msg"];
    XCTAssertEqualObjects(msg.lastText, @"Ada");
    XCTAssertTrue([[XFDeferredUpdates sharedUpdates].messages containsObject:@"Ada"]);
}

- (void)testDispatchRebuild
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>1</n></data></xf:instance>"
                      @"<xf:action id=\"on-rebuild\" ev:event=\"xforms-rebuild\"/>"
                      @"<xf:dispatch id=\"go\" ev:event=\"xforms-ready\" name=\"xforms-rebuild\" targetid=\"m\"/>"
                          extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertTrue([[p actionWithIdentifier:@"go"] wasInvokedForEvent:@"xforms-ready"]);
    XCTAssertTrue([[p actionWithIdentifier:@"on-rebuild"] wasInvokedForEvent:@"xforms-rebuild"]);
}

- (void)testRebuildActionElement
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>1</n></data></xf:instance>"
                      @"<xf:action id=\"on-rebuild\" ev:event=\"xforms-rebuild\"/>"
                      @"<xf:rebuild id=\"rb\" ev:event=\"xforms-ready\"/>"
                          extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertTrue([[p actionWithIdentifier:@"rb"] wasInvokedForEvent:@"xforms-ready"]);
    XCTAssertTrue([[p actionWithIdentifier:@"on-rebuild"] wasInvokedForEvent:@"xforms-rebuild"]);
}

- (void)testSetvalueThenCalculate
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><price>10</price><qty>1</qty><total/></data></xf:instance>"
                      @"<xf:bind ref=\"total\" calculate=\"../price * ../qty\"/>"
                      @"<xf:setvalue ev:event=\"xforms-ready\" ref=\"qty\" value=\"'4'\"/>"
                          extra:@"<xf:output ref=\"total\"><xf:label>T</xf:label></xf:output>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertEqualObjects(p.outputControls.firstObject.stringValue, @"40");
}

@end
