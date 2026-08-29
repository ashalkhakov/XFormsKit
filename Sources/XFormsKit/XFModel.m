#import "XFModel.h"
#import "XFInstance.h"
#import "XFNamespaces.h"
#import "XFXML.h"
#import "XFErrors.h"
#import <Foundation/NSXMLElement.h>

@interface XFModel ()
@property (nonatomic, copy, readwrite) NSArray<XFInstance *> *instances;
@end

@implementation XFModel

+ (instancetype)modelWithElement:(NSXMLElement *)modelElement
                           error:(NSError **)error
{
    XFModel *model = [[self alloc] init];
    NSXMLNode *idAttr = [modelElement attributeForName:@"id"];
    model.identifier = idAttr ? [idAttr stringValue] : nil;

    NSArray<NSXMLElement *> *instanceElements =
        [XFXML elementsWithLocalName:@"instance"
                       namespaceURI:XFXFormsNamespaceURI
                             inNode:modelElement];
    NSMutableArray<XFInstance *> *instances = [NSMutableArray array];
    for (NSXMLElement *el in instanceElements) {
        NSError *inner = nil;
        XFInstance *instance = [XFInstance instanceWithElement:el error:&inner];
        if (instance == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
        [instances addObject:instance];
    }
    if (instances.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorDocument
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"xf:model has no xf:instance" }];
        }
        return nil;
    }
    model.instances = instances;
    return model;
}

- (XFInstance *)instanceWithIdentifier:(NSString *)identifier
{
    if (identifier.length == 0) {
        return [self defaultInstance];
    }
    for (XFInstance *instance in self.instances) {
        if ([instance.identifier isEqualToString:identifier]) {
            return instance;
        }
    }
    return nil;
}

- (XFInstance *)defaultInstance
{
    return self.instances.firstObject;
}

@end
