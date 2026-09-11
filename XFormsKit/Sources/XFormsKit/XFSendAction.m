#import "XFSendAction.h"
#import "XFSubmission.h"
#import "XFModel.h"
#import "XFXMLEvents.h"
#import "XFEvent.h"

@interface XFSendAction ()
@property (nonatomic, copy, readwrite) NSString *submissionID;
@end

@implementation XFSendAction

- (instancetype)initWithElement:(XFXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    (void)error;
    self.submissionID = [[element attributeForName:@"submission"] stringValue];
    return self;
}

- (void)runWithContextNode:(XFXMLNode *)contextNode event:(XFEvent *)event
{
    (void)contextNode;
    (void)event;
    XFSubmission *submission = [self.model submissionWithIdentifier:self.submissionID];
    if (submission == nil) {
        [XFXMLEvents dispatch:self.model name:@"xforms-binding-exception"];
        return;
    }
    [XFXMLEvents dispatch:submission name:@"xforms-submit"];
}

@end
