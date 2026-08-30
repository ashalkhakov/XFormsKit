#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <Foundation/NSXMLDocument.h>
#import <XFormsKit/XFNodeState.h>
#import <XFormsKit/XFXMLEvents.h>

@interface XFXPathTests : XCTestCase
{
    // Keep the document alive: NSXMLNode does not retain its parent, so on
    // GNUstep a root element whose document has been released loses the
    // document (and ancestor axis / absolute paths).
    NSXMLDocument *_doc;
}
@end

@implementation XFXPathTests

- (NSXMLDocument *)dataDocument
{
    NSString *xml = @"<data xmlns=\"\"><name>World</name><count>3</count></data>";
    _doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL];
    return _doc;
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

- (void)testStarPrefixNameTest // G-78
{
    NSString *xml = @"<data xmlns=\"\"><a:name xmlns:a=\"urn:a\">A</a:name>"
                    @"<b:name xmlns:b=\"urn:b\">B</b:name><name>N</name><other>O</other></data>";
    _doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL];
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:[_doc rootElement]];
    NSError *error = nil;
    XFXPath *xp = [XFXPath xpathWithString:@"count(*:name)" error:&error];
    XCTAssertNotNil(xp, @"%@", error);
    XCTAssertEqualObjects([xp stringValueInContext:ctx error:&error], @"3");
    xp = [XFXPath xpathWithString:@"string(*:name[2])" error:&error];
    XCTAssertEqualObjects([xp stringValueInContext:ctx error:&error], @"B");
    // '*' stays multiplication after an operand
    XCTAssertEqualObjects([self eval:@"count(*)*2"], @"4");
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


#pragma mark - Gap fixes (docs/XSLTForms-gaps.md G-03 .. G-15, G-70 .. G-84)

- (NSString *)evalXML:(NSString *)xml expr:(NSString *)expr
{
    NSError *error = nil;
    _doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL];
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:[_doc rootElement]];
    XFXPath *xp = [XFXPath xpathWithString:expr element:[_doc rootElement] error:&error];
    XCTAssertNotNil(xp, @"parse %@ : %@", expr, error);
    NSString *value = [xp stringValueInContext:ctx error:&error];
    XCTAssertNotNil(value, @"eval %@ : %@", expr, error);
    return value;
}

- (void)testMinusAfterOperandIsSubtraction // G-03
{
    XCTAssertEqualObjects([self eval:@"count(name)-1"], @"0");
    XCTAssertEqualObjects([self eval:@"1-1"], @"0");
    // note: `count-1` is a single QName per XPath 1.0 (names may contain '-')
    XCTAssertEqualObjects([self eval:@"count - 1"], @"2");
    XCTAssertEqualObjects([self eval:@"(count)-1"], @"2");
    XCTAssertEqualObjects([self eval:@"count[1]-1"], @"2");
    XCTAssertEqualObjects([self eval:@"-1"], @"-1");
    XCTAssertEqualObjects([self eval:@"2 * -1"], @"-2");
    XCTAssertEqualObjects([self eval:@"count div -1"], @"-3");
    XCTAssertEqualObjects([self eval:@"count*2-1"], @"5");
}

- (void)testLeadingNodeTypeTestsAreSteps // G-15
{
    XCTAssertEqualObjects([self eval:@"name/text()"], @"World");
    XCTAssertEqualObjects([self evalXML:@"<a>hi</a>" expr:@"text()"], @"hi");
    XCTAssertEqualObjects([self evalXML:@"<a>hi</a>" expr:@"count(node())"], @"1");
    XCTAssertEqualObjects([self evalXML:@"<a><!-- c -->x</a>" expr:@"comment()"], @" c ");
}

- (void)testNumberToString // G-05
{
    XCTAssertEqualObjects([self eval:@"1234.5678"], @"1234.5678");
    XCTAssertEqualObjects([self eval:@"string(3.14159265)"], @"3.14159265");
    XCTAssertEqualObjects([self eval:@"0.1 + 0.2"], @"0.30000000000000004");
    XCTAssertEqualObjects([self eval:@"1 div 3"], @"0.3333333333333333");
    XCTAssertEqualObjects([self eval:@"1.5 * 2"], @"3");
    XCTAssertEqualObjects([self eval:@"-0.5"], @"-0.5");
    XCTAssertEqualObjects([self eval:@"0.000001"], @"0.000001");
    XCTAssertEqualObjects([self eval:@"123456789012"], @"123456789012");
    XCTAssertEqualObjects([self eval:@"1 div 0"], @"Infinity");
    XCTAssertEqualObjects([self eval:@"number('x')"], @"NaN");
}

