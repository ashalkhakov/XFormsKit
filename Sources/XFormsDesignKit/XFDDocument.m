#import "XFDDocument.h"
#import <XFormsKit/XFXMLTypes.h>
#import "XFDWindowController.h"

@interface XFDDocument ()
@property (nonatomic, strong, readwrite) XFDFormEditor *formEditor;
/// Where the document came from — captured in readFromURL: (fileURL is
/// set only after the read returns) so relative instance/@src, includes
/// and schemas resolve on the very first processor build.
@property (nonatomic, copy) NSURL *documentBaseURL;
@end

@implementation XFDDocument

- (void)makeWindowControllers
{
    XFDWindowController *controller = [[XFDWindowController alloc] initWithFormEditor:self.formEditor];
    if (controller != nil) {
        [self addWindowController:controller];
    }
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

- (XFProcessor *)processor
{
    return self.formEditor.processor;
}

- (XFHostEdit *)hostEdit
{
    return self.formEditor.hostEdit;
}

/// The form read from `xml`: a form editor the first time, read again after.
- (BOOL)readXMLString:(NSString *)xml error:(NSError **)error
{
    if (self.formEditor != nil) {
        return [self.formEditor replaceWithXMLString:xml error:error];
    }
    XFDFormEditor *editor = [[XFDFormEditor alloc] initWithXMLString:xml
                                                             baseURL:[self fileURL] ?: self.documentBaseURL
                                                         undoManager:[self undoManager]
                                                               error:error];
    self.formEditor = editor;
    return editor != nil;
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
    // windows may not exist yet (fileURL is set after this returns)
    return [self readXMLString:xml error:error];
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
    if (self && ![self readXMLString:[self starterXML] error:error]) {
        return nil;
    }
    return self;
}

- (NSString *)hostXMLString
{
    return [self.formEditor hostXMLString];
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)error
{
    (void)typeName;
    (void)error;
    return [[self hostXMLString] dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)applySourceXML:(NSString *)xml error:(NSError **)error
{
    if (![self.formEditor replaceWithXMLString:xml error:error]) {
        return NO;
    }
    [self updateChangeCount:NSChangeDone];
    return YES;
}

- (BOOL)resetPreview:(NSError **)error
{
    return [self.formEditor resetPreview:error];
}

@end
