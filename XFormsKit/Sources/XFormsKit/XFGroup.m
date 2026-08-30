#import "XFGroup.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFNodeState.h"
#import "XFXML.h"
#import "XFNamespaces.h"

@interface XFGroup ()
@property (nonatomic, strong) NSMutableArray<XFControl *> *mutableChildren;
@end

@implementation XFGroup

- (BOOL)isValueControl
{
    return NO;
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
    for (NSXMLNode *child in [element children]) {
        if ([child kind] != NSXMLElementKind) {
            continue;
        }
        NSXMLElement *el = (NSXMLElement *)child;
        if (![XFControl shouldInstantiateElement:el]) {
            continue;
        }
        XFControl *control = [XFControl controlWithElement:el model:model error:&inner];
        if (control == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
        [group addChild:control];
    }
    return group;
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
    }
    if (!self.relevant) {
        return;
    }
    for (XFControl *child in self.mutableChildren) {
        [child refreshInContext:childCtx error:error];
    }
}

@end
