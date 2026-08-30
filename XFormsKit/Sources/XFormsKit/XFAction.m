#import "XFAction.h"
#import "XFEvent.h"

@implementation XFAction

- (instancetype)initWithElement:(NSXMLElement *)element
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

- (instancetype)initWithElement:(NSXMLElement *)element
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

- (void)runWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    for (XFAbstractAction *child in self.children) {
        [child executeWithContextNode:contextNode event:event];
        if (event.stopped) {
            break;
        }
    }
}

@end
