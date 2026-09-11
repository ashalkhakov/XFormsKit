#import "XFDOMPriv.h"

@implementation XFDOMDocument {
    XFDOMElement *_rootElement;
}

- (instancetype)initWithKind:(XFDOMNodeKind)kind
{
    self = [super initWithKind:XFDOMDocumentKind];
    if (self) {
        self.mutableChildren = [NSMutableArray array];
        _version = @"1.0";
        _characterEncoding = @"UTF-8";
    }
    return self;
}

- (instancetype)init
{
    return [self initWithKind:XFDOMDocumentKind];
}

- (instancetype)initWithRootElement:(XFDOMElement *)element
{
    self = [self init];
    if (self) {
        self.rootElement = element;
    }
    return self;
}

- (instancetype)initWithXMLString:(NSString *)string
                          options:(XFDOMNodeOptions)options
                            error:(NSError **)error
{
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        if (error) {
            *error = [NSError errorWithDomain:XFDOMErrorDomain code:1 userInfo:@{
                NSLocalizedDescriptionKey: @"the document is not valid UTF-8" }];
        }
        return nil;
    }
    return [self initWithData:data options:options error:error];
}

- (instancetype)initWithData:(NSData *)data
                     options:(XFDOMNodeOptions)options
                       error:(NSError **)error
{
    XFDOMDocument *parsed = [XFDOMParser documentWithData:data options:options error:error];
    if (parsed == nil) {
        return nil;
    }
    return parsed;
}

#pragma mark Root

- (XFDOMElement *)rootElement
{
    return _rootElement;
}

- (void)setRootElement:(XFDOMElement *)root
{
    if (_rootElement != nil) {
        [_rootElement detach];
    }
    _rootElement = root;
    if (root != nil) {
        [self adoptNode:root];
        [self.mutableChildren addObject:root];
    }
}

- (void)setRootElementSlot:(XFDOMElement *)root
{
    _rootElement = root;
}

#pragma mark Copying

- (id)copyWithZone:(NSZone *)zone
{
    XFDOMDocument *copy = [[XFDOMDocument allocWithZone:zone] init];
    copy.version = self.version;
    copy.characterEncoding = self.characterEncoding;
    for (XFDOMNode *child in self.mutableChildren) {
        XFDOMNode *childCopy = [child copy];
        childCopy.parent = copy;
        [copy.mutableChildren addObject:childCopy];
        if ([childCopy isKindOfClass:[XFDOMElement class]]) {
            [copy setRootElementSlot:(XFDOMElement *)childCopy];
        }
    }
    return copy;
}

#pragma mark Serialisation

- (void)appendXMLStringWithOptions:(XFDOMNodeOptions)options into:(NSMutableString *)out
{
    [out appendFormat:@"<?xml version=\"%@\" encoding=\"%@\"?>",
                      self.version ?: @"1.0", self.characterEncoding ?: @"UTF-8"];
    for (XFDOMNode *child in self.mutableChildren) {
        [child appendXMLStringWithOptions:options into:out];
    }
}

@end