- (void)testComparisonSemantics // G-14
{
    NSString *xml = @"<d><x>1.0</x><y>2</y><b>abc</b><e/></d>";
    XCTAssertEqualObjects([self evalXML:xml expr:@"x = 1"], @"true");
    XCTAssertEqualObjects([self evalXML:xml expr:@"1 = x"], @"true");
    XCTAssertEqualObjects([self evalXML:xml expr:@"x = '1'"], @"false");
    XCTAssertEqualObjects([self evalXML:xml expr:@"x != 1"], @"false");
    XCTAssertEqualObjects([self evalXML:xml expr:@"y > x"], @"true");
    XCTAssertEqualObjects([self evalXML:xml expr:@"x < 1.5"], @"true");
    XCTAssertEqualObjects([self evalXML:xml expr:@"b = 'abc'"], @"true");
    XCTAssertEqualObjects([self evalXML:xml expr:@"e = ''"], @"true");
    XCTAssertEqualObjects([self evalXML:xml expr:@"e = false()"], @"false");
    XCTAssertEqualObjects([self evalXML:xml expr:@"boolean(e) = true()"], @"true");
    XCTAssertEqualObjects([self evalXML:xml expr:@"nothing = false()"], @"true");
    XCTAssertEqualObjects([self evalXML:xml expr:@"true() = 5"], @"true");
    XCTAssertEqualObjects([self evalXML:xml expr:@"'1' = '1.0'"], @"false");
    XCTAssertEqualObjects([self evalXML:xml expr:@"'a' < 'b'"], @"false");
    XCTAssertEqualObjects([self evalXML:xml expr:@"x | y = 2"], @"true");
}

- (void)testRoundHalfUp // G-78
{
    XCTAssertEqualObjects([self eval:@"round(2.5)"], @"3");
    XCTAssertEqualObjects([self eval:@"round(-2.5)"], @"-2");
    XCTAssertEqualObjects([self eval:@"round(-2.6)"], @"-3");
}

- (void)testDocumentOrderAndReverseAxes // G-78
{
    NSString *xml = @"<d><a>1</a><b>2</b><c>3</c></d>";
    XCTAssertEqualObjects([self evalXML:xml expr:@"string-join(c | a | b, ',')"], @"1,2,3");
    XCTAssertEqualObjects([self evalXML:xml expr:@"string-join(c/preceding-sibling::*, ',')"], @"1,2");
    XCTAssertEqualObjects([self evalXML:xml expr:@"c/preceding-sibling::*[1]"], @"2");
    XCTAssertEqualObjects([self evalXML:xml expr:@"name(c/ancestor-or-self::*[1])"], @"c");
    XCTAssertEqualObjects([self evalXML:xml expr:@"name((c/ancestor-or-self::*)[1])"], @"d");
    XCTAssertEqualObjects([self evalXML:@"<d><or>x</or><and>y</and></d>" expr:@"concat(or, and)"], @"xy");
}

- (void)testNamespacePrefixes // G-04
{
    NSString *xml = @"<d xmlns:my=\"urn:my\" xmlns=\"urn:def\"><my:item>A</my:item><item>B</item></d>";
    XCTAssertEqualObjects([self evalXML:xml expr:@"my:item"], @"A");
    XCTAssertEqualObjects([self evalXML:xml expr:@"count(my:item)"], @"1");
    XCTAssertEqualObjects([self evalXML:xml expr:@"count(my:*)"], @"1");
    XCTAssertEqualObjects([self evalXML:xml expr:@"count(*)"], @"2");
    // prefix registered from a different element than the data node
    NSError *error = nil;
    NSXMLDocument *host = [[NSXMLDocument alloc] initWithXMLString:@"<h xmlns:p=\"urn:my\"/>" options:0 error:NULL];
    XFXPath *xp = [XFXPath xpathWithString:@"p:item" element:host.rootElement error:&error];
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:[_doc rootElement]];
    XCTAssertEqualObjects([xp stringValueInContext:ctx error:&error], @"A");
}

- (void)testStringFunctionsXPath2 // G-70
{
    XCTAssertEqualObjects([self eval:@"ends-with(name, 'ld')"], @"true");
    XCTAssertEqualObjects([self eval:@"upper-case(name)"], @"WORLD");
    XCTAssertEqualObjects([self eval:@"lower-case('AbC')"], @"abc");
    XCTAssertEqualObjects([self eval:@"compare('a', 'b')"], @"-1");
    XCTAssertEqualObjects([self eval:@"compare('b', 'b')"], @"0");
    XCTAssertEqualObjects([self eval:@"replace('a-b-c', '-', '+')"], @"a+b+c");
    XCTAssertEqualObjects([self eval:@"replace('abc', '(b)', '[$1]')"], @"a[b]c");
    XCTAssertEqualObjects([self eval:@"string-join(tokenize('a,b,,c', ','), '|')"], @"a|b||c");
    XCTAssertEqualObjects([self eval:@"count(tokenize('a b  c', '\\s+'))"], @"3");
    XCTAssertEqualObjects([self eval:@"encode-for-uri('a b&c/d')"], @"a%20b%26c%2Fd");
    XCTAssertEqualObjects([self evalXML:@"<d><i>x</i><i>y</i><i>x</i></d>" expr:@"count(distinct-values(i))"], @"2");
    XCTAssertEqualObjects([self evalXML:@"<d><i>x</i><i>y</i></d>" expr:@"string-join(i, '-')"], @"x-y");
}

