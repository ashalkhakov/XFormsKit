#import "XFDialog.h"
#import "XFProcessor.h"

@interface XFDialog ()
@property (nonatomic, assign, readwrite) BOOL shown;
@end

@implementation XFDialog

+ (instancetype)dialogWithElement:(NSXMLElement *)element
                            model:(id)model
                            error:(NSError **)error
{
    return [self groupWithElement:element model:model error:error];
}

- (void)show
{
    // XsltForms_browser.dialog.show: "Don't reopen the top-dialog."
    if (self.shown) {
        return;
    }
    self.shown = YES;
    XFProcessor *processor = [self processor];
    if (processor.dialogRequestHandler) {
        processor.dialogRequestHandler(self, YES);
    }
}

- (void)hide
{
    if (!self.shown) {
        return;
    }
    self.shown = NO;
    XFProcessor *processor = [self processor];
    if (processor.dialogRequestHandler) {
        processor.dialogRequestHandler(self, NO);
    }
}

@end
