#import "XFModelAction.h"
#import "XFXMLEvents.h"
#import "XFModel.h"
#import "XFEvent.h"

@interface XFModelAction ()
@property (nonatomic, copy, readwrite) NSString *eventName;
@end

@implementation XFModelAction

- (instancetype)initWithElement:(NSXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    NSString *local = [element localName];
    self.eventName = [NSString stringWithFormat:@"xforms-%@", local];
    return self;
}

- (void)runWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    (void)contextNode;
    (void)event;
    if (self.model) {
        [XFXMLEvents dispatch:self.model name:self.eventName];
    }
}

@end
