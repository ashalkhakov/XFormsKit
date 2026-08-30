#import "XFOutputControl.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFXPathValue.h"
#import "XFNodeState.h"

@implementation XFOutputControl

- (instancetype)initWithElement:(NSXMLElement *)element
                        binding:(XFBinding *)binding
                          label:(NSString *)label
{
    self = [super initWithElement:element binding:binding label:label];
    if (self) {
        _mediaType = [[element attributeForName:@"mediatype"] stringValue];
    }
    return self;
}

- (NSString *)resolvedMediaType
{
    if (self.mediaType.length) {
        return [self.mediaType lowercaseString];
    }
    XFNodeState *state = [XFNodeState existingStateOnNode:self.boundNode];
    if (state.mediaType.length) {
        return [state.mediaType lowercaseString];
    }
    if (state.typeName.length && [[state.typeName lowercaseString] rangeOfString:@"base64"].location != NSNotFound) {
        return @"application/octet-stream";
    }
    return @"text/plain";
}

- (BOOL)displaysImage
{
    NSString *mt = [self resolvedMediaType];
    return [mt hasPrefix:@"image/"] || [mt isEqualToString:@"application/octet-stream"];
}

- (BOOL)displaysHTML
{
    NSString *mt = [self resolvedMediaType];
    return [mt isEqualToString:@"text/html"]
        || [mt isEqualToString:@"application/xhtml+xml"]
        || [mt isEqualToString:@"application/xml+xhtml"];
}

- (NSData *)imageData
{
    NSString *value = self.stringValue ?: @"";
    if (value.length == 0) {
        XFNodeState *state = [XFNodeState existingStateOnNode:self.boundNode];
        if (state.fileData.length) {
            return state.fileData;
        }
        return nil;
    }
    if ([value hasPrefix:@"data:"]) {
        NSRange comma = [value rangeOfString:@","];
        if (comma.location == NSNotFound) {
            return nil;
        }
        NSString *b64 = [value substringFromIndex:comma.location + 1];
        return [[NSData alloc] initWithBase64EncodedString:b64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
    }
    if ([value hasPrefix:@"http://"] || [value hasPrefix:@"https://"] || [value hasPrefix:@"file:"]) {
        NSURL *url = [NSURL URLWithString:value];
        if (url) {
            return [NSData dataWithContentsOfURL:url];
        }
    }
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:value
                                                          options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (decoded.length) {
        return decoded;
    }
    return [value dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    if (self.binding == nil) {
        return;
    }
    NSError *inner = nil;
    XFXPathValue *value = [self.binding evaluateInContext:context error:&inner];
    if (inner) {
        if (error) {
            *error = inner;
        }
        return;
    }
    self.boundNode = value.firstNode;
    self.stringValue = [value stringValue] ?: @"";
    [self applyMIPsFromBoundNode];
}

@end
