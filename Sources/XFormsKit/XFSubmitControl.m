#import "XFSubmitControl.h"
#import "XFModel.h"
#import "XFSubmission.h"
#import "XFXMLEvents.h"

@implementation XFSubmitControl

+ (instancetype)submitWithElement:(NSXMLElement *)element
                            model:(id)model
                            error:(NSError **)error
{
    XFSubmitControl *submit = [super triggerWithElement:element model:model error:error];
    submit.submissionID = [[element attributeForName:@"submission"] stringValue];
    return submit;
}

- (void)activate
{
    [super activate];
    XFModel *model = nil;
    if ([self.owner isKindOfClass:[XFModel class]]) {
        model = (XFModel *)self.owner;
    } else if ([self.owner respondsToSelector:@selector(model)]) {
        model = [self.owner model];
    }
    XFSubmission *sub = [model submissionWithIdentifier:self.submissionID];
    if (sub) {
        [XFXMLEvents dispatch:sub name:@"xforms-submit"];
    }
}

@end
