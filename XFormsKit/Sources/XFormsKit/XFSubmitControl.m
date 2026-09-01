#import "XFSubmitControl.h"
#import "XFModel.h"
#import "XFProcessor.h"
#import "XFSubmission.h"
#import "XFXMLEvents.h"
#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"

@interface XFSubmitControl ()
@property (nonatomic, strong, readwrite) XFXPath *ifExpr;
@property (nonatomic, strong, readwrite) XFXPath *whileExpr;
@end

@implementation XFSubmitControl

+ (instancetype)submitWithElement:(NSXMLElement *)element
                            model:(id)model
                            error:(NSError **)error
{
    XFSubmitControl *submit = [super triggerWithElement:element model:model error:error];
    submit.submissionID = [[element attributeForName:@"submission"] stringValue];
    NSString *ifattr = [[element attributeForName:@"if"] stringValue];
    if (ifattr.length) {
        submit.ifExpr = [XFXPath xpathWithString:ifattr element:element error:error];
        if (submit.ifExpr == nil) {
            return nil;
        }
    }
    NSString *whileattr = [[element attributeForName:@"while"] stringValue];
    if (whileattr.length) {
        submit.whileExpr = [XFXPath xpathWithString:whileattr element:element error:error];
        if (submit.whileExpr == nil) {
            return nil;
        }
    }
    return submit;
}

- (BOOL)test:(XFXPath *)expr
{
    if (expr == nil) {
        return YES;
    }
    NSXMLNode *node = self.boundNode ?: self.inScopeContextNode;
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:node];
    id owner = self.owner;
    ctx.model = [owner isKindOfClass:[XFModel class]] ? owner : [owner model];
    XFXPathValue *v = [expr evaluateInContext:ctx error:NULL];
    return v ? v.booleanValue : NO;
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
    if (sub == nil) {
        // @submission is an IDREF into the DOCUMENT, not this control's
        // model — a submission defined in another model must resolve
        // (the 2.4.a two-form page)
        XFProcessor *processor = [self processor];
        for (XFModel *m in processor.models) {
            sub = [m submissionWithIdentifier:self.submissionID];
            if (sub) {
                break;
            }
        }
    }
    if (sub == nil) {
        // an IDREF that names nothing raises xforms-binding-exception
        // (XForms 1.1 4.5.1) instead of silently doing nothing
        [XFXMLEvents raise:@"xforms-binding-exception" on:self.element
                   message:[NSString stringWithFormat:@"no submission with id '%@'",
                            self.submissionID ?: @""]];
        return;
    }
    if (![self test:self.ifExpr]) {
        return;
    }
    if (self.whileExpr) {
        NSUInteger guard = 0;
        while ([self test:self.whileExpr] && guard++ < 1000) {
            [XFXMLEvents dispatch:sub name:@"xforms-submit"];
        }
    } else {
        [XFXMLEvents dispatch:sub name:@"xforms-submit"];
    }
}

@end
