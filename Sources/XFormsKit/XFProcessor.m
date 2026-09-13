#import "XFProcessor.h"
#import "XFSubmissionTransport.h"
#import "XFHostNode.h"
#import "XFXPath.h"
#import "XFType.h"
#import "XFListener.h"
#import "XFEvent.h"
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
#import "XFSubform.h"
#import <XFormsKit/XFXMLTypes.h>

@interface XFProcessor ()
@property (nonatomic, strong, readwrite) XFHTTPSubmissionTransport *defaultTransport;
@property (nonatomic, strong, readwrite) XFXMLDocument *hostDocument;
@property (nonatomic, strong, readwrite) XFModel *model;
@property (nonatomic, copy, readwrite) NSArray<XFModel *> *models;
@property (nonatomic, copy, readwrite) NSArray<XFControl *> *controls;
@property (nonatomic, weak, readwrite) XFControl *focusedControl;
@property (nonatomic, assign) BOOL closed;
@property (nonatomic, copy, readwrite) NSArray<XFAbstractAction *> *actions;
@property (nonatomic, copy) NSArray<NSString *> *failedIncludes;
@property (nonatomic, copy, readwrite) NSArray<XFSubform *> *subforms;
/// The model given to actions being collected (a subform's default model
/// while its content is collected).
@property (nonatomic, weak) XFModel *actionModel;
@property (nonatomic, assign) NSUInteger subformCounter;
/// Set when a fatal construct-time exception (link/compute/version) halted
/// processing: the UI is never refreshed afterwards (4.5.2, 4.5.4).
@property (nonatomic, assign) BOOL halted;
@end

@implementation XFProcessor

