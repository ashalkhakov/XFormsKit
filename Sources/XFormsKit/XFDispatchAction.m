#import "XFDispatchAction.h"
#import "XFXMLEvents.h"
#import "XFModel.h"
#import "XFXML.h"
#import "XFEvent.h"

@interface XFDispatchAction ()
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite) NSString *targetID;
@end

@implementation XFDispatchAction

- (instancetype)initWithElement:(NSXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    (void)error;
    self.name = [[element attributeForName:@"name"] stringValue];
    NSString *target = [[element attributeForName:@"targetid"] stringValue];
    if (target.length == 0) {
        target = [[element attributeForName:@"target"] stringValue];
    }
    self.targetID = target;
    return self;
}

- (void)runWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    (void)contextNode;
    (void)event;
    if (self.name.length == 0) {
        return;
    }
    id target = nil;
    if (self.targetID.length) {
        NSString *tid = self.targetID;
        if ([tid hasPrefix:@"#"]) {
            tid = [tid substringFromIndex:1];
        }
        NSXMLElement *el = [XFXML elementWithID:tid inNode:self.element.rootDocument];
        if (el) {
            target = [[XFXMLEvents sharedEvents] xfElementForElement:el] ?: el;
        }
    }
    if (target == nil) {
        if ([self.name hasPrefix:@"xforms-rebuild"] ||
            [self.name isEqualToString:@"xforms-recalculate"] ||
            [self.name isEqualToString:@"xforms-revalidate"] ||
            [self.name isEqualToString:@"xforms-refresh"] ||
            [self.name isEqualToString:@"xforms-reset"]) {
            target = self.model;
        }
    }
    if (target) {
        [XFXMLEvents dispatch:target name:self.name];
    }
}

@end