- (void)testAggregates // G-71
{
    NSString *xml = @"<d><n>3</n><n>1</n><n>2</n><bad>x</bad></d>";
    XCTAssertEqualObjects([self evalXML:xml expr:@"min(n)"], @"1");
    XCTAssertEqualObjects([self evalXML:xml expr:@"max(n)"], @"3");
    XCTAssertEqualObjects([self evalXML:xml expr:@"avg(n)"], @"2");
    XCTAssertEqualObjects([self evalXML:xml expr:@"max(n | bad)"], @"NaN");
    XCTAssertEqualObjects([self evalXML:xml expr:@"min(none)"], @"NaN");
}

- (void)testFormatNumber // G-72
{
    XCTAssertEqualObjects([self eval:@"format-number(1234567.891, '#,##0.00')"], @"1,234,567.89");
    XCTAssertEqualObjects([self eval:@"format-number(0.5, '0.0')"], @"0.5");
    XCTAssertEqualObjects([self eval:@"format-number(42, '000')"], @"042");
    XCTAssertEqualObjects([self eval:@"format-number(1.5, '#.##')"], @"1.5");
    XCTAssertEqualObjects([self eval:@"format-number(-3.7, '0')"], @"-4");
    XCTAssertEqualObjects([self eval:@"format-number(0.256, '0%')"], @"26%");
    XCTAssertEqualObjects([self eval:@"format-number(-5, '#;(#)')"], @"(5)");
    XCTAssertEqualObjects([self eval:@"format-number(1234.5, '$#,##0.00')"], @"$1,234.50");
    XCTAssertEqualObjects([self eval:@"format-number('x', '0')"], @"NaN");
}

- (void)testMathFunctions // G-74
{
    XCTAssertEqualObjects([self eval:@"math:abs(-3)"], @"3");
    XCTAssertEqualObjects([self eval:@"math:sqrt(16)"], @"4");
    XCTAssertEqualObjects([self eval:@"math:power(2, 10)"], @"1024");
    XCTAssertEqualObjects([self eval:@"round(math:constant('PI') * 100)"], @"314");
    XCTAssertEqualObjects([self eval:@"math:atan2(0, 1)"], @"0");
}

- (void)testDurationsAndDates // G-14
{
    XCTAssertEqualObjects([self eval:@"seconds('P1Y2D')"], @"172800");
    XCTAssertEqualObjects([self eval:@"seconds('P1DT1H1M1.5S')"], @"90061.5");
    XCTAssertEqualObjects([self eval:@"seconds('-PT1M')"], @"-60");
    XCTAssertEqualObjects([self eval:@"months('P1Y2M3D')"], @"14");
    XCTAssertEqualObjects([self eval:@"seconds('junk')"], @"NaN");
    XCTAssertEqualObjects([self eval:@"seconds-from-dateTime('1970-01-01T10:00:00+02:00')"], @"28800");
    XCTAssertEqualObjects([self eval:@"seconds-from-dateTime('1970-01-01T00:00:00Z')"], @"0");
    XCTAssertEqualObjects([self eval:@"seconds-from-dateTime('1970-01-02')"], @"NaN");
    XCTAssertEqualObjects([self eval:@"days-from-date('1970-01-03T23:00:00-05:00')"], @"2");
    XCTAssertEqualObjects([self eval:@"days-from-date('2020-02-30')"], @"NaN");
    XCTAssertEqualObjects([self eval:@"adjust-dateTime-to-timezone('bad')"], @"");
    NSString *adjusted = [self eval:@"adjust-dateTime-to-timezone('2020-01-01T12:00:00Z')"];
    XCTAssertEqual(adjusted.length, (NSUInteger)25, @"%@", adjusted);
}

