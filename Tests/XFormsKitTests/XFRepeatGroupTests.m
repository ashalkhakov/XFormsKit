#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFGroup.h>
#import <XFormsKit/XFRepeat.h>
#import <XFormsKit/XFSwitch.h>
#import <XFormsKit/XFHostNode.h>
#import <XFormsKit/XFTableModel.h>
#import <XFormsKit/XFTriggerControl.h>
#import <XFormsKit/XFSetindexAction.h>
#import <XFormsKit/XFXML.h>
#import <XFormsKit/XFAbstractAction.h>
#import <XFormsKit/XFNamespaces.h>
#import <XFormsKit/XFXMLEvents.h>
#import <math.h>
#import <unistd.h>

/// Collects the names of every event the engine dispatches, so a test can
/// assert that a host-driven edit raises the same ones xf:insert and
/// xf:delete do.
@interface XFRepeatEventRecorder : NSObject <XFEventTraceSink>
@property (nonatomic, strong) NSMutableArray<NSString *> *names;
@end

@implementation XFRepeatEventRecorder

- (instancetype)init
{
    self = [super init];
    if (self) {
        _names = [NSMutableArray array];
    }
    return self;
}

- (void)traceEventOfKind:(XFTraceKind)kind
                 message:(NSString *)message
               eventName:(NSString *)eventName
                 element:(XFXMLElement *)element
{
    (void)kind; (void)message; (void)element;
    if (eventName.length) {
        [self.names addObject:eventName];
    }
}

@end

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

#pragma mark - host-driven add / remove (G-20)

- (XFProcessor *)threeItemRepeatForm
{
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\">"
        @"  <item><name>one</name></item>"
        @"  <item><name>two</name></item>"
        @"  <item><name>three</name></item>"
        @"</data></xf:instance>"
        extra:
        @"<xf:repeat id=\"r\" nodeset=\"item\">"
        @"  <xf:input ref=\"name\"><xf:label>Name</xf:label></xf:input>"
        @"</xf:repeat>" error:&error];
    XCTAssertNotNil(p, @"%@", error);
    return p;
}

- (XFRepeat *)repeatIn:(XFProcessor *)p
{
    for (XFControl *c in p.controls) {
        if ([c isKindOfClass:[XFRepeat class]]) { return (XFRepeat *)c; }
    }
    return nil;
}

- (NSArray<NSString *> *)namesIn:(XFProcessor *)p
{
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (XFXMLNode *item in [[[p.model defaultInstance] documentElement] elementsForName:@"item"]) {
        [names addObject:[XFXML stringValueOfNode:
            [(XFXMLElement *)item elementsForName:@"name"].firstObject]];
    }
    return names;
}

- (void)testHostDeleteRemovesThatItemOnly
{
    XFProcessor *p = [self threeItemRepeatForm];
    XFRepeat *repeat = [self repeatIn:p];
    XCTAssertEqual(repeat.items.count, (NSUInteger)3);
    XCTAssertTrue([repeat deleteItemAtPosition:2]);
    XCTAssertEqualObjects([self namesIn:p], (@[ @"one", @"three" ]));
    // the repeat re-read its nodeset, so the rows a host draws follow
    XCTAssertEqual(repeat.items.count, (NSUInteger)2);
    XCTAssertEqual(repeat.nodes.count, (NSUInteger)2);
}

- (void)testHostInsertCopiesTheItemAfterIt
{
    XFProcessor *p = [self threeItemRepeatForm];
    XFRepeat *repeat = [self repeatIn:p];
    XCTAssertTrue([repeat insertItemAfterPosition:1]);
    // a copy of the node, in place, the way xf:insert with no @origin
    // copies rather than inventing an empty one
    XCTAssertEqualObjects([self namesIn:p], (@[ @"one", @"one", @"two", @"three" ]));
    XCTAssertEqual(repeat.items.count, (NSUInteger)4);
    // and the index follows the new item, as after xf:insert
    XCTAssertEqual(repeat.index, (NSUInteger)2);
}

- (void)testHostEditsDispatchTheInsertAndDeleteEvents
{
    XFProcessor *p = [self threeItemRepeatForm];
    XFRepeat *repeat = [self repeatIn:p];
    XFRepeatEventRecorder *recorder = [[XFRepeatEventRecorder alloc] init];
    [XFXMLEvents setTraceSink:recorder];
    XCTAssertTrue([repeat insertItemAfterPosition:3]);
    XCTAssertTrue([repeat deleteItemAtPosition:4]);
    [XFXMLEvents setTraceSink:nil];
    // the same notifications a form's own xf:insert / xf:delete raise, so
    // a form listening for them sees the host's gesture too
    XCTAssertTrue([recorder.names containsObject:@"xforms-insert"], @"%@", recorder.names);
    XCTAssertTrue([recorder.names containsObject:@"xforms-delete"], @"%@", recorder.names);
}

