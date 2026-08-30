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

- (void)testDispatchChildrenPropertiesDelayAndDefaultSubmitTarget // G-48
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><ev>ping</ev><who>Ada</who></data></xf:instance>"
                      @"<xf:submission id=\"s\" resource=\"http://example.test/none\" method=\"post\" replace=\"none\"/>"
                      @"<xf:dispatch id=\"d1\" ev:event=\"go\"><xf:name value=\"ev\"/><xf:targetid>m</xf:targetid>"
                      @"  <xf:property name=\"greeting\" value=\"concat('hi ', who)\"/><xf:property name=\"lit\">L</xf:property></xf:dispatch>"
                      @"<xf:setvalue id=\"h\" ev:event=\"ping\" ref=\"who\" value=\"concat(event('greeting'), '/', event('lit'))\"/>"
                      @"<xf:dispatch ev:event=\"sub\" name=\"xforms-submit\"/>"
                      @"<xf:action id=\"submitted\" ev:event=\"xforms-submit\"/>"
                      @"<xf:dispatch ev:event=\"later\" name=\"late\" targetid=\"m\" delay=\"20\"/>"
                      @"<xf:action id=\"late\" ev:event=\"late\"/>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    [XFXMLEvents dispatch:p.model name:@"go"];
    NSXMLElement *root = [[p defaultInstance] documentElement];
    XCTAssertEqualObjects([XFXML stringValueOfNode:[root elementsForName:@"who"].firstObject], @"hi Ada/L");
    // xforms-submit without a target goes to the model's default submission
    [XFXMLEvents dispatch:p.model name:@"sub"];
    XCTAssertTrue([[p actionWithIdentifier:@"submitted"] wasInvokedForEvent:@"xforms-submit"]);
    // @delay: dispatched later on the main queue
    [XFXMLEvents dispatch:p.model name:@"later"];
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"late"] invocationCount], (NSInteger)0);
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"late"] invocationCount], (NSInteger)1);
}

- (void)testSetvalueContextAndLiteralNormalisation // G-49
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><a>1</a><b><c>7</c></b><lit/></data></xf:instance>"
                      @"<xf:setvalue ev:event=\"xforms-ready\" ref=\"a\" context=\"b\" value=\"c\"/>"
                      @"<xf:setvalue ev:event=\"xforms-ready\" ref=\"lit\">  two   words\n </xf:setvalue>"
                      extra:nil error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLElement *root = [[p defaultInstance] documentElement];
    XCTAssertEqualObjects([XFXML stringValueOfNode:[root elementsForName:@"a"].firstObject], @"7");
    XCTAssertEqualObjects([XFXML stringValueOfNode:[root elementsForName:@"lit"].firstObject], @"two words");
}

- (void)testMessageLoadAndHelpHostHooks // G-50, G-51, G-62
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><who>Ada</who></data></xf:instance>"
                      @"<xf:message ev:event=\"say\" level=\"ephemeral\">Hello  <xf:output ref=\"who\"/> !</xf:message>"
                      @"<xf:load ev:event=\"open\" resource=\"http://example.test/page\" show=\"new\" target=\"t\"/>"
                      extra:
                      @"<xf:group id=\"t\"><xf:action id=\"loaded\" ev:event=\"xforms-load-done\"/>"
                      @"<xf:input id=\"i\" ref=\"who\"><xf:label>W</xf:label><xf:help>Type a name</xf:help></xf:input></xf:group>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    __block NSString *shown = nil, *shownLevel = nil;
    p.messageHandler = ^(NSString *text, NSString *level) { shown = text; shownLevel = level; };
    __block NSURL *opened = nil; __block NSString *how = nil;
    p.loadRequestHandler = ^BOOL(NSURL *url, NSString *show) { opened = url; how = show; return YES; };
    __block XFControl *helped = nil;
    p.helpRequestHandler = ^(XFControl *c) { helped = c; };

    [XFXMLEvents dispatch:p.model name:@"say"];
    XCTAssertEqualObjects(shown, @"Hello Ada !");
    XCTAssertEqualObjects(shownLevel, @"ephemeral");
    [XFXMLEvents dispatch:p.model name:@"open"];
    XCTAssertEqualObjects([opened absoluteString], @"http://example.test/page");
    XCTAssertEqualObjects(how, @"new");
    // load-done goes to the @target element, not the action
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"loaded"] invocationCount], (NSInteger)1);
    [XFXMLEvents dispatch:p.inputControls.firstObject name:@"xforms-help"];
    XCTAssertEqual(helped, p.inputControls.firstObject);
}

@end
