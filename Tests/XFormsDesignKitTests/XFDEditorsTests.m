/* The inspector's view models (XFDEditors) on their own: which one an
   element gets, what each property reads and writes, that a write is one
   undoable change, that observers hear of their own writes and of
   everything else's (-reload), and what key-value validation refuses.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>
#import "XFormsDesignKit.h"
#import "XFDEditors.h"

/// Every change of a key it observes, counted.
@interface XFDKeyCounter : NSObject
@property (nonatomic, assign) NSUInteger changes;
@end

@implementation XFDKeyCounter
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context
{
    (void)keyPath; (void)object; (void)change; (void)context;
    self.changes++;
}
@end

/// The host changes a form editor tells of, counted.
@interface XFDHostChangeCounter : NSObject <XFDFormEditorObserver>
@property (nonatomic, assign) NSUInteger changes;
@end

@implementation XFDHostChangeCounter
- (void)formEditor:(XFDFormEditor *)editor hostDidChange:(XFXMLElement *)element
{
    (void)editor; (void)element;
    self.changes++;
}
@end

@interface XFDEditorsTests : XCTestCase
@end

@implementation XFDEditorsTests {
    XFDFormEditor *_editor;
    NSUndoManager *_undo;
}

/// A form of `model` and `body`; every change on an undo manager that
/// groups only when told to.
- (void)formWithModel:(NSString *)model body:(NSString *)body
{
    NSString *xml = [NSString stringWithFormat:
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"<head><xf:model id=\"m\">%@</xf:model></head>"
        @"<body>%@</body></html>", model, body];
    _undo = [[NSUndoManager alloc] init];
    [_undo setGroupsByEvent:NO];
    NSError *error = nil;
    _editor = [[XFDFormEditor alloc] initWithXMLString:xml baseURL:nil undoManager:_undo error:&error];
    XCTAssertNotNil(_editor, @"%@", error);
}

/// A person (name, age), an input on the name, a submit and an output.
- (void)personForm
{
    [self formWithModel:@"<xf:instance><data xmlns=\"\"><name>Ada</name><age>7</age></data></xf:instance>"
                        @"<xf:bind id=\"b-age\" nodeset=\"age\" type=\"integer\"/>"
                        @"<xf:submission id=\"s\" resource=\"http://example.com\" method=\"post\"/>"
                   body:@"<xf:input id=\"name-in\" ref=\"name\"><xf:label>Name</xf:label></xf:input>"
                        @"<xf:submit id=\"go\" submission=\"s\"><xf:label>Go</xf:label></xf:submit>"
                        @"<xf:output id=\"out\" value=\"age * 2\"/>"
                        @"<xf:trigger id=\"t\"><xf:label>T</xf:label>"
                        @"<xf:setvalue id=\"sv\" ev:event=\"DOMActivate\" ref=\"name\" value=\"'Zed'\"/>"
                        @"<xf:message id=\"msg\" ev:event=\"DOMActivate\">Hi</xf:message>"
                        @"<xf:insert id=\"ins\" ev:event=\"DOMActivate\" nodeset=\"name\"/>"
                        @"</xf:trigger>"];
}

- (XFXMLElement *)elementWithID:(NSString *)identifier
{
    return [XFXML elementWithID:identifier inNode:_editor.processor.hostDocument];
}

- (id)editorOf:(NSString *)identifier
{
    return [XFDElementEditor editorForElement:[self elementWithID:identifier] formEditor:_editor];
}

- (void)change:(void (^)(void))block
{
    [_undo beginUndoGrouping];
    block();
    [_undo endUndoGrouping];
}

/// Whether `value` for `key` of `object` validates, and the error.
- (BOOL)validate:(id)value key:(NSString *)key of:(id)object error:(NSError **)error
{
    id v = value;
    return [object validateValue:&v forKeyPath:key error:error];
}

#pragma mark Which editor

- (void)testEachKindHasItsEditor
{
    [self personForm];
    XCTAssertEqualObjects([[self editorOf:@"name-in"] class], [XFDControlEditor class]);
    XCTAssertEqualObjects([[self editorOf:@"b-age"] class], [XFDBindEditor class]);
    XCTAssertEqualObjects([[self editorOf:@"s"] class], [XFDSubmissionEditor class]);
    XCTAssertEqualObjects([[self editorOf:@"sv"] class], [XFDActionEditor class]);
    XCTAssertEqualObjects([[self editorOf:@"m"] class], [XFDElementEditor class]);
}

- (void)testAnEditorOfNothingIsNil
{
    [self personForm];
    XCTAssertNil([XFDElementEditor editorForElement:nil formEditor:_editor]);
}

#pragma mark Writes

- (void)testAPropertySetWritesTheAttributeUndoably
{
    [self personForm];
    XFDControlEditor *input = [self editorOf:@"name-in"];
    [self change:^{ input.ref = @"age"; }];
    XCTAssertEqualObjects([[input.element attributeForName:@"ref"] stringValue], @"age");
    [_undo undo];
    XCTAssertEqualObjects(input.ref, @"name");
}

- (void)testTheSameValueSetIsNoChange
{
    [self personForm];
    XFDControlEditor *input = [self editorOf:@"name-in"];
    XFDHostChangeCounter *counter = [[XFDHostChangeCounter alloc] init];
    [_editor addObserver:counter];
    [self change:^{ input.ref = @"name"; }];
    [_editor removeObserver:counter];
    XCTAssertEqual(counter.changes, 0u);
}

- (void)testATitleSaysTheElementAndItsId
{
    [self personForm];
    XCTAssertEqualObjects([[self editorOf:@"name-in"] title], @"xf:input — name-in");
}

- (void)testPlainContentIsKeptAsText
{
    [self personForm];
    XFDControlEditor *input = [self editorOf:@"name-in"];
    [self change:^{ input.labelContent = @"Fish &amp; chips"; }];
    XCTAssertEqualObjects(input.labelText, @"Fish & chips");
    XCTAssertEqualObjects(input.labelContent, @"Fish &amp; chips");
}

- (void)testRichContentIsKeptAsMarkup
{
    [self personForm];
    XFDControlEditor *input = [self editorOf:@"name-in"];
    [self change:^{ input.labelContent = @"Your <strong>full</strong> name"; }];
    XCTAssertTrue([input.labelXML containsString:@"<strong>full</strong>"], @"%@", input.labelXML);
    XCTAssertEqualObjects(input.labelText, @"Your full name");
}

- (void)testEmptyContentRemovesTheChild
{
    [self personForm];
    XFDControlEditor *input = [self editorOf:@"name-in"];
    [self change:^{ input.labelContent = @""; }];
    XCTAssertNil(input.labelXML);
    XCTAssertEqualObjects(input.labelContent, @"");
}

- (void)testAValueExpressionIsAnOutputsOnly
{
    [self personForm];
    XFDControlEditor *output = [self editorOf:@"out"];
    XFDControlEditor *input = [self editorOf:@"name-in"];
    XCTAssertTrue(output.takesValueExpression);
    XCTAssertEqualObjects(output.valueExpression, @"age * 2");
    XCTAssertFalse(input.takesValueExpression);
    [self change:^{ input.valueExpression = @"1"; }];
    XCTAssertNil([input.element attributeForName:@"value"], @"dead weight elsewhere");
}

- (void)testASubmissionIsASubmitsOnly
{
    [self personForm];
    XCTAssertTrue([[self editorOf:@"go"] takesSubmission]);
    XCTAssertEqualObjects([[self editorOf:@"go"] submission], @"s");
    XCTAssertFalse([[self editorOf:@"name-in"] takesSubmission]);
    XCTAssertEqualObjects([[self editorOf:@"name-in"] submission], @"");
}

- (void)testThePopUpsDefaultIsNoAttribute
{
    [self personForm];
    XFDControlEditor *input = [self editorOf:@"name-in"];
    XCTAssertEqualObjects(input.appearanceTitle, @"(default)");
    [self change:^{ input.appearanceTitle = @"minimal"; }];
    XCTAssertEqualObjects(input.appearance, @"minimal");
    [self change:^{ input.appearanceTitle = @"(default)"; }];
    XCTAssertNil([input.element attributeForName:@"appearance"]);
    XFDSubmissionEditor *submission = [self editorOf:@"s"];
    XCTAssertEqualObjects(submission.replaceTitle, @"none");
    [self change:^{ submission.replaceTitle = @"instance"; }];
    XCTAssertEqualObjects(submission.replace, @"instance");
}

- (void)testIncrementalIsTrueOrAbsent
{
    [self personForm];
    XFDControlEditor *input = [self editorOf:@"name-in"];
    [self change:^{ input.incremental = YES; }];
    XCTAssertEqualObjects([[input.element attributeForName:@"incremental"] stringValue], @"true");
    [self change:^{ input.incremental = NO; }];
    XCTAssertNil([input.element attributeForName:@"incremental"]);
}

- (void)testTheBindingStatusSaysHowItIsBound
{
    [self personForm];
    XFDControlEditor *input = [self editorOf:@"name-in"];
    XCTAssertEqualObjects(input.bindingStatus, @"Bound in place via ref.");
    XCTAssertTrue(input.canCreateBind);
    [self change:^{ input.bind = @"b-age"; }];
    XCTAssertEqualObjects(input.bindingStatus, @"Bound via bind ‘b-age’.");
    XCTAssertFalse(input.canCreateBind);
    [self change:^{ input.bind = @"nothing"; }];
    XCTAssertEqualObjects(input.bindingStatus, @"Bind ‘nothing’ does not exist.");
    XCTAssertEqualObjects(input.bindingStatusColor, [NSColor redColor]);
}

#pragma mark Actions

- (void)testAnActionsRowsAreTheCommonOnesAndItsKinds
{
    [self personForm];
    XFDActionEditor *setvalue = [self editorOf:@"sv"];
    NSArray *attrs = [setvalue.rows valueForKey:@"attr"];
    XCTAssertEqualObjects(attrs.firstObject, @"ev:event");
    XCTAssertTrue([attrs containsObject:@"if"]);
    XCTAssertTrue([attrs containsObject:@"ref"]);
    XCTAssertTrue([attrs containsObject:@"value"]);
}

- (void)testAnActionsAttributesAreKeys
{
    [self personForm];
    XFDActionEditor *setvalue = [self editorOf:@"sv"];
    XCTAssertEqualObjects([setvalue valueForKeyPath:@"attributes.ev:event"], @"DOMActivate");
    XCTAssertEqualObjects([setvalue valueForKeyPath:@"attributes.ref"], @"name");
    [self change:^{ [setvalue setValue:@"age" forKeyPath:@"attributes.ref"]; }];
    XCTAssertEqualObjects([[setvalue.element attributeForName:@"ref"] stringValue], @"age");
}

- (void)testAnActionsPopUpDefaultIsNoAttribute
{
    [self personForm];
    XFDActionEditor *insert = [self editorOf:@"ins"];
    XCTAssertEqualObjects([insert valueForKeyPath:@"attributes.position"], @"(default)");
    [self change:^{ [insert setValue:@"after" forKeyPath:@"attributes.position"]; }];
    XCTAssertEqualObjects([[insert.element attributeForName:@"position"] stringValue], @"after");
    [self change:^{ [insert setValue:@"(default)" forKeyPath:@"attributes.position"]; }];
    XCTAssertNil([insert.element attributeForName:@"position"]);
}

- (void)testAnActionsInlineContentIsItsMarkup
{
    [self personForm];
    XFDActionEditor *message = [self editorOf:@"msg"];
    XCTAssertEqualObjects(message.inlineContent, @"Hi");
    [self change:^{ message.inlineContent = @"Saved <strong>OK</strong>"; }];
    XCTAssertTrue([message.inlineContent containsString:@"<strong>OK</strong>"]);
}

#pragma mark Observers

- (void)testAnObserverHearsAWrite
{
    [self personForm];
    XFDControlEditor *input = [self editorOf:@"name-in"];
    XFDKeyCounter *counter = [[XFDKeyCounter alloc] init];
    [input addObserver:counter forKeyPath:@"ref" options:0 context:NULL];
    [self change:^{ input.ref = @"age"; }];
    [input removeObserver:counter forKeyPath:@"ref"];
    XCTAssertEqual(counter.changes, 1u);
}

- (void)testAWriteIsHeardByWhatDependsOnIt
{
    [self personForm];
    XFDControlEditor *input = [self editorOf:@"name-in"];
    XFDKeyCounter *counter = [[XFDKeyCounter alloc] init];
    [input addObserver:counter forKeyPath:@"bindingStatus" options:0 context:NULL];
    [input addObserver:counter forKeyPath:@"labelText" options:0 context:NULL];
    [self change:^{ input.ref = @""; }];
    [self change:^{ input.labelContent = @"Who"; }];
    [input removeObserver:counter forKeyPath:@"bindingStatus"];
    [input removeObserver:counter forKeyPath:@"labelText"];
    XCTAssertGreaterThanOrEqual(counter.changes, 2u);
}

- (void)testAReloadIsHeardByEveryProperty
{
    [self personForm];
    XFDControlEditor *input = [self editorOf:@"name-in"];
    XFDKeyCounter *counter = [[XFDKeyCounter alloc] init];
    [input addObserver:counter forKeyPath:@"ref" options:0 context:NULL];
    [input addObserver:counter forKeyPath:@"labelContent" options:0 context:NULL];
    [input reload];
    [input removeObserver:counter forKeyPath:@"ref"];
    [input removeObserver:counter forKeyPath:@"labelContent"];
    XCTAssertEqual(counter.changes, 2u);
}

- (void)testAnUndoIsSeenAfterAReload
{
    [self personForm];
    XFDControlEditor *input = [self editorOf:@"name-in"];
    [self change:^{ input.ref = @"age"; }];
    [_undo undo];
    [input reload];
    XCTAssertEqualObjects(input.ref, @"name", @"the element, changed in place");
}

#pragma mark Validation

- (void)testAnExpressionThatDoesNotCompileIsRefused
{
    [self personForm];
    NSError *error = nil;
    XCTAssertFalse([self validate:@"//[bad((" key:@"ref" of:[self editorOf:@"name-in"] error:&error]);
    XCTAssertEqualObjects(error.domain, XFDEditorErrorDomain);
    XCTAssertTrue([self validate:@"../age" key:@"ref" of:[self editorOf:@"name-in"] error:NULL]);
    XCTAssertTrue([self validate:@"" key:@"ref" of:[self editorOf:@"name-in"] error:NULL], @"none is no expression");
}

- (void)testEveryKindsExpressionsAreValidated
{
    [self personForm];
    XCTAssertFalse([self validate:@"((" key:@"calculate" of:[self editorOf:@"b-age"] error:NULL]);
    XCTAssertFalse([self validate:@"((" key:@"ref" of:[self editorOf:@"s"] error:NULL]);
    XCTAssertFalse([self validate:@"((" key:@"attributes.if" of:[self editorOf:@"sv"] error:NULL]);
    XCTAssertTrue([self validate:@"((" key:@"attributes.ev:event" of:[self editorOf:@"sv"] error:NULL],
                  @"an event name is no expression");
}

- (void)testAnIdMustBeAnNCName
{
    [self personForm];
    NSError *error = nil;
    XCTAssertFalse([self validate:@"two words" key:@"identifier" of:[self editorOf:@"name-in"] error:&error]);
    XCTAssertNotNil(error.localizedRecoverySuggestion);
    XCTAssertFalse([self validate:@"1st" key:@"identifier" of:[self editorOf:@"name-in"] error:NULL]);
    XCTAssertFalse([self validate:@"a:b" key:@"identifier" of:[self editorOf:@"name-in"] error:NULL]);
    XCTAssertTrue([self validate:@"_name-in.2" key:@"identifier" of:[self editorOf:@"name-in"] error:NULL]);
}

- (void)testAnIdMustBeUnused
{
    [self personForm];
    NSError *error = nil;
    XCTAssertFalse([self validate:@"go" key:@"identifier" of:[self editorOf:@"name-in"] error:&error]);
    XCTAssertTrue([error.localizedDescription containsString:@"go"]);
    XCTAssertTrue([self validate:@"name-in" key:@"identifier" of:[self editorOf:@"name-in"] error:NULL],
                  @"its own");
}

- (void)testContentThatDoesNotParseIsRefused
{
    [self personForm];
    XCTAssertFalse([self validate:@"<broken" key:@"labelContent" of:[self editorOf:@"name-in"] error:NULL]);
    XCTAssertFalse([self validate:@"<b>x" key:@"inlineContent" of:[self editorOf:@"msg"] error:NULL]);
    XCTAssertTrue([self validate:@"a <em>b</em>" key:@"labelContent" of:[self editorOf:@"name-in"] error:NULL]);
}

@end