- (void)testHostEditsRejectAPositionOutsideTheNodeset
{
    XFProcessor *p = [self threeItemRepeatForm];
    XFRepeat *repeat = [self repeatIn:p];
    XCTAssertFalse([repeat deleteItemAtPosition:0]);
    XCTAssertFalse([repeat deleteItemAtPosition:4]);
    XCTAssertFalse([repeat insertItemAfterPosition:0]);
    XCTAssertFalse([repeat insertItemAfterPosition:9]);
    XCTAssertEqualObjects([self namesIn:p], (@[ @"one", @"two", @"three" ]));
}

- (void)testDeletingEveryItemLeavesAnEmptyRepeat
{
    XFProcessor *p = [self threeItemRepeatForm];
    XFRepeat *repeat = [self repeatIn:p];
    XCTAssertTrue([repeat deleteItemAtPosition:3]);
    XCTAssertTrue([repeat deleteItemAtPosition:2]);
    XCTAssertTrue([repeat deleteItemAtPosition:1]);
    XCTAssertEqual(repeat.items.count, (NSUInteger)0);
    XCTAssertEqual(repeat.index, (NSUInteger)0);   // 0 means "no item"
    // and the form can be built back up again
    XCTAssertFalse([repeat insertItemAfterPosition:1]);
}

- (void)testValuesEditedAfterAHostInsertGoToTheRightNode
{
    XFProcessor *p = [self threeItemRepeatForm];
    XFRepeat *repeat = [self repeatIn:p];
    XCTAssertTrue([repeat insertItemAfterPosition:1]);
    // the second item's input now binds the COPY: editing it must not
    // write through to the original
    XFControl *second = repeat.items[1].controls.firstObject;
    NSError *error = nil;
    XCTAssertTrue([p setValue:@"copy" ofControl:second error:&error], @"%@", error);
    XCTAssertEqualObjects([self namesIn:p], (@[ @"one", @"copy", @"two", @"three" ]));
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

#pragma mark - G-20: controls nested in host markup

- (void)testGroupInstantiatesControlsInsideHostMarkup
{
    // group.xsl copies host markup and emits controls in place: a control
    // inside <fieldset><p> still belongs to the group and sees its context
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><item><name>Ada</name></item></data></xf:instance>"
                      extra:
                      @"<xf:group id=\"g\" ref=\"item\">"
                      @"  <fieldset><legend>Person</legend>"
                      @"    <p>Name: <xf:output id=\"o\" ref=\"name\"/> !</p>"
                      @"  </fieldset>"
                      @"</xf:group>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFGroup *g = p.groups.firstObject;
    XCTAssertEqual(g.children.count, (NSUInteger)1);
    XCTAssertEqualObjects(g.children.firstObject.stringValue, @"Ada");
    XCTAssertEqual(g.children.firstObject.parentControl, g);
    XCTAssertEqualObjects([g.hostNodes.firstObject treeDescription],
                          @"block:fieldset title=\"Person\"\n"
                          @"  block:p\n"
                          @"    text:\"Name: \"\n"
                          @"    control:output\n"
                          @"    text:\" !\"\n");
    XCTAssertEqualObjects([g.hostNodes.firstObject textContent], @"Name: Ada !");
}

- (void)testRepeatInstantiatesControlsInsideTableRows
{
    // XsltForms_repeat.build_ clones the whole content per node: the
    // balance-table pattern <xf:repeat><tr><td><xf:input/> (G-20)
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><r><a>1</a><b>x</b></r><r><a>2</a><b>y</b></r></data></xf:instance>"
                      extra:
                      @"<table><tbody>"
                      @"<xf:repeat id=\"rep\" nodeset=\"r\">"
                      @"  <tr><td><xf:input ref=\"a\"><xf:label>A</xf:label></xf:input></td>"
                      @"      <td><xf:output ref=\"b\"/></td></tr>"
                      @"</xf:repeat>"
                      @"</tbody></table>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFRepeat *rep = nil;
    for (XFControl *c in p.controls) {
        if ([c isKindOfClass:[XFRepeat class]]) { rep = (XFRepeat *)c; }
    }
    XCTAssertNotNil(rep);
    XCTAssertEqual(rep.items.count, (NSUInteger)2);
    XFRepeatItem *second = rep.items[1];
    XCTAssertEqual(second.controls.count, (NSUInteger)2);
    XCTAssertEqualObjects(second.controls[0].stringValue, @"2");
    XCTAssertEqualObjects(second.controls[1].stringValue, @"y");
    XCTAssertEqual(second.controls[0].parentControl, rep);
    XCTAssertEqual(second.hostNodes.count, (NSUInteger)1);
    XCTAssertEqual(second.hostNodes.firstObject.kind, XFHostNodeKindTableRow);
    XCTAssertEqual(second.hostNodes.firstObject.children.count, (NSUInteger)2);
    // the document tree: table > tbody > control:repeat
    XCTAssertEqualObjects([p.hostNodes.firstObject treeDescription],
                          @"table:table\n  section:tbody\n    control:repeat\n");
    XCTAssertEqual(p.inputControls.count, (NSUInteger)2);
}

- (void)testCaseInstantiatesControlsInsideHostMarkup
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
                      extra:
                      @"<xf:switch><xf:case id=\"c1\"><div><span>Hi <xf:output ref=\"n\"/></span></div></xf:case></xf:switch>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFSwitch *sw = (XFSwitch *)p.controls.firstObject;
    XCTAssertTrue([sw isKindOfClass:[XFSwitch class]]);
    XFCase *c = sw.cases.firstObject;
    XCTAssertEqual(c.children.count, (NSUInteger)1);
    XCTAssertEqualObjects(c.children.firstObject.stringValue, @"Ada");
    XCTAssertEqualObjects([c.hostNodes.firstObject treeDescription],
                          @"block:div\n  inline:span\n    text:\"Hi \"\n    control:output\n");
}

