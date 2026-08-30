#import "XFSubmission.h"
#import "XFSubmissionTransport.h"
#import "XFModel.h"
#import "XFInstance.h"
#import "XFBinding.h"
#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFNodeState.h"
#import "XFXML.h"
#import "XFXMLEvents.h"
#import "XFEvent.h"
#import "XFDeferredUpdates.h"
#import "XFNamespaces.h"
#import "XFErrors.h"
#import <Foundation/NSXMLDocument.h>
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLNode.h>

@interface XFSubmission ()
@property (nonatomic, strong, readwrite) NSXMLElement *element;
@property (nonatomic, copy) NSArray<NSDictionary *> *headers;
@end

@implementation XFSubmission

static BOOL XFBoolAttr(NSXMLElement *el, NSString *name, BOOL fallback)
{
    NSString *v = [[el attributeForName:name] stringValue];
    if (v.length == 0) {
        return fallback;
    }
    if ([v isEqualToString:@"false"] || [v isEqualToString:@"0"] || [v isEqualToString:@"FALSE"]) {
        return NO;
    }
    return YES;
}

+ (instancetype)submissionWithElement:(NSXMLElement *)element
                                model:(XFModel *)model
                                error:(NSError **)error
{
    XFSubmission *sub = [[self alloc] init];
    sub.element = element;
    sub.model = model;
    sub.identifier = [[element attributeForName:@"id"] stringValue];
    sub.method = [[element attributeForName:@"method"] stringValue] ?: @"post";
    sub.separator = [[element attributeForName:@"separator"] stringValue] ?: @"&";
    if ([sub.separator isEqualToString:@"&amp;"]) {
        sub.separator = @"&";
    }
    sub.replace = [[element attributeForName:@"replace"] stringValue] ?: @"all";
    sub.instanceID = [[element attributeForName:@"instance"] stringValue];
    sub.targetref = [[element attributeForName:@"targetref"] stringValue];
    sub.serialization = [[element attributeForName:@"serialization"] stringValue] ?: @"application/xml";
    sub.mediatype = [[element attributeForName:@"mediatype"] stringValue];
    sub.validate = XFBoolAttr(element, @"validate", YES);
    sub.relevant = XFBoolAttr(element, @"relevant", YES);

    NSString *resource = [[element attributeForName:@"resource"] stringValue];
    if (resource.length == 0) {
        resource = [[element attributeForName:@"action"] stringValue];
    }
    NSXMLElement *resourceEl =
        [XFXML firstElementWithLocalName:@"resource"
                           namespaceURI:XFXFormsNamespaceURI
                                 inNode:element];
    if (resourceEl) {
        NSString *value = [[resourceEl attributeForName:@"value"] stringValue];
        if (value.length) {
            sub.resourceExpr = [XFXPath xpathWithString:value error:error];
            if (sub.resourceExpr == nil && value.length) {
                return nil;
            }
        } else if ([XFXML stringValueOfNode:resourceEl].length) {
            resource = [XFXML stringValueOfNode:resourceEl];
        }
    }
    sub.resource = resource;

    NSXMLElement *methodEl =
        [XFXML firstElementWithLocalName:@"method"
                           namespaceURI:XFXFormsNamespaceURI
                                 inNode:element];
    if (methodEl) {
        NSString *value = [[methodEl attributeForName:@"value"] stringValue];
        if (value.length) {
            sub.methodExpr = [XFXPath xpathWithString:value error:error];
            if (sub.methodExpr == nil) {
                return nil;
            }
        } else {
            NSString *lit = [XFXML stringValueOfNode:methodEl];
            if (lit.length) {
                sub.method = lit;
            }
        }
    }

    NSString *ref = [[element attributeForName:@"ref"] stringValue];
    if (ref.length) {
        sub.refBinding = [XFBinding bindingWithExpression:ref error:error];
        if (sub.refBinding == nil) {
            return nil;
        }
    }

    NSMutableArray *headers = [NSMutableArray array];
    NSArray *headerEls =
        [XFXML childElementsWithLocalName:@"header"
                            namespaceURI:XFXFormsNamespaceURI
                               ofElement:element];
    for (NSXMLElement *h in headerEls) {
        NSString *name = [[h attributeForName:@"name"] stringValue];
        NSString *value = [[h attributeForName:@"value"] stringValue];
        NSXMLElement *nameEl = [XFXML firstElementWithLocalName:@"name" namespaceURI:XFXFormsNamespaceURI inNode:h];
        NSXMLElement *valueEl = [XFXML firstElementWithLocalName:@"value" namespaceURI:XFXFormsNamespaceURI inNode:h];
        if (nameEl) {
            name = [XFXML stringValueOfNode:nameEl];
        }
        if (valueEl) {
            value = [XFXML stringValueOfNode:valueEl];
        }
        if (name.length) {
            [headers addObject:@{ @"name": name, @"value": value ?: @"" }];
        }
    }
    sub.headers = headers;
    return sub;
}

