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
#import "XFSelectControl.h"
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
@property (nonatomic, copy, readwrite) NSArray<XFModel *> *models;
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
    return [[self alloc] initWithHostDocument:doc baseURL:url error:error];
}

+ (instancetype)processorWithXMLString:(NSString *)xml error:(NSError **)error
{
    NSData *data = [xml dataUsingEncoding:NSUTF8StringEncoding];
    NSXMLDocument *doc = [self documentFromData:data error:error];
    if (doc == nil) {
        return nil;
    }
    return [[self alloc] initWithHostDocument:doc baseURL:nil error:error];
}

- (instancetype)initWithHostDocument:(NSXMLDocument *)document error:(NSError **)error
{
    return [self initWithHostDocument:document baseURL:nil error:error];
}

- (instancetype)initWithHostDocument:(NSXMLDocument *)document
                             baseURL:(NSURL *)baseURL
                               error:(NSError **)error
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _hostDocument = document;
    _baseURL = baseURL;

    NSArray<NSXMLElement *> *modelElements =
        [XFXML elementsWithLocalName:@"model"
                       namespaceURI:XFXFormsNamespaceURI
                             inNode:document];
    if (modelElements.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorDocument
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"host document has no xf:model" }];
        }
        return nil;
    }

    NSError *inner = nil;
    NSMutableArray<XFModel *> *models = [NSMutableArray array];
    for (NSXMLElement *modelElement in modelElements) {
        XFModel *model = [XFModel modelWithElement:modelElement error:&inner];
        if (model == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
        model.owner = self;
        [models addObject:model];
        [[XFXMLEvents sharedEvents] registerElement:model.element xfElement:model];
        for (XFInstance *instance in model.instances) {
            instance.baseURL = baseURL;
            if (instance.element) {
                [[XFXMLEvents sharedEvents] registerElement:instance.element xfElement:instance];
            }
        }
        for (XFSubmission *submission in model.submissions) {
            [[XFXMLEvents sharedEvents] registerElement:submission.element xfElement:submission];
        }
    }
    _models = [models copy];
    XFModel *model = models.firstObject;
    _model = model;

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

    for (XFModel *m in self.models) {
        [XFXMLEvents dispatch:m name:@"xforms-model-construct"];
        [XFXMLEvents dispatch:m name:@"xforms-model-construct-done"];
    }
    [self refreshControls];
    for (XFModel *m in self.models) {
        m.ready = YES;
        [XFXMLEvents dispatch:m name:@"xforms-ready"];
    }
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
    [self controlDidChangeValue:control];
    return YES;
}

- (void)controlDidChangeValue:(XFControl *)control
{
    // XSLTForms: XsltForms_globals.openAction(); model.addChange(node);
    // xforms-value-changed; closeAction() -> rebuild/recalculate/revalidate/
    // refresh through the deferred-update queue. Every UI-originated change
    // must come through here, or dependent MIPs are not recomputed.
    XFModel *model = [control.owner isKindOfClass:[XFModel class]] ? (XFModel *)control.owner : self.model;
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"setValue"];
    [model addChange:control.boundNode];
    [du addChangedModel:model];
    [XFXMLEvents dispatch:control name:@"xforms-value-changed"];
    [du closeAction:@"setValue"];
}

- (XFControl *)parentControlForElement:(NSXMLElement *)element
{
    NSXMLNode *walk = [element parent];
    while (walk) {
        if ([walk kind] == NSXMLElementKind) {
            XFControl *found = [self controlForElement:(NSXMLElement *)walk];
            if (found) {
                return found;
            }
        }
        walk = [walk parent];
    }
    return nil;
}

- (void)refreshControl:(XFControl *)control
{
    if (control == nil) {
        return;
    }
    [control refreshWithContext:[self evaluationContext] error:NULL];
}