+ (XFXMLDocument *)documentFromData:(NSData *)data error:(NSError **)error
{
    NSError *inner = nil;
    XFXMLDocument *doc =
        [[XFXMLDocument alloc] initWithData:data
                                    options:XFXMLNodePreserveWhitespace
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
    XFXMLDocument *doc = [self documentFromData:data error:error];
    if (doc == nil) {
        return nil;
    }
    return [[self alloc] initWithHostDocument:doc baseURL:url error:error];
}

+ (instancetype)processorWithXMLString:(NSString *)xml error:(NSError **)error
{
    return [self processorWithXMLString:xml baseURL:nil error:error];
}

+ (instancetype)processorWithXMLString:(NSString *)xml
                               baseURL:(NSURL *)baseURL
                                 error:(NSError **)error
{
    NSData *data = [xml dataUsingEncoding:NSUTF8StringEncoding];
    XFXMLDocument *doc = [self documentFromData:data error:error];
    if (doc == nil) {
        return nil;
    }
    return [[self alloc] initWithHostDocument:doc baseURL:baseURL error:error];
}

- (instancetype)initWithHostDocument:(XFXMLDocument *)document error:(NSError **)error
{
    return [self initWithHostDocument:document baseURL:nil error:error];
}

/// include.xsl: `xf:include/@src` is replaced by the root element of the
/// referenced document (which may itself hold controls or further
/// includes) — G-92. A document that cannot be loaded leaves the element
/// out and raises xforms-link-exception once the events are installed.
- (void)expandIncludesIn:(XFXMLDocument *)document
{
    [self expandIncludesIn:document baseURL:self.baseURL];
}

- (void)expandIncludesIn:(XFXMLDocument *)document baseURL:(NSURL *)baseURL
{
    NSMutableArray<NSString *> *failed = [NSMutableArray array];
    for (int depth = 0; depth < 8; depth++) {
        NSArray<XFXMLElement *> *includes = [XFXML elementsWithLocalName:@"include"
                                                            namespaceURI:XFXFormsNamespaceURI
                                                                  inNode:document];
        if (includes.count == 0) {
            break;
        }
        for (XFXMLElement *inc in includes) {
            XFXMLElement *parent = (XFXMLElement *)[inc parent];
            if ([parent kind] != XFXMLElementKind) {
                continue;
            }
            NSString *src = [[inc attributeForName:@"src"] stringValue];
            NSURL *url = src.length ? ([NSURL URLWithString:src relativeToURL:baseURL] ?: [NSURL fileURLWithPath:src]) : nil;
            NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
            XFXMLDocument *doc = data ? [[XFXMLDocument alloc] initWithData:data options:XFXMLNodePreserveWhitespace error:NULL] : nil;
            XFXMLElement *root = [doc rootElement];
            NSUInteger at = [inc index];
            [inc detach];
            if (root) {
                [root detach];
                [parent insertChild:root atIndex:at];
            } else {
                [failed addObject:src ?: @""];
            }
        }
    }
    _failedIncludes = failed;
}

- (instancetype)initWithHostDocument:(XFXMLDocument *)document
                             baseURL:(NSURL *)baseURL
                               error:(NSError **)error
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _hostDocument = document;
    _baseURL = baseURL;
    [self expandIncludesIn:document];

    // XForms 1.1 8.3.3: label/help/hint/alert carry a linking @src whose
    // resource replaces the inline default content (3.2.2.a, non-normative).
    // Resolved once here, before controls read their labels.
    for (NSString *name in @[ @"label", @"help", @"hint", @"alert" ]) {
        for (XFXMLElement *el in [XFXML elementsWithLocalName:name
                                                 namespaceURI:XFXFormsNamespaceURI
                                                       inNode:document]) {
            NSString *src = [[el attributeForName:@"src"] stringValue];
            if (src.length == 0) {
                continue;
            }
            NSURL *url = [NSURL URLWithString:src relativeToURL:baseURL];
            NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
            NSString *text = data ? [[NSString alloc] initWithData:data
                                                          encoding:NSUTF8StringEncoding] : nil;
            if (text.length) {
                [el setStringValue:[text stringByTrimmingCharactersInSet:
                                    [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
            }
        }
    }

    NSArray<XFXMLElement *> *modelElements =
        [XFXML elementsWithLocalName:@"model"
                       namespaceURI:XFXFormsNamespaceURI
                             inNode:document];
    if (modelElements.count == 0) {
        // XForms 1.1 3.3.1 (lazy authoring): a host document with no
        // xf:model gets an implicit empty default model (3.3.1.a2)
        XFXMLElement *implicit = [XFXMLElement elementWithName:@"model"
                                                           URI:XFXFormsNamespaceURI];
        [document.rootElement addChild:implicit];
        modelElements = @[ implicit ];
    }

    NSError *inner = nil;
    NSMutableArray<XFModel *> *models = [NSMutableArray array];
    for (XFXMLElement *modelElement in modelElements) {
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
            submission.baseURL = baseURL;
            [[XFXMLEvents sharedEvents] registerElement:submission.element xfElement:submission];
        }
    }
    _models = [models copy];
    XFModel *model = models.firstObject;
    _model = model;

    NSMutableArray<XFControl *> *controls = [NSMutableArray array];
    if (![self rebuildHostNodesReusing:nil into:controls error:&inner]) {
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
    for (NSString *src in _failedIncludes) {
        [XFXMLEvents raise:@"xforms-link-exception" on:self.models.firstObject
                   message:[NSString stringWithFormat:@"Include %@ not found", src]];
    }
    // fatal-exception window opens here: a missing xf:include (extension,
    // G-92) reports but does not halt — everything below does (4.5.4)
    NSUInteger exceptionsBefore = [[XFXMLEvents sharedEvents] exceptionMessages].count;

    // XsltForms_model.init: xf:model/@functions and @version checks (G-30)
    // XsltForms_schema: a second schema for an already loaded target
    // namespace is an xforms-link-exception (G-82)
    NSMutableSet<NSString *> *schemaNamespaces = [NSMutableSet set];
    NSMutableSet<NSNumber *> *schemaElements = [NSMutableSet set];
    BOOL (^registerSchema)(XFXMLElement *, XFModel *, BOOL) =
        ^BOOL(XFXMLElement *schemaEl, XFModel *m, BOOL external) {
        // XFModel.js: @schema names an already loaded schema, so an inline
        // schema referenced by its id is not loaded twice
        NSNumber *key = @((unsigned long long)(uintptr_t)schemaEl);
        if ([schemaElements containsObject:key]) {
            return YES;
        }
        [schemaElements addObject:key];
        NSString *tns = [[schemaEl attributeForName:@"targetNamespace"] stringValue] ?: @"";
        if (tns.length && [schemaNamespaces containsObject:tns]) {
            if (external) {
                // XML Schema lets several schema DOCUMENTS contribute to
                // one namespace; two valid @schema files sharing a
                // targetNamespace merge without exception (4.2.1.b1)
                [XFType registerSchemaElement:schemaEl];
                return YES;
            }
            [XFXMLEvents raise:@"xforms-link-exception" on:m
                       message:@"More than one schema with the same namespace declaration"];
            return NO;
        }
        [schemaNamespaces addObject:tns];
        [XFType registerSchemaElement:schemaEl];
        return YES;
    };
    for (XFModel *m in self.models) {
        // schemas: inline xs:schema children, and @schema tokens naming an
        // element id (#id / id) or a URL; a missing one is a link-exception
        // (XFModel.js: "Schema … not found", G-56)
        for (XFXMLNode *c in [m.element children]) {
            if ([c kind] == XFXMLElementKind && [[c localName] isEqualToString:@"schema"]
                && [[c URI] isEqualToString:@"http://www.w3.org/2001/XMLSchema"]) {
                registerSchema((XFXMLElement *)c, m, NO);
            }
        }
        NSString *schemas = [[m.element attributeForName:@"schema"] stringValue];
        for (NSString *ref in [schemas componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
            if (ref.length == 0) {
                continue;
            }
            XFXMLElement *schemaEl = nil;
            BOOL external = NO;
            NSString *sid = [ref hasPrefix:@"#"] ? [ref substringFromIndex:1] : ref;
            XFXMLElement *byID = [[XFXMLEvents sharedEvents] elementWithID:sid inDocument:document];
            if (byID && [[byID localName] isEqualToString:@"schema"]) {
                schemaEl = byID;
            } else if (![ref hasPrefix:@"#"]) {
                NSURL *url = [NSURL URLWithString:ref relativeToURL:self.baseURL] ?: [NSURL fileURLWithPath:ref];
                NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
                XFXMLDocument *sdoc = data ? [[XFXMLDocument alloc] initWithData:data options:0 error:NULL] : nil;
                schemaEl = [sdoc rootElement];
                external = YES;
            }
            if (schemaEl) {
                registerSchema(schemaEl, m, external);
            } else {
                [XFXMLEvents raise:@"xforms-link-exception" on:m
                           message:[NSString stringWithFormat:@"Schema %@ not found", ref]];
            }
        }
        NSString *functions = [[m.element attributeForName:@"functions"] stringValue];
        for (NSString *fname in [functions componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
            if (fname.length == 0) {
                continue;
            }
            NSString *local = [fname componentsSeparatedByString:@":"].lastObject;
            if (![XFXPath hasFunctionNamed:fname] && ![XFXPath hasFunctionNamed:local]) {
                [XFXMLEvents raise:@"xforms-compute-exception" on:m
                           message:[NSString stringWithFormat:@"Function %@() not found", fname]];
            }
        }
        NSString *version = [[m.element attributeForName:@"version"] stringValue];
        for (NSString *v in [version componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
            if (v.length && ![v isEqualToString:@"1.0"] && ![v isEqualToString:@"1.1"]) {
                [XFXMLEvents raise:@"xforms-version-exception" on:self.model
                           message:[NSString stringWithFormat:@"Version %@ not supported", v]];
                break;
            }
        }
    }

    for (XFModel *m in self.models) {
        [XFXMLEvents dispatch:m name:@"xforms-model-construct"];
        [XFXMLEvents dispatch:m name:@"xforms-model-construct-done"];
    }
    // XForms 1.1 4.5.2/4.5.4 (also 4.5.3): the exception default actions
    // are FATAL — after dispatching, processing halts. A construct-time
    // link-/compute-/version-exception stops here: the models and their
    // handlers ran (messages, event context), but the UI never refreshes
    // (4.5.2.a, 4.5.4.a). Refresh-time exceptions stay non-halting.
    NSArray<NSString *> *raised = [[XFXMLEvents sharedEvents] exceptionMessages];
    for (NSUInteger e = exceptionsBefore; e < raised.count; e++) {
        if ([raised[e] hasPrefix:@"xforms-link-exception"]
            || [raised[e] hasPrefix:@"xforms-compute-exception"]
            || [raised[e] hasPrefix:@"xforms-version-exception"]) {
            self.halted = YES;
            return self;
        }
    }
    [self refreshControls];
    // case.xsl: the initially selected case of every switch gets
    // xforms-select once (G-26)
    [self dispatchInitialSelectIn:self.controls];
    // XsltForms_globals.init: ready is set once for all models, then
    // xforms-ready is dispatched to every model (G-18). It is synchronous
    // here (no setTimeout): callers see a ready processor on return.
    for (XFModel *m in self.models) {
        m.ready = YES;
    }
    for (XFModel *m in self.models) {
        [XFXMLEvents dispatch:m name:@"xforms-ready"];
    }
    [self refreshControls];
    // xf:component/@resource: each component embeds its resource as a
    // subform into itself (XFComponent.js, G-95)
    NSMutableArray<XFComponentControl *> *components = [NSMutableArray array];
    for (XFControl *c in self.controls) {
        [self collectControlsOfClass:[XFComponentControl class] from:c into:components];
    }
    for (XFComponentControl *component in components) {
        NSString *resource = component.resource;
        NSURL *url = resource.length ? ([NSURL URLWithString:resource relativeToURL:baseURL] ?: [NSURL fileURLWithPath:resource]) : nil;
        NSError *err = nil;
        if (url == nil || ![self loadSubformAtURL:url intoTargetElement:component.element error:&err]) {
            [XFXMLEvents raise:@"xforms-link-exception" on:component
                       message:[NSString stringWithFormat:@"Component %@ not found", resource ?: @""]];
        }
    }
    return self;
}

- (BOOL)collectActionsUnder:(XFXMLNode *)node
                     parent:(XFAction *)parent
                    actions:(NSMutableArray<XFAbstractAction *> *)actions
                      error:(NSError **)error
{
    if ([node kind] != XFXMLElementKind) {
        return YES;
    }
    XFXMLElement *element = (XFXMLElement *)node;
    XFAction *nextParent = parent;
    if ([XFAbstractAction isActionElement:element]) {
        NSError *inner = nil;
        XFAbstractAction *action = [XFAbstractAction actionWithElement:element
                                                                model:self.actionModel ?: self.model
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
    for (XFXMLNode *child in [element children]) {
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

/// The element whose content is the form's UI: the XHTML body when there
/// is one, else the document element (XSLTForms' body template).
- (XFXMLElement *)findHostRoot
{
    XFXMLElement *root = self.hostDocument.rootElement;
    for (XFXMLNode *c in [root children]) {
        if ([c kind] == XFXMLElementKind && [[[c localName] lowercaseString] isEqualToString:@"body"]) {
            return (XFXMLElement *)c;
        }
    }
    return root;
}

- (BOOL)rebuildHostNodesReusing:(NSArray<XFControl *> *)existing
                           into:(NSMutableArray<XFControl *> *)controls
                          error:(NSError **)error
{
    XFXMLElement *hostRoot = [self findHostRoot];
    NSArray *nodes = [XFHostNode hostNodesForChildrenOf:hostRoot
                                                  model:self.model
                                               controls:controls
                                               existing:existing ? [XFHostNode controlMapFor:existing] : nil
                                                  error:error];
    if (nodes == nil) {
        return NO;
    }
    for (XFControl *control in controls) {
        if (control.owner == nil) {
            control.owner = self;
        }
    }
    _hostRootElement = hostRoot;
    _hostNodes = nodes;
    return YES;
}

- (BOOL)rebuildHostNodes:(NSError **)error
{
    NSMutableArray<XFControl *> *controls = [NSMutableArray array];
    if (![self rebuildHostNodesReusing:self.controls into:controls error:error]) {
        return NO;
    }
    self.controls = controls;
    return YES;
}

- (BOOL)collectControlsUnder:(XFXMLNode *)node
                        into:(NSMutableArray<XFControl *> *)controls
                       error:(NSError **)error
{
    if ([node kind] != XFXMLElementKind) {
        return YES;
    }
    XFXMLElement *element = (XFXMLElement *)node;
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
    for (XFXMLNode *child in [element children]) {
        if (![self collectControlsUnder:child into:controls error:error]) {
            return NO;
        }
    }
    return YES;
}

- (NSString *)labelForElement:(XFXMLElement *)element
{
    // only a direct child: a repeat/group must not borrow the label of the
    // first control nested in its markup (G-20)
    XFXMLElement *label =
        [XFXML childElementWithLocalName:@"label"
                           namespaceURI:XFXFormsNamespaceURI
                              ofElement:element];
    return label ? [XFXML stringValueOfNode:label] : nil;
}

- (XFControl *)controlFromElement:(XFXMLElement *)element
                            class:(Class)cls
                 bindingAttribute:(NSString *)attribute
                            error:(NSError **)error
{
    XFXMLNode *attr = [element attributeForName:attribute];
    XFBinding *binding = nil;
    if (attr && [attr stringValue].length > 0) {
        binding = [XFBinding bindingWithExpression:[attr stringValue] element:element error:error];
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
    } else if ([control isKindOfClass:[XFRepeat class]]) {
        for (XFRepeatItem *item in [(XFRepeat *)control items]) {
            for (XFControl *child in item.controls) {
                [self collectControlsOfClass:cls from:child into:out];
            }
        }
    } else if ([control isKindOfClass:[XFSwitch class]]) {
        for (XFCase *caze in [(XFSwitch *)control cases]) {
            for (XFControl *child in caze.children) {
                [self collectControlsOfClass:cls from:child into:out];
            }
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

- (XFHTTPSubmissionTransport *)defaultTransport
{
    if (_defaultTransport == nil) {
        _defaultTransport = [[XFHTTPSubmissionTransport alloc] init];
    }
    return _defaultTransport;
}

- (NSString *)effectiveLanguage
{
    if (self.language.length) {
        return self.language;
    }
    NSString *preferred = [NSLocale preferredLanguages].firstObject;
    return preferred.length ? preferred : @"en";
}

- (XFControl *)controlWithIdentifier:(NSString *)identifier
{
    if (identifier.length == 0) {
        return nil;
    }
    XFXMLElement *element = [[XFXMLEvents sharedEvents] elementWithID:identifier inDocument:self.hostDocument];
    return element ? [self controlForElement:element] : nil;
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
    if (self.halted) {
        return;
    }
    XFExprContext *ctx = [self evaluationContext];
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du pushVariableScope];
    for (XFControl *control in self.controls) {
        [control refreshInContext:ctx error:NULL];
    }
    [du popVariableScope];
}

- (BOOL)refresh:(NSError **)error
{
    XFExprContext *ctx = [self evaluationContext];
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du pushVariableScope];
    for (XFControl *control in self.controls) {
        NSError *inner = nil;
        [control refreshInContext:ctx error:&inner];
        if (inner) {
            if (error) {
                *error = inner;
            }
            [du popVariableScope];
            return NO;
        }
    }
    [du popVariableScope];
    return YES;
}

- (void)activateControl:(XFTriggerControl *)control
{
    [control activate];
    [self refreshControls];
}

- (XFControl *)matchControl:(XFControl *)control element:(XFXMLElement *)element
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

- (XFControl *)controlForElement:(XFXMLElement *)element
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
    // XForms 1.1 6.1.2: a readonly node refuses the edit at the MODEL —
    // graying the widget is not enough (a scripted write must bounce too)
    if (control.readonly) {
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorBinding
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"bound node is readonly" }];
        }
        return NO;
    }
    value = [control applyInputMode:value];   // G-41
    // XsltForms_control.valueChanged: nothing happens when the value is unchanged
    if (control.boundNode && [[XFXML stringValueOfNode:control.boundNode] isEqualToString:value ?: @""]) {
        control.stringValue = value ?: @"";
        return YES;
    }
    if (![control commitStringValue:value error:error]) {
        return NO;
    }
    [self controlDidChangeValue:control];
    return YES;
}

- (void)dispatchInitialSelectIn:(NSArray<XFControl *> *)controls
{
    for (XFControl *c in controls) {
        if ([c isKindOfClass:[XFSwitch class]]) {
            [(XFSwitch *)c dispatchInitialSelect];
            for (XFCase *caze in [(XFSwitch *)c cases]) {
                [self dispatchInitialSelectIn:caze.children];
            }
        } else if ([c isKindOfClass:[XFGroup class]]) {
            [self dispatchInitialSelectIn:[(XFGroup *)c children]];
        } else if ([c isKindOfClass:[XFRepeat class]]) {
            for (XFRepeatItem *item in [(XFRepeat *)c items]) {
                [self dispatchInitialSelectIn:item.controls];
            }
        }
    }
}

#pragma mark - close (G-54)

- (void)close
{
    if (self.closed) {
        return;
    }
    self.closed = YES;
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"close"];
    for (XFListener *listener in [[XFListener destructs] copy]) {
        XFXMLElement *observer = listener.observer;
        if (observer == nil || [observer rootDocument] != self.hostDocument) {
            continue;
        }
        XFEvent *event = [[XFEvent alloc] init];
        event.type = @"xforms-model-destruct";
        event.target = observer;
        event.currentTarget = observer;
        event.xfElement = [[XFXMLEvents sharedEvents] xfElementForElement:observer];
        event.phase = @"default";
        [listener invoke:event];
    }
    [du closeAction:@"close"];
    for (XFListener *listener in [[XFListener destructs] copy]) {
        if ([listener.observer rootDocument] == self.hostDocument) {
            [listener detach];
        }
    }
    self.focusRequestHandler = nil;
}

#pragma mark - subforms (G-90)

- (XFSubform *)subformContainingElement:(XFXMLNode *)element
{
    // innermost first: a nested subform's target lies below its parent's
    for (XFSubform *sf in [self.subforms reverseObjectEnumerator]) {
        if ([sf containsElement:element]) {
            return sf;
        }
    }
    return nil;
}

- (XFSubform *)subformAtTarget:(XFXMLElement *)target
{
    for (XFSubform *sf in self.subforms) {
        if (sf.targetElement == target) {
            return sf;
        }
    }
    return nil;
}

/// YES when the element sits inside an xf:repeat template — where one
/// host element serves every repeat item and subform targets need
/// per-item owners.
static BOOL XFElementInsideRepeat(XFXMLElement *element)
{
    for (XFXMLNode *walk = [element parent]; walk != nil; walk = [walk parent]) {
        if ([walk kind] == XFXMLElementKind
            && [XFXML element:(XFXMLElement *)walk hasLocalName:@"repeat"
                 namespaceURI:XFXFormsNamespaceURI]) {
            return YES;
        }
    }
    return NO;
}

/// The subform loaded into `target` for this owner (nil owner = the
/// unscoped one).
- (XFSubform *)subformAtTarget:(XFXMLElement *)target ownerNode:(XFXMLNode *)owner
{
    for (XFSubform *sf in self.subforms) {
        if (sf.targetElement == target && sf.ownerNode == owner) {
            return sf;
        }
    }
    return nil;
}

static NSError *XFSubformError(NSString *message)
{
    return [NSError errorWithDomain:XFErrorDomain code:XFErrorDocument
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

/// The element whose content a subform replaces: the target itself, or for
/// a control target its element minus label/help/hint/alert (XFLoad.js
/// replaces the innerHTML of the control's last child div).
- (void)clearSubformTarget:(XFXMLElement *)target ownerNode:(XFXMLNode *)owner
{
    for (XFXMLNode *c in [[target children] copy]) {
        if (owner != nil && [XFSubform ownerNodeOfImportedNode:c] != owner) {
            continue;   // another repeat item's subform (or authored content)
        }
        if ([c kind] == XFXMLElementKind && [[c URI] isEqualToString:XFXFormsNamespaceURI]) {
            NSString *n = [c localName];
            if ([n isEqualToString:@"label"] || [n isEqualToString:@"help"]
                || [n isEqualToString:@"hint"] || [n isEqualToString:@"alert"]) {
                continue;
            }
        }
        [c detach];
    }
}

- (void)rebuildAroundTarget:(XFXMLElement *)target
{
    // a target inside a repeat template must rebuild THROUGH the repeat:
    // items re-instantiate under their own item scope, so per-item
    // subform content lands only in its owner's tree
    for (XFXMLNode *walk = [target parent]; walk != nil; walk = [walk parent]) {
        if ([walk kind] == XFXMLElementKind
            && [XFXML element:(XFXMLElement *)walk hasLocalName:@"repeat"
                 namespaceURI:XFXFormsNamespaceURI]) {
            XFControl *repeat = [self controlForElement:(XFXMLElement *)walk];
            if ([repeat isKindOfClass:[XFRepeat class]]) {
                [(XFRepeat *)repeat reloadTemplates];
                [(XFRepeat *)repeat rebuildItemsWithContext:[self evaluationContext] error:NULL];
                return;
            }
        }
    }
    XFControl *targetControl = [self controlForElement:target];
    XFControl *container = targetControl ?: [self parentControlForElement:target];
    if ([container isKindOfClass:[XFGroup class]]) {
        [(XFGroup *)container rebuildHostNodesWithError:NULL];
        for (XFControl *child in [(XFGroup *)container children]) {
            [self registerControlTree:child];
        }
    } else if ([container isKindOfClass:[XFCase class]]) {
        [(XFCase *)container rebuildHostNodesWithError:NULL];
        for (XFControl *child in [(XFCase *)container children]) {
            [self registerControlTree:child];
        }
    } else if ([container isKindOfClass:[XFRepeat class]]) {
        [(XFRepeat *)container reloadTemplates];
        [(XFRepeat *)container rebuildItemsWithContext:[self evaluationContext] error:NULL];
    } else {
        [self rebuildHostNodes:NULL];
        for (XFControl *c in self.controls) {
            [self registerControlTree:c];
        }
    }
}

- (XFSubform *)loadSubformAtURL:(NSURL *)url intoTargetID:(NSString *)targetID error:(NSError **)error
{
    return [self loadSubformAtURL:url intoTargetID:targetID contextNode:nil error:error];
}

- (XFSubform *)loadSubformAtURL:(NSURL *)url
                   intoTargetID:(NSString *)targetID
                    contextNode:(XFXMLNode *)contextNode
                          error:(NSError **)error
{
    XFXMLElement *target = [[XFXMLEvents sharedEvents] elementWithID:targetID inDocument:self.hostDocument];
    if (target == nil) {
        if (error) *error = XFSubformError([NSString stringWithFormat:@"Unknown subform target %@", targetID ?: @""]);
        return nil;
    }
    return [self loadSubformAtURL:url intoTargetElement:target ownerNode:contextNode error:error];
}

- (XFSubform *)loadSubformAtURL:(NSURL *)url intoTargetElement:(XFXMLElement *)target error:(NSError **)error
{
    return [self loadSubformAtURL:url intoTargetElement:target ownerNode:nil error:error];
}

- (XFSubform *)loadSubformAtURL:(NSURL *)url
              intoTargetElement:(XFXMLElement *)target
                      ownerNode:(XFXMLNode *)ownerNode
                          error:(NSError **)error
{
    // per-item scoping only where one template element serves many items
    XFXMLNode *owner = XFElementInsideRepeat(target) ? ownerNode : nil;
    NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
    XFXMLDocument *doc = data ? [[self class] documentFromData:data error:error] : nil;
    if (doc == nil) {
        if (error && *error == nil) *error = XFSubformError([NSString stringWithFormat:@"Cannot load %@", url.absoluteString ?: @""]);
        return nil;
    }
    [self expandIncludesIn:doc baseURL:url];

    // a subform already loaded there FOR THIS OWNER is disposed first
    // (XFLoad.js; other repeat items keep theirs)
    XFSubform *previous = [self subformAtTarget:target ownerNode:owner];
    if (previous) {
        [self disposeSubform:previous];
    }

    XFSubform *sf = [[XFSubform alloc] init];
    sf.identifier = [NSString stringWithFormat:@"xsltforms-subform-%lu", (unsigned long)self.subformCounter++];
    sf.processor = self;
    sf.parent = [self subformContainingElement:target];
    sf.targetElement = target;
    sf.ownerNode = owner;
    sf.URL = url;
    sf.subforms = @[];

    // import: the models first (skipped by the host tree), then the body
    NSMutableArray<XFXMLNode *> *imported = [NSMutableArray array];
    for (XFXMLElement *modelEl in [XFXML elementsWithLocalName:@"model" namespaceURI:XFXFormsNamespaceURI inNode:doc]) {
        XFXMLElement *copy = [modelEl copy];
        [imported addObject:copy];
    }
    XFXMLElement *body = nil;
    for (XFXMLNode *c in [[doc rootElement] children]) {
        if ([c kind] == XFXMLElementKind && [[[c localName] lowercaseString] isEqualToString:@"body"]) {
            body = (XFXMLElement *)c;
        }
    }
    NSArray *bodyNodes = body ? [body children] : @[ [doc rootElement] ];
    for (XFXMLNode *n in bodyNodes) {
        if ([n kind] == XFXMLElementKind && [XFXML element:(XFXMLElement *)n hasLocalName:@"model" namespaceURI:XFXFormsNamespaceURI]) {
            continue;   // already imported
        }
        [imported addObject:[n copy]];
    }
    [self clearSubformTarget:target ownerNode:owner];
    for (XFXMLNode *n in imported) {
        [target addChild:n];
        if (owner != nil) {
            [XFSubform tagImportedNode:n ownerNode:owner];
        }
    }
    sf.importedNodes = imported;

    NSMutableArray<XFModel *> *models = [NSMutableArray array];
    for (XFXMLNode *n in imported) {
        if (!([n kind] == XFXMLElementKind && [XFXML element:(XFXMLElement *)n hasLocalName:@"model" namespaceURI:XFXFormsNamespaceURI])) {
            continue;
        }
        NSError *inner = nil;
        XFModel *model = [XFModel modelWithElement:(XFXMLElement *)n error:&inner];
        if (model == nil) {
            for (XFXMLNode *m in imported) { [m detach]; }
            if (error) *error = inner;
            return nil;
        }
        model.owner = self;
        model.subform = sf;
        [models addObject:model];
        [[XFXMLEvents sharedEvents] registerElement:model.element xfElement:model];
        for (XFInstance *instance in model.instances) {
            instance.baseURL = url;
            if (instance.element) {
                [[XFXMLEvents sharedEvents] registerElement:instance.element xfElement:instance];
            }
        }
        for (XFSubmission *submission in model.submissions) {
            submission.baseURL = url;   // the subform document's URL
            [[XFXMLEvents sharedEvents] registerElement:submission.element xfElement:submission];
        }
    }
    sf.models = models;
    self.models = [self.models arrayByAddingObjectsFromArray:models];
    NSMutableArray *subforms = [self.subforms mutableCopy] ?: [NSMutableArray array];
    [subforms addObject:sf];
    self.subforms = subforms;
    if (sf.parent) {
        sf.parent.subforms = [sf.parent.subforms arrayByAddingObject:sf];
    }

    // controls, actions, listeners of the imported content
    [self rebuildAroundTarget:target];
    NSMutableArray<XFAbstractAction *> *actions = [self.actions mutableCopy] ?: [NSMutableArray array];
    self.actionModel = models.firstObject;
    NSError *actionError = nil;
    [self collectActionsUnder:target parent:nil actions:actions error:&actionError];
    self.actionModel = nil;
    self.actions = actions;
    [[XFXMLEvents sharedEvents] installListenersUnder:target inDocument:self.hostDocument];

    // XsltForms_subform.construct: model construction, then
    // xforms-subform-ready on every model (no xforms-ready for a subform)
    for (XFModel *m in models) {
        [XFXMLEvents dispatch:m name:@"xforms-model-construct"];
        [XFXMLEvents dispatch:m name:@"xforms-model-construct-done"];
    }
    [self refreshControls];
    for (XFModel *m in models) {
        m.ready = YES;
    }
    for (XFModel *m in models) {
        [XFXMLEvents dispatch:m name:@"xforms-subform-ready"];
    }
    sf.ready = YES;
    // imported content may live INSIDE repeat items: the reuse cache
    // would hide it, so every repeat rebuilds its rows once
    [self invalidateRepeatItemCaches];
    [self refreshControls];
    return sf;
}

- (void)invalidateRepeatItemCaches
{
    for (XFModel *m in self.models) {
        for (XFRepeat *r in m.repeats) {
            [r invalidateItems];
        }
    }
}

- (BOOL)unloadSubformAtTargetID:(NSString *)targetID
{
    return [self unloadSubformAtTargetID:targetID contextNode:nil];
}

- (BOOL)unloadSubformAtTargetID:(NSString *)targetID contextNode:(XFXMLNode *)contextNode
{
    XFXMLElement *target = [[XFXMLEvents sharedEvents] elementWithID:targetID inDocument:self.hostDocument];
    XFXMLNode *owner = (target != nil && XFElementInsideRepeat(target)) ? contextNode : nil;
    XFSubform *sf = target ? [self subformAtTarget:target ownerNode:owner] : nil;
    if (sf == nil) {
        return NO;
    }
    [self disposeSubform:sf];
    [self rebuildAroundTarget:target];
    [self invalidateRepeatItemCaches];
    [self refreshControls];
    return YES;
}

- (void)disposeSubform:(XFSubform *)sf
{
    for (XFSubform *nested in [sf.subforms copy]) {
        [self disposeSubform:nested];
    }
    // listeners and actions of the imported content
    NSMutableArray *kept = [NSMutableArray array];
    for (XFAbstractAction *a in self.actions) {
        if (a.element && [sf containsElement:a.element]) {
            for (XFListener *l in [[[XFXMLEvents sharedEvents] listenersForElement:a.element] copy]) {
                [l detach];
            }
            continue;
        }
        [kept addObject:a];
    }
    self.actions = kept;
    NSMutableArray *models = [self.models mutableCopy];
    [models removeObjectsInArray:sf.models];
    self.models = models;
    NSMutableArray *list = [self.controls mutableCopy] ?: [NSMutableArray array];
    for (XFControl *c in [list copy]) {
        if (c.element && [sf containsElement:c.element]) {
            [self removeControl:c fromList:list];
        }
    }
    self.controls = list;
    for (XFXMLNode *n in sf.importedNodes) {
        [n detach];
    }
    NSMutableArray *subforms = [self.subforms mutableCopy];
    [subforms removeObject:sf];
    self.subforms = subforms;
    if (sf.parent) {
        NSMutableArray *siblings = [sf.parent.subforms mutableCopy];
        [siblings removeObject:sf];
        sf.parent.subforms = siblings;
    }
    sf.ready = NO;
}

#pragma mark - focus (G-24)

- (void)focusControl:(XFControl *)control fromUI:(BOOL)fromUI
{
    if (control == nil || [control isKindOfClass:[XFOutputControl class]]) {
        return;   // XsltForms_control.focus: outputs never take the focus
    }
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    if (self.focusedControl != control) {
        [du openAction:@"focus"];
        [self blurFocusedControl];
        _focusedControl = control;
        control.focused = YES;
        // XsltForms_repeat.selectItem for every enclosing repeat item —
        // but only for a USER click into the widget. A programmatic
        // xf:setfocus targets the occurrence at the repeat's CURRENT
        // index (10.7.a: setindex 3 then setfocus must keep index 3);
        // re-selecting the item that owns the resolved control object
        // would yank the index back to that row.
        if (fromUI) {
            XFControl *child = control;
            XFControl *parent = control.parentControl;
            while (parent) {
                if ([parent isKindOfClass:[XFRepeat class]]) {
                    XFRepeat *repeat = (XFRepeat *)parent;
                    for (XFRepeatItem *item in repeat.items) {
                        if ([item.controls indexOfObjectIdenticalTo:child] != NSNotFound) {
                            [repeat setIndex:item.position];
                            break;
                        }
                    }
                }
                child = parent;
                parent = parent.parentControl;
            }
        }
        [XFXMLEvents dispatch:control name:@"DOMFocusIn"];
        [du closeAction:@"focus"];
    }
    if (!fromUI && self.focusRequestHandler) {
        self.focusRequestHandler(control);
    }
}

- (void)blurFocusedControl
{
    XFControl *previous = self.focusedControl;
    if (previous == nil) {
        return;
    }
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"blur"];
    previous.focused = NO;
    _focusedControl = nil;
    [XFXMLEvents dispatch:previous name:@"DOMFocusOut"];
    [du closeAction:@"blur"];
}

- (XFModel *)modelContainingNode:(XFXMLNode *)node
{
    if (node == nil) {
        return nil;
    }
    for (XFModel *m in self.models) {
        if ([m instanceOwningNode:node]) {
            return m;
        }
    }
    return nil;
}

- (void)controlDidChangeValue:(XFControl *)control
{
    // XSLTForms: XsltForms_globals.openAction(); model.addChange(node);
    // xforms-value-changed; closeAction() -> rebuild/recalculate/revalidate/
    // refresh through the deferred-update queue. Every UI-originated change
    // must come through here, or dependent MIPs are not recomputed.
    // the model owning the bound node (a control may bind into another
    // model via model="id" / instance('id'), G-22)
    XFModel *model = [self modelContainingNode:control.boundNode]
        ?: ([control.owner isKindOfClass:[XFModel class]] ? (XFModel *)control.owner : self.model);
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    // xforms-value-changed is dispatched by the refresh that follows
    // (XsltForms_control.refresh), once, and only if the value changed (G-11)
    [du openAction:@"setValue"];
    [model addChange:control.boundNode];
    [du addChangedModel:model];
    [du closeAction:@"setValue"];
}

- (XFControl *)parentControlForElement:(XFXMLElement *)element
{
    XFXMLNode *walk = [element parent];
    while (walk) {
        if ([walk kind] == XFXMLElementKind) {
            XFControl *found = [self controlForElement:(XFXMLElement *)walk];
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
    [control refreshInContext:[self evaluationContext] error:NULL];
}

- (XFControl *)attachElement:(XFXMLElement *)element error:(NSError **)error
{
    if (element == nil) {
        return nil;
    }
    NSString *local = [element localName];
    if ([local isEqualToString:@"bind"] || [local isEqualToString:@"instance"]
        || [local isEqualToString:@"submission"]) {
        XFModel *model = self.model;
        XFXMLNode *walk = element;
        while (walk) {
            if ([walk kind] == XFXMLElementKind
                && [XFXML element:(XFXMLElement *)walk hasLocalName:@"model" namespaceURI:XFXFormsNamespaceURI]) {
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
        // a nested action (setvalue inside xf:action) is compiled as part
        // of its outermost handler — recompile that whole handler
        XFXMLElement *top = XFOutermostActionElement(element);
        [self dropCompiledActionForElement:top];
        NSError *inner = nil;
        XFAbstractAction *action = [XFAbstractAction actionWithElement:top
                                                                model:self.model
                                                                error:&inner];
        if (action == nil) {
            if (error) { *error = inner; }
            return nil;
        }
        NSMutableArray *actions = [self.actions mutableCopy] ?: [NSMutableArray array];
        [actions addObject:action];
        self.actions = actions;
        [[XFXMLEvents sharedEvents] registerElement:top xfElement:action];
        [[XFXMLEvents sharedEvents] installListenersUnder:top inDocument:self.hostDocument];
        return nil;
    }

    if (![XFControl shouldInstantiateElement:element]) {
        XFControl *parent = [self parentControlForElement:element];
        if ([parent isKindOfClass:[XFSelectControl class]]) {
            // item / itemset / choices live on the select templates —
            // recompile them, the element set just changed
            [(XFSelectControl *)parent reloadTemplatesWithError:NULL];
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
        [(XFGroup *)parent rebuildHostNodesWithError:NULL];
    } else if ([parent isKindOfClass:[XFCase class]]) {
        [(XFCase *)parent addChild:control];
        [(XFCase *)parent rebuildHostNodesWithError:NULL];
    } else if ([parent isKindOfClass:[XFRepeat class]]) {
        [(XFRepeat *)parent reloadTemplates];
        [(XFRepeat *)parent rebuildItemsWithContext:[self evaluationContext] error:NULL];
    } else {
        NSMutableArray *list = [self.controls mutableCopy] ?: [NSMutableArray array];
        [list addObject:control];
        self.controls = list;
        [self rebuildHostNodes:NULL];
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

/// The highest action element on `element`'s ancestor chain (element
/// itself when none is above it) — nested actions compile as part of it.
static XFXMLElement *XFOutermostActionElement(XFXMLElement *element)
{
    XFXMLElement *top = element;
    for (XFXMLNode *walk = [element parent]; walk != nil; walk = [walk parent]) {
        if ([walk kind] == XFXMLElementKind
            && [XFAbstractAction isActionElement:(XFXMLElement *)walk]) {
            top = (XFXMLElement *)walk;
        }
    }
    return top;
}

/// Removes the compiled action for `element` (if any) with its listeners.
- (void)dropCompiledActionForElement:(XFXMLElement *)element
{
    NSMutableArray *actions = [self.actions mutableCopy] ?: [NSMutableArray array];
    for (XFAbstractAction *action in [actions copy]) {
        if (action.element == element) {
            [actions removeObject:action];
        }
    }
    self.actions = actions;
    [[XFXMLEvents sharedEvents] removeListenersWithHandlersUnder:element
                                                      inDocument:self.hostDocument];
    [[XFXMLEvents sharedEvents] registerElement:element xfElement:nil];
}

- (void)detachElement:(XFXMLElement *)element
{
    if (element == nil) {
        return;
    }
    if ([XFAbstractAction isActionElement:element]) {
        // the element is already physically detached, so the ancestor
        // walk cannot reach a surrounding handler here; XFHostEdit
        // notifies the surviving parent separately
        [self dropCompiledActionForElement:element];
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
        [(XFGroup *)parent rebuildHostNodesWithError:NULL];
    } else if ([parent isKindOfClass:[XFCase class]]) {
        [(XFCase *)parent removeChild:control];
        [(XFCase *)parent rebuildHostNodesWithError:NULL];
    } else if ([parent isKindOfClass:[XFRepeat class]]) {
        [(XFRepeat *)parent reloadTemplates];
        [(XFRepeat *)parent rebuildItemsWithContext:[self evaluationContext] error:NULL];
    } else if ([parent isKindOfClass:[XFSelectControl class]]) {
        // a deleted item / itemset leaves the compiled templates stale
        [(XFSelectControl *)parent reloadTemplatesWithError:NULL];
        [(XFSelectControl *)parent rebuildItemsWithContext:[self evaluationContext] error:NULL];
    } else if (control) {
        NSMutableArray *list = [self.controls mutableCopy] ?: [NSMutableArray array];
        [self removeControl:control fromList:list];
        self.controls = list;
        [self rebuildHostNodes:NULL];
    } else {
        [self rebuildHostNodes:NULL];
    }
    if ([control isKindOfClass:[XFRepeat class]]) {
        // drop from model.repeats is best-effort; next rebuild is fine
    }
}

- (void)noteElementChanged:(XFXMLElement *)element
{
    if (element == nil) {
        return;
    }
    if ([XFAbstractAction isActionElement:element]) {
        // actions compile their attributes and content up front —
        // recompile the outermost handler the element belongs to
        XFXMLElement *top = XFOutermostActionElement(element);
        [self dropCompiledActionForElement:top];
        [self attachElement:top error:NULL];
        return;
    }
    XFControl *control = [self controlForElement:element];
    if (control == nil) {
        XFXMLNode *walk = [element parent];
        while (walk && control == nil) {
            if ([walk kind] == XFXMLElementKind) {
                control = [self controlForElement:(XFXMLElement *)walk];
            }
            walk = [walk parent];
        }
    }
    if (control) {
        [control reconfigureFromElement:NULL];
        if ([control isKindOfClass:[XFSelectControl class]]) {
            [(XFSelectControl *)control reloadTemplatesWithError:NULL];
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