- (void)testHostDocumentKeepsWhitespaceOnlyTextNodes
{
    // The host tree needs "<b>x</b> <i>y</i>" to keep its space, like the
    // browser DOM XSLTForms works on. libxml2-based NSXMLDocuments dropped
    // whitespace-only text in element content whatever the options, which
    // is why the parser used to be handed marker comments; XFDOM keeps the
    // text nodes when asked to preserve whitespace, so the document that
    // comes back is the document that went in.
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"<head><xf:model><xf:instance><d xmlns=\"\"><n>1</n></d></xf:instance></xf:model></head>"
        @"<body><p><b>x</b> <i>y</i></p></body></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSString *serialized = [p.hostDocument XMLString];
    XCTAssertNotEqual([serialized rangeOfString:@"<b>x</b> <i>y</i>"].location,
                      (NSUInteger)NSNotFound, @"the gap survives serialisation: %@", serialized);
    XCTAssertEqual([serialized rangeOfString:@"xf:ws"].location, (NSUInteger)NSNotFound,
                   @"and nothing was inserted to carry it");
    XCTAssertEqualObjects([p.hostNodes.firstObject treeDescription],
                          @"block:p\n  inline:b\n    text:\"x\"\n  text:\" \"\n  inline:i\n    text:\"y\"\n");
}

- (void)testHostTreeKeepsBodyMarkupAndSkipsHead
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"<head><title>T</title><xf:model><xf:instance><d xmlns=\"\"><n>1</n></d></xf:instance></xf:model></head>"
        @"<body><h2>Title</h2><p>Value <b>is</b> <xf:output ref=\"n\"/><br/>next</p>"
        @"<pre>  keep   this </pre><hr/><ul><li>one</li></ul>"
        @"<svg xmlns=\"http://www.w3.org/2000/svg\"><text><xf:output ref=\"n\"/></text></svg></body></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertEqualObjects([p.hostRootElement localName], @"body");
    NSMutableString *dump = [NSMutableString string];
    for (XFHostNode *n in p.hostNodes) {
        [dump appendString:[n treeDescription]];
    }
    XCTAssertEqualObjects(dump,
        @"block:h2\n  text:\"Title\"\n"
        @"block:p\n  text:\"Value \"\n  inline:b\n    text:\"is\"\n  text:\" \"\n  control:output\n  br:br\n  text:\"next\"\n"
        @"block:pre\n  text:\"  keep   this \"\n"
        @"hr:hr\n"
        @"block:ul\n  block:li\n    text:\"one\"\n"
        @"svg:svg\n  inline:text\n    control:output\n");
    XCTAssertEqual(p.hostNodes[1].headingLevel, (NSInteger)0);
    XCTAssertEqual(p.hostNodes[0].headingLevel, (NSInteger)2);
    XCTAssertEqual(p.outputControls.count, (NSUInteger)2);
    XCTAssertTrue([p.hostNodes[1].children[3] isInlineLevel]);
}

#pragma mark - G-20 phase 2: table model

