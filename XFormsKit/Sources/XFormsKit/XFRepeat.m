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
#import "XFHostNode.h"

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

- (BOOL)isValueControl
{
    return NO;
}

- (BOOL)isBlockLevel
{
    return YES;
}

+ (instancetype)repeatWithElement:(NSXMLElement *)element
                            model:(id)model
                            error:(NSError **)error
{
    NSError *inner = nil;
    NSString *preferred = [element attributeForName:@"nodeset"] ? @"nodeset" : @"ref";
    XFBinding *binding = nil;
    NSString *from = [[element attributeForName:@"from"] stringValue];
    NSString *to = [[element attributeForName:@"to"] stringValue];
    if (from.length && to.length) {
        // jsgen/repeat.xsl: @from/@to/@step become fromtostep(from, to, step),
        // a nodeset of detached "repeatitem" nodes holding the numbers (G-91)
        NSString *step = [[element attributeForName:@"step"] stringValue];
        NSString *expr = [NSString stringWithFormat:@"fromtostep(%@,%@,%@)", from, to, step.length ? step : @"1"];
        binding = [XFBinding bindingWithExpression:expr element:element error:&inner];
    } else {
        binding = [XFControl bindingOnElement:element preferredAttribute:preferred error:&inner];
    }
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

- (void)reloadTemplates
{
    NSMutableArray<NSXMLElement *> *templates = [NSMutableArray array];
    for (NSXMLNode *child in [self.element children]) {
        if ([child kind] != NSXMLElementKind) continue;
        NSXMLElement *el = (NSXMLElement *)child;
        if ([XFControl shouldInstantiateElement:el]) {
            [templates addObject:el];
        }
    }
    self.templateElements = templates;
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
    // XsltForms_repeat.build_ clones the whole content (host markup
    // included) per node; controls at any depth are instantiated (G-20)
    NSMutableArray<XFControl *> *found = [NSMutableArray array];
    NSError *inner = nil;
    // the whole build (nested groups constructing their own subtrees
    // included) runs in this item's scope — per-item subform content
    // filters on it
    NSXMLNode *outerScope = [XFHostNode currentRepeatItemNode];
    [XFHostNode setCurrentRepeatItemNode:node];
    NSArray *nodes = [XFHostNode hostNodesForChildrenOf:self.element
                                                  model:self.model ?: self.owner
                                               controls:found
                                               existing:nil
                                                  error:&inner];
    [XFHostNode setCurrentRepeatItemNode:outerScope];
    if (nodes == nil) {
        if (error) {
            *error = inner;
        }
        return nil;
    }
    for (XFControl *control in found) {
        control.parentControl = self;
        if ([control isKindOfClass:[XFRepeat class]] && self.model) {
            [self.model addRepeat:(XFRepeat *)control];
        }
        [item addControl:control];
    }
    item.hostNodes = nodes;
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
    // XsltForms_repeat.build_: the index follows the current node when it
    // is still in the nodeset (G-27); otherwise the number is kept, clamped
    NSXMLNode *current = [self currentItem].node;
    self.nodes = nodes;
    self.boundNode = nodes.firstObject;
    if (current) {
        NSUInteger at = [nodes indexOfObjectIdenticalTo:current];
        if (at != NSNotFound && _index != at + 1) {
            _index = at + 1;
            if (self.model) {
                [[XFDeferredUpdates sharedUpdates] addChangedModel:self.model];
            }
        }
    }

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

- (void)resetNestedRepeatIndexes
{
    // XForms 1.1 (repeat processing) / XSLTForms: moving an outer
    // repeat's index re-initializes the indexes of repeats nested in it
    // to their startindex — the newly selected item's inner repeats
    // start fresh (10.3.h, 10.4.f).
    if (self.element == nil) {
        return;
    }
    for (XFRepeat *other in self.model.repeats) {
        if (other == self || other.element == nil) {
            continue;
        }
        BOOL nested = NO;
        NSXMLNode *walk = [other.element parent];
        while (walk) {
            if (walk == self.element) {
                nested = YES;
                break;
            }
            walk = [walk parent];
        }
        if (!nested || other.nodes.count == 0) {
            continue;
        }
        NSUInteger start = other.startIndex ?: 1;
        if (start > other.nodes.count) {
            start = other.nodes.count;
        }
        if (other.index != start) {
            [other setIndex:start];   // recurses into deeper nestings
        }
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
    [self resetNestedRepeatIndexes];
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
        XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
        [du pushVariableScope];
        for (XFControl *control in item.controls) {
            [control refreshInContext:itemCtx error:error];
        }
        [du popVariableScope];
        i++;
    }
    self.relevant = self.nodes.count > 0;
}

@end
