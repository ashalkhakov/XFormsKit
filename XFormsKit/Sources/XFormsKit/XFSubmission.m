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
    NSString *mode = [[[element attributeForName:@"mode"] stringValue] lowercaseString];
    sub.asynchronous = ![mode isEqualToString:@"synchronous"];
    if (mode.length == 0) {
        // XForms 1.1 default is asynchronous; keep tests that omit @mode
        // behaving as they do today (apply the result before submit returns).
        sub.asynchronous = NO;
    }

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

    if (sub.targetref.length) {
        sub.targetrefBinding = [XFBinding bindingWithExpression:sub.targetref error:error];
        if (sub.targetrefBinding == nil) {
            return nil;
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
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        NSString *name = [[h attributeForName:@"name"] stringValue];
        NSString *valueAttr = [[h attributeForName:@"value"] stringValue];
        NSString *value = valueAttr;
        NSXMLElement *nameEl = [XFXML firstElementWithLocalName:@"name" namespaceURI:XFXFormsNamespaceURI inNode:h];
        NSXMLElement *valueEl = [XFXML firstElementWithLocalName:@"value" namespaceURI:XFXFormsNamespaceURI inNode:h];
        NSString *nameValue = nameEl ? [[nameEl attributeForName:@"value"] stringValue] : nil;
        NSString *valueValue = valueEl ? [[valueEl attributeForName:@"value"] stringValue] : nil;
        if (nameEl && nameValue.length == 0) {
            name = [XFXML stringValueOfNode:nameEl];
        }
        if (valueEl && valueValue.length == 0) {
            value = [XFXML stringValueOfNode:valueEl];
        }
        if (name.length) {
            entry[@"name"] = name;
        }
        if (nameValue.length) {
            XFXPath *xp = [XFXPath xpathWithString:nameValue error:NULL];
            if (xp) entry[@"nameExpr"] = xp;
        }
        if (valueValue.length) {
            XFXPath *xp = [XFXPath xpathWithString:valueValue error:NULL];
            if (xp) entry[@"valueExpr"] = xp;
        } else if (valueAttr.length && valueEl == nil) {
            XFXPath *xp = [XFXPath xpathWithString:valueAttr error:NULL];
            if (xp) {
                entry[@"valueExpr"] = xp;
                value = nil;
            }
        }
        if (value.length) {
            entry[@"value"] = value;
        }
        if (entry[@"name"] || entry[@"nameExpr"]) {
            [headers addObject:entry];
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

- (BOOL)isMultipartSerialization
{
    NSString *s = [self.serialization lowercaseString];
    NSString *m = [[self resolvedMethod] lowercaseString];
    return [s hasPrefix:@"multipart/"]
        || [s isEqualToString:@"application/octet-stream"]
        || [m isEqualToString:@"form-data-post"]
        || [m isEqualToString:@"multipart-post"]
        || [m isEqualToString:@"form-data"];
}

- (void)collectLeaves:(NSXMLNode *)node into:(NSMutableArray<NSXMLElement *> *)leaves
{
    if ([node kind] != NSXMLElementKind) {
        return;
    }
    NSXMLElement *el = (NSXMLElement *)node;
    XFNodeState *st = [XFNodeState existingStateOnNode:el];
    if (self.relevant && st && !st.relevant) {
        return;
    }
    BOOL hasEl = NO;
    for (NSXMLNode *c in [el children]) {
        if ([c kind] == NSXMLElementKind) {
            hasEl = YES;
            [self collectLeaves:c into:leaves];
        }
    }
    if (!hasEl) {
        [leaves addObject:el];
    }
}

- (NSData *)multipartBodyFromNode:(NSXMLNode *)node
                        mediaType:(NSString **)outMediaType
{
    NSString *boundary = [NSString stringWithFormat:@"XFormsKit-%08x%08x",
                          arc4random(), arc4random()];
    NSMutableData *data = [NSMutableData data];
    NSMutableArray *leaves = [NSMutableArray array];
    [self collectLeaves:node into:leaves];
    BOOL related = [[self.serialization lowercaseString] hasPrefix:@"multipart/related"]
        || [[[self resolvedMethod] lowercaseString] isEqualToString:@"multipart-post"];
    BOOL octet = [[self.serialization lowercaseString] isEqualToString:@"application/octet-stream"];
    if (octet) {
        for (NSXMLElement *el in leaves) {
            XFNodeState *st = [XFNodeState existingStateOnNode:el];
            if (st.fileData.length) {
                if (outMediaType) {
                    *outMediaType = st.mediaType ?: @"application/octet-stream";
                }
                return st.fileData;
            }
        }
        NSString *xml = [node XMLString] ?: @"";
        if (outMediaType) {
            *outMediaType = @"application/octet-stream";
        }
        return [xml dataUsingEncoding:NSUTF8StringEncoding];
    }
    void (^append)(NSString *) = ^(NSString *s) {
        [data appendData:[s dataUsingEncoding:NSUTF8StringEncoding]];
    };
    for (NSXMLElement *el in leaves) {
        XFNodeState *st = [XFNodeState existingStateOnNode:el];
        append([NSString stringWithFormat:@"--%@\r\n", boundary]);
        NSString *name = [el localName] ?: [el name] ?: @"part";
        if (st.fileData.length) {
            NSString *fn = st.fileName ?: name;
            NSString *mt = st.mediaType ?: @"application/octet-stream";
            if (related) {
                append([NSString stringWithFormat:
                        @"Content-Disposition: attachment; filename=\"%@\"\r\n"
                        @"Content-Type: %@\r\n"
                        @"Content-ID: <%@>\r\n\r\n", fn, mt, name]);
            } else {
                append([NSString stringWithFormat:
                        @"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n"
                        @"Content-Type: %@\r\n"
                        @"Content-Transfer-Encoding: binary\r\n\r\n",
                        name, fn, mt]);
            }
            [data appendData:st.fileData];
            append(@"\r\n");
        } else {
            NSString *val = [XFXML stringValueOfNode:el] ?: @"";
            if (related) {
                append([NSString stringWithFormat:
                        @"Content-Disposition: inline\r\nContent-Type: text/plain; charset=UTF-8\r\n"
                        @"Content-ID: <%@>\r\n\r\n%@\r\n", name, val]);
            } else {
                append([NSString stringWithFormat:
                        @"Content-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",
                        name, val]);
            }
        }
    }
    append([NSString stringWithFormat:@"--%@--\r\n", boundary]);
    if (outMediaType) {
        NSString *kind = related ? @"multipart/related" : @"multipart/form-data";
        *outMediaType = [NSString stringWithFormat:@"%@; boundary=%@", kind, boundary];
    }
    return data;
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
    NSData *bodyData = nil;
    NSString *mediaType = self.mediatype;
    if (![self.serialization isEqualToString:@"none"]) {
        [XFXMLEvents dispatch:self name:@"xforms-submit-serialize" context:evcontext];
        if ([self isMultipartSerialization] && node
            && !([method isEqualToString:@"get"] || [method isEqualToString:@"delete"])) {
            NSString *mt = nil;
            bodyData = [self multipartBodyFromNode:node mediaType:&mt];
            mediaType = self.mediatype.length ? self.mediatype : mt;
            body = [[NSString alloc] initWithData:bodyData encoding:NSISOLatin1StringEncoding] ?: @"";
            self.lastBodyData = bodyData;
            self.lastSerialization = body;
            evcontext[@"submission-body"] = body;
        } else {
            body = [self serializeNode:node method:method] ?: @"";
            self.lastSerialization = body;
            self.lastBodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
            evcontext[@"submission-body"] = body;
        }
    } else {
        self.lastSerialization = @"";
        self.lastBodyData = nil;
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
    req.bodyData = bodyData;
    req.mediaType = mediaType ?:
        ([self.serialization isEqualToString:@"application/x-www-form-urlencoded"]
         ? @"application/x-www-form-urlencoded"
         : @"application/xml");
    NSMutableDictionary *hdrs = [NSMutableDictionary dictionary];
    XFExprContext *hctx = [self rootContext];
    for (NSDictionary *h in self.headers) {
        NSString *name = h[@"name"];
        NSString *value = h[@"value"];
        XFXPath *nameExpr = h[@"nameExpr"];
        XFXPath *valueExpr = h[@"valueExpr"];
        if (nameExpr) {
            name = [nameExpr stringValueInContext:hctx error:NULL];
        }
        if (valueExpr) {
            value = [valueExpr stringValueInContext:hctx error:NULL];
        }
        if (name.length) {
            hdrs[name] = value ?: @"";
        }
    }
    req.headers = hdrs;

    if (![method isEqualToString:@"get"] && ![method isEqualToString:@"delete"]
        && node == nil && ![self.serialization isEqualToString:@"none"]) {
        [self fail:evcontext type:@"no-data"];
        [du closeAction:@"submission"];
        self.pending = NO;
        return;
    }

    if (self.asynchronous) {
        [du closeAction:@"submission"];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError *net = nil;
            XFSubmissionResponse *resp = [transport performRequest:req error:&net];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self finishWithResponse:resp error:net context:evcontext];
            });
        });
        return;
    }

    NSError *net = nil;
    XFSubmissionResponse *resp = [transport performRequest:req error:&net];
    [self finishWithResponse:resp error:net context:evcontext];
}

