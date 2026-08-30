#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFXMLEvents.h>
#import <XFormsKit/XFListener.h>
#import <XFormsKit/XFEvent.h>
#import <Foundation/NSXMLDocument.h>
#import <Foundation/NSXMLElement.h>

@interface XFXMLEventsTests : XCTestCase
@end

@implementation XFXMLEventsTests

- (NSXMLDocument *)tree
{
    NSString *xml =
        @"<root id=\"root\"><mid id=\"mid\"><leaf id=\"leaf\"/></mid></root>";
    return [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL];
}

- (NSXMLElement *)el:(NSString *)identifier inDocument:(NSXMLDocument *)doc
{
    return [[XFXMLEvents sharedEvents] elementWithID:identifier inDocument:doc];
}

- (void)testRegistryHasXFormsEvents
{
    XFXMLEvents *ev = [XFXMLEvents sharedEvents];
    XCTAssertNotNil(ev.registry[@"xforms-model-construct"]);
    XCTAssertFalse(ev.registry[@"xforms-model-construct"].cancelable);
    XCTAssertTrue(ev.registry[@"xforms-rebuild"].cancelable);
    XCTAssertTrue(ev.registry[@"xforms-value-changed"].bubbles);
    XCTAssertNotNil(ev.registry[@"DOMActivate"]);
    XCTAssertNotNil(ev.registry[@"ajx-start"]);
}

- (void)testCaptureThenTargetThenBubble
{
    NSXMLDocument *doc = [self tree];
    NSXMLElement *root = [self el:@"root" inDocument:doc];
    NSXMLElement *mid  = [self el:@"mid" inDocument:doc];
    NSXMLElement *leaf = [self el:@"leaf" inDocument:doc];
    NSMutableArray *order = [NSMutableArray array];

    XFEventHandlerBlock rec = ^(XFEvent *event) {
        NSString *idv = [[event.currentTarget attributeForName:@"id"] stringValue];
        [order addObject:[NSString stringWithFormat:@"%@:%@", event.phase, idv]];
    };

    (void)[[XFListener alloc] initWithObserver:root evtTarget:nil name:@"ping" phase:@"capture" handler:rec defaultAction:YES];
    (void)[[XFListener alloc] initWithObserver:mid  evtTarget:nil name:@"ping" phase:@"capture" handler:rec defaultAction:YES];
    (void)[[XFListener alloc] initWithObserver:leaf evtTarget:nil name:@"ping" phase:@"capture" handler:rec defaultAction:YES];
    (void)[[XFListener alloc] initWithObserver:leaf evtTarget:nil name:@"ping" phase:@"default" handler:rec defaultAction:YES];
    (void)[[XFListener alloc] initWithObserver:mid  evtTarget:nil name:@"ping" phase:@"default" handler:rec defaultAction:YES];
    (void)[[XFListener alloc] initWithObserver:root evtTarget:nil name:@"ping" phase:@"default" handler:rec defaultAction:YES];

    [XFXMLEvents dispatch:leaf name:@"ping"];

    NSArray *expected = @[
        @"capture:root", @"capture:mid", @"capture:leaf",
        @"default:leaf", @"default:mid", @"default:root"
    ];
    XCTAssertEqualObjects(order, expected);
}

- (void)testStopPropagationHaltsBubble
{
    NSXMLDocument *doc = [self tree];
    NSXMLElement *root = [self el:@"root" inDocument:doc];
    NSXMLElement *leaf = [self el:@"leaf" inDocument:doc];
    NSMutableArray *order = [NSMutableArray array];

    (void)[[XFListener alloc] initWithObserver:leaf evtTarget:nil name:@"ping" phase:@"default" handler:^(XFEvent *e) {
        [order addObject:@"leaf"];
        [e stopPropagation];
    } defaultAction:YES];
    (void)[[XFListener alloc] initWithObserver:root evtTarget:nil name:@"ping" phase:@"default" handler:^(XFEvent *e) {
        (void)e;
        [order addObject:@"root"];
    } defaultAction:YES];

    [XFXMLEvents dispatch:leaf name:@"ping"];
    XCTAssertEqualObjects(order, @[ @"leaf" ]);
}

