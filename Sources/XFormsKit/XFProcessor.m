#import "XFProcessor.h"
#import "XFModel.h"
#import "XFInstance.h"
#import "XFBinding.h"
#import "XFControl.h"
#import "XFInputControl.h"
#import "XFOutputControl.h"
#import "XFGroup.h"
#import "XFRepeat.h"
#import "XFSwitch.h"
#import "XFTriggerControl.h"
#import "XFAction.h"
#import "XFAbstractAction.h"
#import "XFDeferredUpdates.h"
#import "XFSubmission.h"
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
@property (nonatomic, copy, readwrite) NSArray<XFAbstractAction *> *actions;
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
    for (XFInstance *instance in model.instances) {
        if (instance.element) {
            [[XFXMLEvents sharedEvents] registerElement:instance.element xfElement:instance];
        }
    }
    for (XFSubmission *submission in model.submissions) {
        [[XFXMLEvents sharedEvents] registerElement:submission.element xfElement:submission];
    }

    NSMutableArray<XFControl *> *controls = [NSMutableArray array];
    if (![self collectControlsUnder:document.rootElement
                            into:controls
                           error:&inner]) {
        if (error) {
            *error = inner;
        }
        return nil;
    }

    _controls = controls;
    for (XFControl *control in controls) {
        [self registerControlTree:control];
    }

    [[XFDeferredUpdates sharedUpdates] reset];
    NSMutableArray<XFAbstractAction *> *actions = [NSMutableArray array];
    [self collectActionsUnder:document.rootElement
                       parent:nil
                      actions:actions
                        error:&inner];
    if (inner) {
        if (error) {
            *error = inner;
        }
        return nil;
    }
    _actions = actions;

    [[XFXMLEvents sharedEvents] installListenersInDocument:document];

    [XFXMLEvents dispatch:model name:@"xforms-model-construct"];
    [XFXMLEvents dispatch:model name:@"xforms-model-construct-done"];
    [self refreshControls];
    model.ready = YES;
    [XFXMLEvents dispatch:model name:@"xforms-ready"];
    [self refreshControls];
    return self;
}

- (BOOL)collectActionsUnder:(NSXMLNode *)node
                     parent:(XFAction *)parent
                    actions:(NSMutableArray<XFAbstractAction *> *)actions
                      error:(NSError **)error
{
    if ([node kind] != NSXMLElementKind) {
        return YES;
    }
    NSXMLElement *element = (NSXMLElement *)node;
    XFAction *nextParent = parent;
    if ([XFAbstractAction isActionElement:element]) {
        NSError *inner = nil;
        XFAbstractAction *action = [XFAbstractAction actionWithElement:element
                                                                model:self.model
                                                                error:&inner];
        if (action == nil) {
            if (error) {
                *error = inner;
            }
            return NO;
        }
        [actions addObject:action];
        [[XFXMLEvents sharedEvents] registerElement:element xfElement:action];
        if (parent) {
            [parent addChild:action];
        }
        if ([action isKindOfClass:[XFAction class]]) {
            nextParent = (XFAction *)action;
        }
    }
    for (NSXMLNode *child in [element children]) {
        if (![self collectActionsUnder:child parent:nextParent actions:actions error:error]) {
            return NO;
        }
    }
    return YES;
}

- (void)registerControlTree:(XFControl *)control
{
    if (control == nil) {
        return;
    }
    [[XFXMLEvents sharedEvents] registerElement:control.element xfElement:control];
    if ([control isKindOfClass:[XFRepeat class]]) {
        [self.model addRepeat:(XFRepeat *)control];
    }
    if ([control isKindOfClass:[XFGroup class]]) {
        for (XFControl *child in [(XFGroup *)control children]) {
            [self registerControlTree:child];
        }
    }
    if ([control isKindOfClass:[XFSwitch class]]) {
        for (XFCase *caze in [(XFSwitch *)control cases]) {
            [self registerControlTree:caze];
            for (XFControl *child in caze.children) {
                [self registerControlTree:child];
            }
        }
    }
}