- (XFInstance *)targetInstance
{
    if (self.instanceID.length) {
        return [self.model instanceWithIdentifier:self.instanceID];
    }
    return [self.model defaultInstance];
}

- (XFExprContext *)rootContext
{
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:[[self.model defaultInstance] documentElement]];
    ctx.model = self.model;
    return ctx;
}

- (NSString *)resolvedResource
{
    if (self.resourceExpr) {
        return [self.resourceExpr stringValueInContext:[self rootContext] error:NULL] ?: @"";
    }
    return self.resource ?: @"";
}

- (NSXMLNode *)submissionNode
{
    if (self.refBinding) {
        return [self.refBinding boundNodeInContext:[self rootContext] error:NULL];
    }
    return [[self targetInstance] documentElement];
}

+ (NSString *)urlencodedFromNode:(NSXMLNode *)node separator:(NSString *)sep
{
    if ([node kind] != NSXMLElementKind) {
        return @"";
    }
    NSMutableString *url = [NSMutableString string];
    BOOL hasChildEl = NO;
    NSMutableString *text = [NSMutableString string];
    for (NSXMLNode *child in [node children]) {
        if ([child kind] == NSXMLElementKind) {
            hasChildEl = YES;
            [url appendString:[self urlencodedFromNode:child separator:sep]];
        } else if ([child kind] == NSXMLTextKind) {
            [text appendString:[child stringValue] ?: @""];
        }
    }
    if (!hasChildEl && text.length > 0) {
        [url appendFormat:@"%@=%@%@", [node name], XFPercentEncode(text), sep];
    }
    return url;
}

- (NSString *)resolvedMethod
{
    if (self.methodExpr) {
        NSString *m = [self.methodExpr stringValueInContext:[self rootContext] error:NULL];
        if (m.length) {
            return [m lowercaseString];
        }
    }
    return [self.method lowercaseString] ?: @"post";
}

- (NSString *)serializeNode:(NSXMLNode *)node method:(NSString *)method
{
    if ([self.serialization isEqualToString:@"none"]) {
        return @"";
    }
    if ([self.serialization isEqualToString:@"application/x-www-form-urlencoded"] ||
        [method isEqualToString:@"urlencoded-post"] ||
        [method isEqualToString:@"get"] ||
        [method isEqualToString:@"delete"]) {
        NSString *sep = self.separator.length ? self.separator : @"&";
        NSString *pair = [[self class] urlencodedFromNode:node separator:sep];
        if ([pair hasSuffix:sep]) {
            pair = [pair substringToIndex:pair.length - sep.length];
        }
        return pair;
    }
    if (self.relevant && [node kind] == NSXMLElementKind) {
        NSXMLElement *copy = [self relevantCopy:(NSXMLElement *)node];
        return copy ? [copy XMLString] : @"";
    }
    if ([node isKindOfClass:[NSXMLElement class]]) {
        return [(NSXMLElement *)node XMLString];
    }
    return [node XMLString] ?: [XFXML stringValueOfNode:node];
}

- (NSXMLElement *)relevantCopy:(NSXMLElement *)element
{
    XFNodeState *state = [XFNodeState existingStateOnNode:element];
    if (state && !state.relevant) {
        return nil;
    }
    NSXMLElement *copy = [[NSXMLElement alloc] initWithName:[element name] URI:[element URI]];
    for (NSXMLNode *attr in [element attributes]) {
        NSXMLNode *ac = [attr copy];
        [copy addAttribute:ac];
    }
    for (NSXMLNode *child in [element children]) {
        if ([child kind] == NSXMLElementKind) {
            NSXMLElement *cc = [self relevantCopy:(NSXMLElement *)child];
            if (cc) {
                [copy addChild:cc];
            }
        } else if ([child kind] == NSXMLTextKind) {
            [copy addChild:[child copy]];
        }
    }
    return copy;
}

- (BOOL)nodeIsValid:(NSXMLNode *)node
{
    XFNodeState *state = [XFNodeState existingStateOnNode:node];
    if (state && !state.valid && state.relevant) {
        return NO;
    }
    if ([node kind] == NSXMLElementKind) {
        for (NSXMLNode *child in [node children]) {
            if ([child kind] == NSXMLElementKind && ![self nodeIsValid:child]) {
                return NO;
            }
        }
    }
    return YES;
}

- (void)fail:(NSMutableDictionary *)ctx type:(NSString *)type
{
    ctx[@"error-type"] = type;
    self.lastEventContext = ctx;
    [XFXMLEvents dispatch:self name:@"xforms-submit-error" context:ctx];
}

