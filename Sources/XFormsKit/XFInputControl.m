#import "XFInputControl.h"
#import "XFXML.h"
#import "XFErrors.h"
#import <Foundation/NSXMLNode.h>

@implementation XFInputControl

- (BOOL)commitStringValue:(NSString *)value error:(NSError **)error
{
    if (self.boundNode == nil) {
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorBinding
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"xf:input has no bound node" }];
        }
        return NO;
    }
    [XFXML setStringValue:value ?: @"" ofNode:self.boundNode];
    self.stringValue = value ?: @"";
    return YES;
}

@end