- (void)testIdWithScopeAndIsValidRecursion // G-84
{
    NSString *xml = @"<d><i xml:id=\"a\">x</i><j xml:id=\"b\">y</j></d>";
    XCTAssertEqualObjects([self evalXML:xml expr:@"id('a b')"], @"x");
    XCTAssertEqualObjects([self evalXML:xml expr:@"count(id('a b'))"], @"2");
    XCTAssertEqualObjects([self evalXML:xml expr:@"id('b', /d)"], @"y");
    XCTAssertEqualObjects([self evalXML:xml expr:@"is-valid(/d)"], @"true");
    XFNodeState *st = [XFNodeState stateOnNode:[[_doc rootElement] elementsForName:@"j"].firstObject];
    st.valid = NO;
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:[_doc rootElement]];
    NSError *error = nil;
    XCTAssertEqualObjects([[XFXPath xpathWithString:@"is-valid(/d)" error:&error] stringValueInContext:ctx error:&error], @"false");
    XCTAssertEqualObjects([[XFXPath xpathWithString:@"is-valid(i)" error:&error] stringValueInContext:ctx error:&error], @"true");
}

- (void)testUnboundVariableAndFromToStep // G-77, G-73
{
    XCTAssertEqualObjects([self eval:@"concat('[', $nothing, ']')"], @"[]");
    XCTAssertEqualObjects([self eval:@"count(fromtostep(1, 5, 2))"], @"3");
    XCTAssertEqualObjects([self eval:@"string-join(fromtostep(1, 3, 1), ',')"], @"1,2,3");
}

- (void)testEventContextValues // G-06
{
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:@"<d><i>1</i><i>2</i></d>" options:0 error:NULL];
    NSArray *items = [[doc rootElement] elementsForName:@"i"];
    NSMutableDictionary *outer = [XFXMLEvents makeEventContext:@{ @"inserted-nodes": items, @"who": @"outer" }
                                                          type:@"xforms-insert" targetid:nil bubbles:YES cancelable:NO];
    NSMutableDictionary *inner = [XFXMLEvents makeEventContext:@{ @"response-headers": @{ @"Content-Type": @"text/xml" },
                                                                  @"response-body": @"<r><v>ok</v></r>" }
                                                          type:@"xforms-submit-done" targetid:nil bubbles:YES cancelable:NO];
    [[XFXMLEvents eventContexts] addObject:outer];
    [[XFXMLEvents eventContexts] addObject:inner];
    @try {
        XFExprContext *ctx = [[XFExprContext alloc] initWithNode:[doc rootElement]];
        NSError *error = nil;
        XCTAssertEqualObjects([[XFXPath xpathWithString:@"count(event('inserted-nodes'))" error:&error] stringValueInContext:ctx error:&error], @"2");
        XCTAssertEqualObjects([[XFXPath xpathWithString:@"event('who')" error:&error] stringValueInContext:ctx error:&error], @"outer");
        XCTAssertEqualObjects([[XFXPath xpathWithString:@"event('response-headers')/name" error:&error] stringValueInContext:ctx error:&error], @"Content-Type");
        XCTAssertEqualObjects([[XFXPath xpathWithString:@"event('response-headers')[name = 'Content-Type']/value" error:&error] stringValueInContext:ctx error:&error], @"text/xml");
        XCTAssertEqualObjects([[XFXPath xpathWithString:@"event('response-body')/v" error:&error] stringValueInContext:ctx error:&error], @"ok");
        XCTAssertEqualObjects([[XFXPath xpathWithString:@"event('type')" error:&error] stringValueInContext:ctx error:&error], @"xforms-submit-done");
    } @finally {
        [[XFXMLEvents eventContexts] removeLastObject];
        [[XFXMLEvents eventContexts] removeLastObject];
    }
}

- (void)testItextTranslations // G-94
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"<head><xf:model>"
        @"  <xf:instance><data xmlns=\"\"><n/></data></xf:instance>"
        @"  <xf:itext>"
        @"    <xf:translation lang=\"en\"><xf:text id=\"hello\"><xf:value>Hello</xf:value></xf:text></xf:translation>"
        @"    <xf:translation lang=\"fr-FR\"><xf:text id=\"hello\"><xf:value>Bonjour</xf:value></xf:text></xf:translation>"
        @"  </xf:itext>"
        @"</xf:model></head><body>"
        @"<xf:output value=\"itext('hello')\"><xf:label>H</xf:label></xf:output>"
        @"</body></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XCTAssertEqualObjects(p.model.defaultLanguage, @"en");
    p.language = @"fr";          // primary-subtag match
    [p refresh:NULL];
    XCTAssertEqualObjects(p.outputControls.firstObject.stringValue, @"Bonjour");
    p.language = @"de";          // unknown → default language
    [p refresh:NULL];
    XCTAssertEqualObjects(p.outputControls.firstObject.stringValue, @"Hello");
    XCTAssertEqualObjects([p.model itextForIdentifier:@"hello" language:@"fr-FR"], @"Bonjour");
    XCTAssertNil([p.model itextForIdentifier:@"nope" language:nil]);
}

@end