- (void)submit
{
    if (self.pending) {
        [self fail:[NSMutableDictionary dictionary] type:@"submission-in-progress"];
        return;
    }
    self.pending = YES;
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"submission"];

    NSString *method = [self resolvedMethod];
    NSString *action = [self resolvedResource];
    NSMutableDictionary *evcontext = [@{
        @"method": method,
        @"resource-uri": action ?: @""
    } mutableCopy];

    NSXMLNode *node = [self submissionNode];
    if (self.validate && node && ![self nodeIsValid:node]) {
        evcontext[@"error-type"] = @"validation-error";
        self.lastEventContext = evcontext;
        [self.model addChange:node];
        [XFXMLEvents dispatch:self.model name:@"xforms-rebuild"];
        [self.model refresh];
        [self fail:evcontext type:@"validation-error"];
        [du closeAction:@"submission"];
        self.pending = NO;
        return;
    }

    if (([method isEqualToString:@"get"] || [method isEqualToString:@"delete"]) &&
        ![self.serialization isEqualToString:@"none"] && node) {
        NSString *qs = [self serializeNode:node method:method];
        if (qs.length) {
            action = [action stringByAppendingFormat:@"%@%@",
                      [action rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&",
                      qs];
            evcontext[@"resource-uri"] = action;
        }
    }

    NSString *body = @"";
    if (![self.serialization isEqualToString:@"none"]) {
        [XFXMLEvents dispatch:self name:@"xforms-submit-serialize" context:evcontext];
        body = [self serializeNode:node method:method] ?: @"";
        self.lastSerialization = body;
        evcontext[@"submission-body"] = body;
    } else {
        self.lastSerialization = @"";
    }

    if ([self.replace isEqualToString:@"none"] && [self.serialization isEqualToString:@"none"]
        && action.length == 0) {
        self.lastEventContext = evcontext;
        [XFXMLEvents dispatch:self name:@"xforms-submit-done" context:evcontext];
        [du closeAction:@"submission"];
        self.pending = NO;
        return;
    }

    id<XFSubmissionTransport> transport = self.transport ?: self.model.transport;
    if (transport == nil) {
        transport = [[XFHTTPSubmissionTransport alloc] init];
    }

    XFSubmissionRequest *req = [[XFSubmissionRequest alloc] init];
    req.method = method;
    req.URLString = action;
    req.body = body;
    req.mediaType = self.mediatype ?:
        ([self.serialization isEqualToString:@"application/x-www-form-urlencoded"]
         ? @"application/x-www-form-urlencoded"
         : @"application/xml");
    NSMutableDictionary *hdrs = [NSMutableDictionary dictionary];
    for (NSDictionary *h in self.headers) {
        hdrs[h[@"name"]] = h[@"value"];
    }
    req.headers = hdrs;

    NSError *net = nil;
    XFSubmissionResponse *resp = [transport performRequest:req error:&net];
    if (resp == nil || net ||
        (resp.statusCode != 0 && (resp.statusCode < 200 || resp.statusCode >= 300))) {
        evcontext[@"error-type"] = resp.errorType ?: @"resource-error";
        if (resp.body) {
            evcontext[@"response-body"] = resp.body;
        }
        evcontext[@"response-status-code"] = @(resp ? resp.statusCode : 0);
        [self fail:evcontext type:evcontext[@"error-type"]];
        [du closeAction:@"submission"];
        self.pending = NO;
        return;
    }

    evcontext[@"response-status-code"] = @(resp.statusCode);
    evcontext[@"response-body"] = resp.body ?: @"";

    if ([self.replace isEqualToString:@"instance"] ||
        ([self.replace isEqualToString:@"text"] && self.targetref.length)) {
        NSError *parse = nil;
        if ([self.replace isEqualToString:@"text"] && self.targetref.length) {
            XFBinding *tb = [XFBinding bindingWithExpression:self.targetref error:NULL];
            XFExprContext *ctx = [self rootContext];
            NSXMLNode *target = [tb boundNodeInContext:ctx error:NULL];
            if (target) {
                [XFXML setStringValue:resp.body ?: @"" ofNode:target];
                [self.model addChange:target];
            }
        } else {
            XFInstance *inst = [self targetInstance];
            if (![inst replaceWithXMLString:resp.body ?: @"" error:&parse]) {
                evcontext[@"error-type"] = @"parse-error";
                [self fail:evcontext type:@"parse-error"];
                [du closeAction:@"submission"];
                self.pending = NO;
                return;
            }
            [self.model addChange:[inst documentElement]];
        }
        [self.model setRebuilded:YES];
        [du addChangedModel:self.model];
        [XFXMLEvents dispatch:self.model name:@"xforms-rebuild"];
        [self.model refresh];
    }

    self.lastEventContext = evcontext;
    [XFXMLEvents dispatch:self name:@"xforms-submit-done" context:evcontext];
    [du closeAction:@"submission"];
    self.pending = NO;
}

@end
