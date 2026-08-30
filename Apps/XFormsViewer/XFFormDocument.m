#import "XFFormDocument.h"

@implementation XFFormDocument

+ (BOOL)autosavesInPlace
{
    return NO;
}

- (NSString *)windowNibName
{
    return nil;
}

- (void)makeWindowControllers
{
    Class cls = NSClassFromString(@"XFDocumentWindowController");
    NSWindowController *wc = [[cls alloc] initWithWindow:nil];
    [self addWindowController:wc];
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error
{
    NSError *inner = nil;
    NSString *xml = [NSString stringWithContentsOfURL:url
                                             encoding:NSUTF8StringEncoding
                                                error:&inner];
    if (xml == nil) {
        if (error) {
            *error = inner;
        }
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

- (BOOL)reloadProcessor:(NSError **)error
{
    NSError *inner = nil;
    XFProcessor *processor = [XFProcessor processorWithXMLString:self.sourceXML ?: @""
                                                           error:&inner];
    self.processor = processor;
    self.loadError = inner;
    if (processor == nil) {
        if (error) {
            *error = inner;
        }
        return NO;
    }
    return YES;
}

- (NSString *)hostXMLString
{
    if (self.processor.hostDocument) {
        return [self.processor.hostDocument XMLStringWithOptions:NSXMLNodePrettyPrint] ?: self.sourceXML;
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
    NSString *xml = self.sourceXML ?: @"";
    return [xml dataUsingEncoding:NSUTF8StringEncoding];
}

@end
