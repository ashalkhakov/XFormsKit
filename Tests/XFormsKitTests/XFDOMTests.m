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

/// Apple's NSXML and GNUstep's do NOT agree on everything, so for some
/// questions there is no single reference answer to assert against. Those
/// cases are marked below: XFDOM picks one answer, the test pins that
/// answer exactly — it has to be identical on every platform, which is the
/// entire point of having our own DOM — and the platform's answer is
/// recorded here for whoever reads the log.
static void XFNoteReference(NSString *what, id value)
{
    NSLog(@"[XFDOMTests] this platform's NSXML: %@ = %@", what, value ?: @"(nil)");
}

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
    XCTAssertNil([mine attributeForName:@"k"], @"lookup is by qualified name");
    // DIVERGENT: Apple answers nil here, GNUstep finds the prefixed
    // attribute by its local name. XFDOM follows Apple, which is also what
    // NSXML documents; the engine only ever asks for names it wrote.
    XFNoteReference(@"attributeForName:@\"k\" against h:k", [theirs attributeForName:@"k"]);
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

/// XML Namespaces binds "xml" and "xmlns" without a declaration, so
/// xml:id and xml:lang resolve in any document — and, as in NSXML, the
/// implicit binding does not show up in `namespaces`.
- (void)testReservedPrefixesResolveWithoutDeclaration
{
    NSString *xml = @"<data xmlns=\"\"><item xml:id=\"a\" xml:lang=\"en\">x</item></data>";
    XFDOMElement *mine = (XFDOMElement *)[[[self parse:xml] rootElement] childAtIndex:0];
    NSXMLElement *theirs = (NSXMLElement *)[[[self parseNS:xml] rootElement] childAtIndex:0];

    XCTAssertEqualObjects([mine attributeForName:@"xml:id"].URI,
                          @"http://www.w3.org/XML/1998/namespace");
    XCTAssertEqualObjects([[mine resolveNamespaceForName:@"xml:id"] stringValue],
                          @"http://www.w3.org/XML/1998/namespace");
    XCTAssertEqual(mine.namespaces.count, (NSUInteger)0,
                   @"the implicit binding is not a declaration");

    // DIVERGENT: Apple resolves the reserved prefix, GNUstep leaves xml:id
    // in no namespace. XFDOM follows the XML Namespaces specification,
    // which makes xml: bound everywhere without a declaration.
    XFNoteReference(@"URI of xml:id", [[theirs attributeForName:@"xml:id"] URI]);
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
    // DIVERGENT: Apple answers "acdx", GNUstep "acd". XFDOM implements the
    // XPath meaning, so it agrees with GNUstep and deliberately not with
    // Apple.
    XFNoteReference(@"stringValue of <r>a<b>c</b>d<!--x--></r>",
                    [[[self parseNS:@"<r>a<b>c</b>d<!--x--></r>"] rootElement] stringValue]);

    XFDOMElement *withPI = [[self parse:@"<r>a<?pi dat?>b</r>"] rootElement];
    XCTAssertEqualObjects(withPI.stringValue, @"ab");

    // the node's own value is still readable through the comment node
    XCTAssertEqualObjects([withComment childAtIndex:3].stringValue, @"x");
}

/// CDATA parses to an ordinary text node: the CDATA form is a
/// serialisation option, not a property of the content.
- (void)testCDATAParsesToTextAndSerialisesEscaped
{
    NSString *xml = @"<r><![CDATA[c & d]]></r>";

    // the value is the same everywhere, and both NSXMLs agree on it
    XCTAssertEqualObjects([[self parse:xml] rootElement].stringValue, @"c & d");
    XCTAssertEqualObjects([[self parse:xml] rootElement].stringValue,
                          [[[self parseNS:xml] rootElement] stringValue]);

    // DIVERGENT: Apple re-serialises it as escaped text, GNUstep keeps the
    // CDATA section. XFDOM escapes, so the bytes it writes for a given tree
    // are the same on every platform.
    XCTAssertEqualObjects([[[self parse:xml] rootElement] XMLString], @"<r>c &amp; d</r>");
    XFNoteReference(@"XMLString of a parsed CDATA section",
                    [[[self parseNS:xml] rootElement] XMLString]);

    // asked for explicitly, the text comes back wrapped
    XCTAssertEqualObjects([[[self parse:xml] rootElement] XMLStringWithOptions:XFDOMNodeIsCDATA],
                          @"<r><![CDATA[c & d]]></r>");
}

/// A single text node can be marked as a section, which is how
/// xf:submission serialises @cdata-section-elements. It used to write a
/// token into the tree and patch the serialised string afterwards,
/// because GNUstep's NSXML ignored NSXMLNodeIsCDATA.
- (void)testATextNodeCanBeAskedToSerialiseAsASection
{
    XFDOMElement *root = [XFDOMElement elementWithName:@"r"];
    [root addChild:[XFDOMNode CDATAWithStringValue:@"c & d"]];
    [root addChild:[XFDOMNode textWithStringValue:@" e & f"]];
    // the section is not escaped, the ordinary text beside it still is
    XCTAssertEqualObjects([root XMLString], @"<r><![CDATA[c & d]]> e &amp; f</r>");
    // and the value reads back as the text it stands for
    XCTAssertEqualObjects([root stringValue], @"c & d e & f");

    // "]]>" cannot appear inside a section: it closes and reopens around
    // it, which a parser reads back as one run
    XFDOMElement *tricky = [XFDOMElement elementWithName:@"r"];
    [tricky addChild:[XFDOMNode CDATAWithStringValue:@"a ]]> b"]];
    XCTAssertEqualObjects([tricky XMLString], @"<r><![CDATA[a ]]]]><![CDATA[> b]]></r>");
    XCTAssertEqualObjects([[[self parse:[tricky XMLString]] rootElement] stringValue], @"a ]]> b");
}

