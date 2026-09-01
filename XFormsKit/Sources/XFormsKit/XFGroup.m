#import "XFGroup.h"
#import "XFProcessor.h"
#import "XFInstance.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFNodeState.h"
#import "XFXML.h"
#import "XFNamespaces.h"
#import "XFHostNode.h"
#import "XFDeferredUpdates.h"

@interface XFGroup ()
@property (nonatomic, strong) NSMutableArray<XFControl *> *mutableChildren;
@property (nonatomic, copy, readwrite) NSArray<XFHostNode *> *hostNodes;
@end

@implementation XFGroup

- (BOOL)isValueControl
{
    return NO;
}

- (BOOL)isBlockLevel
{
    return YES;
}

+ (instancetype)groupWithElement:(NSXMLElement *)element
                           model:(id)model
                           error:(NSError **)error
{
    NSError *inner = nil;
    XFBinding *binding = [XFControl bindingOnElement:element preferredAttribute:@"ref" error:&inner];
    if (inner) {
        if (error) {
            *error = inner;
        }
        return nil;
    }
    XFGroup *group = [[self alloc] initWithElement:element
                                           binding:binding
                                             label:[XFControl labelForElement:element]];
    group.owner = model;
    group.mutableChildren = [NSMutableArray array];
    // XSLTForms group.xsl copies the host markup and emits controls in
    // place: controls at any depth inside the group belong to it (G-20)
    NSMutableArray<XFControl *> *found = [NSMutableArray array];
    NSArray *nodes = [XFHostNode hostNodesForChildrenOf:element
                                                  model:model
                                               controls:found
                                               existing:nil
                                                  error:&inner];
    if (nodes == nil) {
        if (error) {
            *error = inner;
        }
        return nil;
    }
    for (XFControl *control in found) {
        [group addChild:control];
    }
    group.hostNodes = nodes;
    return group;
}

- (BOOL)rebuildHostNodesWithError:(NSError **)error
{
    NSMutableArray<XFControl *> *found = [NSMutableArray array];
    NSArray *nodes = [XFHostNode hostNodesForChildrenOf:self.element
                                                  model:self.owner
                                               controls:found
                                               existing:[XFHostNode controlMapFor:self.mutableChildren]
                                                  error:error];
    if (nodes == nil) {
        return NO;
    }
    NSMutableArray *children = [NSMutableArray array];
    for (XFControl *control in found) {
        if (control.parentControl != self) {
            control.parentControl = self;
            if (control.owner == nil) {
                control.owner = self.owner;
            }
        }
        [children addObject:control];
    }
    self.mutableChildren = children;
    self.hostNodes = nodes;
    return YES;
}

- (NSArray<XFControl *> *)children
{
    return [self.mutableChildren copy] ?: @[];
}

- (void)removeChild:(XFControl *)child
{
    if (child == nil) {
        return;
    }
    [self.mutableChildren removeObject:child];
    if (child.parentControl == self) {
        child.parentControl = nil;
    }
}

- (void)addChild:(XFControl *)child
{
    if (child == nil) {
        return;
    }
    child.parentControl = self;
    if (child.owner == nil) {
        child.owner = self.owner;
    }
    if (self.mutableChildren == nil) {
        self.mutableChildren = [NSMutableArray array];
    }
    [self.mutableChildren addObject:child];
}

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    XFExprContext *childCtx = context;
    if (self.binding) {
        NSError *inner = nil;
        NSXMLNode *node = [self.binding boundNodeInContext:context error:&inner];
        if (inner) {
            if (error) {
                *error = inner;
            }
            return;
        }
        self.boundNode = node;
        BOOL relevant = (node != nil);
        if (node) {
            XFNodeState *state = [XFNodeState existingStateOnNode:node];
            if (state) {
                relevant = state.relevant;
            }
        }
        self.relevant = relevant;
        if (node) {
            childCtx = [context cloneWithNode:node position:1 nodeList:@[ node ]];
        }
    } else {
        self.relevant = YES;
        self.boundNode = context.contextNode;
        // a group's model= (with no binding of its own) reroutes its
        // children to that model's default instance root
        // (XsltForms_binding.bind_evaluate; 7.2.c)
        NSString *mid = [[self.element attributeForName:@"model"] stringValue];
        if (mid.length && ![mid isEqualToString:context.model.identifier]) {
            XFModel *target = nil;
            XFProcessor *processor = [self processor];
            for (XFModel *m in processor.models) {
                if ([m.identifier isEqualToString:mid]) {
                    target = m;
                    break;
                }
            }
            NSXMLElement *root = [[target defaultInstance] documentElement];
            if (root) {
                childCtx = [context cloneWithNode:root position:1 nodeList:@[ root ]];
                childCtx.model = target;
                self.boundNode = root;
            }
        }
    }
    // XsltForms_group.refresh only toggles xforms-disabled; the children
    // keep being built/refreshed (their own relevance comes from the
    // node inheritance), so MIP state and events stay current while the
    // group is hidden (G-29)
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du pushVariableScope];   // xf:var children publish here (G-77)
    for (XFControl *child in self.mutableChildren) {
        [child refreshInContext:childCtx error:error];
    }
    [du popVariableScope];
}

@end

@interface XFComponentControl ()
@property (nonatomic, copy, readwrite) NSString *resource;
@end

@implementation XFComponentControl

+ (instancetype)componentWithElement:(NSXMLElement *)element model:(id)model error:(NSError **)error
{
    XFComponentControl *c = [self groupWithElement:element model:model error:error];
    c.resource = [[element attributeForName:@"resource"] stringValue];
    return c;
}

@end
