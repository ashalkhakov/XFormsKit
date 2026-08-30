#import "XFFormDocument.h"
#import "XFDocumentWindowController.h"
#import <XFormsKit/XFNamespaces.h>
#import <XFormsKit/XFXML.h>

@implementation XFFormDocument

+ (BOOL)autosavesInPlace
{
    return NO;
}

+ (NSString *)blankXML
{
    return
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\"\n"
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\"\n"
        @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\"\n"
        @"      xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">\n"
        @"  <head>\n"
        @"    <title>Untitled</title>\n"
        @"    <xf:model>\n"
        @"      <xf:instance>\n"
        @"        <data xmlns=\"\">\n"
        @"          <n></n>\n"
        @"        </data>\n"
        @"      </xf:instance>\n"
        @"    </xf:model>\n"
        @"  </head>\n"
        @"  <body>\n"
        @"  </body>\n"
        @"</html>\n";
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _sourceXML = [[self class] blankXML];
        [self reloadProcessor:NULL];
    }
    return self;
}

- (NSString *)windowNibName
{
    return nil;
}

- (void)makeWindowControllers
{
    XFDocumentWindowController *wc = [[XFDocumentWindowController alloc] init];
    [self addWindowController:wc];
    [[wc window] makeKeyAndOrderFront:self];
}

- (void)showWindows
{
    if ([[self windowControllers] count] == 0) {
        [self makeWindowControllers];
    }
    for (NSWindowController *wc in [self windowControllers]) {
        if ([wc window] == nil) {
            [wc loadWindow];
        }
        [wc showWindow:self];
    }
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error
{
    NSError *inner = nil;
    NSString *xml = [NSString stringWithContentsOfURL:url
                                             encoding:NSUTF8StringEncoding
                                                error:&inner];
    if (xml == nil) {
        if (error) { *error = inner; }
        return NO;
    }
    self.sourceXML = xml;
    return [self reloadProcessor:error];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)error
{
    NSString *xml = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (xml == nil) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileReadUnknownError
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"Could not decode document as UTF-8" }];
        }
        return NO;
    }
    self.sourceXML = xml;
    return [self reloadProcessor:error];
}

- (void)close
{
    [self.processor close];
    [super close];
}

- (BOOL)reloadProcessor:(NSError **)error
{
    NSError *inner = nil;
    XFProcessor *processor = [XFProcessor processorWithXMLString:self.sourceXML ?: @""
                                                           error:&inner];
    [self.processor close];   // xforms-model-destruct listeners of the old form (G-54)
    if (processor) {
        processor.baseURL = [self fileURL];
    }
    self.processor = processor;
    self.loadError = inner;
    if (processor == nil) {
        if (error) { *error = inner; }
        return NO;
    }
    return YES;
}

- (BOOL)replaceHostWithXMLString:(NSString *)xml error:(NSError **)error
{
    if (xml.length == 0) {
        return NO;
    }
    self.sourceXML = xml;
    [self updateChangeCount:NSChangeDone];
    return [self reloadProcessor:error];
}

- (void)markHostEdited
{
    NSXMLDocument *host = self.processor.hostDocument;
    if (host) {
        NSString *xml = XFHostXMLString(host, NSXMLNodePrettyPrint);
        if (xml.length) {
            self.sourceXML = xml;
        }
    }
    [self updateChangeCount:NSChangeDone];
}

- (BOOL)commitHostTree:(NSError **)error
{
    NSXMLDocument *host = self.processor.hostDocument;
    if (host == nil) {
        return [self reloadProcessor:error];
    }
    NSString *xml = XFHostXMLString(host, NSXMLNodePrettyPrint);
    return [self replaceHostWithXMLString:xml error:error];
}

- (NSXMLElement *)hostRoot
{
    return [self.processor.hostDocument rootElement];
}

- (NSXMLElement *)firstElement:(NSString *)local URI:(NSString *)uri under:(NSXMLNode *)node
{
    if (node == nil) {
        return nil;
    }
    return [XFXML firstElementWithLocalName:local namespaceURI:uri inNode:node];
}

- (NSXMLElement *)modelElement
{
    return [self firstElement:@"model" URI:XFXFormsNamespaceURI under:[self hostRoot]];
}

- (NSXMLElement *)bodyElement
{
    NSXMLElement *html = [self hostRoot];
    NSXMLElement *body = [self firstElement:@"body" URI:XFXHTMLNamespaceURI under:html];
    if (body == nil) {
        body = [self firstElement:@"body" URI:@"" under:html];
    }
    if (body == nil && html) {
        for (NSXMLNode *c in [html children]) {
            if ([c kind] == NSXMLElementKind && [[(NSXMLElement *)c localName] isEqualToString:@"body"]) {
                return (NSXMLElement *)c;
            }
        }
    }
    return body;
}

- (NSXMLElement *)elementWithID:(NSString *)identifier
{
    if (identifier.length == 0) {
        return nil;
    }
    return [XFXML elementWithID:identifier inNode:[self hostRoot]];
}

- (NSString *)uniqueIdentifierWithPrefix:(NSString *)prefix
{
    NSString *base = prefix.length ? prefix : @"xf";
    NSXMLElement *root = [self hostRoot];
    for (NSUInteger i = 1; i < 10000; i++) {
        NSString *ident = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)i];
        if ([XFXML elementWithID:ident inNode:root] == nil) {
            return ident;
        }
    }
    return [base stringByAppendingString:@"x"];
}

- (NSString *)hostXMLString
{
    if (self.processor.hostDocument) {
        NSString *xml = XFHostXMLString(self.processor.hostDocument, NSXMLNodePrettyPrint);
        return xml.length ? xml : self.sourceXML;
    }
    return self.sourceXML ?: @"";
}

- (NSString *)instanceXMLString
{
    NSXMLDocument *doc = [[self.processor defaultInstance] document];
    if (doc == nil) {
        return @"";
    }
    return [doc XMLStringWithOptions:NSXMLNodePrettyPrint] ?: @"";
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)error
{
    (void)typeName;
    NSString *xml = [self hostXMLString] ?: self.sourceXML ?: @"";
    self.sourceXML = xml;
    return [xml dataUsingEncoding:NSUTF8StringEncoding];
}

@end