- (void)testTableModelRowsFromRepeatAndFooter
{
    // balance-table pattern: repeat over <tr> in tbody, tfoot with colspan,
    // no thead -> column titles from the first row's control labels
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><t><d>a</d><n>1</n></t><t><d>b</d><n>2</n></t><sum>3</sum></data></xf:instance>"
                      extra:
                      @"<table><tbody>"
                      @"<xf:repeat id=\"rep\" nodeset=\"t\">"
                      @"  <tr><td><xf:input ref=\"d\"><xf:label>Desc</xf:label></xf:input></td>"
                      @"      <td><xf:output ref=\"n\"><xf:label>N</xf:label></xf:output></td>"
                      @"      <td><xf:trigger><xf:label>X</xf:label></xf:trigger></td></tr>"
                      @"</xf:repeat>"
                      @"</tbody><tfoot><tr><td colspan=\"2\">Total</td><td><xf:output ref=\"sum\"/></td></tr></tfoot></table>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFHostNode *tableNode = p.hostNodes.firstObject;
    XCTAssertEqual(tableNode.kind, XFHostNodeKindTable);
    XFTableModel *m = [XFTableModel modelWithTableNode:tableNode];
    XCTAssertEqual(m.columnCount, (NSUInteger)3);
    XCTAssertEqualObjects(m.columnTitles, (@[@"Desc", @"N", @""]));
    XCTAssertEqual(m.rows.count, (NSUInteger)3);
    XCTAssertEqual(m.headerRows.count, (NSUInteger)0);
    XFTableRow *r1 = m.rows[1];
    XCTAssertNotNil(r1.repeat);
    XCTAssertEqual(r1.repeatItem.position, (NSUInteger)2);
    XCTAssertEqualObjects(r1.cells[0].control.stringValue, @"b");
    XCTAssertEqualObjects(r1.cells[1].control.stringValue, @"2");
    XCTAssertTrue([r1.cells[2].control isKindOfClass:[XFTriggerControl class]]);
    XFTableRow *foot = m.rows[2];
    XCTAssertTrue(foot.footer);
    XCTAssertNil(foot.repeat);
    XCTAssertEqual(foot.cells[0].colspan, (NSUInteger)2);
    XCTAssertNil(foot.cells[0].control);
    XCTAssertEqualObjects(foot.cells[0].text, @"Total");
    XCTAssertEqual([foot cellAtColumn:1], foot.cells[0]);
    XCTAssertEqual([foot cellAtColumn:2].column, (NSUInteger)2);
    XCTAssertEqualObjects([foot cellAtColumn:2].control.stringValue, @"3");
    XCTAssertEqual([m selectedRow], m.rows[0]);
}

- (void)testTableModelHeaderRowGivesTitlesAndMixedCellsAreText
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>7</n></data></xf:instance>"
                      extra:
                      @"<table><thead><tr><th>Key</th><th>Value</th></tr></thead>"
                      @"<tr><td>Raw: </td><td>n = <xf:output ref=\"n\"/></td></tr>"
                      @"<tr><th>Bold</th><td><xf:output ref=\"n\"/></td></tr></table>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFTableModel *m = [XFTableModel modelWithTableNode:p.hostNodes.firstObject];
    XCTAssertEqualObjects(m.columnTitles, (@[@"Key", @"Value"]));
    XCTAssertEqual(m.headerRows.count, (NSUInteger)1);
    XCTAssertEqual(m.rows.count, (NSUInteger)2);
    XCTAssertNil(m.rows[0].cells[1].control);
    XCTAssertEqualObjects(m.rows[0].cells[1].text, @"n = 7");
    XCTAssertEqual(m.rows[0].cells[1].controls.count, (NSUInteger)1);
    XCTAssertTrue(m.rows[1].cells[0].header);
    XCTAssertFalse(m.rows[1].header);
    XCTAssertEqualObjects(m.rows[1].cells[1].control.stringValue, @"7");
    XCTAssertNil([m selectedRow]);
}

- (void)testRepeatIndexFollowsNodeAfterRebuild // G-27
{
    // the first item turns non-relevant: the nodeset shrinks in front of
    // the current node; the index follows the node (XsltForms_repeat
    // build_), it does not keep the number (which would now mean "c")
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><item>a</item><item>b</item><item>c</item><hide>0</hide></data></xf:instance>"
                      @"<xf:bind nodeset=\"item[1]\" relevant=\"../hide = '0'\"/>"
                      @"<xf:setindex ev:event=\"pick\" repeat=\"r\" index=\"2\"/>"
                      @"<xf:setvalue ev:event=\"hide\" ref=\"hide\" value=\"'1'\"/>"
                      extra:@"<xf:repeat id=\"r\" nodeset=\"item\"><xf:output ref=\".\"/></xf:repeat>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFRepeat *r = p.repeats.firstObject;
    [XFXMLEvents dispatch:p.model name:@"pick"];
    XCTAssertEqual(r.index, (NSUInteger)2);
    XFXMLNode *b = [r currentNode];
    XCTAssertEqualObjects([XFXML stringValueOfNode:b], @"b");
    [XFXMLEvents dispatch:p.model name:@"hide"];
    XCTAssertEqual(r.items.count, (NSUInteger)2);
    XCTAssertEqual([r currentNode], b);
    XCTAssertEqual(r.index, (NSUInteger)1);
}

