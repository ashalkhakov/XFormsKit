#import "XFFormDocument.h"
#import <XFormsKit/XFXMLTypes.h>
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
    self.documentBaseURL = url;   // fileURL is not set yet during read
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
    // relative instance/@src, includes and schemas resolve DURING
    // construction — the base URL must ride in, never be set after
    NSURL *base = [self fileURL] ?: self.documentBaseURL;
    XFProcessor *processor = [XFProcessor processorWithXMLString:self.sourceXML ?: @""
                                                         baseURL:base
                                                           error:&inner];
    [self.processor close];   // xforms-model-destruct listeners of the old form (G-54)
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
    XFXMLDocument *host = self.processor.hostDocument;
    if (host) {
        NSString *xml = XFHostXMLString(host, XFXMLNodePrettyPrint);
        if (xml.length) {
            self.sourceXML = xml;
        }
    }
    [self updateChangeCount:NSChangeDone];
}

- (BOOL)commitHostTree:(NSError **)error
{
    XFXMLDocument *host = self.processor.hostDocument;
    if (host == nil) {
        return [self reloadProcessor:error];
    }
    NSString *xml = XFHostXMLString(host, XFXMLNodePrettyPrint);
    return [self replaceHostWithXMLString:xml error:error];
}

- (XFXMLElement *)hostRoot
{
    return [self.processor.hostDocument rootElement];
}

- (XFXMLElement *)firstElement:(NSString *)local URI:(NSString *)uri under:(XFXMLNode *)node
{
    if (node == nil) {
        return nil;
    }
    return [XFXML firstElementWithLocalName:local namespaceURI:uri inNode:node];
}

- (XFXMLElement *)modelElement
{
    return [self firstElement:@"model" URI:XFXFormsNamespaceURI under:[self hostRoot]];
}

- (XFXMLElement *)bodyElement
{
    XFXMLElement *html = [self hostRoot];
    XFXMLElement *body = [self firstElement:@"body" URI:XFXHTMLNamespaceURI under:html];
    if (body == nil) {
        body = [self firstElement:@"body" URI:@"" under:html];
    }
    if (body == nil && html) {
        for (XFXMLNode *c in [html children]) {
            if ([c kind] == XFXMLElementKind && [[(XFXMLElement *)c localName] isEqualToString:@"body"]) {
                return (XFXMLElement *)c;
            }
        }
    }
    return body;
}

- (XFXMLElement *)elementWithID:(NSString *)identifier
{
    if (identifier.length == 0) {
        return nil;
    }
    return [XFXML elementWithID:identifier inNode:[self hostRoot]];
}

- (NSString *)uniqueIdentifierWithPrefix:(NSString *)prefix
{
    NSString *base = prefix.length ? prefix : @"xf";
    XFXMLElement *root = [self hostRoot];
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
        NSString *xml = XFHostXMLString(self.processor.hostDocument, XFXMLNodePrettyPrint);
        return xml.length ? xml : self.sourceXML;
    }
    return self.sourceXML ?: @"";
}

- (NSString *)instanceXMLString
{
    XFXMLDocument *doc = [[self.processor defaultInstance] document];
    if (doc == nil) {
        return @"";
    }
    return [doc XMLStringWithOptions:XFXMLNodePrettyPrint] ?: @"";
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)error
{
    (void)typeName;
    NSString *xml = [self hostXMLString] ?: self.sourceXML ?: @"";
    self.sourceXML = xml;
    return [xml dataUsingEncoding:NSUTF8StringEncoding];
}

@end