- (void)testPreventDefaultSkipsCancelableDefaultAction
{
    __block BOOL ran = NO;
    [XFXMLEvents define:@"xf-test-cancelable" bubbles:YES cancelable:YES defaultAction:^(id xf, XFEvent *ev) {
        (void)xf; (void)ev;
        ran = YES;
    }];

    NSXMLDocument *doc = [self tree];
    NSXMLElement *leaf = [self el:@"leaf" inDocument:doc];
    (void)[[XFListener alloc] initWithObserver:leaf evtTarget:nil name:@"xf-test-cancelable" phase:@"default" handler:^(XFEvent *e) {
        [e preventDefault];
    } defaultAction:YES];

    [XFXMLEvents dispatch:leaf name:@"xf-test-cancelable"];
    XCTAssertFalse(ran);
}

- (void)testNonCancelableDefaultActionStillRuns
{
    __block BOOL ran = NO;
    [XFXMLEvents define:@"xf-test-forced" bubbles:YES cancelable:NO defaultAction:^(id xf, XFEvent *ev) {
        (void)xf; (void)ev;
        ran = YES;
    }];

    NSXMLDocument *doc = [self tree];
    NSXMLElement *leaf = [self el:@"leaf" inDocument:doc];
    (void)[[XFListener alloc] initWithObserver:leaf evtTarget:nil name:@"xf-test-forced" phase:@"default" handler:^(XFEvent *e) {
        [e preventDefault];
    } defaultAction:YES];

    [XFXMLEvents dispatch:leaf name:@"xf-test-forced"];
    XCTAssertTrue(ran);
}

- (void)testListenerDefaultActionCancel
{
    __block BOOL ran = NO;
    [XFXMLEvents define:@"xf-test-da" bubbles:YES cancelable:YES defaultAction:^(id xf, XFEvent *ev) {
        (void)xf; (void)ev;
        ran = YES;
    }];
    NSXMLDocument *doc = [self tree];
    NSXMLElement *leaf = [self el:@"leaf" inDocument:doc];
    (void)[[XFListener alloc] initWithObserver:leaf evtTarget:nil name:@"xf-test-da" phase:@"default" handler:nil defaultAction:NO];
    [XFXMLEvents dispatch:leaf name:@"xf-test-da"];
    XCTAssertFalse(ran);
}

- (void)testEvtTargetFilter
{
    NSXMLDocument *doc = [self tree];
    NSXMLElement *mid  = [self el:@"mid" inDocument:doc];
    NSXMLElement *leaf = [self el:@"leaf" inDocument:doc];
    __block NSInteger hits = 0;
    (void)[[XFListener alloc] initWithObserver:mid evtTarget:leaf name:@"ping" phase:@"default" handler:^(XFEvent *e) {
        (void)e;
        hits++;
    } defaultAction:YES];

    [XFXMLEvents dispatch:leaf name:@"ping"];
    [XFXMLEvents dispatch:mid name:@"ping"];
    XCTAssertEqual(hits, (NSInteger)1);
}

- (void)testEventContextStack
{
    NSXMLDocument *doc = [self tree];
    NSXMLElement *leaf = [self el:@"leaf" inDocument:doc];
    __block NSString *seenType = nil;
    (void)[[XFListener alloc] initWithObserver:leaf evtTarget:nil name:@"ping" phase:@"default" handler:^(XFEvent *e) {
        (void)e;
        seenType = [XFXMLEvents currentEventContext][@"type"];
    } defaultAction:YES];
    [XFXMLEvents dispatch:leaf name:@"ping"];
    XCTAssertEqualObjects(seenType, @"ping");
    XCTAssertNil([XFXMLEvents currentEventContext]);
}