- (void)testNonRelevantGroupStillRefreshesChildren // G-29
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><g><n>Ada</n></g><other>x</other><show>0</show></data></xf:instance>"
                      @"<xf:bind nodeset=\"g\" relevant=\"../show = '1'\"/>"
                      @"<xf:setvalue ev:event=\"poke\" ref=\"g/n\" value=\"'Bob'\"/>"
                      @"<xf:setvalue ev:event=\"poke\" ref=\"other\" value=\"'y'\"/>"
                      extra:
                      @"<xf:group ref=\"g\">"
                      @"  <xf:output id=\"o\" ref=\"n\"><xf:action id=\"chg\" ev:event=\"xforms-value-changed\"/></xf:output>"
                      @"  <xf:output id=\"o2\" ref=\"../other\"/>"
                      @"</xf:group>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFGroup *g = p.groups.firstObject;
    XCTAssertFalse(g.relevant);
    NSArray<XFOutputControl *> *outs = p.outputControls;
    XCTAssertEqualObjects(outs[0].stringValue, @"Ada");
    XCTAssertFalse(outs[0].relevant);   // inherited from g
    XCTAssertTrue(outs[1].relevant);    // bound outside g
    [XFXMLEvents dispatch:p.model name:@"poke"];
    XCTAssertEqualObjects(outs[0].stringValue, @"Bob");
    XCTAssertEqualObjects(outs[1].stringValue, @"y");
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"chg"] invocationCount], (NSInteger)1);
}

- (void)testRepeatFromToStep // G-91
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n>2</n></data></xf:instance>"
                      extra:
                      @"<xf:repeat id=\"r\" from=\"1\" to=\"7\" step=\"3\">"
                      @"  <xf:output value=\".\"><xf:label>N</xf:label></xf:output>"
                      @"  <xf:output value=\". * 2\"><xf:label>D</xf:label></xf:output>"
                      @"</xf:repeat>"
                      @"<xf:repeat id=\"r2\" from=\"1\" to=\"n\">"
                      @"  <xf:output value=\".\"><xf:label>N</xf:label></xf:output>"
                      @"</xf:repeat>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFRepeat *r = [p repeatWithIdentifier:@"r"];
    XCTAssertEqual(r.items.count, (NSUInteger)3);
    XCTAssertEqualObjects([(XFOutputControl *)r.items[0].controls[0] stringValue], @"1");
    XCTAssertEqualObjects([(XFOutputControl *)r.items[1].controls[0] stringValue], @"4");
    XCTAssertEqualObjects([(XFOutputControl *)r.items[2].controls[0] stringValue], @"7");
    XCTAssertEqualObjects([(XFOutputControl *)r.items[2].controls[1] stringValue], @"14");
    // @to may be an expression over the instance
    XCTAssertEqual([p repeatWithIdentifier:@"r2"].items.count, (NSUInteger)2);
}

- (void)testIncludeSrcInlinesDocument // G-92
{
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"xfinc-%d", (int)getpid()]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *part =
        @"<div xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"<xf:output id=\"inc\" ref=\"n\"><xf:label>N</xf:label></xf:output></div>";
    [part writeToFile:[dir stringByAppendingPathComponent:@"part.xml"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @" xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"<head><xf:model><xf:instance><data xmlns=\"\"><n>42</n></data></xf:instance>"
        @"<xf:action id=\"link\" ev:event=\"xforms-link-exception\"/></xf:model></head>"
        @"<body><xf:include src=\"part.xml\"/><xf:include src=\"missing.xml\"/></body></html>";
    NSString *main = [dir stringByAppendingPathComponent:@"main.xhtml"];
    [xml writeToFile:main atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithContentsOfURL:[NSURL fileURLWithPath:main] error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertEqual(p.outputControls.count, (NSUInteger)1);
    XCTAssertEqualObjects(p.outputControls.firstObject.stringValue, @"42");
    XCTAssertEqual([XFXML elementsWithLocalName:@"include" namespaceURI:XFXFormsNamespaceURI inNode:p.hostDocument].count, (NSUInteger)0);
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"link"] invocationCount], (NSInteger)1);
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
}

