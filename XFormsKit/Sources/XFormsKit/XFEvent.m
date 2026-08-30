#import "XFEvent.h"

@implementation XFEvent

- (instancetype)init
{
    self = [super init];
    if (self) {
        _context = [NSMutableDictionary dictionary];
        _eventPhase = XFEventPhaseTarget;
        _phase = @"default";
        _returnValue = YES;
        _bubbles = YES;
        _cancelable = YES;
    }
    return self;
}

- (void)stopPropagation
{
    _stopped = YES;
    _cancelBubble = YES;
}

- (void)preventDefault
{
    _defaultPrevented = YES;
    _returnValue = NO;
}

@end
