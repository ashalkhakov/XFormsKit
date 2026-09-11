#import "XFVarControl.h"
#import "XFBinding.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFDeferredUpdates.h"
#import <XFormsKit/XFXMLTypes.h>

@interface XFVarControl ()
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, strong, readwrite) XFXPathValue *value;
@end

@implementation XFVarControl

+ (instancetype)varWithElement:(XFXMLElement *)element
                         model:(id)model
                         error:(NSError **)error
{
    NSError *inner = nil;
    XFBinding *binding = [XFBinding bindingForElement:element attribute:@"value" error:&inner];
    if (inner) {
        if (error) {
            *error = inner;
        }
        return nil;
    }
    XFVarControl *var = [[self alloc] initWithElement:element binding:binding label:nil];
    var.owner = model;
    var.name = [[element attributeForName:@"name"] stringValue] ?: @"";
    return var;
}

- (BOOL)isValueControl
{
    return NO;
}

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    self.boundNode = context.contextNode;
    self.relevant = YES;
    XFXPathValue *v = self.binding ? [self.binding evaluateInContext:context error:error] : nil;
    self.value = v ?: [XFXPathValue string:@""];
    if (self.name.length) {
        [[XFDeferredUpdates sharedUpdates] setVariable:self.value named:self.name];
    }
}

@end