- (void)testInstallEvListenerAndAttribute
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"  <xf:model id=\"m\">"
        @"    <xf:instance><data xmlns=\"\"><n>1</n></data></xf:instance>"
        @"    <xf:action id=\"ready-handler\" ev:event=\"xforms-ready\"/>"
        @"  </xf:model>"
        @"  <ev:listener event=\"DOMActivate\" observer=\"m\" handler=\"#ready-handler\" phase=\"capture\"/>"
        @"</html>";
    NSError *error = nil;
    XFProcessor *processor = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(processor, @"%@", error);

    NSXMLElement *modelEl = processor.model.element;
    NSArray<XFListener *> *onModel = [[XFXMLEvents sharedEvents] listenersForElement:modelEl];
    BOOL sawReady = NO;
    BOOL sawActivate = NO;
    for (XFListener *l in onModel) {
        if ([l.name isEqualToString:@"xforms-ready"]) {
            sawReady = YES;
            XCTAssertEqualObjects(l.phase, @"default");
        }
        if ([l.name isEqualToString:@"DOMActivate"] && [l.phase isEqualToString:@"capture"]) {
            sawActivate = YES;
        }
    }
    XCTAssertTrue(sawReady, @"ev:event on xf:action observes the parent model");
    XCTAssertTrue(sawActivate, @"ev:listener should attach DOMActivate capture on model");

    XFAction *ready = (XFAction *)[processor actionWithIdentifier:@"ready-handler"];
    XCTAssertNotNil(ready);
    XCTAssertTrue([ready wasInvokedForEvent:@"xforms-ready"],
                  @"xforms-ready during init should run the document action: %@",
                  ready.invokedEvents);
}

- (void)testModelConstructChainRuns
{
    NSError *error = nil;
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <xf:model><xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance></xf:model>"
        @"  <xf:output value=\"concat('Hi ', n)\"><xf:label>G</xf:label></xf:output>"
        @"</html>";
    XFProcessor *processor = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(processor, @"%@", error);
    XCTAssertEqualObjects(processor.outputControls.firstObject.stringValue, @"Hi Ada");
}

- (void)testDocumentActionsSeeModelLifecycle
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"  <xf:model id=\"m\">"
        @"    <xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
        @"    <xf:action id=\"on-construct\" ev:event=\"xforms-model-construct\"/>"
        @"    <xf:action id=\"on-rebuild\" ev:event=\"xforms-rebuild\"/>"
        @"    <xf:action id=\"on-refresh\" ev:event=\"xforms-refresh\"/>"
        @"    <xf:action id=\"on-ready\" ev:event=\"xforms-ready\"/>"
        @"  </xf:model>"
        @"  <xf:output value=\"concat('Hi ', n)\"><xf:label>G</xf:label></xf:output>"
        @"</html>";
    NSError *error = nil;
    XFProcessor *processor = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(processor, @"%@", error);
    XCTAssertEqualObjects(processor.outputControls.firstObject.stringValue, @"Hi Ada");

    XCTAssertTrue([[processor actionWithIdentifier:@"on-construct"] wasInvokedForEvent:@"xforms-model-construct"]);
    XCTAssertFalse([[processor actionWithIdentifier:@"on-rebuild"] wasInvokedForEvent:@"xforms-rebuild"],
                   @"xforms-model-construct runs rebuild/recalculate/revalidate without events");
    XCTAssertFalse([[processor actionWithIdentifier:@"on-refresh"] wasInvokedForEvent:@"xforms-refresh"]);
    XCTAssertTrue([[processor actionWithIdentifier:@"on-ready"] wasInvokedForEvent:@"xforms-ready"]);

    [XFXMLEvents dispatch:processor.model name:@"xforms-rebuild"];
    XCTAssertTrue([[processor actionWithIdentifier:@"on-rebuild"] wasInvokedForEvent:@"xforms-rebuild"]);
    XCTAssertTrue([[processor actionWithIdentifier:@"on-refresh"] wasInvokedForEvent:@"xforms-refresh"]);
}

- (void)testEvDefaultActionCancelStopsRebuildChain
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"  <xf:model id=\"m\">"
        @"    <xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
        @"    <xf:action id=\"cancel-rebuild\" ev:event=\"xforms-rebuild\""
        @"               ev:defaultAction=\"cancel\"/>"
        @"    <xf:action id=\"on-recalculate\" ev:event=\"xforms-recalculate\"/>"
        @"    <xf:action id=\"on-refresh\" ev:event=\"xforms-refresh\"/>"
        @"  </xf:model>"
        @"</html>";
    NSError *error = nil;
    XFProcessor *processor = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(processor, @"%@", error);

    XCTAssertFalse([[processor actionWithIdentifier:@"cancel-rebuild"] wasInvokedForEvent:@"xforms-rebuild"],
                   @"init must not dispatch xforms-rebuild");

    [XFXMLEvents dispatch:processor.model name:@"xforms-rebuild"];
    XCTAssertTrue([[processor actionWithIdentifier:@"cancel-rebuild"] wasInvokedForEvent:@"xforms-rebuild"]);
    XCTAssertFalse([[processor actionWithIdentifier:@"on-recalculate"] wasInvokedForEvent:@"xforms-recalculate"],
                   @"cancelling xforms-rebuild must skip the default rebuild → recalculate dispatch");
    XCTAssertFalse([[processor actionWithIdentifier:@"on-refresh"] wasInvokedForEvent:@"xforms-refresh"]);
}

