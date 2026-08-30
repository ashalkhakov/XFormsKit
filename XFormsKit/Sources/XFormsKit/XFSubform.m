#import "XFSubform.h"
#import "XFModel.h"

@implementation XFSubform

- (XFModel *)defaultModel
{
    return self.models.firstObject;
}

- (BOOL)containsElement:(NSXMLNode *)element
{
    // the target element itself belongs to the enclosing form; the content
    // below it belongs to this subform unless a nested subform's target
    // lies in between
    NSXMLNode *walk = [element parent];
    while (walk) {
        if (walk == self.targetElement) {
            return YES;
        }
        for (XFSubform *nested in self.subforms) {
            if (walk == nested.targetElement) {
                return NO;
            }
        }
        walk = [walk parent];
    }
    return NO;
}

@end
