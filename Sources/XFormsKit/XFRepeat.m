#import "XFRepeat.h"
#import "XFBinding.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFNodeState.h"
#import "XFXML.h"
#import "XFXMLEvents.h"
#import "XFNamespaces.h"
#import "XFDeferredUpdates.h"
#import "XFModel.h"

@interface XFRepeatItem ()
@property (nonatomic, strong) NSMutableArray<XFControl *> *mutableControls;
@end

@implementation XFRepeatItem

- (instancetype)init
{
    self = [super init];
    if (self) {
        _mutableControls = [NSMutableArray array];
        _position = 1;
    }
    return self;
}

- (NSArray<XFControl *> *)controls
{
    return [self.mutableControls copy];
}

- (void)addControl:(XFControl *)control
{
    if (control) {
        [self.mutableControls addObject:control];
    }
}

@end

@interface XFRepeat ()
@property (nonatomic, copy, readwrite) NSArray<NSXMLNode *> *nodes;
@property (nonatomic, assign, readwrite) NSUInteger index;
@property (nonatomic, copy, readwrite) NSArray<XFRepeatItem *> *items;
@property (nonatomic, copy, readwrite) NSArray<NSXMLElement *> *templateElements;
@property (nonatomic, weak) XFModel *model;
@end

@implementation XFRepeat

+ (instancetype)repeatWithElement:(NSXMLElement *)element
                            model:(id)model
                            error:(NSError **)error
{
    NSError *inner = nil;
    NSString *preferred = [element attributeForName:@"nodeset"] ? @"nodeset" : @"ref";
    XFBinding *binding = [XFControl bindingOnElement:element preferredAttribute:preferred error:&inner];
    if (inner) {
        if (error) {
            *error = inner;
        }
        return nil;
    }
    XFRepeat *repeat = [[self alloc] initWithElement:element
                                             binding:binding
                                               label:[XFControl labelForElement:element]];
    repeat.owner = model;
    if ([model isKindOfClass:[XFModel class]]) {
        repeat.model = (XFModel *)model;
    }
    NSString *start = [[element attributeForName:@"startindex"] stringValue];
    NSUInteger startIndex = start.length ? (NSUInteger)MAX(1, [start integerValue]) : 1;
    repeat.startIndex = startIndex;
    repeat.index = startIndex;

    NSMutableArray<NSXMLElement *> *templates = [NSMutableArray array];
    for (NSXMLNode *child in [element children]) {
        if ([child kind] != NSXMLElementKind) {
            continue;
        }
        NSXMLElement *el = (NSXMLElement *)child;
        if ([XFControl shouldInstantiateElement:el]) {
            [templates addObject:el];
        }
    }
    repeat.templateElements = templates;
    repeat.nodes = @[];
    repeat.items = @[];
    return repeat;
}

- (XFRepeatItem *)currentItem
{
    if (self.index == 0 || self.index > self.items.count) {
        return nil;
    }
    return self.items[self.index - 1];
}

- (NSXMLNode *)currentNode
{
    return [self currentItem].node ?: self.boundNode;
}

- (NSArray<NSXMLNode *> *)relevantNodesFrom:(NSArray<NSXMLNode *> *)nodes
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSXMLNode *node in nodes) {
        XFNodeState *state = [XFNodeState existingStateOnNode:node];
        if (state && !state.relevant) {
            continue;
        }
        [out addObject:node];
    }
    return out;
}

- (XFRepeatItem *)makeItemForNode:(NSXMLNode *)node
                         position:(NSUInteger)position
                            error:(NSError **)error
{
    XFRepeatItem *item = [[XFRepeatItem alloc] init];
    item.node = node;
    item.position = position;
    for (NSXMLElement *tmpl in self.templateElements) {
        NSError *inner = nil;
        XFControl *control = [XFControl controlWithElement:tmpl model:self.model ?: self.owner error:&inner];
        if (control == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
        control.parentControl = self;
        if ([control isKindOfClass:[XFRepeat class]] && self.model) {
            [self.model addRepeat:(XFRepeat *)control];
        }
        [item addControl:control];
    }
    return item;
}

- (void)rebuildItemsWithContext:(XFExprContext *)context error:(NSError **)error
{
    NSArray<NSXMLNode *> *raw = @[];
    if (self.binding) {
        XFXPathValue *value = [self.binding evaluateInContext:context error:error];
        raw = value.nodes ?: @[];
    }
    NSArray<NSXMLNode *> *nodes = [self relevantNodesFrom:raw];
    self.nodes = nodes;
    self.boundNode = nodes.firstObject;

    NSMutableArray<XFRepeatItem *> *items = [NSMutableArray array];
    NSUInteger i = 1;
    for (NSXMLNode *node in nodes) {
        XFRepeatItem *item = [self makeItemForNode:node position:i error:error];
        if (item == nil && error && *error) {
            return;
        }
        if (self.identifier.length) {
            [XFNodeState stateOnNode:node].repeatIdentifier = self.identifier;
        }
        [items addObject:item];
        i++;
    }
    self.items = items;

    if (nodes.count == 0) {
        _index = 0;
        return;
    }
    if (_index < 1 || _index > nodes.count) {
        NSUInteger idx = self.startIndex;
        if (idx < 1) {
            idx = 1;
        }
        if (idx > nodes.count) {
            idx = nodes.count;
        }
        _index = idx;
    }
}

- (void)setIndex:(NSUInteger)index
{
    if (self.nodes.count == 0) {
        _index = 0;
        return;
    }
    NSUInteger clamped = index;
    BOOL first = NO;
    BOOL last = NO;
    if (index < 1) {
        clamped = 1;
        first = YES;
    } else if (index > self.nodes.count) {
        clamped = self.nodes.count;
        last = YES;
    }
    if (clamped == _index && !first && !last) {
        return;
    }
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"setIndex"];
    _index = clamped;
    self.boundNode = self.nodes[clamped - 1];
    if (self.model) {
        [du addChangedModel:self.model];
    }
    if (first) {
        [XFXMLEvents dispatch:self name:@"xforms-scroll-first"];
    } else if (last) {
        [XFXMLEvents dispatch:self name:@"xforms-scroll-last"];
    }
    [du closeAction:@"setIndex"];
}

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    [self rebuildItemsWithContext:context error:error];
    NSUInteger i = 1;
    for (XFRepeatItem *item in self.items) {
        item.selected = (i == self.index);
        XFExprContext *itemCtx =
            [context cloneWithNode:item.node position:item.position nodeList:self.nodes];
        for (XFControl *control in item.controls) {
            [control refreshWithContext:itemCtx error:error];
        }
        i++;
    }
    self.relevant = self.nodes.count > 0;
}

@end
