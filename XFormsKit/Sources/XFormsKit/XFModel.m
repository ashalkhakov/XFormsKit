#import "XFModel.h"
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
@property (nonatomic, copy, readwrite) NSArray<XFSubmission *> *submissions;
@property (nonatomic, strong) NSMutableArray<XFRepeat *> *mutableRepeats;
@property (nonatomic, strong, readwrite) NSMutableArray<XFBind *> *binds;
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
    model.binds = [NSMutableArray array];
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
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorDocument
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"xf:model has no xf:instance" }];
        }
        return nil;
    }
    model.instances = instances;

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
        [(NSMutableArray *)self.binds addObject:bind];
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
        self.binds = keep;
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

- (XFInstance *)instanceContainingNode:(NSXMLNode *)node
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
    return [self defaultInstance];
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
    NSMutableArray<NSXMLNode *> *list = self.building ? self.pendingNodesChanged : self.nodesChanged;
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
    [self.nodesChanged removeAllObjects];
    [self.nodesChanged addObjectsFromArray:self.pendingNodesChanged];
    [self.pendingNodesChanged removeAllObjects];
    self.rebuilded = self.pendingRebuild;
    self.pendingRebuild = NO;
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
    if (self.ready) {
        [self setRebuilded:YES];
    }
    self.building = YES;
    for (XFBind *bind in self.binds) {
        [bind refresh];
    }
    self.building = NO;
    [self swapChangeLists];
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
    [self.owner refreshControls];
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
