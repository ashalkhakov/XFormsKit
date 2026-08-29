#import "XFInstance.h"
#import "XFErrors.h"
#import "XFXML.h"
#import <Foundation/NSXMLDocument.h>
#import <Foundation/NSXMLElement.h>

@interface XFInstance ()
@property (nonatomic, strong, readwrite) NSXMLDocument *document;
@property (nonatomic, strong, readwrite) NSXMLDocument *originalDocument;
@end

@implementation XFInstance

+ (instancetype)instanceWithElement:(NSXMLElement *)instanceElement
                              error:(NSError **)error
{
    XFInstance *instance = [[self alloc] init];
    NSXMLNode *idAttr = [instanceElement attributeForName:@"id"];
    instance.identifier = idAttr ? [idAttr stringValue] : nil;

    NSXMLElement *dataRoot = nil;
    for (NSXMLNode *child in [instanceElement children]) {
        if ([child kind] == NSXMLElementKind) {
            dataRoot = (NSXMLElement *)child;
            break;
        }
    }
    if (dataRoot == nil) {
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorDocument
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"xf:instance has no inline document element" }];
        }
        return nil;
    }

    // Detach a deep copy so the live instance is a standalone document.
    NSXMLElement *copy = [dataRoot copy];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:copy];
    [doc setVersion:@"1.0"];
    [doc setCharacterEncoding:@"UTF-8"];
    instance.document = doc;
    instance.originalDocument = [doc copy];
    return instance;
}

- (NSXMLElement *)documentElement
{
    return [self.document rootElement];
}

- (void)reset
{
    self.document = [self.originalDocument copy];
}

@end
