#import "XFModelAction.h"
#import "XFXMLEvents.h"
#import "XFModel.h"
#import "XFEvent.h"
#import "XFNamespaces.h"
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLDocument.h>

@interface XFModelAction ()
@property (nonatomic, copy, readwrite) NSString *eventName;
@property (nonatomic, copy) NSString *modelID;
@end

@implementation XFModelAction

- (instancetype)initWithElement:(NSXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    NSString *local = [element localName];
    self.eventName = [NSString stringWithFormat:@"xforms-%@", local];
    self.modelID = [[element attributeForName:@"model"] stringValue];
    return self;
}

/// XSLTForms `xf:rebuild/@model` etc.: the named model, else the model the
/// action element sits in, else the default model.
- (XFModel *)targetModel
{
    XFXMLEvents *events = [XFXMLEvents sharedEvents];
    if (self.modelID.length) {
        NSXMLElement *el = [events elementWithID:self.modelID
                                      inDocument:(NSXMLDocument *)[self.element rootDocument]];
        id xf = el ? [events xfElementForElement:el] : nil;
        if ([xf isKindOfClass:[XFModel class]]) {
            return xf;
        }
    }
    for (NSXMLNode *walk = [self.element parent]; walk; walk = [walk parent]) {
        if ([walk kind] == NSXMLElementKind &&
            [[walk localName] isEqualToString:@"model"] &&
            [[walk URI] isEqualToString:XFXFormsNamespaceURI]) {
            id xf = [events xfElementForElement:(NSXMLElement *)walk];
            if ([xf isKindOfClass:[XFModel class]]) {
                return xf;
            }
        }
    }
    return self.model;
}

- (void)runWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    (void)contextNode;
    (void)event;
    XFModel *model = [self targetModel];
    if (model) {
        [XFXMLEvents dispatch:model name:self.eventName];
    }
}

@end
