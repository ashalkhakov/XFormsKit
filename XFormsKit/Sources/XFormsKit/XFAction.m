#import "XFAction.h"
#import "XFEvent.h"
#import "XFDeferredUpdates.h"

@implementation XFAction

- (instancetype)initWithElement:(XFXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    _children = [NSMutableArray array];
    return self;
}

- (instancetype)initWithElement:(XFXMLElement *)element
{
    return [self initWithElement:element model:nil error:NULL];
}

- (void)addChild:(XFAbstractAction *)action
{
    if (action == nil) {
        return;
    }
    action.parentAction = self;
    [self.children addObject:action];
}

- (void)runWithContextNode:(XFXMLNode *)contextNode event:(XFEvent *)event
{
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du pushVariableScope];   // setvar / var children publish here (G-77)
    for (XFAbstractAction *child in self.children) {
        [child executeWithContextNode:contextNode event:event];
        if (event.stopped) {
            break;
        }
    }
    [du popVariableScope];
}

@end
