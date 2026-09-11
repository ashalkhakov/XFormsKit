#import <XCTest/XCTest.h>
#import <XFormsKit/XFDOM.h>

/// Differential tests for XFDOM.
///
/// The specification XFDOM is written against is not a document, it is
/// the behaviour of the NSXML implementation the engine grew up on. So
/// almost every case here runs the same operation twice — once through
/// NSXML, once through XFDOM — and asserts the answers agree. Because
/// NSXML exists on both Apple Foundation and GNUstep base, running this
/// suite on each platform is what pins XFDOM to both.
///
/// Where the two NSXML implementations themselves disagree (serialised
/// whitespace is the known case) the test says so and asserts only what
/// they agree on.
@interface XFDOMTests : XCTestCase
@end

@implementation XFDOMTests

- (XFDOMDocument *)parse:(NSString *)xml
{
    NSError *error = nil;
    XFDOMDocument *doc = [[XFDOMDocument alloc] initWithXMLString:xml
                                                          options:XFDOMNodeOptionsNone
                                                            error:&error];
    XCTAssertNotNil(doc, @"XFDOM failed to parse: %@", error);
    return doc;
}

- (NSXMLDocument *)parseNS:(NSString *)xml
{
    NSError *error = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:&error];
    XCTAssertNotNil(doc, @"NSXML failed to parse: %@", error);
    return doc;
}

#pragma mark - Structure

- (void)testChildrenMatchNSXMLIncludingWhitespaceHandling
{
    NSString *xml = @"<data>\n  <a>1</a>\n  <b>2</b>\n</data>";
    XCTAssertEqual([[self parse:xml] rootElement].childCount,
                   [[[self parseNS:xml] rootElement] childCount],
                   @"whitespace-only text between elements must be dropped, as NSXML does");

    // mixed content keeps its text, in both
    NSString *mixed = @"<p>hello <b>x</b> there</p>";
    XCTAssertEqual([[self parse:mixed] rootElement].childCount,
                   [[[self parseNS:mixed] rootElement] childCount]);
}

- (void)testKindsMatchNSXMLNumerically
{
    NSString *xml = @"<data><!--c--><a>t</a></data>";
    NSArray<XFDOMNode *> *mine = [[self parse:xml] rootElement].children;
    NSArray<NSXMLNode *> *theirs = [[[self parseNS:xml] rootElement] children];
    XCTAssertEqual(mine.count, theirs.count);
    for (NSUInteger i = 0; i < MIN(mine.count, theirs.count); i++) {
        XCTAssertEqual((NSUInteger)mine[i].kind, (NSUInteger)[theirs[i] kind],
                       @"kind %lu", (unsigned long)i);
    }
    XCTAssertEqual([[self parse:xml] kind], (XFDOMNodeKind)XFDOMDocumentKind);
}

- (void)testIndexSiblingsAndDetach
{
    XFDOMElement *root = [[self parse:@"<r><a/><b/><c/></r>"] rootElement];
    XFDOMNode *b = [root childAtIndex:1];
    XCTAssertEqual(b.index, (NSUInteger)1);
    XCTAssertEqualObjects(b.previousSibling.name, @"a");
    XCTAssertEqualObjects(b.nextSibling.name, @"c");

    [b detach];
    XCTAssertNil(b.parent);
    XCTAssertEqual(root.childCount, (NSUInteger)2);
    XCTAssertEqualObjects([root childAtIndex:1].name, @"c");

    // a detached node stays usable and can be re-inserted
    [root insertChild:b atIndex:0];
    XCTAssertEqual(b.index, (NSUInteger)0);
    XCTAssertEqual(root.childCount, (NSUInteger)3);
}

#pragma mark - Names and namespaces

- (void)testNamesAndNamespacesMatchNSXML
{
    NSString *xml = @"<h:data xmlns:h=\"urn:h\" xmlns=\"urn:d\" h:k=\"v\" plain=\"p\"><kid/></h:data>";
    XFDOMElement *mine = [[self parse:xml] rootElement];
    NSXMLElement *theirs = [[self parseNS:xml] rootElement];

    XCTAssertEqualObjects(mine.name, [theirs name]);
    XCTAssertEqualObjects(mine.localName, [theirs localName]);
    XCTAssertEqualObjects(mine.prefix, [theirs prefix]);
    XCTAssertEqualObjects(mine.URI, [theirs URI]);

    // the namespaces / attributes split is the one the engine depends on
    XCTAssertEqual(mine.namespaces.count, [[theirs namespaces] count]);
    XCTAssertEqual(mine.attributes.count, [[theirs attributes] count]);
    XCTAssertEqualObjects([mine attributeForName:@"h:k"].stringValue,
                          [[theirs attributeForName:@"h:k"] stringValue]);
    XCTAssertEqualObjects([mine attributeForName:@"plain"].stringValue, @"p");

    // an unprefixed attribute is in no namespace even under a default one
    XCTAssertNil([mine attributeForName:@"plain"].URI);
    // a child inherits the default namespace
    XCTAssertEqualObjects([mine childAtIndex:0].URI, @"urn:d");
}