- (void)testSubformLoadEmbedAndUnload // G-90
{
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"xfsub-%d", (int)getpid()]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *sub =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @" xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"<head><xf:model id=\"subm\"><xf:instance id=\"sdatai\"><sdata xmlns=\"\"><s>sub</s><ctx/></sdata></xf:instance>"
        @"  <xf:action id=\"subready\" ev:event=\"xforms-subform-ready\">"
        @"    <xf:setvalue ref=\"ctx\" value=\"subform-context()\"/></xf:action>"
        @"  <xf:action id=\"second\" ev:event=\"xforms-subform-ready\"/>"
        @"</xf:model></head>"
        // relative refs INHERIT the embedding context (XsltForms_globals.
        // build: one ctx chain across the whole DOM) — the subform's own
        // data is reached through instance('id')/subform-instance()
        @"<body><xf:output id=\"so\" value=\"instance('sdatai')/s\"><xf:label>S</xf:label></xf:output>"
        @"<xf:output id=\"si\" value=\"name(subform-instance())\"><xf:label>I</xf:label></xf:output>"
        @"<xf:output id=\"sc\" value=\"instance('sdatai')/ctx\"><xf:label>C</xf:label></xf:output>"
        @"<xf:output id=\"sinh\" ref=\".\"><xf:label>H</xf:label></xf:output>"
        @"<xf:trigger id=\"bye\"><xf:label>Bye</xf:label><xf:unload ev:event=\"DOMActivate\"/></xf:trigger></body></html>";
    [sub writeToFile:[dir stringByAppendingPathComponent:@"sub.xhtml"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSString *main =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @" xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"<head><xf:model><xf:instance><data xmlns=\"\"><n>main</n><slot>here</slot></data></xf:instance>"
        @"</xf:model></head>"
        @"<body><xf:output id=\"mo\" ref=\"n\"><xf:label>N</xf:label></xf:output>"
        @"<xf:group id=\"slot\" ref=\"slot\"><xf:label>Slot</xf:label><xf:output id=\"old\" ref=\".\"><xf:label>O</xf:label></xf:output></xf:group>"
        @"<xf:trigger id=\"go\"><xf:label>Go</xf:label><xf:load ev:event=\"DOMActivate\" show=\"embed\" targetid=\"slot\" resource=\"sub.xhtml\"/></xf:trigger>"
        @"<xf:trigger id=\"bad\"><xf:label>Bad</xf:label><xf:load ev:event=\"DOMActivate\" show=\"embed\" targetid=\"slot\" resource=\"nope.xhtml\"/></xf:trigger>"
        @"<xf:action id=\"loaded\" ev:event=\"xforms-load-done\" ev:observer=\"slot\"/>"
        @"<xf:action id=\"linkerr\" ev:event=\"xforms-link-exception\" ev:observer=\"slot\"/>"
        @"</body></html>";
    NSString *path = [dir stringByAppendingPathComponent:@"main.xhtml"];
    [main writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertEqual(p.models.count, (NSUInteger)1);
    XCTAssertEqual(p.outputControls.count, (NSUInteger)2);

    [(XFTriggerControl *)[p controlWithIdentifier:@"go"] activate];
    XCTAssertEqual(p.subforms.count, (NSUInteger)1);
    XCTAssertEqual(p.models.count, (NSUInteger)2);
    XFSubform *sf = p.subforms.firstObject;
    XCTAssertTrue(sf.ready);
    XCTAssertEqualObjects(sf.defaultModel.identifier, @"subm");
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"subready"] invocationCount], (NSInteger)1);
    // Listener.js: only the first xforms-subform-ready listener per observer
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"second"] invocationCount], (NSInteger)0);
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"loaded"] invocationCount], (NSInteger)1);
    XCTAssertNil([p controlWithIdentifier:@"old"], @"the target's previous content is replaced");
    XCTAssertEqualObjects([p controlWithIdentifier:@"mo"].stringValue, @"main");
    XCTAssertEqualObjects([p controlWithIdentifier:@"so"].stringValue, @"sub", @"instance('id') reaches the subform model");
    XCTAssertEqualObjects([p controlWithIdentifier:@"si"].stringValue, @"sdata");
    XCTAssertEqualObjects([p controlWithIdentifier:@"sc"].stringValue, @"here", @"subform-context() is the target's bound node");
    XCTAssertEqualObjects([p controlWithIdentifier:@"sinh"].stringValue, @"here", @"relative refs inherit the embedding context");
    XCTAssertEqual([(XFGroup *)[p controlWithIdentifier:@"slot"] children].count, (NSUInteger)5);

    // loading again replaces the subform; a missing document is a link exception
    [(XFTriggerControl *)[p controlWithIdentifier:@"go"] activate];
    XCTAssertEqual(p.subforms.count, (NSUInteger)1);
    XCTAssertEqual(p.models.count, (NSUInteger)2);
    [(XFTriggerControl *)[p controlWithIdentifier:@"bad"] activate];
    XCTAssertEqual([(XFAction *)[p actionWithIdentifier:@"linkerr"] invocationCount], (NSInteger)1);

    // xf:unload from inside the subform
    [(XFTriggerControl *)[p controlWithIdentifier:@"bye"] activate];
    XCTAssertEqual(p.subforms.count, (NSUInteger)0);
    XCTAssertEqual(p.models.count, (NSUInteger)1);
    XCTAssertNil([p controlWithIdentifier:@"so"]);
    XCTAssertEqual([(XFGroup *)[p controlWithIdentifier:@"slot"] children].count, (NSUInteger)0);
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
}

