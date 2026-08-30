#import "XFProcessor.h"
#import "XFModel.h"
#import "XFInstance.h"
#import "XFBinding.h"
#import "XFControl.h"
#import "XFInputControl.h"
#import "XFOutputControl.h"
#import "XFExprContext.h"
#import "XFNamespaces.h"
#import "XFXML.h"
#import "XFErrors.h"
#import "XFXMLEvents.h"
#import <Foundation/NSXMLDocument.h>
#import <Foundation/NSXMLElement.h>

@interface XFProcessor ()
@property (nonatomic, strong, readwrite) NSXMLDocument *hostDocument;
@property (nonatomic, strong, readwrite) XFModel *model;
@property (nonatomic, copy, readwrite) NSArray<XFControl *> *controls;
@end

@implementation XFProcessor

+ (NSXMLDocument *)documentFromData:(NSData *)data error:(NSError **)error
{
    NSError *inner = nil;
    NSXMLDocument *doc =
        [[NSXMLDocument alloc] initWithData:data
                                    options:0
                                      error:&inner];
    if (doc == nil) {
        if (error) {
            *error = inner ?: [NSError errorWithDomain:XFErrorDomain
                                                  code:XFErrorDocument
                                              userInfo:@{ NSLocalizedDescriptionKey:
                                                              @"could not parse host document" }];
        }
        return nil;
    }
    return doc;
}

+ (instancetype)processorWithContentsOfURL:(NSURL *)url error:(NSError **)error
{
    NSError *inner = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&inner];
    if (data == nil) {
        if (error) {
            *error = inner;
        }
        return nil;
    }
    NSXMLDocument *doc = [self documentFromData:data error:error];
    if (doc == nil) {
        return nil;
    }
    return [[self alloc] initWithHostDocument:doc error:error];
}

+ (instancetype)processorWithXMLString:(NSString *)xml error:(NSError **)error
{
    NSData *data = [xml dataUsingEncoding:NSUTF8StringEncoding];
    NSXMLDocument *doc = [self documentFromData:data error:error];
    if (doc == nil) {
        return nil;
    }
    return [[self alloc] initWithHostDocument:doc error:error];
}

- (instancetype)initWithHostDocument:(NSXMLDocument *)document error:(NSError **)error
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _hostDocument = document;

    NSXMLElement *modelElement =
        [XFXML firstElementWithLocalName:@"model"
                           namespaceURI:XFXFormsNamespaceURI
                                 inNode:document];
    if (modelElement == nil) {
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorDocument
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"host document has no xf:model" }];
        }
        return nil;
    }

    NSError *inner = nil;
    XFModel *model = [XFModel modelWithElement:modelElement error:&inner];
    if (model == nil) {
        if (error) {
            *error = inner;
        }
        return nil;
    }
    _model = model;
    model.owner = self;
    [[XFXMLEvents sharedEvents] registerElement:model.element xfElement:model];

    NSMutableArray<XFControl *> *controls = [NSMutableArray array];
    NSArray<NSXMLElement *> *inputs =
        [XFXML elementsWithLocalName:@"input"
                       namespaceURI:XFXFormsNamespaceURI
                             inNode:document];
    for (NSXMLElement *el in inputs) {
        XFControl *control = [self controlFromElement:el
                                            class:[XFInputControl class]
                                       bindingAttribute:@"ref"
                                            error:&inner];
        if (control == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
        [controls addObject:control];
    }

    NSArray<NSXMLElement *> *outputs =
        [XFXML elementsWithLocalName:@"output"
                       namespaceURI:XFXFormsNamespaceURI
                             inNode:document];
    for (NSXMLElement *el in outputs) {
        NSString *attr = [el attributeForName:@"value"] ? @"value" : @"ref";
        XFControl *control = [self controlFromElement:el
                                            class:[XFOutputControl class]
                                       bindingAttribute:attr
                                            error:&inner];
        if (control == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
        [controls addObject:control];
    }

    _controls = controls;
    for (XFControl *control in controls) {
        [[XFXMLEvents sharedEvents] registerElement:control.element xfElement:control];
    }
    [[XFXMLEvents sharedEvents] installListenersInDocument:document];

    [XFXMLEvents dispatch:model name:@"xforms-model-construct"];
    [XFXMLEvents dispatch:model name:@"xforms-model-construct-done"];
    [XFXMLEvents dispatch:model name:@"xforms-ready"];

    if (self.outputControls.count > 0 && self.outputControls.firstObject.stringValue.length == 0) {
        [self refreshControls];
    }
    return self;
}

- (NSString *)labelForElement:(NSXMLElement *)element
{
    NSXMLElement *label =
        [XFXML firstElementWithLocalName:@"label"
                           namespaceURI:XFXFormsNamespaceURI
                                 inNode:element];
    return label ? [XFXML stringValueOfNode:label] : nil;
}

- (XFControl *)controlFromElement:(NSXMLElement *)element
                            class:(Class)cls
                 bindingAttribute:(NSString *)attribute
                            error:(NSError **)error
{
    NSXMLNode *attr = [element attributeForName:attribute];
    XFBinding *binding = nil;
    if (attr && [attr stringValue].length > 0) {
        binding = [XFBinding bindingWithExpression:[attr stringValue] error:error];
        if (binding == nil) {
            return nil;
        }
    }
    XFControl *control = [[cls alloc] initWithElement:element
                                              binding:binding
                                                label:[self labelForElement:element]];
    control.owner = self;
    return control;
}

- (XFInstance *)defaultInstance
{
    return [self.model defaultInstance];
}

- (NSArray<XFInputControl *> *)inputControls
{
    NSMutableArray *out = [NSMutableArray array];
    for (XFControl *c in self.controls) {
        if ([c isKindOfClass:[XFInputControl class]]) {
            [out addObject:c];
        }
    }
    return out;
}

- (NSArray<XFOutputControl *> *)outputControls
{
    NSMutableArray *out = [NSMutableArray array];
    for (XFControl *c in self.controls) {
        if ([c isKindOfClass:[XFOutputControl class]]) {
            [out addObject:c];
        }
    }
    return out;
}

- (XFExprContext *)evaluationContext
{
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:[[self defaultInstance] documentElement]];
    ctx.model = self.model;
    return ctx;
}

- (void)refreshControls
{
    XFExprContext *ctx = [self evaluationContext];
    for (XFControl *control in self.controls) {
        [control refreshWithContext:ctx error:NULL];
    }
}

- (BOOL)refresh:(NSError **)error
{
    XFExprContext *ctx = [self evaluationContext];
    for (XFControl *control in self.controls) {
        NSError *inner = nil;
        [control refreshWithContext:ctx error:&inner];
        if (inner) {
            if (error) {
                *error = inner;
            }
            return NO;
        }
    }
    return YES;
}

- (BOOL)setValue:(NSString *)value ofControl:(XFInputControl *)control error:(NSError **)error
{
    if (![control commitStringValue:value error:error]) {
        return NO;
    }
    [XFXMLEvents dispatch:control name:@"xforms-value-changed"];
    [XFXMLEvents dispatch:self.model name:@"xforms-recalculate"];
    return YES;
}

@end
