/* XFHostEdit, the designer's model layer: where an element may go, what an
   insert makes, and every edit (attributes, support children, rich and
   inline content, instance data, deletes and moves) live on the processor
   and undoable. One behaviour per test, each on a form of its own.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFTriggerControl.h>
#import <XFormsKit/XFSelectControl.h>
#import <XFormsKit/XFXML.h>

@interface XFHostEditTests : XCTestCase
@property (nonatomic, strong) XFProcessor *processor;
@property (nonatomic, strong) NSUndoManager *undo;
@property (nonatomic, strong) XFHostEdit *edit;
@property (nonatomic, strong) XFXMLDocument *orderDocument;
@end

@implementation XFHostEditTests

/// A form of `model` (the default model's content) and `body`, and an
/// edit of it whose undo manager groups only when told to.
- (void)formWithModel:(NSString *)model body:(NSString *)body
{
    NSString *xml = [NSString stringWithFormat:
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"<head><xf:model id=\"m\">%@</xf:model></head>"
        @"<body>%@</body></html>", model, body];
    NSError *error = nil;
    self.processor = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(self.processor, @"%@", error);
    self.undo = [[NSUndoManager alloc] init];
    [self.undo setGroupsByEvent:NO];
    self.edit = [XFHostEdit editWithProcessor:self.processor undoManager:self.undo];
}

/// The person form: a name and an age, and an input on the name.
- (void)personForm
{
    [self formWithModel:@"<xf:instance><data xmlns=\"\"><name>Ada</name><age>7</age></data></xf:instance>"
                   body:@"<xf:input id=\"taken-1\" ref=\"name\"><xf:label>Name</xf:label></xf:input>"];
}

- (XFXMLElement *)elementWithID:(NSString *)identifier
{
    return [XFXML elementWithID:identifier inNode:self.processor.hostDocument];
}

- (XFXMLElement *)body
{
    return [XFXML childElementWithLocalName:@"body" namespaceURI:XFXHTMLNamespaceURI
                                  ofElement:[self.processor.hostDocument rootElement]];
}

- (XFXMLElement *)modelElement
{
    return (XFXMLElement *)self.processor.model.element;
}

- (XFXMLElement *)instanceData
{
    return [[self.processor defaultInstance] documentElement];
}

/// `block` as one undoable change.
- (void)change:(void (^)(void))block
{
    [self.undo beginUndoGrouping];
    block();
    [self.undo endUndoGrouping];
}

- (XFXMLElement *)insert:(NSString *)name under:(XFXMLElement *)parent
{
    __block XFXMLElement *element = nil;
    __block NSError *error = nil;
    [self change:^{
        element = [self.edit insertElementNamed:name underParent:parent atIndex:-1 error:&error];
    }];
    XCTAssertNotNil(element, @"%@", error);
    return element;
}

/// The ids of `parent`'s element children, in order ("?" for one without).
- (NSArray *)idsUnder:(XFXMLElement *)parent
{
    NSMutableArray *ids = [NSMutableArray array];
    for (XFXMLNode *child in [parent children]) {
        if ([child kind] == XFXMLElementKind) {
            [ids addObject:[[(XFXMLElement *)child attributeForName:@"id"] stringValue] ?: @"?"];
        }
    }
    return ids;
}

#pragma mark Where an element may go

- (void)testTheBodyTakesControls
{
    [self personForm];
    XCTAssertTrue([[XFHostEdit insertableNamesUnderParent:[self body]] containsObject:@"input"]);
}

- (void)testTheModelTakesItsOwnElementsFirstAndActions
{
    [self personForm];
    NSArray *names = [XFHostEdit insertableNamesUnderParent:[self modelElement]];
    XCTAssertEqualObjects([names subarrayWithRange:NSMakeRange(0, 3)],
                          (@[ @"instance", @"bind", @"submission" ]));
    XCTAssertTrue([names containsObject:@"action"]);
    XCTAssertFalse([XFHostEdit canInsertElementNamed:@"input" underParent:[self modelElement]]);
}

- (void)testAControlTakesActions
{
    [self formWithModel:@"<xf:instance><data xmlns=\"\"/></xf:instance>"
                   body:@"<xf:trigger id=\"t\"><xf:label>Go</xf:label></xf:trigger>"];
    XCTAssertTrue([[XFHostEdit insertableNamesUnderParent:[self elementWithID:@"t"]]
                      containsObject:@"setvalue"]);
}

- (void)testASelectTakesAnItemset
{
    [self formWithModel:@"<xf:instance><data xmlns=\"\"><color/></data></xf:instance>"
                   body:@"<xf:select1 id=\"s\" ref=\"color\"><xf:label>Color</xf:label></xf:select1>"];
    XCTAssertTrue([[XFHostEdit insertableNamesUnderParent:[self elementWithID:@"s"]]
                      containsObject:@"itemset"]);
}

- (void)testInstanceDataTakesNothing
{
    [self personForm];
    XFXMLElement *data = (XFXMLElement *)[[self.processor.defaultInstance.document rootElement] copy];
    XCTAssertEqual([XFHostEdit insertableNamesUnderParent:data].count, (NSUInteger)0);
    XCTAssertFalse([XFHostEdit canInsertElementNamed:@"setvalue" underParent:data]);
}

#pragma mark What an insert makes

- (void)testUniqueIdentifiersSkipTakenOnes
{
    [self personForm];
    XCTAssertEqualObjects([self.edit uniqueIdentifierWithPrefix:@"taken"], @"taken-2");
}

- (void)testAnInsertedInputIsAControlWithAnIdAndALabel
{
    [self personForm];
    NSUInteger before = self.processor.controls.count;
    XFXMLElement *input = [self insert:@"input" under:[self body]];
    XCTAssertEqual(self.processor.controls.count, before + 1);
    XCTAssertNotNil([self.processor controlForElement:input]);
    XCTAssertEqualObjects([[input attributeForName:@"id"] stringValue], @"input-1");
    XCTAssertEqualObjects([self.edit supportChildText:@"label" onElement:input], @"Input");
}

- (void)testAnInsertIsOneChange
{
    [self personForm];
    __block NSUInteger changes = 0;
    self.edit.changedHandler = ^(XFXMLElement *e) { (void)e; changes++; };
    [self insert:@"input" under:[self body]];
    XCTAssertEqual(changes, (NSUInteger)1);
}

- (void)testAnInsertedBindReachesTheModel
{
    [self personForm];
    XFXMLElement *bind = [self insert:@"bind" under:[self modelElement]];
    [self change:^{
        [self.edit setAttribute:@"nodeset" value:@"age" onElement:bind];
        [self.edit setAttribute:@"required" value:@"true()" onElement:bind];
    }];
    XCTAssertTrue([[self.processor.hostDocument XMLString] containsString:@"required=\"true()\""]);
}

- (void)testAnInsertedItemsetStartsAtTheContext
{
    [self formWithModel:@"<xf:instance><data xmlns=\"\"><color/></data></xf:instance>"
                   body:@"<xf:select1 id=\"s\" ref=\"color\"><xf:label>Color</xf:label></xf:select1>"];
    XFXMLElement *itemset = [self insert:@"itemset" under:[self elementWithID:@"s"]];
    XCTAssertEqualObjects([[itemset attributeForName:@"nodeset"] stringValue], @".");
    XCTAssertEqualObjects([self.edit supportChildAttribute:@"ref" child:@"label" onElement:itemset], @".");
}

- (void)testAnInsertedActionListensForDOMActivate
{
    [self formWithModel:@"<xf:instance><data xmlns=\"\"><name>Ada</name></data></xf:instance>"
                   body:@"<xf:trigger id=\"t\"><xf:label>Go</xf:label></xf:trigger>"];
    NSUInteger before = self.processor.actions.count;
    XFXMLElement *setvalue = [self insert:@"setvalue" under:[self elementWithID:@"t"]];
    XCTAssertEqualObjects([[setvalue attributeForName:@"ev:event"] stringValue], @"DOMActivate");
    XCTAssertEqual(self.processor.actions.count, before + 1);
}

#pragma mark Attributes and support children

- (void)testAnAttributeSetIsUndoneAndRedone
{
    [self personForm];
    XFXMLElement *input = [self elementWithID:@"taken-1"];
    [self change:^{ [self.edit setAttribute:@"ref" value:@"age" onElement:input]; }];
    XCTAssertEqualObjects([[input attributeForName:@"ref"] stringValue], @"age");
    [self.undo undo];
    XCTAssertEqualObjects([[input attributeForName:@"ref"] stringValue], @"name");
    [self.undo redo];
    XCTAssertEqualObjects([[input attributeForName:@"ref"] stringValue], @"age");
}

- (void)testASupportChildSetIsUndone
{
    [self personForm];
    XFXMLElement *input = [self elementWithID:@"taken-1"];
    [self change:^{ [self.edit setSupportChild:@"hint" text:@"Years" onElement:input]; }];
    XCTAssertEqualObjects([self.edit supportChildText:@"hint" onElement:input], @"Years");
    [self.undo undo];
    XCTAssertNil([self.edit supportChildText:@"hint" onElement:input]);
}

- (void)testRichContentThatDoesNotParseIsRefused
{
    [self personForm];
    XFXMLElement *input = [self elementWithID:@"taken-1"];
    [self change:^{ [self.edit setSupportChild:@"hint" text:@"Years" onElement:input]; }];
    NSError *error = nil;
    XCTAssertFalse([self.edit setSupportChild:@"hint" contentXML:@"<broken" onElement:input error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects([self.edit supportChildText:@"hint" onElement:input], @"Years");
}

- (void)testRichContentIsReadBackAsXMLAndUndone
{
    [self personForm];
    XFXMLElement *input = [self elementWithID:@"taken-1"];
    [self change:^{ [self.edit setSupportChild:@"hint" text:@"Years" onElement:input]; }];
    __block NSError *error = nil;
    __block BOOL set = NO;
    [self change:^{
        set = [self.edit setSupportChild:@"hint"
                              contentXML:@"Age in <strong>years</strong>: <xf:output value=\"'7'\"/>"
                               onElement:input error:&error];
    }];
    XCTAssertTrue(set, @"%@", error);
    NSString *xml = [self.edit supportChildXML:@"hint" onElement:input];
    XCTAssertTrue([xml containsString:@"Age in <strong>years</strong>: "], @"%@", xml);
    XCTAssertTrue([xml containsString:@"output"], @"%@", xml);
    XCTAssertFalse([xml containsString:@"xmlns"], @"%@", xml);
    XCTAssertTrue([[self.processor.hostDocument XMLString] containsString:@"<strong>years</strong>"]);
    [self.undo undo];
    XCTAssertEqualObjects([self.edit supportChildText:@"hint" onElement:input], @"Years");
    XCTAssertEqualObjects([self.edit supportChildXML:@"hint" onElement:input], @"Years");
}

- (void)testANewRichLabelIsTheFirstChild
{
    [self personForm];
    XFXMLElement *input = [self elementWithID:@"taken-1"];
    __block NSError *error = nil;
    __block BOOL set = NO;
    [self change:^{
        [self.edit setSupportChild:@"hint" text:@"Years" onElement:input];
        [self.edit setSupportChild:@"label" text:nil onElement:input];
        set = [self.edit setSupportChild:@"label" contentXML:@"<em>Nom</em>" onElement:input error:&error];
    }];
    XCTAssertTrue(set, @"%@", error);
    XCTAssertEqualObjects([(XFXMLElement *)[input childAtIndex:0] localName], @"label");
    XCTAssertEqualObjects([self.edit supportChildText:@"label" onElement:input], @"Nom");
}

- (void)testAnItemsetsChildRefsAreSetAndUndone
{
    [self formWithModel:@"<xf:instance><data xmlns=\"\"><color>red</color>"
                        @"<option>red</option><option>blue</option></data></xf:instance>"
                   body:@"<xf:select1 id=\"s\" ref=\"color\"><xf:label>Color</xf:label>"
                        @"<xf:item><xf:label>None</xf:label><xf:value/></xf:item></xf:select1>"];
    XFXMLElement *select = [self elementWithID:@"s"];
    XFXMLElement *itemset = [self insert:@"itemset" under:select];
    [self change:^{
        [self.edit setAttribute:@"nodeset" value:@"../option" onElement:itemset];
        [self.edit setSupportChildAttribute:@"ref" child:@"value" value:@"." onElement:itemset];
        [self.edit setSupportChildAttribute:@"ref" child:@"label" value:@"." onElement:itemset];
    }];
    XFSelectControl *control = (XFSelectControl *)[self.processor controlForElement:select];
    XCTAssertGreaterThanOrEqual((NSInteger)control.items.count, 3, @"the item and the two options");
    [self.undo undo];
    XCTAssertEqualObjects([self.edit supportChildAttribute:@"ref" child:@"label" onElement:itemset], @".");
    [self.undo undo];
    XCTAssertNil([itemset parent]);
}

- (void)testInlineContentIsSetAndUndone
{
    [self formWithModel:@"<xf:instance><data xmlns=\"\"/></xf:instance>"
                   body:@"<xf:trigger id=\"t\"><xf:label>Go</xf:label></xf:trigger>"];
    __block XFXMLElement *message = nil;
    __block NSError *error = nil;
    __block BOOL set = NO;
    [self change:^{
        message = [self.edit insertElementNamed:@"message" underParent:[self elementWithID:@"t"]
                                        atIndex:-1 error:&error];
        set = [self.edit setInlineContentXML:@"Saved <strong>OK</strong>" onElement:message error:&error];
    }];
    XCTAssertTrue(set, @"%@", error);
    XCTAssertTrue([[self.edit inlineContentXMLOfElement:message] containsString:@"<strong>OK</strong>"]);
    [self.undo undo];
    XCTAssertNil([message parent]);
}

#pragma mark Instance data

- (void)testInstanceContentThatDoesNotParseIsRefused
{
    [self personForm];
    XFXMLElement *instance = [XFXML childElementWithLocalName:@"instance" namespaceURI:XFXFormsNamespaceURI
                                                    ofElement:[self modelElement]];
    NSError *error = nil;
    XCTAssertFalse([self.edit setContentXML:@"<broken" onElement:instance error:&error]);
    XCTAssertNotNil(error);
}

- (void)testInstanceContentIsReplacedAndUndone
{
    [self personForm];
    XFXMLElement *instance = [XFXML childElementWithLocalName:@"instance" namespaceURI:XFXFormsNamespaceURI
                                                    ofElement:[self modelElement]];
    __block NSError *error = nil;
    __block BOOL set = NO;
    [self change:^{
        set = [self.edit setContentXML:@"<data xmlns=\"\"><name>Zed</name><city/></data>"
                             onElement:instance error:&error];
    }];
    XCTAssertTrue(set, @"%@", error);
    XCTAssertEqualObjects([[[self instanceData] childAtIndex:0] stringValue], @"Zed");
    XCTAssertEqual([[self instanceData] childCount], (NSUInteger)2);
    [self.undo undo];
    XCTAssertEqualObjects([[[self instanceData] childAtIndex:0] stringValue], @"Ada");
}

#pragma mark Actions

- (void)testAnEditedActionIsRecompiledAndFires
{
    [self formWithModel:@"<xf:instance><data xmlns=\"\"><name>Ada</name></data></xf:instance>"
                   body:@"<xf:trigger id=\"t\"><xf:label>Go</xf:label></xf:trigger>"];
    XFXMLElement *trigger = [self elementWithID:@"t"];
    NSUInteger before = self.processor.actions.count;
    XFXMLElement *setvalue = [self insert:@"setvalue" under:trigger];
    [self change:^{
        [self.edit setAttribute:@"ref" value:@"name" onElement:setvalue];
        [self.edit setAttribute:@"value" value:@"'Zed'" onElement:setvalue];
    }];
    XCTAssertEqual(self.processor.actions.count, before + 1, @"recompiled, not duplicated");
    [(XFTriggerControl *)[self.processor controlForElement:trigger] activate];
    XCTAssertEqualObjects([[self instanceData] stringValue], @"Zed");
}

- (void)testADeletedActionStopsListening
{
    [self formWithModel:@"<xf:instance><data xmlns=\"\"><name>Ada</name></data></xf:instance>"
                   body:@"<xf:trigger id=\"t\"><xf:label>Go</xf:label>"
                        @"<xf:setvalue id=\"sv\" ev:event=\"DOMActivate\" ref=\"name\" value=\"'Zed'\"/>"
                        @"</xf:trigger>"];
    NSUInteger before = self.processor.actions.count;
    [self change:^{ [self.edit deleteElement:[self elementWithID:@"sv"]]; }];
    XCTAssertEqual(self.processor.actions.count, before - 1);
    [(XFTriggerControl *)[self.processor controlForElement:[self elementWithID:@"t"]] activate];
    XCTAssertEqualObjects([[self instanceData] stringValue], @"Ada");
}

/// ev:observer (the XML Events attribute module) set on a handler under
/// the model makes it listen on the trigger, and its delete unhooks it.
- (void)testAnObserverRedirectsAHandler
{
    [self formWithModel:@"<xf:instance><data xmlns=\"\"><name>Ada</name></data></xf:instance>"
                   body:@"<xf:trigger id=\"t\"><xf:label>Go</xf:label></xf:trigger>"];
    XFTriggerControl *trigger = (XFTriggerControl *)[self.processor controlForElement:[self elementWithID:@"t"]];
    NSUInteger before = self.processor.actions.count;
    XFXMLElement *remote = [self insert:@"setvalue" under:[self modelElement]];
    [self change:^{
        [self.edit setAttribute:@"ref" value:@"name" onElement:remote];
        [self.edit setAttribute:@"value" value:@"'Observed'" onElement:remote];
        [self.edit setAttribute:@"ev:event" value:@"DOMActivate" onElement:remote];
        [self.edit setAttribute:@"ev:observer" value:@"t" onElement:remote];
    }];
    [trigger activate];
    XCTAssertEqualObjects([[self instanceData] stringValue], @"Observed");
    [self change:^{ [self.edit deleteElement:remote]; }];
    XCTAssertEqual(self.processor.actions.count, before);
    [[self instanceData] setStringValue:@"Ada"];
    [trigger activate];
    XCTAssertEqualObjects([[self instanceData] stringValue], @"Ada");
}

#pragma mark Deletes

- (void)testADeletedControlComesBackWhereItWas
{
    [self personForm];
    XFXMLElement *input = [self insert:@"input" under:[self body]];
    NSUInteger controls = self.processor.controls.count;
    NSUInteger index = [input index];
    [self change:^{ [self.edit deleteElement:input]; }];
    XCTAssertEqual(self.processor.controls.count, controls - 1);
    XCTAssertNil([self.processor controlForElement:input]);
    [self.undo undo];
    XCTAssertEqual(self.processor.controls.count, controls);
    XCTAssertEqual([input index], index);
    XCTAssertEqual([input parent], [self body]);
    XCTAssertNotNil([self.processor controlForElement:input], @"the same element, a control again");
}

#pragma mark Moves

/// Three inputs: a and b in the body, c in the group g.
- (void)movesForm
{
    [self formWithModel:@"<xf:instance><data xmlns=\"\"><one/><two/><three/></data></xf:instance>"
                   body:@"<xf:input id=\"a\" ref=\"one\"><xf:label>A</xf:label></xf:input>"
                        @"<xf:input id=\"b\" ref=\"two\"><xf:label>B</xf:label></xf:input>"
                        @"<xf:group id=\"g\"><xf:label>G</xf:label>"
                        @"<xf:input id=\"c\" ref=\"three\"><xf:label>C</xf:label></xf:input>"
                        @"</xf:group>"];
}

- (void)move:(NSString *)identifier under:(XFXMLElement *)parent at:(NSInteger)index
{
    __block BOOL moved = NO;
    [self change:^{
        moved = [self.edit moveElement:[self elementWithID:identifier] underParent:parent atIndex:index];
    }];
    XCTAssertTrue(moved);
}

- (void)testAMoveToTheEndOfItsParent
{
    [self movesForm];
    NSUInteger controls = self.processor.controls.count;
    [self move:@"a" under:[self body] at:-1];
    XCTAssertEqualObjects([self idsUnder:[self body]], (@[ @"b", @"g", @"a" ]));
    XCTAssertEqual(self.processor.controls.count, controls);
    XCTAssertNotNil([self.processor controlForElement:[self elementWithID:@"a"]], @"still a control");
}

- (void)testAMoveTowardTheFrontOfItsParent
{
    [self movesForm];
    [self move:@"a" under:[self body] at:-1];
    [self move:@"a" under:[self body] at:(NSInteger)[[self elementWithID:@"b"] index]];
    XCTAssertEqualObjects([self idsUnder:[self body]], (@[ @"a", @"b", @"g" ]));
}

- (void)testAMoveIntoAnotherParent
{
    [self movesForm];
    [self move:@"b" under:[self elementWithID:@"g"] at:-1];
    XCTAssertEqualObjects([self idsUnder:[self body]], (@[ @"a", @"g" ]));
    XCTAssertEqualObjects([self idsUnder:[self elementWithID:@"g"]], (@[ @"?", @"c", @"b" ]), @"? is the label");
    XCTAssertNotNil([self.processor controlForElement:[self elementWithID:@"b"]]);
}

- (void)testMovesThatAreRefusedChangeNothing
{
    [self movesForm];
    XFXMLElement *g = [self elementWithID:@"g"], *a = [self elementWithID:@"a"];
    XCTAssertFalse([self.edit moveElement:g underParent:g atIndex:-1], @"into itself");
    XCTAssertFalse([self.edit moveElement:g underParent:(XFXMLElement *)[[self elementWithID:@"c"] parent] atIndex:0],
                   @"into its own subtree");
    XCTAssertFalse([self.edit moveElement:a underParent:[self modelElement] atIndex:-1], @"where a control may not go");
    XCTAssertFalse([self.edit moveElement:a underParent:[self body] atIndex:(NSInteger)[a index]], @"where it is");
    XCTAssertEqualObjects([self idsUnder:[self body]], (@[ @"a", @"b", @"g" ]));
}

- (void)testMovesAreUndoneOneByOne
{
    [self movesForm];
    NSUInteger controls = self.processor.controls.count;
    [self move:@"a" under:[self body] at:-1];
    [self move:@"a" under:[self body] at:(NSInteger)[[self elementWithID:@"b"] index]];
    [self move:@"b" under:[self elementWithID:@"g"] at:-1];
    [self.undo undo];
    XCTAssertEqualObjects([self idsUnder:[self body]], (@[ @"a", @"b", @"g" ]));
    XCTAssertEqualObjects([self idsUnder:[self elementWithID:@"g"]], (@[ @"?", @"c" ]));
    [self.undo undo];
    XCTAssertEqualObjects([self idsUnder:[self body]], (@[ @"b", @"g", @"a" ]));
    [self.undo undo];
    XCTAssertEqualObjects([self idsUnder:[self body]], (@[ @"a", @"b", @"g" ]));
    XCTAssertEqual(self.processor.controls.count, controls);
}

#pragma mark Paths between nodes

/// An order of a customer and two lines.
- (XFXMLElement *)order
{
    NSError *error = nil;
    self.orderDocument = [[XFXMLDocument alloc] initWithXMLString:
        @"<order xmlns=\"\">"
        @"<customer><name>Ada</name><city>Kyzylorda</city></customer>"
        @"<line qty=\"2\"><sku>A-1</sku></line>"
        @"<line qty=\"5\"><sku>B-2</sku></line>"
        @"</order>" options:0 error:&error];
    XCTAssertNotNil(self.orderDocument, @"%@", error);
    return [self.orderDocument rootElement];
}

- (void)testPathsDownFromANode
{
    XFXMLElement *order = [self order];
    XFXMLElement *customer = (XFXMLElement *)[order childAtIndex:0];
    XFXMLElement *line2 = (XFXMLElement *)[order childAtIndex:2];
    XCTAssertEqualObjects([XFHostEdit pathFromNode:order toNode:order], @".");
    XCTAssertEqualObjects([XFHostEdit pathFromNode:order toNode:[customer childAtIndex:0]], @"customer/name");
    XCTAssertEqualObjects([XFHostEdit pathFromNode:order toNode:[line2 childAtIndex:0]], @"line[2]/sku",
                          @"a position only where it is needed");
}

- (void)testPathsUpAndAcross
{
    XFXMLElement *order = [self order];
    XFXMLElement *customer = (XFXMLElement *)[order childAtIndex:0];
    XFXMLElement *line2 = (XFXMLElement *)[order childAtIndex:2];
    XFXMLNode *sku2 = [line2 childAtIndex:0];
    XCTAssertEqualObjects([XFHostEdit pathFromNode:[customer childAtIndex:0] toNode:sku2], @"../../line[2]/sku");
    XCTAssertEqualObjects([XFHostEdit pathFromNode:customer toNode:[line2 attributeForName:@"qty"]],
                          @"../line[2]/@qty");
    XCTAssertEqualObjects([XFHostEdit pathFromNode:sku2 toNode:customer], @"../../customer");
}

- (void)testStepsBelowTheRoot
{
    XFXMLElement *order = [self order];
    XCTAssertEqualObjects([XFHostEdit stepsBelowRootToNode:order], @"");
    XCTAssertEqualObjects([XFHostEdit stepsBelowRootToNode:[[order childAtIndex:2] childAtIndex:0]], @"line[2]/sku");
}

- (void)testNoPathToAnotherDocument
{
    XFXMLDocument *other = [[XFXMLDocument alloc] initWithXMLString:@"<x/>" options:0 error:NULL];
    XCTAssertNil([XFHostEdit pathFromNode:[self order] toNode:[other rootElement]]);
}

@end