/// Attribute lookup is by QUALIFIED name in NSXML: asking for "k" does
/// not find "h:k". Getting this wrong would silently break every binding
/// attribute lookup in the engine.
- (void)testAttributeLookupMatchesNSXML
{
    NSString *xml = @"<r xmlns:h=\"urn:h\" h:k=\"prefixed\" plain=\"p\"/>";
    XFDOMElement *mine = [[self parse:xml] rootElement];
    NSXMLElement *theirs = [[self parseNS:xml] rootElement];

    XCTAssertEqualObjects([mine attributeForName:@"h:k"].stringValue,
                          [[theirs attributeForName:@"h:k"] stringValue]);
    XCTAssertNil([mine attributeForName:@"k"]);
    XCTAssertNil([theirs attributeForName:@"k"], @"pinning: NSXML matches the qualified name only");
    XCTAssertEqualObjects([mine attributeForLocalName:@"k" URI:@"urn:h"].stringValue, @"prefixed");

    XCTAssertNil([mine attributeForName:@"plain"].URI);
    XCTAssertNil([[theirs attributeForName:@"plain"] URI]);
    XCTAssertEqualObjects([mine attributeForName:@"h:k"].URI, @"urn:h");
    XCTAssertEqualObjects([[theirs attributeForName:@"h:k"] URI], @"urn:h");
}

- (void)testResolveNamespaceSearchesAncestors
{
    XFDOMElement *root = [[self parse:@"<r xmlns:xf=\"urn:xf\"><mid><leaf/></mid></r>"] rootElement];
    XFDOMElement *leaf = (XFDOMElement *)[[root childAtIndex:0] childAtIndex:0];
    XCTAssertEqualObjects([[leaf resolveNamespaceForName:@"xf:anything"] stringValue], @"urn:xf");
    XCTAssertNil([leaf resolveNamespaceForName:@"nope:x"]);
    // namespaceForPrefix: is local only
    XCTAssertNil([leaf namespaceForPrefix:@"xf"]);
    XCTAssertNotNil([root namespaceForPrefix:@"xf"]);
}

#pragma mark - Values

- (void)testStringValueMatchesNSXMLOnOrdinaryContent
{
    NSString *xml = @"<r>a<b>c</b>d</r>";
    XCTAssertEqualObjects([[self parse:xml] rootElement].stringValue,
                          [[[self parseNS:xml] rootElement] stringValue]);

    XFDOMElement *root = [[self parse:xml] rootElement];
    root.stringValue = @"replaced";
    XCTAssertEqualObjects(root.stringValue, @"replaced");
    XCTAssertEqual(root.childCount, (NSUInteger)1, @"setting a string value collapses the content");
}

/// A DELIBERATE divergence from Apple's NSXML, not an oversight.
///
/// Apple's -[NSXMLElement stringValue] concatenates every descendant,
/// comments and processing-instruction data included:
/// "<r>a<b>c</b>d<!--x--></r>" answers "acdx", and "<r>a<?pi dat?>b</r>"
/// answers "adatb". XPath 1.0 string-value is text (and CDATA) only, and
/// XForms needs the XPath meaning — a comment inside instance data must
/// not leak into a submitted value.
///
/// The engine already refuses NSXML's answer for exactly this reason:
/// +[XFXML stringValueOfNode:] walks the children itself and keeps only
/// text and element kinds. XFDOM implements that directly, so the
/// workaround can eventually go.
- (void)testStringValueUsesXPathSemanticsNotNSXMLs
{
    XFDOMElement *withComment = [[self parse:@"<r>a<b>c</b>d<!--x--></r>"] rootElement];
    XCTAssertEqualObjects(withComment.stringValue, @"acd");
    XCTAssertEqualObjects([[[self parseNS:@"<r>a<b>c</b>d<!--x--></r>"] rootElement] stringValue],
                          @"acdx", @"pinning the Apple behaviour we are diverging from");

    XFDOMElement *withPI = [[self parse:@"<r>a<?pi dat?>b</r>"] rootElement];
    XCTAssertEqualObjects(withPI.stringValue, @"ab");

    // the node's own value is still readable through the comment node
    XCTAssertEqualObjects([withComment childAtIndex:3].stringValue, @"x");
}

/// CDATA parses to an ordinary text node, as in NSXML: the CDATA form is
/// a serialisation option, not a property of the content.
- (void)testCDATARoundTripMatchesNSXML
{
    NSString *xml = @"<r><![CDATA[c & d]]></r>";
    XCTAssertEqualObjects([[self parse:xml] rootElement].stringValue,
                          [[[self parseNS:xml] rootElement] stringValue]);
    XCTAssertEqualObjects([[[self parse:xml] rootElement] XMLString],
                          [[[self parseNS:xml] rootElement] XMLString]);

    // asked for explicitly, the text comes back wrapped
    XCTAssertEqualObjects([[[self parse:xml] rootElement] XMLStringWithOptions:XFDOMNodeIsCDATA],
                          @"<r><![CDATA[c & d]]></r>");
}

