#import "XFSubform.h"
#import "XFModel.h"

#import <objc/runtime.h>

static const void *kXFSubformOwnerKey = &kXFSubformOwnerKey;

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

+ (void)tagImportedNode:(NSXMLNode *)node ownerNode:(NSXMLNode *)owner
{
    objc_setAssociatedObject(node, kXFSubformOwnerKey, owner,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (NSXMLNode *)ownerNodeOfImportedNode:(NSXMLNode *)node
{
    return objc_getAssociatedObject(node, kXFSubformOwnerKey);
}

@end