- (void)fillResponseContext:(NSMutableDictionary *)evcontext
                   response:(XFSubmissionResponse *)resp
{
    evcontext[@"response-status-code"] = @(resp ? resp.statusCode : 0);
    evcontext[@"response-body"] = resp.body ?: @"";
    evcontext[@"response-reason-phrase"] = resp.errorType ?: (resp.statusCode >= 200 && resp.statusCode < 300 ? @"OK" : @"");
    if (resp.headers.count) {
        evcontext[@"response-headers"] = resp.headers;
    }
}

- (NSXMLNode *)evaluateTargetref
{
    if (self.targetrefBinding == nil) {
        return nil;
    }
    XFExprContext *ctx = [self rootContext];
    XFInstance *inst = [self targetInstance];
    if (inst.documentElement) {
        ctx.contextNode = inst.documentElement;
        ctx.currentNode = inst.documentElement;
    }
    return [self.targetrefBinding boundNodeInContext:ctx error:NULL];
}

- (BOOL)applyReplacement:(XFSubmissionResponse *)resp context:(NSMutableDictionary *)evcontext
{
    NSString *replace = [self.replace lowercaseString] ?: @"all";
    if ([replace isEqualToString:@"none"]) {
        return YES;
    }
    if ([replace isEqualToString:@"all"]) {
        self.lastAllReplacement = resp.body ?: @"";
        evcontext[@"replace"] = @"all";
        return YES;
    }
    XFInstance *inst = [self targetInstance];
    NSXMLNode *target = [self evaluateTargetref];
    NSError *parse = nil;
    if ([replace isEqualToString:@"text"]) {
        if (target == nil) {
            [self fail:evcontext type:@"target-error"];
            return NO;
        }
        [XFXML setStringValue:resp.body ?: @"" ofNode:target];
        [self.model addChange:target];
    } else {
        // instance
        BOOL ok;
        if (target && target != [inst documentElement]) {
            ok = [inst replaceNode:target withXMLString:resp.body ?: @"" error:&parse];
        } else {
            ok = [inst replaceWithXMLString:resp.body ?: @"" error:&parse];
        }
        if (!ok) {
            evcontext[@"error-type"] = @"parse-error";
            [self fail:evcontext type:@"parse-error"];
            return NO;
        }
        [self.model addChange:[inst documentElement]];
    }
    [self.model setRebuilded:YES];
    [[XFDeferredUpdates sharedUpdates] addChangedModel:self.model];
    [XFXMLEvents dispatch:self.model name:@"xforms-rebuild"];
    [self.model refresh];
    return YES;
}

- (void)finishWithResponse:(XFSubmissionResponse *)resp
                     error:(NSError *)net
                   context:(NSMutableDictionary *)evcontext
{
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"submission-finish"];
    [self fillResponseContext:evcontext response:resp];
    if (resp == nil || net ||
        (resp.statusCode != 0 && (resp.statusCode < 200 || resp.statusCode >= 300))) {
        evcontext[@"error-type"] = (resp.errorType.length ? resp.errorType : @"resource-error");
        [self fail:evcontext type:evcontext[@"error-type"]];
        [du closeAction:@"submission-finish"];
        self.pending = NO;
        return;
    }
    if (![self applyReplacement:resp context:evcontext]) {
        [du closeAction:@"submission-finish"];
        self.pending = NO;
        return;
    }
    self.lastEventContext = evcontext;
    [XFXMLEvents dispatch:self name:@"xforms-submit-done" context:evcontext];
    [du closeAction:@"submission-finish"];
    self.pending = NO;
}

- (BOOL)waitUntilFinished:(NSTimeInterval)timeout
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (self.pending && [limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    return !self.pending;
}

@end
