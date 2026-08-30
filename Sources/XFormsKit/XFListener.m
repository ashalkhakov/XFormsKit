#import "XFListener.h"
#import "XFXMLEvents.h"
#import "XFEvent.h"
#import <Foundation/NSXMLElement.h>

@implementation XFListener

+ (NSMutableArray *)destructs
{
    static NSMutableArray *destructs = nil;
    @synchronized(self) {
        if (destructs == nil) {
            destructs = [NSMutableArray array];
        }
    }
    return destructs;
}

- (instancetype)initWithObserver:(NSXMLElement *)observer
                       evtTarget:(NSXMLElement *)evtTarget
                            name:(NSString *)name
                           phase:(NSString *)phase
                         handler:(XFEventHandlerBlock)handler
                   defaultAction:(BOOL)defaultAction
{
    return [self initWithSubform:nil
                        observer:observer
                       evtTarget:evtTarget
                            name:name
                           phase:phase
                         handler:handler
                   defaultAction:defaultAction];
}

- (instancetype)initWithSubform:(id)subform
                       observer:(NSXMLElement *)observer
                      evtTarget:(NSXMLElement *)evtTarget
                           name:(NSString *)name
                          phase:(NSString *)phase
                        handler:(XFEventHandlerBlock)handler
                  defaultAction:(BOOL)defaultAction
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    NSString *resolved = phase.length ? phase : @"default";
    if (![resolved isEqualToString:@"default"] && ![resolved isEqualToString:@"capture"]) {
        NSLog(@"XFormsKit: unknown event-phase(%@) for event(%@)%@",
              resolved, name,
              observer ? [NSString stringWithFormat:@" on element(%@)",
                          [[observer attributeForName:@"id"] stringValue] ?: @""] : @"");
        resolved = @"default";
    }
    NSAssert(observer != nil, @"XsltForms_listener requires an observer");
    _subform = subform;
    _observer = observer;
    _evtTarget = evtTarget;
    _name = [name copy];
    _phase = [resolved copy];
    _handler = [handler copy];
    _defaultAction = defaultAction;
    _propagate = YES;

    NSMutableArray *list = [[XFXMLEvents sharedEvents] listenersOn:observer];
    if ([name isEqualToString:@"xforms-subform-ready"]) {
        for (XFListener *existing in list) {
            if ([existing.name isEqualToString:name]) {
                return existing;
            }
        }
    }
    [list addObject:self];
    [self attach];
    if (subform && [subform respondsToSelector:@selector(listeners)]) {
        id listeners = [subform listeners];
        if ([listeners isKindOfClass:[NSMutableArray class]]) {
            [listeners addObject:self];
        }
    }
    return self;
}

- (void)attach
{
    if ([self.name isEqualToString:@"xforms-model-destruct"]) {
        [[XFListener destructs] addObject:self];
    }
}

- (void)detach
{
    NSXMLElement *observer = self.observer;
    if (observer) {
        NSMutableArray *list = [[XFXMLEvents sharedEvents] listenersOn:observer];
        [list removeObject:self];
    }
    [[XFListener destructs] removeObject:self];
}

- (instancetype)cloneForElement:(NSXMLElement *)element
{
    XFListener *copy = [[XFListener alloc] initWithSubform:self.subform
                                                  observer:element
                                                 evtTarget:self.evtTarget
                                                      name:self.name
                                                     phase:self.phase
                                                   handler:self.handler
                                             defaultAction:self.defaultAction];
    copy.propagate = self.propagate;
    copy.handlerElement = self.handlerElement;
    return copy;
}

- (void)invoke:(XFEvent *)event
{
    if (event.phase.length && ![event.phase isEqualToString:self.phase]) {
        return;
    }
    if (event.phase.length == 0 && [self.phase isEqualToString:@"capture"]) {
        return;
    }

    BOOL effectiveTarget = YES;
    if (self.evtTarget && event.target != self.evtTarget) {
        effectiveTarget = NO;
    }

    if (effectiveTarget && self.handler) {
        self.handler(event);
    }
    if (!self.defaultAction) {
        [event preventDefault];
    }
    if (!self.propagate) {
        [event stopPropagation];
    }
}

@end