- (XFControl *)attachElement:(NSXMLElement *)element error:(NSError **)error
{
    if (element == nil) {
        return nil;
    }
    NSString *local = [element localName];
    if ([local isEqualToString:@"bind"] || [local isEqualToString:@"instance"]
        || [local isEqualToString:@"submission"]) {
        XFModel *model = self.model;
        NSXMLNode *walk = element;
        while (walk) {
            if ([walk kind] == NSXMLElementKind
                && [XFXML element:(NSXMLElement *)walk hasLocalName:@"model" namespaceURI:XFXFormsNamespaceURI]) {
                for (XFModel *m in self.models) {
                    if (m.element == walk) {
                        model = m;
                        break;
                    }
                }
                break;
            }
            walk = [walk parent];
        }
        [model adoptElement:element error:error];
        [model setRebuilded:YES];
        [model rebuild];
        [model refresh];
        return nil;
    }

    if ([XFAbstractAction isActionElement:element]) {
        NSError *inner = nil;
        XFAbstractAction *action = [XFAbstractAction actionWithElement:element
                                                                model:self.model
                                                                error:&inner];
        if (action == nil) {
            if (error) { *error = inner; }
            return nil;
        }
        NSMutableArray *actions = [self.actions mutableCopy] ?: [NSMutableArray array];
        [actions addObject:action];
        self.actions = actions;
        [[XFXMLEvents sharedEvents] registerElement:element xfElement:action];
        [[XFXMLEvents sharedEvents] installListenersUnder:element inDocument:self.hostDocument];
        return nil;
    }

    if (![XFControl shouldInstantiateElement:element]) {
        XFControl *parent = [self parentControlForElement:element];
        if ([parent isKindOfClass:[XFSelectControl class]]) {
            // item / itemset / choices live on the select templates
            [(XFSelectControl *)parent rebuildItemsWithContext:[self evaluationContext] error:NULL];
        }
        [[XFXMLEvents sharedEvents] installListenersUnder:element inDocument:self.hostDocument];
        return parent;
    }

    NSError *inner = nil;
    XFControl *control = [XFControl controlWithElement:element model:self.model error:&inner];
    if (control == nil) {
        if (error) { *error = inner; }
        return nil;
    }
    control.owner = self;
    XFControl *parent = [self parentControlForElement:element];
    if ([parent isKindOfClass:[XFGroup class]]) {
        [(XFGroup *)parent addChild:control];
    } else if ([parent isKindOfClass:[XFCase class]]) {
        [(XFCase *)parent addChild:control];
    } else if ([parent isKindOfClass:[XFRepeat class]]) {
        [(XFRepeat *)parent reloadTemplates];
        [(XFRepeat *)parent rebuildItemsWithContext:[self evaluationContext] error:NULL];
    } else {
        NSMutableArray *list = [self.controls mutableCopy] ?: [NSMutableArray array];
        [list addObject:control];
        self.controls = list;
    }
    [self registerControlTree:control];
    [[XFXMLEvents sharedEvents] installListenersUnder:element inDocument:self.hostDocument];
    [self refreshControl:control];
    return control;
}

- (void)removeControl:(XFControl *)control fromList:(NSMutableArray *)list
{
    [list removeObject:control];
    if ([control isKindOfClass:[XFGroup class]]) {
        for (XFControl *child in [(XFGroup *)control children]) {
            [self removeControl:child fromList:list];
        }
    }
}

- (void)detachElement:(NSXMLElement *)element
{
    if (element == nil) {
        return;
    }
    NSString *local = [element localName];
    if ([local isEqualToString:@"bind"] || [local isEqualToString:@"instance"]
        || [local isEqualToString:@"submission"]) {
        [self.model dropElement:element];
        [self.model setRebuilded:YES];
        [self.model rebuild];
        [self.model refresh];
        return;
    }
    XFControl *control = [self controlForElement:element];
    XFControl *parent = control.parentControl ?: [self parentControlForElement:element];
    if ([parent isKindOfClass:[XFGroup class]]) {
        [(XFGroup *)parent removeChild:control];
    } else if ([parent isKindOfClass:[XFCase class]]) {
        [(XFCase *)parent removeChild:control];
    } else if ([parent isKindOfClass:[XFRepeat class]]) {
        [(XFRepeat *)parent reloadTemplates];
        [(XFRepeat *)parent rebuildItemsWithContext:[self evaluationContext] error:NULL];
    } else if (control) {
        NSMutableArray *list = [self.controls mutableCopy] ?: [NSMutableArray array];
        [self removeControl:control fromList:list];
        self.controls = list;
    }
    if ([control isKindOfClass:[XFRepeat class]]) {
        // drop from model.repeats is best-effort; next rebuild is fine
    }
}

- (void)noteElementChanged:(NSXMLElement *)element
{
    if (element == nil) {
        return;
    }
    XFControl *control = [self controlForElement:element];
    if (control == nil) {
        NSXMLNode *walk = [element parent];
        while (walk && control == nil) {
            if ([walk kind] == NSXMLElementKind) {
                control = [self controlForElement:(NSXMLElement *)walk];
            }
            walk = [walk parent];
        }
    }
    if (control) {
        [control reconfigureFromElement:NULL];
        if ([control isKindOfClass:[XFSelectControl class]]) {
            [(XFSelectControl *)control rebuildItemsWithContext:[self evaluationContext] error:NULL];
        }
        if ([control isKindOfClass:[XFRepeat class]]) {
            [(XFRepeat *)control reloadTemplates];
            [(XFRepeat *)control rebuildItemsWithContext:[self evaluationContext] error:NULL];
        }
        [self refreshControl:control];
    }
    NSString *local = [element localName];
    if ([local isEqualToString:@"bind"] || [local isEqualToString:@"submission"]) {
        [self.model setRebuilded:YES];
        [self.model rebuild];
        [self.model refresh];
    }
}

@end
