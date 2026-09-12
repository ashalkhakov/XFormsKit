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
#import "XFBind.h"
#import "XFInstance.h"

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
@property (nonatomic, copy, readwrite) NSArray<XFXMLNode *> *nodes;
@property (nonatomic, assign, readwrite) NSUInteger index;
@property (nonatomic, copy, readwrite) NSArray<XFRepeatItem *> *items;
@property (nonatomic, copy, readwrite) NSArray<XFXMLElement *> *templateElements;
@property (nonatomic, weak) XFModel *model;
@property (nonatomic, assign) BOOL itemsNeedRebuild;
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

+ (instancetype)repeatWithElement:(XFXMLElement *)element
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

    NSMutableArray<XFXMLElement *> *templates = [NSMutableArray array];
    for (XFXMLNode *child in [element children]) {
        if ([child kind] != XFXMLElementKind) {
            continue;
        }
        XFXMLElement *el = (XFXMLElement *)child;
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
    NSMutableArray<XFXMLElement *> *templates = [NSMutableArray array];
    for (XFXMLNode *child in [self.element children]) {
        if ([child kind] != XFXMLElementKind) continue;
        XFXMLElement *el = (XFXMLElement *)child;
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

- (XFXMLNode *)currentNode
{
    return [self currentItem].node ?: self.boundNode;
}

- (NSArray<XFXMLNode *> *)relevantNodesFrom:(NSArray<XFXMLNode *> *)nodes
{
    NSMutableArray *out = [NSMutableArray array];
    for (XFXMLNode *node in nodes) {
        XFNodeState *state = [XFNodeState existingStateOnNode:node];
        if (state && !state.relevant) {
            continue;
        }
        [out addObject:node];
    }
    return out;
}

- (XFRepeatItem *)makeItemForNode:(XFXMLNode *)node
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
    XFXMLNode *outerScope = [XFHostNode currentRepeatItemNode];
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
    NSArray<XFXMLNode *> *raw = @[];
    if (self.binding) {
        XFXPathValue *value = [self.binding evaluateInContext:context error:error];
        raw = value.nodes ?: @[];
    }
    NSArray<XFXMLNode *> *nodes = [self relevantNodesFrom:raw];
    // XsltForms_repeat.build_: the index follows the current node when it
    // is still in the nodeset (G-27); otherwise the number is kept, clamped
    XFXMLNode *current = [self currentItem].node;
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
    for (XFXMLNode *node in nodes) {
        // XsltForms_repeat.build_ keeps the DOM of unchanged rows and
        // only inserts/removes the delta — REUSING the item keeps its
        // per-item UI state (a toggled switch inside this row, a nested
        // repeat's index) across refreshes (9.3.1.f, 9.3.4.a)
        XFRepeatItem *item = nil;
        if (!self.itemsNeedRebuild) {
            for (XFRepeatItem *old in self.items) {
                if (old.node == node) {
                    item = old;
                    item.position = i;
                    break;
                }
            }
        }
        if (item == nil) {
            item = [self makeItemForNode:node position:i error:error];
            if (item == nil && error && *error) {
                return;
            }
        }
        if (self.identifier.length) {
            [XFNodeState stateOnNode:node].repeatIdentifier = self.identifier;
        }
        [items addObject:item];
        i++;
    }
    self.items = items;
    self.itemsNeedRebuild = NO;

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

- (void)invalidateItems
{
    self.itemsNeedRebuild = YES;
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
        XFXMLNode *walk = [other.element parent];
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

#pragma mark - Add / remove from a host affordance

/// The evaluation context a repeat rebuild wants: its model's default
/// instance root, which is what both actions use for the same call.
- (XFExprContext *)rebuildContext
{
    XFExprContext *ctx =
        [[XFExprContext alloc] initWithNode:[[self.model defaultInstance] documentElement]];
    ctx.model = self.model;
    return ctx;
}

/// Re-read the nodeset and put the index back where it belongs, the way
/// xf:insert and xf:delete each finish.
- (void)rebuildAfterEditKeepingIndex:(NSUInteger)wanted
{
    [self rebuildItemsWithContext:[self rebuildContext] error:NULL];
    if (self.nodes.count == 0) {
        [self setIndex:0];
        return;
    }
    [self setIndex:MIN(MAX(wanted, (NSUInteger)1), self.nodes.count)];
    // the index now names a DIFFERENT node even where its number did not
    // change, so repeats nested in it start at their startindex again
    [self resetNestedRepeatIndexes];
}

- (BOOL)insertItemAfterPosition:(NSUInteger)position
{
    NSArray<XFXMLNode *> *nodes = self.nodes;
    XFModel *model = self.model;
    if (model == nil || position < 1 || position > nodes.count) {
        return NO;
    }
    XFXMLNode *origin = nodes[position - 1];
    XFXMLNode *parent = [origin parent];
    if (![parent isKindOfClass:[XFXMLElement class]]) {
        return NO;   // nothing to insert into (an instance root)
    }
    XFXMLElement *owner = (XFXMLElement *)parent;
    XFXMLNode *clone = [origin copy];
    if (clone == nil) {
        return NO;
    }
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"insert"];
    XFXMLNode *before = [origin nextSibling];
    if (before && [before parent] == owner) {
        [owner insertChild:clone atIndex:[before index]];
    } else {
        [owner addChild:clone];
    }
    [model addChange:owner];
    [model setRebuilded:YES];
    [du addChangedModel:model];
    XFInstance *instance = [model instanceContainingNode:owner];
    [XFXMLEvents dispatch:instance ?: model name:@"xforms-insert" context:@{
        @"inserted-nodes": @[ clone ],
        @"origin-nodes": @[ origin ],
        @"insert-location-node": @(position),
        @"position": @"after",
    }];
    [self rebuildAfterEditKeepingIndex:position + 1];
    [du closeAction:@"insert"];
    return YES;
}

- (BOOL)deleteItemAtPosition:(NSUInteger)position
{
    NSArray<XFXMLNode *> *nodes = self.nodes;
    XFModel *model = self.model;
    if (model == nil || position < 1 || position > nodes.count) {
        return NO;
    }
    XFXMLNode *node = nodes[position - 1];
    XFXMLNode *parent = [node parent];
    if (![parent isKindOfClass:[XFXMLElement class]]) {
        return NO;   // the instance root is not deletable (§10.4)
    }
    XFInstance *instance = [model instanceContainingNode:node];
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"delete"];
    [XFBind disposeNode:node model:model];
    [(XFXMLElement *)parent removeChildAtIndex:[node index]];
    [model addChange:parent];
    [model setRebuilded:YES];
    [du addChangedModel:model];
    [XFXMLEvents dispatch:instance ?: model name:@"xforms-delete" context:@{
        @"deleted-nodes": @[ node ],
        @"delete-location": @(position),
    }];
    [self rebuildAfterEditKeepingIndex:self.index];
    [du closeAction:@"delete"];
    return YES;
}

@end
