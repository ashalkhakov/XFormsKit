#import "XFModelAction.h"
#import "XFXMLEvents.h"
#import "XFModel.h"
#import "XFEvent.h"
#import "XFNamespaces.h"
#import <XFormsKit/XFXMLTypes.h>

@interface XFModelAction ()
@property (nonatomic, copy, readwrite) NSString *eventName;
@property (nonatomic, copy) NSString *modelID;
@end

@implementation XFModelAction

- (instancetype)initWithElement:(XFXMLElement *)element
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
        XFXMLElement *el = [events elementWithID:self.modelID
                                      inDocument:(XFXMLDocument *)[self.element rootDocument]];
        id xf = el ? [events xfElementForElement:el] : nil;
        if ([xf isKindOfClass:[XFModel class]]) {
            return xf;
        }
    }
    for (XFXMLNode *walk = [self.element parent]; walk; walk = [walk parent]) {
        if ([walk kind] == XFXMLElementKind &&
            [[walk localName] isEqualToString:@"model"] &&
            [[walk URI] isEqualToString:XFXFormsNamespaceURI]) {
            id xf = [events xfElementForElement:(XFXMLElement *)walk];
            if ([xf isKindOfClass:[XFModel class]]) {
                return xf;
            }
        }
    }
    return self.model;
}

- (void)runWithContextNode:(XFXMLNode *)contextNode event:(XFEvent *)event
{
    (void)contextNode;
    (void)event;
    XFModel *model = [self targetModel];
    if (model) {
        [XFXMLEvents dispatch:model name:self.eventName];
    }
}

@end