#pragma mark - Serialisation

/// The exact bytes XFDOM writes for a parsed document. Pinned literally
/// rather than compared with NSXML: the two NSXMLs disagree on the empty
/// element form (Apple writes <empty></empty>, GNUstep <empty/>), and a
/// serialisation that changed with the platform would defeat the point of
/// the portable DOM — the W3C suite compares submitted instance bytes.
- (void)testDocumentSerialisationIsExactAndPlatformIndependent
{
    NSString *xml = @"<data xmlns=\"urn:d\" xmlns:h=\"urn:h\">"
                     "<name h:k=\"v &amp; w\">Ada &amp; Co</name>"
                     "<empty/><lt>a &lt; b</lt></data>";
    XCTAssertEqualObjects([[self parse:xml] XMLString],
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
         "<data xmlns=\"urn:d\" xmlns:h=\"urn:h\">"
         "<name h:k=\"v &amp; w\">Ada &amp; Co</name>"
         "<empty></empty><lt>a &lt; b</lt></data>");
    XFNoteReference(@"XMLString of the same document", [[self parseNS:xml] XMLString]);
}

/// Escaping, pinned exactly. Markup characters are escaped in text; an
/// attribute value additionally escapes the delimiter. Apostrophes are
/// left alone in both, since the delimiter written is always a quote.
///
/// Not compared with NSXML: GNUstep's -setStringValue: runs the string
/// through libxml2's entity parser, which reports "unterminated entity
/// reference" for a bare ampersand and does not produce a comparable
/// answer.
/// XFDOMNodePrettyPrint, which the source views and the instance editor
/// serialise through.
///
/// Asserted literally, and logged beside the platform's NSXML for
/// comparison — the same shape as the rest of this suite. Two rules
/// matter more than the exact spacing: an element whose children are all
/// elements is broken across lines, and an element with TEXT in it is
/// left exactly as it stands, since indentation inside mixed content
/// would change the value the document carries.
- (void)testPrettyPrintIndentsStructureAndLeavesTextAlone
{
    NSString *xml = @"<data><item><name>Ada</name><qty>7</qty></item>"
                    @"<note>a <b>bold</b> word</note></data>";
    XFDOMDocument *doc = [self parse:xml];
    XCTAssertNotNil(doc);
    NSString *pretty = [doc.rootElement XMLStringWithOptions:XFDOMNodePrettyPrint];
    NSLog(@"[XFDOMTests] XFDOM pretty print:\n%@", pretty);

    // structure is broken across lines and indented two spaces per level
    XCTAssertTrue([pretty containsString:@"<data>\n  <item>"], @"%@", pretty);
    XCTAssertTrue([pretty containsString:@"\n    <name>Ada</name>"], @"%@", pretty);
    XCTAssertTrue([pretty containsString:@"\n  </item>"], @"%@", pretty);
    // a text-bearing element keeps its content verbatim, mixed or not
    XCTAssertTrue([pretty containsString:@"<name>Ada</name>"], @"%@", pretty);
    XCTAssertTrue([pretty containsString:@"<note>a <b>bold</b> word</note>"],
                  @"mixed content must not be reflowed: %@", pretty);
    // and it is still the same document
    XCTAssertFalse([pretty containsString:@"  Ada"], @"%@", pretty);

#if !TARGET_OS_IPHONE
    NSError *error = nil;
    NSXMLDocument *reference = [[NSXMLDocument alloc] initWithXMLString:xml
                                                               options:0
                                                                 error:&error];
    NSLog(@"[XFDOMTests] this platform's NSXML pretty print:\n%@",
          [[reference rootElement] XMLStringWithOptions:NSXMLNodePrettyPrint]);
#endif
}

/// Without the option nothing is indented — the engine's own
/// serialisation, which submissions depend on, is untouched.
- (void)testPlainSerialisationIsUnchangedByThePrettyPrinter
{
    NSString *xml = @"<data><item><name>Ada</name></item></data>";
    XFDOMDocument *doc = [self parse:xml];
    XCTAssertEqualObjects([doc.rootElement XMLStringWithOptions:XFDOMNodeOptionsNone],
                          @"<data><item><name>Ada</name></item></data>");
}

- (void)testEscapingIsExactAndPlatformIndependent
{
    XFDOMElement *mine = [XFDOMElement elementWithName:@"e"];
    mine.stringValue = @"< & > \" '";
    [mine addAttribute:[XFDOMNode attributeWithName:@"a" stringValue:@"< & > \" '"]];

    XCTAssertEqualObjects([mine XMLString],
                          @"<e a=\"&lt; &amp; &gt; &quot; '\">&lt; &amp; &gt; \" '</e>");
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
