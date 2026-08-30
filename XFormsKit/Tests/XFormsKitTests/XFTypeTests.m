#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFType.h>
#import <XFormsKit/XFNodeState.h>
#import <XFormsKit/XFXML.h>

@interface XFTypeTests : XCTestCase
@end

@implementation XFTypeTests

- (void)testBuiltinLookup
{
    XCTAssertNotNil([XFType typeNamed:@"xsd:integer"]);
    XCTAssertNotNil([XFType typeNamed:@"xf:date"]);
    XCTAssertNotNil([XFType typeNamed:@"integer"]);
    XCTAssertEqualObjects([XFType typeNamed:@"xs:boolean"].localName, @"boolean");
}

- (void)testIntegerAndDecimal
{
    XFType *integer = [XFType typeNamed:@"xsd:integer"];
    XCTAssertTrue([integer validateValue:@"42"]);
    XCTAssertTrue([integer validateValue:@"-7"]);
    XCTAssertFalse([integer validateValue:@"3.14"]);
    XCTAssertTrue([[XFType typeNamed:@"xsd:decimal"] validateValue:@"3.14"]);
    XCTAssertFalse([[XFType typeNamed:@"xsd:boolean"] validateValue:@"yes"]);
    XCTAssertTrue([[XFType typeNamed:@"xsd:boolean"] validateValue:@"true"]);
}

- (void)testDateAndEmail
{
    XCTAssertTrue([[XFType typeNamed:@"xsd:date"] validateValue:@"2026-08-30"]);
    XCTAssertFalse([[XFType typeNamed:@"xsd:date"] validateValue:@"30/08/2026"]);
    XCTAssertTrue([[XFType typeNamed:@"xf:email"] validateValue:@"a@b.com"]);
    XCTAssertFalse([[XFType typeNamed:@"xf:email"] validateValue:@"not-an-email"]);
}

- (void)testEmptyValueValidity // G-12: XSLTForms TypeDefs semantics
{
    XCTAssertFalse([XFType value:@"" conformsToTypeNamed:@"xsd:integer"]);
    XCTAssertFalse([XFType value:nil conformsToTypeNamed:@"xsd:date"]);
    XCTAssertTrue([XFType value:@"" conformsToTypeNamed:@"xsd:string"]);
    XCTAssertTrue([XFType value:@"" conformsToTypeNamed:@"xf:integer"]);
    XCTAssertTrue([XFType value:@"" conformsToTypeNamed:@"xf:date"]);
    XCTAssertTrue([XFType value:@"" conformsToTypeNamed:@"xf:email"]);
    XCTAssertTrue([XFType value:@"" conformsToTypeNamed:@"xsd:anyURI"]);
    XCTAssertFalse([XFType value:@"x" conformsToTypeNamed:@"xsd:integer"]);
}

- (void)testRevalidateAppliesType
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">"
        @"  <xf:model>"
        @"    <xf:instance><data xmlns=\"\"><n>3</n><bad>zz</bad></data></xf:instance>"
        @"    <xf:bind ref=\"n\" type=\"xsd:integer\"/>"
        @"    <xf:bind ref=\"bad\" type=\"xsd:integer\"/>"
        @"  </xf:model>"
        @"</html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSXMLElement *root = [[p.model defaultInstance] documentElement];
    NSXMLNode *n = [root elementsForName:@"n"].firstObject;
    NSXMLNode *bad = [root elementsForName:@"bad"].firstObject;
    XCTAssertTrue([XFNodeState existingStateOnNode:n].valid);
    XCTAssertFalse([XFNodeState existingStateOnNode:bad].valid);
}

- (void)testRequiredEmptyInvalid
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <xf:model>"
        @"    <xf:instance><data xmlns=\"\"><n/></data></xf:instance>"
        @"    <xf:bind ref=\"n\" type=\"xsd:integer\" required=\"true()\"/>"
        @"  </xf:model>"
        @"</html>";
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:NULL];
    NSXMLNode *n = [[[[p.model defaultInstance] documentElement] elementsForName:@"n"] firstObject];
    XCTAssertFalse([XFNodeState existingStateOnNode:n].valid);
    XCTAssertTrue([XFNodeState existingStateOnNode:n].required);
}

@end
