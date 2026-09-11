#import "XFNodeState.h"
#import <XFormsKit/XFXMLTypes.h>
#import <objc/runtime.h>

static const void *kXFNodeStateKey = &kXFNodeStateKey;

@implementation XFNodeState

- (instancetype)init
{
    self = [super init];
    if (self) {
        _bindIdentifiers = [NSMutableArray array];
        _relevant = YES;
        _readonly = NO;
        _required = NO;
        _valid = YES;
        _constraint = YES;
    }
    return self;
}

+ (instancetype)stateOnNode:(XFXMLNode *)node
{
    XFNodeState *state = [self existingStateOnNode:node];
    if (state == nil) {
        state = [[self alloc] init];
        objc_setAssociatedObject(node, kXFNodeStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

+ (instancetype)existingStateOnNode:(XFXMLNode *)node
{
    return node ? objc_getAssociatedObject(node, kXFNodeStateKey) : nil;
}

+ (void)attachBind:(NSString *)bindIdentifier toNode:(XFXMLNode *)node
{
    if (bindIdentifier.length == 0 || node == nil) {
        return;
    }
    XFNodeState *state = [self stateOnNode:node];
    if (![state.bindIdentifiers containsObject:bindIdentifier]) {
        [state.bindIdentifiers addObject:bindIdentifier];
    }
}

@end
