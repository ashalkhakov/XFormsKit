#import "XFXPathPriv.h"
#import <XFormsKit/XFXMLTypes.h>

@implementation XFNodeTest
- (BOOL)matches:(XFXMLNode *)node resolver:(XFNSResolver *)resolver axis:(NSString *)axis
{
    (void)node; (void)resolver; (void)axis;
    return NO;
}
@end

@implementation XFNodeTestAny
- (BOOL)matches:(XFXMLNode *)node resolver:(XFNSResolver *)resolver axis:(NSString *)axis
{
    (void)resolver;
    if (node == nil) {
        return NO;
    }
    // Principal node type of the axis (XPath 1.0).
    if ([axis isEqualToString:XFAxisAttribute]) {
        return [node kind] == XFXMLAttributeKind;
    }
    if ([axis isEqualToString:XFAxisNamespace]) {
        return NO;
    }
    return [node kind] == XFXMLElementKind;
}
@end

@implementation XFNodeTestName

+ (instancetype)prefix:(NSString *)prefix name:(NSString *)name
{
    XFNodeTestName *t = [[self alloc] init];
    t.prefix = prefix;
    t.name = name;
    return t;
}

- (BOOL)matches:(XFXMLNode *)node resolver:(XFNSResolver *)resolver axis:(NSString *)axis
{
    if (node == nil) {
        return NO;
    }
    BOOL wildcard = [self.name isEqualToString:@"*"];
    XFXMLNodeKind expected = [axis isEqualToString:XFAxisAttribute] ? XFXMLAttributeKind : XFXMLElementKind;
    if ([axis isEqualToString:XFAxisNamespace]) {
        return NO;
    }
    if ([node kind] != expected && !wildcard) {
        // Name tests only apply to the principal node type, except * handled above.
        if ([node kind] != XFXMLElementKind && [node kind] != XFXMLAttributeKind) {
            return NO;
        }
        if ([node kind] != expected) {
            return NO;
        }
    }
    if (!wildcard && [node kind] != expected) {
        return NO;
    }
    if (wildcard) {
        if ([node kind] != expected) {
            return NO;
        }
        if (self.prefix.length > 0 && ![self.prefix isEqualToString:@"*"]) {
            // prefix:* — any local name in that namespace
            NSString *uri = [resolver lookupNamespaceURI:self.prefix];
            if (uri == nil) {
                XFXMLNode *el = [node kind] == XFXMLElementKind ? node : [node parent];
                if ([el kind] == XFXMLElementKind) {
                    uri = [[(XFXMLElement *)el resolveNamespaceForName:[self.prefix stringByAppendingString:@":x"]] stringValue];
                }
            }
            return uri.length > 0 && [[node URI] ?: @"" isEqualToString:uri];
        }
        return YES;
    }

    NSString *local = [node localName] ?: [node name];
    if (![local isEqualToString:self.name] && ![[node name] isEqualToString:self.name]) {
        return NO;
    }
    NSString *ns = [node URI];
    if ([self.prefix isEqualToString:@"*"]) {
        // *:name — local name in any namespace (G-78)
        return [local isEqualToString:self.name];
    }
    if (self.prefix.length > 0) {
        NSString *uri = [resolver lookupNamespaceURI:self.prefix];
        if (uri == nil) {
            // Not registered from the host element: fall back to the
            // declaration in scope at the candidate node itself.
            XFXMLNode *el = [node kind] == XFXMLElementKind ? node : [node parent];
            if ([el kind] == XFXMLElementKind) {
                uri = [[(XFXMLElement *)el resolveNamespaceForName:[self.prefix stringByAppendingString:@":x"]] stringValue];
            }
        }
        return uri.length > 0 && [ns ?: @"" isEqualToString:uri];
    }
    // Unprefixed name: XPath 1.0 says no namespace. Also accept a local-name
    // match so typical un-namespaced instance data works.
    return ns.length == 0 || [resolver lookupNamespaceURI:@""] == nil ||
           [ns isEqualToString:[resolver lookupNamespaceURI:@""] ?: @""] ||
           [local isEqualToString:self.name];
}

@end

@implementation XFNodeTestType

+ (instancetype)anyNode
{
    XFNodeTestType *t = [[self alloc] init];
    t.anyNode = YES;
    return t;
}

+ (instancetype)kind:(XFXMLNodeKind)kind
{
    XFNodeTestType *t = [[self alloc] init];
    t.kind = kind;
    return t;
}

+ (instancetype)processingInstruction:(NSString *)target
{
    XFNodeTestType *t = [[self alloc] init];
    t.kind = XFXMLProcessingInstructionKind;
    t.piTarget = target;
    return t;
}

- (BOOL)matches:(XFXMLNode *)node resolver:(XFNSResolver *)resolver axis:(NSString *)axis
{
    (void)resolver; (void)axis;
    if (node == nil) {
        return NO;
    }
    if (self.anyNode) {
        return YES;
    }
    if ([node kind] != self.kind) {
        return NO;
    }
    if (self.kind == XFXMLProcessingInstructionKind && self.piTarget.length) {
        return [[node name] isEqualToString:self.piTarget];
    }
    return YES;
}

@end
