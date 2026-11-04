/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDFormEditor.h"
#import "XFDEditors.h"
#import "XFDInspectorSpecs.h"

static NSString *const XFDFormEditorErrorDomain = @"XFormsDesigner";

static NSError *XFDFormError(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:XFDFormEditorErrorDomain code:code
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

@interface XFDFormEditor ()
@property (nonatomic, strong, readwrite) XFProcessor *processor;
@property (nonatomic, strong, readwrite) XFHostEdit *hostEdit;
@end

@implementation XFDFormEditor {
    NSHashTable *_observers;
}

- (instancetype)initWithXMLString:(NSString *)xml
                          baseURL:(NSURL *)baseURL
                      undoManager:(NSUndoManager *)undoManager
                            error:(NSError **)error
{
    if ((self = [super init])) {
        _observers = [NSHashTable weakObjectsHashTable];
        _undoManager = undoManager;
        _baseURL = [baseURL copy];
        if (![self adoptXMLString:xml error:error]) {
            return nil;
        }
    }
    return self;
}

/// A processor for `xml`, and the commands bound to it and the undo
/// manager; the old ones kept when it is no form.
- (BOOL)adoptXMLString:(NSString *)xml error:(NSError **)error
{
    // relative instance/@src, includes and schemas resolve DURING
    // construction: the base URL rides in, never set after
    XFProcessor *processor = [XFProcessor processorWithXMLString:xml baseURL:self.baseURL error:error];
    if (processor == nil) {
        return NO;
    }
    self.processor = processor;
    XFHostEdit *edit = [XFHostEdit editWithProcessor:processor undoManager:self.undoManager];
    __weak XFDFormEditor *weakSelf = self;
    edit.changedHandler = ^(XFXMLElement *element) {
        [weakSelf hostChanged:element];
    };
    self.hostEdit = edit;
    return YES;
}

- (NSString *)hostXMLString
{
    NSString *xml = [self.processor.hostDocument XMLString];
    return [xml hasSuffix:@"\n"] ? xml : [xml stringByAppendingString:@"\n"];
}

- (BOOL)replaceWithXMLString:(NSString *)xml error:(NSError **)error
{
    NSArray *kept = [self pathOfElement:self.selection];
    if (![self adoptXMLString:xml error:error]) {
        return NO;
    }
    [self.undoManager removeAllActions];
    _selection = [self elementAtPath:kept];
    [self processorReplaced];
    return YES;
}

- (BOOL)resetPreview:(NSError **)error
{
    return [self replaceWithXMLString:[self hostXMLString] error:error];
}

- (BOOL)applySourceXMLString:(NSString *)xml error:(NSError **)error
{
    if (![self replaceWithXMLString:xml error:error]) {
        return NO;
    }
    if ([self.delegate respondsToSelector:@selector(formEditorDidApplySource:)]) {
        [self.delegate formEditorDidApplySource:self];
    }
    return YES;
}

- (void)showAttributes
{
    if ([self.delegate respondsToSelector:@selector(formEditorShowAttributes:)]) {
        [self.delegate formEditorShowAttributes:self];
    }
}

#pragma mark Observers

- (void)addObserver:(id<XFDFormEditorObserver>)observer
{
    [_observers addObject:observer];
}

- (void)removeObserver:(id<XFDFormEditorObserver>)observer
{
    [_observers removeObject:observer];
}

- (void)hostChanged:(XFXMLElement *)element
{
    for (id<XFDFormEditorObserver> observer in [_observers allObjects]) {
        if ([observer respondsToSelector:@selector(formEditor:hostDidChange:)]) {
            [observer formEditor:self hostDidChange:element];
        }
    }
}

- (void)processorReplaced
{
    for (id<XFDFormEditorObserver> observer in [_observers allObjects]) {
        if ([observer respondsToSelector:@selector(formEditorProcessorWasReplaced:)]) {
            [observer formEditorProcessorWasReplaced:self];
        }
    }
}

#pragma mark The selection

- (void)setSelection:(XFXMLElement *)selection
{
    _selection = selection;
    [self selectionMayHaveChanged];
}

- (void)selectionMayHaveChanged
{
    for (id<XFDFormEditorObserver> observer in [_observers allObjects]) {
        if ([observer respondsToSelector:@selector(formEditorSelectionDidChange:)]) {
            [observer formEditorSelectionDidChange:self];
        }
    }
}

- (NSArray<NSNumber *> *)pathOfElement:(XFXMLElement *)element
{
    if (element == nil || [element rootDocument] != self.processor.hostDocument) {
        return nil;
    }
    NSMutableArray *path = [NSMutableArray array];
    XFXMLElement *walk = element;
    while (walk != nil && walk != [self rootElement]) {
        XFXMLNode *up = [walk parent];
        if (up == nil || [up kind] != XFXMLElementKind) {
            return nil;
        }
        NSUInteger index = [[self elementChildrenOf:(XFXMLElement *)up] indexOfObjectIdenticalTo:walk];
        if (index == NSNotFound) {
            return nil;
        }
        [path insertObject:@(index) atIndex:0];
        walk = (XFXMLElement *)up;
    }
    return walk == nil ? nil : path;
}

- (XFXMLElement *)elementAtPath:(NSArray<NSNumber *> *)path
{
    if (path == nil) {
        return nil;
    }
    XFXMLElement *walk = [self rootElement];
    for (NSNumber *index in path) {
        NSArray *children = [self elementChildrenOf:walk];
        if ([index unsignedIntegerValue] >= children.count) {
            return nil;
        }
        walk = children[[index unsignedIntegerValue]];
    }
    return walk;
}

#pragma mark The document's structure

- (XFXMLElement *)rootElement
{
    return [self.processor.hostDocument rootElement];
}

- (XFXMLElement *)bodyElement
{
    for (XFXMLElement *top in [self elementChildrenOf:[self rootElement]]) {
        if ([[top localName] isEqualToString:@"body"]) {
            return top;
        }
    }
    return nil;
}

- (NSArray<XFXMLElement *> *)elementChildrenOf:(XFXMLElement *)element
{
    NSMutableArray *out = [NSMutableArray array];
    for (XFXMLNode *child in [element children]) {
        if ([child kind] == XFXMLElementKind) {
            [out addObject:child];
        }
    }
    return out;
}

- (XFXMLElement *)instanceElementOf:(XFXMLElement *)element
{
    for (XFXMLNode *walk = element; walk != nil; walk = [walk parent]) {
        if ([walk kind] == XFXMLElementKind
            && [XFXML element:(XFXMLElement *)walk hasLocalName:@"instance"
                 namespaceURI:XFXFormsNamespaceURI]) {
            return (XFXMLElement *)walk;
        }
    }
    return nil;
}

- (XFXMLElement *)selectedInstanceDataNode
{
    XFXMLElement *selected = self.selection;
    if (selected == nil
        || [XFXML element:selected hasLocalName:[selected localName]
             namespaceURI:XFXFormsNamespaceURI]) {
        return nil;
    }
    XFXMLElement *instance = [self instanceElementOf:selected];
    return (instance != nil && instance != selected) ? selected : nil;
}

- (NSString *)refForDataNode:(XFXMLElement *)node
{
    // the outline shows the HOST document's inline instance content;
    // XFInstance works on a COPY: mapped through the owning xf:instance
    XFXMLElement *instanceHost = [self instanceElementOf:node];
    XFXMLElement *dataRoot = [self elementChildrenOf:instanceHost].firstObject;
    if (dataRoot == nil) {
        return nil;
    }
    NSString *tail = [XFHostEdit pathFromNode:dataRoot toNode:node];
    if (tail == nil) {
        return nil;
    }
    XFInstance *owner = nil;
    for (XFModel *model in self.processor.models) {
        for (XFInstance *instance in model.instances) {
            if (instance.element == instanceHost) {
                owner = instance;
            }
        }
    }
    if (owner == nil) {
        return nil;
    }
    if (owner == [self.processor defaultInstance]) {
        return tail;   // "." for the root itself
    }
    if (owner.identifier.length == 0) {
        return nil;    // unaddressable: not default, no id
    }
    return [tail isEqualToString:@"."]
        ? [NSString stringWithFormat:@"instance('%@')", owner.identifier]
        : [NSString stringWithFormat:@"instance('%@')/%@", owner.identifier, tail];
}

#pragma mark Inserting and deleting

/// Where an insert starts from: the selection, else the body.
- (XFXMLElement *)insertStartParent
{
    return self.selection ?: [self bodyElement];
}

static XFXMLElement *XFDParentElement(XFXMLElement *element)
{
    XFXMLNode *up = [element parent];
    return (up != nil && [up kind] == XFXMLElementKind) ? (XFXMLElement *)up : nil;
}

- (XFXMLElement *)insertParentForSelection:(NSInteger *)indexOut
{
    // the selection itself when it can contain children, else the nearest
    // ancestor that can, AFTER the selection there ("+ with an input
    // selected" adds a sibling, as Xcode's outline does)
    XFXMLElement *parent = [self insertStartParent];
    XFXMLElement *child = nil;
    while (parent != nil && [XFHostEdit insertableNamesUnderParent:parent].count == 0) {
        child = parent;
        parent = XFDParentElement(child);
    }
    if (indexOut) {
        *indexOut = (parent != nil && child != nil) ? (NSInteger)[child index] + 1 : -1;
    }
    return parent;
}

/// The parent that takes `name` itself: depths accept different sets (with
/// an input selected, a setvalue goes INTO it, another input beside it).
- (XFXMLElement *)insertParentForName:(NSString *)name index:(NSInteger *)indexOut
{
    XFXMLElement *parent = [self insertStartParent];
    XFXMLElement *child = nil;
    while (parent != nil && ![XFHostEdit canInsertElementNamed:name underParent:parent]) {
        child = parent;
        parent = XFDParentElement(child);
    }
    if (indexOut) {
        *indexOut = (parent != nil && child != nil) ? (NSInteger)[child index] + 1 : -1;
    }
    return parent;
}

- (NSSet<NSString *> *)insertableNamesForSelection
{
    NSMutableSet *names = [NSMutableSet set];
    for (XFXMLElement *parent = [self insertStartParent]; parent != nil;
         parent = XFDParentElement(parent)) {
        [names addObjectsFromArray:[XFHostEdit insertableNamesUnderParent:parent]];
    }
    return names;
}

- (XFXMLElement *)insertElementNamed:(NSString *)name error:(NSError **)error
{
    NSInteger index = -1;
    XFXMLElement *parent = [self insertParentForName:name index:&index];
    if (parent == nil) {
        if (error) {
            *error = XFDFormError(2, [NSString stringWithFormat:@"A %@ cannot go here.", name]);
        }
        return nil;
    }
    NSError *failure = nil;
    XFXMLElement *element = [self.hostEdit insertElementNamed:name underParent:parent
                                                      atIndex:index error:&failure];
    if (element == nil) {
        if (error) {
            *error = failure ?: XFDFormError(2, @"Cannot insert here.");
        }
        return nil;
    }
    self.selection = element;
    return element;
}

- (BOOL)canDeleteSelection
{
    XFXMLElement *element = self.selection;
    if (element == nil || XFDParentElement(element) == nil) {
        return NO;
    }
    NSString *local = [element localName];
    return !([local isEqualToString:@"html"] || [local isEqualToString:@"head"]
             || [local isEqualToString:@"body"] || [local isEqualToString:@"model"]);
}

- (BOOL)deleteSelection
{
    if (![self canDeleteSelection]) {
        return NO;
    }
    XFXMLElement *parent = XFDParentElement(self.selection);
    [self.hostEdit deleteElement:self.selection];
    self.selection = parent;
    return YES;
}

- (BOOL)moveElement:(XFXMLElement *)element underParent:(XFXMLElement *)parent atIndex:(NSInteger)index
{
    [self.undoManager beginUndoGrouping];
    BOOL moved = [self.hostEdit moveElement:element underParent:parent atIndex:index];
    [self.undoManager endUndoGrouping];
    if (moved) {
        self.selection = element;
    }
    return moved;
}

- (BOOL)createBindFromSelectedRef:(NSError **)error
{
    XFXMLElement *control = self.selection;
    if (control == nil || ![XFDControlKinds() containsObject:[control localName]]) {
        if (error) {
            *error = XFDFormError(3, @"Select a control to make a bind of its ref.");
        }
        return NO;
    }
    XFDControlEditor *e = [XFDControlEditor editorForElement:control formEditor:self];
    NSString *ref = e.ref;
    if (ref.length == 0 || e.bind.length) {
        if (error) {
            *error = XFDFormError(3, @"The control has no ref of its own to make a bind of.");
        }
        return NO;
    }
    XFXMLElement *model = (XFXMLElement *)self.processor.model.element;
    XFXMLElement *bind = [self.hostEdit insertElementNamed:@"bind" underParent:model
                                                   atIndex:-1 error:error];
    if (bind == nil) {
        return NO;
    }
    [self.hostEdit setAttribute:@"nodeset" value:ref onElement:bind];
    NSString *identifier = [[bind attributeForName:@"id"] stringValue];
    [self.hostEdit setAttribute:@"bind" value:identifier onElement:control];
    [self.hostEdit setAttribute:@"ref" value:@"" onElement:control];
    [self selectionMayHaveChanged];
    return YES;
}

- (XFXMLElement *)createControlOfKind:(NSString *)kind boundToSelectedDataNode:(NSError **)error
{
    XFXMLElement *dataNode = [self selectedInstanceDataNode];
    NSString *ref = dataNode ? [self refForDataNode:dataNode] : nil;
    XFXMLElement *body = [self bodyElement];
    if (ref == nil || body == nil) {
        if (error) {
            *error = XFDFormError(4, @"Select instance data a control can be bound to.");
        }
        return nil;
    }
    XFXMLElement *control = [self.hostEdit insertElementNamed:kind underParent:body
                                                      atIndex:-1 error:error];
    if (control == nil) {
        return nil;
    }
    NSString *name = [dataNode localName];
    [self.hostEdit setAttribute:@"ref" value:ref onElement:control];
    [self.hostEdit setSupportChild:@"label"
                              text:[[[name substringToIndex:1] uppercaseString]
                                       stringByAppendingString:[name substringFromIndex:1]]
                         onElement:control];
    self.selection = control;
    return control;
}

#pragma mark What the inspectors' fields evaluate against

/// The selected bind's compiled XFBind (binds nest).
- (XFBind *)bindOfElement:(XFXMLElement *)element in:(NSArray *)binds
{
    for (XFBind *bind in binds) {
        if (bind.element == element) {
            return bind;
        }
        XFBind *nested = [self bindOfElement:element in:bind.binds];
        if (nested != nil) {
            return nested;
        }
    }
    return nil;
}

- (XFXMLNode *)defaultContextNode
{
    return [[self.processor defaultInstance] documentElement];
}

- (XFXMLNode *)contextNodeForSelectionNodeset:(BOOL)nodeset
{
    XFXMLElement *selected = self.selection;
    NSString *local = [selected localName];
    BOOL xforms = selected != nil
        && [XFXML element:selected hasLocalName:local namespaceURI:XFXFormsNamespaceURI];
    if (xforms && [local isEqualToString:@"bind"]) {
        // model item properties (calculate, constraint…) evaluate PER BOUND
        // NODE (`../in - ../out` means nothing from the instance root); the
        // nodeset in the OUTER context: the parent bind's node for a nested
        // bind, the root otherwise
        for (XFModel *model in self.processor.models) {
            XFBind *bind = [self bindOfElement:selected in:model.binds];
            if (bind == nil) {
                continue;
            }
            if (nodeset) {
                if (bind.parent.nodes.count) {
                    return bind.parent.nodes.firstObject;
                }
                break;
            }
            if (bind.nodes.count) {
                return bind.nodes.firstObject;
            }
        }
        return [self defaultContextNode];
    }
    if (xforms && [XFDControlKinds() containsObject:local]) {
        XFControl *up = [self.processor controlForElement:selected].parentControl;
        while (up != nil && up.boundNode == nil) {
            up = up.parentControl;
        }
        if (up.boundNode != nil) {
            return up.boundNode;
        }
    }
    return [self defaultContextNode];
}

- (XFXMLNode *)contextNodeForSelectionContent
{
    XFXMLElement *selected = self.selection;
    if (selected != nil && [XFDControlKinds() containsObject:[selected localName]]
        && [XFXML element:selected hasLocalName:[selected localName] namespaceURI:XFXFormsNamespaceURI]) {
        XFControl *control = [self.processor controlForElement:selected];
        while (control != nil && control.boundNode == nil) {
            control = control.parentControl;
        }
        if (control.boundNode != nil) {
            return control.boundNode;
        }
    }
    return [self defaultContextNode];
}

@end
