#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "XFUploadControl.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFXML.h"
#import "XFNamespaces.h"
#import "XFNodeState.h"
#import "XFModel.h"
#import "XFType.h"
#import "XFErrors.h"
#import "XFXMLEvents.h"
#import "XFInstance.h"

@implementation XFUploadControl

+ (instancetype)uploadWithElement:(NSXMLElement *)element
                            model:(id)model
                            error:(NSError **)error
{
    NSError *inner = nil;
    XFBinding *binding = [XFControl bindingOnElement:element preferredAttribute:@"ref" error:&inner];
    if (inner) {
        if (error) { *error = inner; }
        return nil;
    }
    XFUploadControl *upload = [[self alloc] initWithElement:element
                                                    binding:binding
                                                      label:[XFControl labelForElement:element]];
    upload.owner = model;
    NSXMLElement *fn = [XFXML firstElementWithLocalName:@"filename"
                                          namespaceURI:XFXFormsNamespaceURI
                                                inNode:element];
    NSXMLElement *mt = [XFXML firstElementWithLocalName:@"mediatype"
                                          namespaceURI:XFXFormsNamespaceURI
                                                inNode:element];
    if (fn) {
        upload.filenameBinding = [XFControl bindingOnElement:fn preferredAttribute:@"ref" error:&inner];
    }
    if (mt) {
        upload.mediatypeBinding = [XFControl bindingOnElement:mt preferredAttribute:@"ref" error:&inner];
    }
    if (inner) {
        if (error) { *error = inner; }
        return nil;
    }
    return upload;
}

- (NSString *)resolvedTypeName
{
    XFNodeState *state = [XFNodeState existingStateOnNode:self.boundNode];
    NSString *name = state.typeName ?: @"";
    if (name.length == 0) {
        name = [[self.element attributeForName:@"mediatype"] stringValue] ?: @"";
    }
    return name;
}

- (NSString *)encodeData:(NSData *)data
{
    NSString *type = [[self resolvedTypeName] lowercaseString];
    if ([type rangeOfString:@"hex"].location != NSNotFound) {
        static const char *hex = "0123456789ABCDEF";
        const unsigned char *b = data.bytes;
        NSMutableString *out = [NSMutableString stringWithCapacity:data.length * 2];
        for (NSUInteger i = 0; i < data.length; i++) {
            [out appendFormat:@"%c%c", hex[(b[i] >> 4) & 0xF], hex[b[i] & 0xF]];
        }
        return out;
    }
    if ([type rangeOfString:@"uri"].location != NSNotFound) {
        return self.fileName.length
            ? [@"file:" stringByAppendingString:self.fileName]
            : @"";
    }
    if ([type rangeOfString:@"string"].location != NSNotFound
        && [type rangeOfString:@"base64"].location == NSNotFound) {
        NSString *latin = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        if (latin) {
            return latin;
        }
    }
    return [data base64EncodedStringWithOptions:0];
}

- (void)writeBinding:(XFBinding *)binding value:(NSString *)value context:(XFExprContext *)ctx
{
    if (binding == nil) {
        return;
    }
    NSXMLNode *node = [binding boundNodeInContext:ctx error:NULL];
    if (node) {
        [XFXML setStringValue:value ?: @"" ofNode:node];
        if ([self.owner isKindOfClass:[XFModel class]]) {
            [(XFModel *)self.owner addChange:node];
        }
    }
}

- (BOOL)commitFileData:(NSData *)data
              fileName:(NSString *)fileName
             mediaType:(NSString *)mediaType
                 error:(NSError **)error
{
    self.fileData = data;
    self.fileName = fileName;
    self.mediaType = mediaType;
    if (self.boundNode == nil && self.binding) {
        XFExprContext *probe = [[XFExprContext alloc] initWithNode:nil];
        if ([self.owner isKindOfClass:[XFModel class]]) {
            probe.model = (XFModel *)self.owner;
            probe.contextNode = [[(XFModel *)self.owner defaultInstance] documentElement];
        }
        [self refreshWithContext:probe error:NULL];
    }
    if (self.boundNode == nil) {
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorBinding
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"xf:upload has no bound node" }];
        }
        return NO;
    }
    NSString *encoded = [self encodeData:data ?: [NSData data]];
    if (![self commitStringValue:encoded error:error]) {
        return NO;
    }
    XFNodeState *state = [XFNodeState stateOnNode:self.boundNode];
    state.fileName = fileName;
    state.mediaType = mediaType;
    state.fileData = data;
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:self.boundNode];
    if ([self.owner isKindOfClass:[XFModel class]]) {
        ctx.model = (XFModel *)self.owner;
        [(XFModel *)self.owner addChange:self.boundNode];
    }
    [self writeBinding:self.filenameBinding value:fileName context:ctx];
    [self writeBinding:self.mediatypeBinding value:mediaType context:ctx];
    // xforms-value-changed and the recalculation cycle are driven by
    // -[XFProcessor controlDidChangeValue:].
    return YES;
}

- (BOOL)commitFileAtURL:(NSURL *)url error:(NSError **)error
{
    if (url == nil) {
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorDocument
                                     userInfo:@{ NSLocalizedDescriptionKey: @"no file URL" }];
        }
        return NO;
    }
    NSError *inner = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&inner];
    if (data == nil) {
        if (error) { *error = inner; }
        return NO;
    }
    NSString *name = url.lastPathComponent;
    NSString *ext = url.pathExtension;
    NSString *mt = @"application/octet-stream";
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"txt": @"text/plain", @"xml": @"application/xml", @"xhtml": @"application/xhtml+xml",
            @"html": @"text/html", @"png": @"image/png", @"jpg": @"image/jpeg",
            @"jpeg": @"image/jpeg", @"gif": @"image/gif", @"pdf": @"application/pdf",
            @"bin": @"application/octet-stream"
        };
    });
    if (ext.length && map[[ext lowercaseString]]) {
        mt = map[[ext lowercaseString]];
    }
    return [self commitFileData:data fileName:name mediaType:mt error:error];
}

@end
