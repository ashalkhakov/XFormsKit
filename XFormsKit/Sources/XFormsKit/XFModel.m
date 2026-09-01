#import "XFModel.h"
#import "XFProcessor.h"
#import "XFDeferredUpdates.h"
#import "XFInstance.h"
#import "XFBind.h"
#import "XFSubmission.h"
#import "XFRepeat.h"
#import "XFNamespaces.h"
#import "XFXML.h"
#import "XFErrors.h"
#import "XFXMLEvents.h"
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLNode.h>
#import <Foundation/NSXMLDocument.h>

@interface XFModel ()
@property (nonatomic, copy, readwrite) NSArray<XFInstance *> *instances;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *translations;
@property (nonatomic, copy, readwrite) NSString *defaultLanguage;
@property (nonatomic, copy, readwrite) NSArray<XFSubmission *> *submissions;
@property (nonatomic, strong) NSMutableArray<XFRepeat *> *mutableRepeats;
@property (nonatomic, strong) NSMutableArray<XFBind *> *mutableBinds;
@property (nonatomic, strong, readwrite) NSMutableArray<NSXMLNode *> *nodesChanged;
@property (nonatomic, strong, readwrite) NSMutableArray<NSXMLNode *> *pendingNodesChanged;
@end

@implementation XFModel

