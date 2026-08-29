#import "XFControl.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFXML.h"

@implementation XFControl

- (instancetype)initWithElement:(NSXMLElement *)element
                        binding:(XFBinding *)binding
                          label:(NSString *)label
{
    self = [super init];
    if (self) {
        _element = element;
        _binding = binding;
        _label = [label copy];
        _stringValue = @"";
    }
    return self;
}

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    if (self.binding == nil) {
        return;
    }
    NSError *inner = nil;
    NSXMLNode *node = [self.binding boundNodeInContext:context error:&inner];
    if (inner && error) {
        *error = inner;
        return;
    }
    self.boundNode = node;
    NSString *value = [self.binding stringValueInContext:context error:&inner];
    if (inner && error) {
        *error = inner;
        return;
    }
    self.stringValue = value ?: @"";
}

@end
