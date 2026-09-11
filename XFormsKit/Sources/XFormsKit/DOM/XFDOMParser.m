#import "XFDOMPriv.h"

/// Builds an XFDOM tree from XML data.
///
/// NSXMLParser's own namespace processing is left OFF on purpose: with it
/// on, the parser consumes xmlns declarations and reports only resolved
/// URIs, but the DOM has to keep the declarations themselves (they are
/// nodes in `namespaces`, and submission serialisation re-emits them). So
/// the scope stack is maintained here, from the raw xmlns attributes.
@interface XFDOMParser () <NSXMLParserDelegate>
@property (nonatomic, strong) XFDOMDocument *document;
@property (nonatomic, strong) NSMutableArray<XFDOMElement *> *stack;
@property (nonatomic, strong) NSMutableString *pendingText;
@property (nonatomic, assign) BOOL preserveWhitespace;
@property (nonatomic, strong, nullable) NSError *failure;
@end

@implementation XFDOMParser

+ (XFDOMDocument *)documentWithData:(NSData *)data
                            options:(XFDOMNodeOptions)options
                              error:(NSError **)error
{
    XFDOMParser *builder = [[XFDOMParser alloc] init];
    builder.document = [[XFDOMDocument alloc] init];
    builder.stack = [NSMutableArray array];
    builder.pendingText = [NSMutableString string];
    builder.preserveWhitespace = (options & XFDOMNodePreserveWhitespace) != 0;

    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    parser.delegate = builder;
    parser.shouldProcessNamespaces = NO;
    parser.shouldReportNamespacePrefixes = NO;
    parser.shouldResolveExternalEntities = NO;

    if (![parser parse] || builder.failure != nil) {
        if (error) {
            *error = builder.failure ?: [parser parserError]
                ?: [NSError errorWithDomain:XFDOMErrorDomain code:2 userInfo:@{
                       NSLocalizedDescriptionKey: @"the document is not well-formed XML" }];
        }
        return nil;
    }
    if (builder.document.rootElement == nil) {
        if (error) {
            *error = [NSError errorWithDomain:XFDOMErrorDomain code:3 userInfo:@{
                NSLocalizedDescriptionKey: @"the document has no root element" }];
        }
        return nil;
    }
    return builder.document;
}

#pragma mark Text

/// Whitespace-only text between elements is dropped, which is what both
/// Apple's and GNUstep's NSXML expose through `children` (Apple keeps it
/// internally and still serialises it; GNUstep discards it at parse
/// time). The engine relies on this — it re-inserts the gaps it actually
/// needs in host markup through the <!--xf:ws--> marker in XFProcessor.
- (void)flushText
{
    if (self.pendingText.length == 0) {
        return;
    }
    NSString *text = [self.pendingText copy];
    [self.pendingText setString:@""];
    BOOL blank = [text stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0;
    if (self.stack.count == 0) {
        return;   // text outside the root element is not representable
    }
    if (blank && !self.preserveWhitespace) {
        return;
    }
    [[self.stack lastObject] addChild:[XFDOMNode textWithStringValue:text]];
}

#pragma mark NSXMLParserDelegate

- (void)parser:(NSXMLParser *)parser
    didStartElement:(NSString *)elementName
       namespaceURI:(NSString *)namespaceURI
      qualifiedName:(NSString *)qName
         attributes:(NSDictionary<NSString *, NSString *> *)attributeDict
{
    [self flushText];

    // With namespace processing off, elementName is the qualified name.
    NSString *name = qName.length ? qName : elementName;
    XFDOMElement *element = [[XFDOMElement alloc] initWithName:name URI:nil];

    // Declarations first: an attribute on this element may use a prefix
    // this element itself declares.
    for (NSString *attributeName in [[attributeDict allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        if ([attributeName isEqualToString:@"xmlns"]) {
            [element addNamespace:[XFDOMNode namespaceWithName:@""
                                                   stringValue:attributeDict[attributeName]]];
        } else if ([attributeName hasPrefix:@"xmlns:"]) {
            [element addNamespace:[XFDOMNode namespaceWithName:[attributeName substringFromIndex:6]
                                                   stringValue:attributeDict[attributeName]]];
        }
    }

    if (self.stack.count == 0) {
        self.document.rootElement = element;
    } else {
        [[self.stack lastObject] addChild:element];
    }
    // resolvable only once the element is attached to its ancestors
    element.URI = [[element resolveNamespaceForName:name] stringValue];
    if (element.URI.length == 0) {
        element.URI = nil;
    }

    for (NSString *attributeName in [[attributeDict allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        if ([attributeName isEqualToString:@"xmlns"] || [attributeName hasPrefix:@"xmlns:"]) {
            continue;
        }
        XFDOMNode *attribute = [XFDOMNode attributeWithName:attributeName
                                                stringValue:attributeDict[attributeName]];
        // an unprefixed attribute is in no namespace, never the default one
        if ([attributeName rangeOfString:@":"].location != NSNotFound) {
            NSString *uri = [[element resolveNamespaceForName:attributeName] stringValue];
            attribute.URI = uri.length ? uri : nil;
        }
        [element addAttribute:attribute];
    }

    [self.stack addObject:element];
}

- (void)parser:(NSXMLParser *)parser
    didEndElement:(NSString *)elementName
     namespaceURI:(NSString *)namespaceURI
    qualifiedName:(NSString *)qName
{
    [self flushText];
    [self.stack removeLastObject];
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    [self.pendingText appendString:string];
}

/// A CDATA section parses to an ordinary text node, which is what NSXML
/// does: Apple's round-trip of "<r><![CDATA[cd]]></r>" comes back as
/// "<r>cd</r>". The CDATA form is a serialisation choice, requested with
/// XFDOMNodeIsCDATA, not a property of the parsed content — see
/// XFSubmission's @cdata-section-elements handling, which today works
/// around GNUstep ignoring that option.
- (void)parser:(NSXMLParser *)parser foundCDATA:(NSData *)CDATABlock
{
    NSString *text = [[NSString alloc] initWithData:CDATABlock encoding:NSUTF8StringEncoding];
    if (text == nil) {
        return;
    }
    [self.pendingText appendString:text];
    [self flushText];
}

- (void)parser:(NSXMLParser *)parser foundComment:(NSString *)comment
{
    [self flushText];
    XFDOMNode *node = [XFDOMNode commentWithStringValue:comment];
    if (self.stack.count == 0) {
        node.parent = self.document;
        [self.document.mutableChildren addObject:node];
    } else {
        [[self.stack lastObject] addChild:node];
    }
}

- (void)parser:(NSXMLParser *)parser
    foundProcessingInstructionWithTarget:(NSString *)target
                                   data:(NSString *)data
{
    [self flushText];
    XFDOMNode *node = [XFDOMNode processingInstructionWithName:target stringValue:data ?: @""];
    if (self.stack.count == 0) {
        node.parent = self.document;
        [self.document.mutableChildren addObject:node];
    } else {
        [[self.stack lastObject] addChild:node];
    }
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    if (self.failure == nil) {
        self.failure = parseError;
    }
}

@end