+ (instancetype)modelWithElement:(NSXMLElement *)modelElement
                           error:(NSError **)error
{
    XFModel *model = [[self alloc] init];
    model.element = modelElement;
    NSXMLNode *idAttr = [modelElement attributeForName:@"id"];
    model.identifier = idAttr ? [idAttr stringValue] : nil;
    model.mutableBinds = [NSMutableArray array];
    model.mutableRepeats = [NSMutableArray array];
    model.nodesChanged = [NSMutableArray array];
    model.pendingNodesChanged = [NSMutableArray array];

    NSArray<NSXMLElement *> *instanceElements =
        [XFXML childElementsWithLocalName:@"instance"
                            namespaceURI:XFXFormsNamespaceURI
                               ofElement:modelElement];
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
        instance.model = model;
        [instances addObject:instance];
    }
    if (instances.count == 0) {
        // jsgen/model.xsl: a model without xf:instance gets a synthesised
        // default instance <data/> holding one empty element per plain
        // NCName `ref` in the document (G-28; duplicates collapsed here)
        NSError *inner = nil;
        XFInstance *synthesised = [XFInstance instanceWithElement:[self synthesisedInstanceElementFor:modelElement]
                                                            error:&inner];
        if (synthesised == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
        synthesised.model = model;
        [instances addObject:synthesised];
    }
    model.instances = instances;

    // xf:itext/xf:translation[@lang]/xf:text[@id]/xf:value (G-94)
    NSMutableDictionary *translations = [NSMutableDictionary dictionary];
    NSString *defaultLanguage = nil;
    for (NSXMLElement *itext in [XFXML childElementsWithLocalName:@"itext" namespaceURI:XFXFormsNamespaceURI ofElement:modelElement]) {
        for (NSXMLElement *tr in [XFXML childElementsWithLocalName:@"translation" namespaceURI:XFXFormsNamespaceURI ofElement:itext]) {
            NSString *lang = [[tr attributeForName:@"lang"] stringValue] ?: @"";
            if (defaultLanguage == nil) {
                defaultLanguage = lang;
            }
            NSMutableDictionary *texts = translations[lang] ?: [NSMutableDictionary dictionary];
            for (NSXMLElement *text in [XFXML childElementsWithLocalName:@"text" namespaceURI:XFXFormsNamespaceURI ofElement:tr]) {
                NSString *tid = [[text attributeForName:@"id"] stringValue];
                if (tid.length == 0) {
                    continue;
                }
                NSXMLElement *value = [XFXML childElementsWithLocalName:@"value" namespaceURI:XFXFormsNamespaceURI ofElement:text].firstObject;
                texts[tid] = [XFXML stringValueOfNode:value ?: text] ?: @"";
            }
            translations[lang] = texts;
        }
    }
    model.translations = translations;
    model.defaultLanguage = defaultLanguage;

    NSArray<NSXMLElement *> *submissionElements =
        [XFXML childElementsWithLocalName:@"submission"
                            namespaceURI:XFXFormsNamespaceURI
                               ofElement:modelElement];
    NSMutableArray<XFSubmission *> *submissions = [NSMutableArray array];
    for (NSXMLElement *el in submissionElements) {
        NSError *inner = nil;
        XFSubmission *submission = [XFSubmission submissionWithElement:el model:model error:&inner];
        if (submission == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
        [submissions addObject:submission];
        if (model.defaultSubmission == nil) {
            model.defaultSubmission = submission;
        }
    }
    model.submissions = submissions;

    NSArray<NSXMLElement *> *bindElements =
        [XFXML childElementsWithLocalName:@"bind"
                            namespaceURI:XFXFormsNamespaceURI
                               ofElement:modelElement];
    for (NSXMLElement *el in bindElements) {
        NSError *inner = nil;
        XFBind *bind = [XFBind bindWithElement:el model:model parent:nil error:&inner];
        if (bind == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
        [model addBind:bind];
    }
    return model;
}

- (void)addBind:(XFBind *)bind
{
    if (bind) {
        [self.mutableBinds addObject:bind];
    }
}

- (BOOL)adoptElement:(NSXMLElement *)element error:(NSError **)error
{
    NSString *name = [element localName];
    NSError *inner = nil;
    if ([name isEqualToString:@"bind"]) {
        XFBind *bind = [XFBind bindWithElement:element model:self parent:nil error:&inner];
        if (bind == nil) {
            if (error) { *error = inner; }
            return NO;
        }
        [self addBind:bind];
        return YES;
    }
    if ([name isEqualToString:@"submission"]) {
        XFSubmission *sub = [XFSubmission submissionWithElement:element model:self error:&inner];
        if (sub == nil) {
            if (error) { *error = inner; }
            return NO;
        }
        NSMutableArray *list = [self.submissions mutableCopy] ?: [NSMutableArray array];
        [list addObject:sub];
        self.submissions = list;
        if (self.defaultSubmission == nil) {
            self.defaultSubmission = sub;
        }
        [[XFXMLEvents sharedEvents] registerElement:element xfElement:sub];
        return YES;
    }
    if ([name isEqualToString:@"instance"]) {
        XFInstance *inst = [XFInstance instanceWithElement:element error:&inner];
        if (inst == nil) {
            if (error) { *error = inner; }
            return NO;
        }
        inst.model = self;
        [inst construct];
        NSMutableArray *list = [self.instances mutableCopy] ?: [NSMutableArray array];
        [list addObject:inst];
        self.instances = list;
        return YES;
    }
    return NO;
}

- (void)dropElement:(NSXMLElement *)element
{
    NSString *name = [element localName];
    if ([name isEqualToString:@"bind"]) {
        NSMutableArray *keep = [NSMutableArray array];
        for (XFBind *bind in self.binds) {
            if (bind.element != element) {
                [keep addObject:bind];
            }
        }
        self.mutableBinds = keep;
    } else if ([name isEqualToString:@"submission"]) {
        NSMutableArray *keep = [NSMutableArray array];
        for (XFSubmission *sub in self.submissions) {
            if (sub.element != element) {
                [keep addObject:sub];
            }
        }
        self.submissions = keep;
        if (self.defaultSubmission.element == element) {
            self.defaultSubmission = self.submissions.firstObject;
        }
    } else if ([name isEqualToString:@"instance"]) {
        NSMutableArray *keep = [NSMutableArray array];
        for (XFInstance *inst in self.instances) {
            if (inst.element != element) {
                [keep addObject:inst];
            }
        }
        if (keep.count) {
            self.instances = keep;
        }
    }
}

- (NSString *)itextForIdentifier:(NSString *)identifier language:(NSString *)language
{
    NSDictionary *texts = nil;
    if (language.length) {
        texts = self.translations[language];
        if (texts == nil) {
            NSString *primary = [language componentsSeparatedByString:@"-"].firstObject;
            for (NSString *lang in self.translations) {
                if ([[[lang componentsSeparatedByString:@"-"].firstObject lowercaseString] isEqualToString:[primary lowercaseString]]) {
                    texts = self.translations[lang];
                    break;
                }
            }
        }
    }
    if (texts == nil && self.defaultLanguage) {
        texts = self.translations[self.defaultLanguage];
    }
    return texts[identifier];
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

+ (NSXMLElement *)synthesisedInstanceElementFor:(NSXMLElement *)modelElement
{
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSCharacterSet *nameChars = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-."];
    NSCharacterSet *startChars = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_"];
    NSXMLNode *root = [modelElement rootDocument] ?: (NSXMLNode *)modelElement;
    for (NSXMLNode *attr in [root nodesForXPath:@"//@ref" error:NULL]) {
        NSXMLNode *parent = [attr parent];
        if (![[parent URI] isEqualToString:XFXFormsNamespaceURI]) {
            continue;
        }
        NSString *ref = [attr stringValue] ?: @"";
        if (ref.length == 0 || ![startChars characterIsMember:[ref characterAtIndex:0]]
            || [ref rangeOfCharacterFromSet:[nameChars invertedSet]].location != NSNotFound) {
            // lazy authoring auto-constructs only plain element NCNames:
            // any other binding expression over the synthesised instance
            // is an xforms-binding-exception (4.2.2.c2)
            if (ref.length && [parent isKindOfClass:[NSXMLElement class]]) {
                [XFXMLEvents raise:@"xforms-binding-exception" on:(NSXMLElement *)parent
                           message:[NSString stringWithFormat:
                                    @"lazy authoring cannot construct '%@'", ref]];
            }
            continue;
        }
        if (![names containsObject:ref]) {
            [names addObject:ref];
        }
    }
    NSXMLElement *data = [[NSXMLElement alloc] initWithName:@"data"];
    [data addNamespace:[NSXMLNode namespaceWithName:@"" stringValue:@""]];
    for (NSString *name in names) {
        [data addChild:[[NSXMLElement alloc] initWithName:name]];
    }
    NSXMLElement *instance = [[NSXMLElement alloc] initWithName:@"xf:instance" URI:XFXFormsNamespaceURI];
    [instance addNamespace:[NSXMLNode namespaceWithName:@"xf" stringValue:XFXFormsNamespaceURI]];
    [instance addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:@"instance-default"]];
    [instance addChild:data];
    return instance;
}

- (XFInstance *)instanceOwningNode:(NSXMLNode *)node
{
    if (node == nil) {
        return nil;
    }
    NSXMLDocument *doc = ([node kind] == NSXMLDocumentKind)
        ? (NSXMLDocument *)node
        : [node rootDocument];
    for (XFInstance *instance in self.instances) {
        if (instance.document == doc) {
            return instance;
        }
    }
    return nil;
}

- (XFInstance *)instanceContainingNode:(NSXMLNode *)node
{
    if (node == nil) {
        return nil;
    }
    return [self instanceOwningNode:node] ?: [self defaultInstance];
}

- (XFSubmission *)submissionWithIdentifier:(NSString *)identifier
{
    if (identifier.length == 0) {
        return self.defaultSubmission;
    }
    for (XFSubmission *submission in self.submissions) {
        if ([submission.identifier isEqualToString:identifier]) {
            return submission;
        }
    }
    return nil;
}

- (NSArray<XFBind *> *)binds
{
    return [self.mutableBinds copy] ?: @[];
}

- (NSArray<XFRepeat *> *)repeats
{
    return [self.mutableRepeats copy] ?: @[];
}

- (void)addRepeat:(XFRepeat *)repeat
{
    if (repeat == nil) {
        return;
    }
    if ([self.mutableRepeats indexOfObjectIdenticalTo:repeat] == NSNotFound) {
        [self.mutableRepeats addObject:repeat];
    }
}

- (XFRepeat *)repeatWithIdentifier:(NSString *)identifier
{
    if (identifier.length == 0) {
        return self.mutableRepeats.firstObject;
    }
    for (XFRepeat *repeat in self.mutableRepeats) {
        if ([repeat.identifier isEqualToString:identifier]) {
            return repeat;
        }
    }
    return nil;
}

- (XFBind *)bindWithIdentifier:(NSString *)identifier
{
    return [self bindWithIdentifier:identifier inBinds:self.binds];
}

- (XFBind *)bindWithIdentifier:(NSString *)identifier inBinds:(NSArray<XFBind *> *)binds
{
    for (XFBind *bind in binds) {
        if ([bind.identifier isEqualToString:identifier]) {
            return bind;
        }
        XFBind *found = [self bindWithIdentifier:identifier inBinds:bind.binds];
        if (found) {
            return found;
        }
    }
    return nil;
}

- (void)addChange:(NSXMLNode *)node
{
    if (node == nil) {
        return;
    }
    // A node of another model's instance (written through model="id" /
    // instance('id'), G-22) is recorded with that model — XSLTForms keys
    // the change on the instance document's model.
    if (![self instanceOwningNode:node] && [self.owner isKindOfClass:[XFProcessor class]]) {
        for (XFModel *m in [(XFProcessor *)self.owner models]) {
            if (m != self && [m instanceOwningNode:node]) {
                [m addChange:node];
                return;
            }
        }
    }
    // XsltForms_model.addChange: pick the list by the global `building`
    // state and register the model with the deferred-update queue.
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    NSMutableArray<NSXMLNode *> *list = du.building ? self.pendingNodesChanged : self.nodesChanged;
    if ([list indexOfObjectIdenticalTo:node] == NSNotFound) {
        [du addChangedModel:self];
    }
    if ([node kind] == NSXMLAttributeKind) {
        if ([list indexOfObjectIdenticalTo:node] == NSNotFound) {
            [list addObject:node];
        }
        node = [node parent];
    }
    while (node && [node kind] != NSXMLDocumentKind) {
        if ([list indexOfObjectIdenticalTo:node] == NSNotFound) {
            [list addObject:node];
        }
        node = [node parent];
    }
}

- (BOOL)building
{
    return [XFDeferredUpdates sharedUpdates].building;
}

- (void)setBuilding:(BOOL)building
{
    [XFDeferredUpdates sharedUpdates].building = building;
}

- (void)setRebuilded:(BOOL)rebuilded
{
    if (self.building) {
        self.pendingRebuild = rebuilded;
    } else {
        _rebuilded = rebuilded;
    }
}

- (void)swapChangeLists
{
    // XsltForms_globals.refresh: changes recorded during the UI refresh
    // become the current ones; otherwise the lists are cleared so the MIP
    // caches (XFMIPBinding) only re-evaluate for the next real change.
    if (self.pendingNodesChanged.count > 0 || self.pendingRebuild) {
        [self.nodesChanged removeAllObjects];
        [self.nodesChanged addObjectsFromArray:self.pendingNodesChanged];
        [self.pendingNodesChanged removeAllObjects];
        _rebuilded = self.pendingRebuild;
        self.pendingRebuild = NO;
    } else {
        [self.nodesChanged removeAllObjects];
        _rebuilded = NO;
    }
}

- (void)construct
{
    for (XFInstance *instance in self.instances) {
        [instance construct];
    }
    if (self.ready) {
        [XFXMLEvents dispatch:self name:@"xforms-rebuild"];
    } else {
        [self rebuild];
    }
}

- (void)rebuild
{
    // XsltForms_model.rebuild: the change lists are NOT swapped here; they
    // stay visible to recalculate/revalidate and are promoted after the UI
    // refresh (XFDeferredUpdates finishRefreshForModels:).
    if (self.ready) {
        [self setRebuilded:YES];
    }
    for (XFBind *bind in self.binds) {
        [bind refresh];
    }
    if (self.ready) {
        [XFXMLEvents dispatch:self name:@"xforms-recalculate"];
    } else {
        [self recalculate];
    }
}

- (void)recalculate
{
    for (XFBind *bind in self.binds) {
        [bind recalculate];
    }
    if (self.ready) {
        [XFXMLEvents dispatch:self name:@"xforms-revalidate"];
    } else {
        [self revalidate];
    }
}

- (void)revalidate
{
    for (XFInstance *instance in self.instances) {
        [instance revalidate];
    }
    if (self.ready) {
        [XFXMLEvents dispatch:self name:@"xforms-refresh"];
    }
}

- (void)refresh
{
    // UI refresh (XsltForms_globals.refresh → build). Changes made by
    // controls while refreshing are queued (`building`).
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    BOOL was = du.building;
    du.building = YES;
    [self.owner refreshControls];
    du.building = was;
}

- (void)reset
{
    for (XFInstance *instance in self.instances) {
        [instance reset];
    }
    [self setRebuilded:YES];
    if (self.ready) {
        [XFXMLEvents dispatch:self name:@"xforms-rebuild"];
    } else {
        [self rebuild];
    }
}

@end