- (void)testEvPropagateStopOnCaptureSkipsTargetActions
{
    NSString *xml =
        @"<html id=\"root\" xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"  <xf:model id=\"m\">"
        @"    <xf:instance><data xmlns=\"\"><n>1</n></data></xf:instance>"
        @"    <xf:action id=\"capture-stop\" ev:event=\"xforms-ready\""
        @"               ev:observer=\"root\" ev:phase=\"capture\""
        @"               ev:propagate=\"stop\"/>"
        @"    <xf:action id=\"on-ready\" ev:event=\"xforms-ready\"/>"
        @"  </xf:model>"
        @"</html>";
    NSError *error = nil;
    XFProcessor *processor = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(processor, @"%@", error);

    XFAction *cap = (XFAction *)[processor actionWithIdentifier:@"capture-stop"];
    XFAction *ready = (XFAction *)[processor actionWithIdentifier:@"on-ready"];
    XCTAssertTrue([cap wasInvokedForEvent:@"xforms-ready"]);
    XCTAssertEqualObjects(cap.lastEvent.phase, @"capture");
    XCTAssertFalse([ready wasInvokedForEvent:@"xforms-ready"],
                   @"stopPropagation in capture must hide the model's default-phase ready handler");
}

- (void)testEvListenerElementDispatchesToHandlerAction
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"  <xf:model id=\"m\">"
        @"    <xf:instance><data xmlns=\"\"><n>1</n></data></xf:instance>"
        @"    <xf:action id=\"ping-handler\"/>"
        @"  </xf:model>"
        @"  <ev:listener event=\"ping\" observer=\"m\" handler=\"#ping-handler\"/>"
        @"</html>";
    NSError *error = nil;
    XFProcessor *processor = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(processor, @"%@", error);

    XFAction *handler = (XFAction *)[processor actionWithIdentifier:@"ping-handler"];
    XCTAssertEqual(handler.invocationCount, (NSInteger)0);
    [XFXMLEvents dispatch:processor.model name:@"ping"];
    XCTAssertTrue([handler wasInvokedForEvent:@"ping"]);
}

- (void)testSetValueFiresValueChangedAndRefreshActions
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"  <xf:model id=\"m\">"
        @"    <xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
        @"    <xf:action id=\"on-recalculate\" ev:event=\"xforms-recalculate\"/>"
        @"    <xf:action id=\"on-refresh\" ev:event=\"xforms-refresh\"/>"
        @"  </xf:model>"
        @"  <xf:input id=\"in\" ref=\"n\">"
        @"    <xf:label>N</xf:label>"
        @"    <xf:action id=\"on-changed\" ev:event=\"xforms-value-changed\"/>"
        @"  </xf:input>"
        @"  <xf:output value=\"concat('Hi ', n)\"><xf:label>G</xf:label></xf:output>"
        @"</html>";
    NSError *error = nil;
    XFProcessor *processor = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(processor, @"%@", error);

    XFAction *changed = (XFAction *)[processor actionWithIdentifier:@"on-changed"];
    XFAction *recalc = (XFAction *)[processor actionWithIdentifier:@"on-recalculate"];
    XFAction *refresh = (XFAction *)[processor actionWithIdentifier:@"on-refresh"];
    NSInteger recalcAtInit = recalc.invocationCount;
    NSInteger refreshAtInit = refresh.invocationCount;
    XCTAssertEqual(changed.invocationCount, (NSInteger)0);

    BOOL ok = [processor setValue:@"Bob" ofControl:processor.inputControls.firstObject error:&error];
    XCTAssertTrue(ok, @"%@", error);
    XCTAssertTrue([changed wasInvokedForEvent:@"xforms-value-changed"]);
    XCTAssertGreaterThan(recalc.invocationCount, recalcAtInit);
    XCTAssertGreaterThan(refresh.invocationCount, refreshAtInit);
    XCTAssertEqualObjects(processor.outputControls.firstObject.stringValue, @"Hi Bob");
}

@end