- (BOOL)collectControlsUnder:(NSXMLNode *)node
                        into:(NSMutableArray<XFControl *> *)controls
                       error:(NSError **)error
{
    if ([node kind] != NSXMLElementKind) {
        return YES;
    }
    NSXMLElement *element = (NSXMLElement *)node;
    if ([XFXML element:element hasLocalName:@"model" namespaceURI:XFXFormsNamespaceURI]) {
        return YES;
    }
    if ([XFControl shouldInstantiateElement:element]) {
        NSError *inner = nil;
        XFControl *control = [XFControl controlWithElement:element model:self.model error:&inner];
        if (control == nil) {
            if (error) {
                *error = inner;
            }
            return NO;
        }
        control.owner = self;
        [controls addObject:control];
        return YES;
    }
    for (NSXMLNode *child in [element children]) {
        if (![self collectControlsUnder:child into:controls error:error]) {
            return NO;
        }
    }
    return YES;
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

- (void)collectControlsOfClass:(Class)cls
                        from:(XFControl *)control
                        into:(NSMutableArray *)out
{
    if ([control isKindOfClass:cls]) {
        [out addObject:control];
    }
    if ([control isKindOfClass:[XFGroup class]]) {
        for (XFControl *child in [(XFGroup *)control children]) {
            [self collectControlsOfClass:cls from:child into:out];
        }
    }
}

- (NSArray<XFInputControl *> *)inputControls
{
    NSMutableArray *out = [NSMutableArray array];
    for (XFControl *c in self.controls) {
        [self collectControlsOfClass:[XFInputControl class] from:c into:out];
    }
    return out;
}

- (XFAbstractAction *)actionWithIdentifier:(NSString *)identifier
{
    if (identifier.length == 0) {
        return nil;
    }
    for (XFAbstractAction *action in self.actions) {
        if ([action.identifier isEqualToString:identifier]) {
            return action;
        }
    }
    return nil;
}

- (NSArray<XFGroup *> *)groups
{
    NSMutableArray *out = [NSMutableArray array];
    for (XFControl *c in self.controls) {
        if ([c isKindOfClass:[XFGroup class]]) {
            [out addObject:c];
        }
    }
    return out;
}

- (NSArray<XFRepeat *> *)repeats
{
    return self.model.repeats;
}

- (XFRepeat *)repeatWithIdentifier:(NSString *)identifier
{
    return [self.model repeatWithIdentifier:identifier];
}

- (NSArray<XFOutputControl *> *)outputControls
{
    NSMutableArray *out = [NSMutableArray array];
    for (XFControl *c in self.controls) {
        [self collectControlsOfClass:[XFOutputControl class] from:c into:out];
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

- (void)activateControl:(XFTriggerControl *)control
{
    [control activate];
    [self refreshControls];
}

- (XFControl *)matchControl:(XFControl *)control element:(NSXMLElement *)element
{
    if (control.element == element) {
        return control;
    }
    if ([control isKindOfClass:[XFGroup class]]) {
        for (XFControl *child in [(XFGroup *)control children]) {
            XFControl *found = [self matchControl:child element:element];
            if (found) {
                return found;
            }
        }
    }
    if ([control isKindOfClass:[XFRepeat class]]) {
        for (XFRepeatItem *item in [(XFRepeat *)control items]) {
            for (XFControl *child in item.controls) {
                XFControl *found = [self matchControl:child element:element];
                if (found) {
                    return found;
                }
            }
        }
    }
    if ([control isKindOfClass:[XFSwitch class]]) {
        for (XFCase *caze in [(XFSwitch *)control cases]) {
            XFControl *found = [self matchControl:caze element:element];
            if (found) {
                return found;
            }
            for (XFControl *child in caze.children) {
                found = [self matchControl:child element:element];
                if (found) {
                    return found;
                }
            }
        }
    }
    return nil;
}

- (XFControl *)controlForElement:(NSXMLElement *)element
{
    if (element == nil) {
        return nil;
    }
    for (XFControl *control in self.controls) {
        XFControl *found = [self matchControl:control element:element];
        if (found) {
            return found;
        }
    }
    return nil;
}

- (BOOL)setValue:(NSString *)value ofControl:(XFControl *)control error:(NSError **)error
{
    if (![control commitStringValue:value error:error]) {
        return NO;
    }
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"setValue"];
    [self.model addChange:control.boundNode];
    [du addChangedModel:self.model];
    [XFXMLEvents dispatch:control name:@"xforms-value-changed"];
    [du closeAction:@"setValue"];
    return YES;
}

@end
