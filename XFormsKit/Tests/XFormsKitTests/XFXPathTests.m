#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <Foundation/NSXMLDocument.h>

@interface XFXPathTests : XCTestCase
@end

@implementation XFXPathTests

- (NSXMLDocument *)dataDocument
{
    NSString *xml = @"<data xmlns=\"\"><name>World</name><count>3</count></data>";
    return [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL];
}

- (XFExprContext *)context
{
    return [[XFExprContext alloc] initWithNode:[[self dataDocument] rootElement]];
}

- (NSString *)eval:(NSString *)expr
{
    NSError *error = nil;
    XFXPath *xp = [XFXPath xpathWithString:expr error:&error];
    XCTAssertNotNil(xp, @"parse %@ : %@", expr, error);
    NSString *value = [xp stringValueInContext:[self context] error:&error];
    XCTAssertNotNil(value, @"eval %@ : %@", expr, error);
    return value;
}

- (void)testChildPath
{
    XCTAssertEqualObjects([self eval:@"name"], @"World");
}

- (void)testAbsolutePath
{
    XCTAssertEqualObjects([self eval:@"/data/name"], @"World");
}

- (void)testConcat
{
    XCTAssertEqualObjects([self eval:@"concat('Hello ', name)"], @"Hello World");
}

- (void)testStringLiteral
{
    XCTAssertEqualObjects([self eval:@"'Hello '"], @"Hello ");
}

- (void)testCount
{
    XCTAssertEqualObjects([self eval:@"count(name)"], @"1");
}

- (void)testDependenciesRecordBoundNode
{
    NSError *error = nil;
    XFXPath *xp = [XFXPath xpathWithString:@"name" error:&error];
    XFExprContext *ctx = [self context];
    [xp evaluateInContext:ctx error:&error];
    XCTAssertGreaterThan(ctx.dependencyNodes.count, (NSUInteger)0);
}

- (void)testPredicatePosition
{
    XCTAssertEqualObjects([self eval:@"name[1]"], @"World");
    XCTAssertEqualObjects([self eval:@"name[position() = 1]"], @"World");
}

- (void)testArithmeticAndBoolean
{
    XCTAssertEqualObjects([self eval:@"1 + 2"], @"3");
    XCTAssertEqualObjects([self eval:@"6 div 2"], @"3");
    XCTAssertEqualObjects([self eval:@"5 mod 2"], @"1");
    XCTAssertEqualObjects([self eval:@"true() and false()"], @"false");
    XCTAssertEqualObjects([self eval:@"not(false())"], @"true");
}

- (void)testStringFunctions
{
    XCTAssertEqualObjects([self eval:@"starts-with(name, 'Wo')"], @"true");
    XCTAssertEqualObjects([self eval:@"substring-before(name, 'r')"], @"Wo");
    XCTAssertEqualObjects([self eval:@"normalize-space('  a   b ')"], @"a b");
    XCTAssertEqualObjects([self eval:@"string-length(name)"], @"5");
}

- (void)testUnionAndParent
{
    XCTAssertEqualObjects([self eval:@"count(name | count)"], @"2");
    XCTAssertEqualObjects([self eval:@"name/parent::*/count"], @"3");
}

- (void)testAttributeAxis
{
    NSString *xml = @"<data xmlns=\"\"><item id=\"a\">x</item></data>";
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL];
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:[doc rootElement]];
    NSError *error = nil;
    XFXPath *xp = [XFXPath xpathWithString:@"item/@id" error:&error];
    XCTAssertEqualObjects([xp stringValueInContext:ctx error:&error], @"a");
}

- (void)testXFormsFunctions
{
    XCTAssertEqualObjects([self eval:@"if(true(), 'yes', 'no')"], @"yes");
    XCTAssertEqualObjects([self eval:@"if(false(), 'yes', 'no')"], @"no");
    XCTAssertEqualObjects([self eval:@"boolean-from-string('1')"], @"true");
    XCTAssertEqualObjects([self eval:@"power(2, 3)"], @"8");
    XCTAssertEqualObjects([self eval:@"property('version')"], @"1.1");
    XCTAssertEqualObjects([self eval:@"count-non-empty(name)"], @"1");
    XCTAssertEqualObjects([self eval:@"days-from-date('1970-01-02')"], @"1");
    XCTAssertEqualObjects([self eval:@"seconds('PT1H')"], @"3600");
    XCTAssertEqualObjects([self eval:@"months('P1Y2M')"], @"14");
    XCTAssertEqualObjects([self eval:@"is-card-number('4111111111111111')"], @"true");
    XCTAssertEqualObjects([self eval:@"is-card-number('4111111111111112')"], @"false");
}

- (void)testCurrentAndId
{
    NSString *xml = @"<data xmlns=\"\"><item xml:id=\"a\">x</item><item xml:id=\"b\">y</item></data>";
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL];
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:[doc rootElement]];
    NSError *error = nil;
    XFXPath *xp = [XFXPath xpathWithString:@"id('a')" error:&error];
    XCTAssertEqualObjects([xp stringValueInContext:ctx error:&error], @"x");
    xp = [XFXPath xpathWithString:@"current()/name" error:&error];
    ctx = [[XFExprContext alloc] initWithNode:[[self dataDocument] rootElement]];
    XCTAssertEqualObjects([xp stringValueInContext:ctx error:&error], @"World");
}

@end