- (void)testSubformPerRepeatItemScoping // writers.xhtml
{
    // One shared <group id="sub"/> template inside a repeat: each item's
    // load must open ITS OWN subform there (XSLTForms clones the content
    // per item, so its IdManager resolves the targetid per clone)
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"xfsubrep-%d", (int)getpid()]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    // sub.xhtml mirrors books.xhtml: its own model exists, but the repeat
    // inherits the embedding context — each writer's OWN books render
    NSString *sub =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"<head><xf:model><xf:instance><b xmlns=\"\"><book t=\"static\"/></b></xf:instance></xf:model></head>"
        @"<body><xf:repeat nodeset=\"book\">"
        @"<xf:output id=\"bt\" value=\"@t\"><xf:label>T</xf:label></xf:output>"
        @"</xf:repeat></body></html>";
    [sub writeToFile:[dir stringByAppendingPathComponent:@"sub.xhtml"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSString *main =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @" xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"<head><xf:model><xf:instance><data xmlns=\"\">"
        @"<w><book t=\"a1\"/><book t=\"a2\"/></w>"
        @"<w><book t=\"b1\"/></w>"
        @"<w/></data></xf:instance>"
        @"</xf:model></head>"
        @"<body><xf:repeat id=\"r\" ref=\"w\">"
        @"<xf:trigger id=\"show\"><xf:label>Show</xf:label>"
        @"<xf:load ev:event=\"DOMActivate\" show=\"embed\" targetid=\"sub\" resource=\"sub.xhtml\"/></xf:trigger>"
        @"<xf:trigger id=\"hide\"><xf:label>Hide</xf:label>"
        @"<xf:unload ev:event=\"DOMActivate\" targetid=\"sub\"/></xf:trigger>"
        @"<xf:group id=\"sub\"/>"
        @"</xf:repeat></body></html>";
    NSString *path = [dir stringByAppendingPathComponent:@"main.xhtml"];
    [main writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFRepeat *rep = (XFRepeat *)[p controlWithIdentifier:@"r"];
    XCTAssertTrue([rep isKindOfClass:[XFRepeat class]]);
    XCTAssertEqual(rep.items.count, (NSUInteger)3);

    XFGroup *(^groupIn)(NSUInteger) = ^XFGroup *(NSUInteger i) {
        for (XFControl *c in rep.items[i].controls) {
            if ([c isKindOfClass:[XFGroup class]]) return (XFGroup *)c;
        }
        return nil;
    };
    XFTriggerControl *(^trig)(NSUInteger, NSString *) = ^XFTriggerControl *(NSUInteger i, NSString *ident) {
        for (XFControl *c in rep.items[i].controls) {
            if ([c isKindOfClass:[XFTriggerControl class]] && [c.identifier isEqualToString:ident]) {
                return (XFTriggerControl *)c;
            }
        }
        return nil;
    };
    NSString *(^bookIn)(NSUInteger) = ^NSString *(NSUInteger i) {
        XFControl *c = groupIn(i).children.firstObject;
        if (![c isKindOfClass:[XFRepeat class]]) {
            return nil;
        }
        NSMutableArray *titles = [NSMutableArray array];
        for (XFRepeatItem *it in [(XFRepeat *)c items]) {
            for (XFControl *b in it.controls) {
                if ([b.identifier isEqualToString:@"bt"]) {
                    [titles addObject:b.stringValue ?: @""];
                }
            }
        }
        return titles.count ? [titles componentsJoinedByString:@","] : nil;
    };
    for (NSUInteger i = 0; i < 3; i++) {
        XCTAssertEqual(groupIn(i).children.count, (NSUInteger)0);
    }

    // load into item 2's context: only item 2 shows content, and the
    // subform's repeat inherits the ITEM context — writer 2's own books
    [trig(1, @"show") activate];
    XCTAssertEqual(p.subforms.count, (NSUInteger)1);
    XCTAssertEqual(p.subforms.firstObject.ownerNode, rep.nodes[1]);
    XCTAssertEqual(p.models.count, (NSUInteger)2);
    XCTAssertNil(bookIn(0));
    XCTAssertEqualObjects(bookIn(1), @"b1");
    XCTAssertNil(bookIn(2));

    // item 1 opens its own, independent of item 2's, with ITS books
    [trig(0, @"show") activate];
    XCTAssertEqual(p.subforms.count, (NSUInteger)2);
    XCTAssertEqual(p.models.count, (NSUInteger)3);
    XCTAssertEqualObjects(bookIn(0), @"a1,a2");
    XCTAssertEqualObjects(bookIn(1), @"b1");
    XCTAssertNil(bookIn(2));

    // reloading item 1's replaces only item 1's
    [trig(0, @"show") activate];
    XCTAssertEqual(p.subforms.count, (NSUInteger)2);
    XCTAssertEqual(p.models.count, (NSUInteger)3);

    // unload in item 2's context leaves item 1's alone
    [trig(1, @"hide") activate];
    XCTAssertEqual(p.subforms.count, (NSUInteger)1);
    XCTAssertEqual(p.models.count, (NSUInteger)2);
    XCTAssertEqualObjects(bookIn(0), @"a1,a2");
    XCTAssertNil(bookIn(1));
    XCTAssertNil(bookIn(2));

    [trig(0, @"hide") activate];
    XCTAssertEqual(p.subforms.count, (NSUInteger)0);
    XCTAssertEqual(p.models.count, (NSUInteger)1);
    XCTAssertNil(bookIn(0));
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
}

- (void)testComponentResourceEmbedsSubform // G-95 (xf:component)
{
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"xfcomp-%d", (int)getpid()]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    // component content inherits the component's bound node as context
    // (XsltForms_component: innerHTML + the one global build walk); its
    // own instance is reached through instance('id')
    NSString *comp =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"<head><xf:model><xf:instance id=\"cdatai\"><c xmlns=\"\"><v>component</v></c></xf:instance></xf:model></head>"
        @"<body><xf:output id=\"cv\" value=\"instance('cdatai')/v\"><xf:label>V</xf:label></xf:output>"
        @"<xf:output id=\"ci\" ref=\".\"><xf:label>H</xf:label></xf:output>"
        @"<xf:output id=\"cc\" value=\"subform-context()\"><xf:label>C</xf:label></xf:output></body></html>";
    [comp writeToFile:[dir stringByAppendingPathComponent:@"comp.xhtml"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSString *main =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"<head><xf:model><xf:instance><data xmlns=\"\"><n>bound</n></data></xf:instance></xf:model></head>"
        @"<body><xf:component id=\"k\" ref=\"n\" resource=\"comp.xhtml\"><xf:label>K</xf:label></xf:component></body></html>";
    NSString *path = [dir stringByAppendingPathComponent:@"main.xhtml"];
    [main writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertEqual(p.subforms.count, (NSUInteger)1);
    XCTAssertEqual(p.subforms.firstObject.targetElement, [p controlWithIdentifier:@"k"].element);
    XCTAssertEqualObjects([p controlWithIdentifier:@"k"].label, @"K");
    XCTAssertEqualObjects([p controlWithIdentifier:@"cv"].stringValue, @"component");
    XCTAssertEqualObjects([p controlWithIdentifier:@"ci"].stringValue, @"bound", @"content inherits the component's bound node");
    XCTAssertEqualObjects([p controlWithIdentifier:@"cc"].stringValue, @"bound");
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
}

- (void)testTableCellShowsSwitchSelectedCaseControl // calculator "="
{
    NSError *error = nil;
    XFProcessor *p = [self form:
                      @"<xf:instance><data xmlns=\"\"><n/></data></xf:instance>"
                      extra:
                      @"<table><tr><td>"
                      @"  <xf:switch>"
                      @"    <xf:case id=\"one\" selected=\"true\"><xf:trigger id=\"t1\"><xf:label>=</xf:label>"
                      @"      <xf:action ev:event=\"DOMActivate\"><xf:setvalue ref=\"n\">one</xf:setvalue><xf:toggle case=\"two\"/></xf:action>"
                      @"    </xf:trigger></xf:case>"
                      @"    <xf:case id=\"two\"><xf:trigger id=\"t2\"><xf:label>=</xf:label>"
                      @"      <xf:setvalue ev:event=\"DOMActivate\" ref=\"n\">two</xf:setvalue>"
                      @"    </xf:trigger></xf:case>"
                      @"  </xf:switch>"
                      @"</td><td><xf:group><xf:output value=\"'g'\"><xf:label>G</xf:label></xf:output></xf:group></td></tr></table>"
                        error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFHostNode *tableNode = nil;
    for (XFHostNode *n in p.hostNodes) {
        if (n.kind == XFHostNodeKindTable) tableNode = n;
    }
    XFTableModel *m = [XFTableModel modelWithTableNode:tableNode];
    XFTableCell *cell = [m.rows.firstObject cellAtColumn:0];
    XCTAssertEqual(cell.control, [p controlWithIdentifier:@"t1"], @"the selected case's trigger is the cell");
    // a group showing one control resolves too
    XFControl *inGroup = [m.rows.firstObject cellAtColumn:1].control;
    XCTAssertNotNil(inGroup);
    XCTAssertFalse([inGroup isBlockLevel]);
    XCTAssertEqualObjects(inGroup.stringValue, @"g");
    // toggling rebuilds the model with the other case's trigger
    [(XFTriggerControl *)[p controlWithIdentifier:@"t1"] activate];
    [p refreshControls];
    m = [XFTableModel modelWithTableNode:tableNode];
    XCTAssertEqual([m.rows.firstObject cellAtColumn:0].control, [p controlWithIdentifier:@"t2"]);
}

@end
