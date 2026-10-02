#import "XFDDocument.h"
#import <XFormsKit/XFXMLTypes.h>
#import "XFDWindowController.h"

@interface XFDDocument ()
@property (nonatomic, strong, readwrite) XFProcessor *processor;
@property (nonatomic, strong, readwrite) XFHostEdit *hostEdit;
@property (nonatomic, copy) NSString *pendingXML;   // set by readFromData:, consumed once
/// Where the document came from — captured in readFromURL: (fileURL is
/// set only after the read returns) so relative instance/@src, includes
/// and schemas resolve on the very first processor build.
@property (nonatomic, copy) NSURL *documentBaseURL;
@end

@implementation XFDDocument

/// The window's nib in this framework's bundle, not the host app's: compiled
/// (.nib) by Xcode, the xib itself on GNUstep, which loads it through GSXib5.
static NSString *XFDWindowNibPath(void)
{
    NSBundle *bundle = [NSBundle bundleForClass:[XFDWindowController class]];
    return [bundle pathForResource:@"XFDDocumentWindow" ofType:@"nib"]
        ?: [bundle pathForResource:@"XFDDocumentWindow" ofType:@"xib"];
}

- (void)makeWindowControllers
{
    NSString *path = XFDWindowNibPath();
    if (path == nil) {
        NSLog(@"XFormsDesignKit: XFDDocumentWindow is not in %@",
              [[NSBundle bundleForClass:[XFDWindowController class]] bundlePath]);
        return;
    }
    XFDWindowController *controller = [XFDWindowController alloc];
    controller = [controller initWithWindowNibPath:path owner:controller];
    [self addWindowController:controller];
}

+ (NSMenuItem *)formMenuItem
{
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Form"];
    [menu addItemWithTitle:@"Insert Element" action:@selector(insertElement:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Delete Element" action:@selector(deleteElement:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Reset Instance Data" action:@selector(resetInstances:) keyEquivalent:@""];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Form" action:NULL keyEquivalent:@""];
    [item setSubmenu:menu];
    return item;
}

- (BOOL)adoptProcessorFromXML:(NSString *)xml error:(NSError **)error
{
    // relative instance/@src, includes and schemas resolve DURING
    // construction — the base URL must ride in, never be set after
    XFProcessor *p = [XFProcessor processorWithXMLString:xml
                                                 baseURL:[self fileURL] ?: self.documentBaseURL
                                                   error:error];
    if (p == nil) {
        return NO;
    }
    self.processor = p;
    XFHostEdit *edit = [XFHostEdit editWithProcessor:p undoManager:[self undoManager]];
    __weak XFDDocument *weakSelf = self;
    edit.changedHandler = ^(XFXMLElement *element) {
        XFDDocument *doc = weakSelf;
        if (doc.hostChangedHandler) {
            doc.hostChangedHandler(element);
        }
    };
    self.hostEdit = edit;
    return YES;
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error
{
    self.documentBaseURL = url;
    return [super readFromURL:url ofType:typeName error:error];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)error
{
    (void)typeName;
    NSString *xml = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (xml == nil) {
        xml = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    }
    if (xml == nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"XFormsDesigner" code:1 userInfo:@{
                NSLocalizedDescriptionKey: @"The file is not text." }];
        }
        return NO;
    }
    // windows may not exist yet (fileURL is set after this returns); the
    // window controller reads `processor` in windowDidLoad
    return [self adoptProcessorFromXML:xml error:error];
}

/// An empty starter form for File > New.
- (NSString *)starterXML
{
    return
    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    @"<html xmlns=\"http://www.w3.org/1999/xhtml\"\n"
    @"      xmlns:xf=\"http://www.w3.org/2002/xforms\"\n"
    @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">\n"
    @"  <head>\n"
    @"    <title>Untitled Form</title>\n"
    @"    <xf:model id=\"model-1\">\n"
    @"      <xf:instance id=\"instance-1\">\n"
    @"        <data xmlns=\"\"/>\n"
    @"      </xf:instance>\n"
    @"    </xf:model>\n"
    @"  </head>\n"
    @"  <body>\n"
    @"    <h1>Untitled Form</h1>\n"
    @"  </body>\n"
    @"</html>\n";
}

- (instancetype)initWithType:(NSString *)typeName error:(NSError **)error
{
    self = [super initWithType:typeName error:error];
    if (self && ![self adoptProcessorFromXML:[self starterXML] error:error]) {
        return nil;
    }
    return self;
}

- (NSString *)hostXMLString
{
    NSString *xml = [self.processor.hostDocument XMLString];
    return [xml hasSuffix:@"\n"] ? xml : [xml stringByAppendingString:@"\n"];
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)error
{
    (void)typeName;
    (void)error;
    return [[self hostXMLString] dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)applySourceXML:(NSString *)xml error:(NSError **)error
{
    if (![self adoptProcessorFromXML:xml error:error]) {
        return NO;
    }
    [[self undoManager] removeAllActions];
    [self updateChangeCount:NSChangeDone];
    if (self.processorReplacedHandler) {
        self.processorReplacedHandler();
    }
    return YES;
}

- (BOOL)resetPreview:(NSError **)error
{
    NSString *xml = [self hostXMLString];
    if (![self adoptProcessorFromXML:xml error:error]) {
        return NO;
    }
    [[self undoManager] removeAllActions];
    if (self.processorReplacedHandler) {
        self.processorReplacedHandler();
    }
    return YES;
}

@end