#pragma mark - Serialisation

- (void)testXMLStringMatchesNSXML
{
    // element-only content, so the two agree on whitespace too
    NSString *xml = @"<data xmlns=\"urn:d\" xmlns:h=\"urn:h\">"
                     "<name h:k=\"v &amp; w\">Ada &amp; Co</name>"
                     "<empty/><lt>a &lt; b</lt></data>";
    NSString *mine = [[self parse:xml] XMLString];
    NSString *theirs = [[self parseNS:xml] XMLString];
    XCTAssertEqualObjects(mine, theirs);
}

- (void)testEscapingMatchesNSXML
{
    NSXMLElement *theirs = [NSXMLElement elementWithName:@"e"];
    [theirs setStringValue:@"< & > \" '"];
    [theirs addAttribute:[NSXMLNode attributeWithName:@"a" stringValue:@"< & > \" '"]];

    XFDOMElement *mine = [XFDOMElement elementWithName:@"e"];
    mine.stringValue = @"< & > \" '";
    [mine addAttribute:[XFDOMNode attributeWithName:@"a" stringValue:@"< & > \" '"]];

    XCTAssertEqualObjects([mine XMLString], [theirs XMLString]);
}

- (void)testBuiltTreeSerialisesLikeNSXML
{
    NSXMLElement *theirs = [NSXMLElement elementWithName:@"data"];
    [theirs addNamespace:[NSXMLNode namespaceWithName:@"xf" stringValue:@"urn:xf"]];
    [theirs addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:@"1"]];
    [theirs addChild:[NSXMLElement elementWithName:@"kid"]];

    XFDOMElement *mine = [XFDOMElement elementWithName:@"data"];
    [mine addNamespace:[XFDOMNode namespaceWithName:@"xf" stringValue:@"urn:xf"]];
    [mine addAttribute:[XFDOMNode attributeWithName:@"id" stringValue:@"1"]];
    [mine addChild:[XFDOMElement elementWithName:@"kid"]];

    XCTAssertEqualObjects([mine XMLString], [theirs XMLString]);
}

#pragma mark - Copying

- (void)testCopyIsDeepAndDetached
{
    XFDOMDocument *doc = [self parse:@"<r xmlns:h=\"urn:h\"><a h:k=\"v\">t</a></r>"];
    XFDOMElement *root = [doc rootElement];
    XFDOMElement *copy = [root copy];

    XCTAssertNil(copy.parent, @"a copy is detached, as in NSXML");
    XCTAssertEqualObjects([copy XMLString], [root XMLString]);
    XCTAssertNotEqual(copy, root);
    XCTAssertNotEqual([copy childAtIndex:0], [root childAtIndex:0], @"children are copied too");

    // and the copy is independent
    [(XFDOMElement *)[copy childAtIndex:0] setStringValue:@"changed"];
    XCTAssertEqualObjects([root childAtIndex:0].stringValue, @"t");

    XFDOMDocument *docCopy = [doc copy];
    XCTAssertNotNil([docCopy rootElement]);
    XCTAssertEqualObjects([docCopy XMLString], [doc XMLString]);
    XCTAssertNotEqual([docCopy rootElement], [doc rootElement]);
}

#pragma mark - Identity

- (void)testNodesKeepIdentityForAssociatedState
{
    // XFNodeState hangs MIP state off nodes with objc_setAssociatedObject
    // and XFExprContext compares them with indexOfObjectIdenticalTo:, so
    // the same node must come back from every accessor, every time.
    XFDOMElement *root = [[self parse:@"<r><a/></r>"] rootElement];
    XFDOMNode *first = [root childAtIndex:0];
    XCTAssertEqual(first, [root childAtIndex:0]);
    XCTAssertEqual(first, root.children[0]);
    XCTAssertEqual(first, first.parent.children[0]);
    XCTAssertEqual((NSUInteger)[root.children indexOfObjectIdenticalTo:first], (NSUInteger)0);
}

#pragma mark - Errors

- (void)testMalformedDocumentFailsLikeNSXML
{
    NSError *mineError = nil;
    XFDOMDocument *mine = [[XFDOMDocument alloc] initWithXMLString:@"<a><b></a>"
                                                           options:XFDOMNodeOptionsNone
                                                             error:&mineError];
    NSError *theirsError = nil;
    NSXMLDocument *theirs = [[NSXMLDocument alloc] initWithXMLString:@"<a><b></a>"
                                                             options:0
                                                               error:&theirsError];
    XCTAssertNil(mine);
    XCTAssertNotNil(mineError);
    XCTAssertNil(theirs, @"NSXML rejects it too, so XFDOM must not be more permissive");
}

@end
