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
        }
        if ([l.name isEqualToString:@"DOMActivate"] && [l.phase isEqualToString:@"capture"]) {
            sawActivate = YES;
        }
    }
    NSXMLElement *action = [[XFXMLEvents sharedEvents] elementWithID:@"ready-handler" inDocument:processor.hostDocument];
    for (XFListener *l in [[XFXMLEvents sharedEvents] listenersForElement:action]) {
        if ([l.name isEqualToString:@"xforms-ready"]) {
            sawReady = YES;
        }
    }
    XCTAssertTrue(sawReady, @"ev:event on xf:action should attach a listener");
    XCTAssertTrue(sawActivate, @"ev:listener should attach DOMActivate capture on model");
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

@end
