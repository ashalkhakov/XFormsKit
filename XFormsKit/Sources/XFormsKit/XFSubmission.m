#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "XFSubmission.h"
#import "XFSubmissionTransport.h"
#import "XFModel.h"
#import "XFInstance.h"
#import "XFBinding.h"
#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFNodeState.h"
#import "XFProcessor.h"
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
@property (nonatomic, strong) NSMutableArray<NSString *> *cdataTexts;
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
    // XForms 1.1: validate / relevant default to false with serialization="none" (G-58)
    BOOL noSerialization = [sub.serialization isEqualToString:@"none"];
    sub.validate = XFBoolAttr(element, @"validate", !noSerialization);
    sub.relevant = XFBoolAttr(element, @"relevant", !noSerialization);
    NSString *cdata = [[element attributeForName:@"cdata-section-elements"] stringValue];
    if (cdata.length) {
        NSMutableArray *names = [NSMutableArray array];
        for (NSString *n in [cdata componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
            if (n.length) {
                [names addObject:[[n componentsSeparatedByString:@":"] lastObject]];
            }
        }
        sub.cdataSectionElements = names;
    }
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
            sub.resourceExpr = [XFXPath xpathWithString:value element:element error:error];
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
            sub.methodExpr = [XFXPath xpathWithString:value element:element error:error];
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
        sub.targetrefBinding = [XFBinding bindingWithExpression:sub.targetref element:element error:error];
        if (sub.targetrefBinding == nil) {
            return nil;
        }
    }

    NSError *bindError = nil;
    sub.refBinding = [XFBinding bindingForElement:element attribute:@"ref" error:&bindError];
    if (bindError) {
        if (error) {
            *error = bindError;
        }
        return nil;
    }

    // xf:header (XSLTForms .header(nodeset, combine, name, values)): the
    // name and each xf:value are literals or @value expressions; @nodeset
    // repeats the header per node; @combine = append (default) | prepend |
    // replace. `@name` / `@value` attribute shorthands are also accepted.
    NSMutableArray *headers = [NSMutableArray array];
    NSArray *headerEls =
        [XFXML childElementsWithLocalName:@"header"
                            namespaceURI:XFXFormsNamespaceURI
                               ofElement:element];
    for (NSXMLElement *h in headerEls) {
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        NSString *nodeset = [[h attributeForName:@"nodeset"] stringValue] ?: [[h attributeForName:@"ref"] stringValue];
        if (nodeset.length) {
            XFBinding *b = [XFBinding bindingWithExpression:nodeset element:h error:NULL];
            if (b) entry[@"nodeset"] = b;
        }
        entry[@"combine"] = [[h attributeForName:@"combine"] stringValue] ?: @"append";
        NSXMLElement *nameEl = [XFXML firstElementWithLocalName:@"name" namespaceURI:XFXFormsNamespaceURI inNode:h];
        NSString *nameValue = nameEl ? [[nameEl attributeForName:@"value"] stringValue] : nil;
        if (nameValue.length) {
            XFXPath *xp = [XFXPath xpathWithString:nameValue element:h error:NULL];
            if (xp) entry[@"nameExpr"] = xp;
        } else if (nameEl) {
            entry[@"name"] = [XFXML stringValueOfNode:nameEl] ?: @"";
        } else {
            NSString *name = [[h attributeForName:@"name"] stringValue];
            if (name.length) entry[@"name"] = name;
        }
        NSMutableArray *values = [NSMutableArray array];
        NSArray *valueEls = [XFXML childElementsWithLocalName:@"value" namespaceURI:XFXFormsNamespaceURI ofElement:h];
        for (NSXMLElement *v in valueEls) {
            NSString *vv = [[v attributeForName:@"value"] stringValue];
            if (vv.length) {
                XFXPath *xp = [XFXPath xpathWithString:vv element:h error:NULL];
                [values addObject:xp ?: (id)@""];
            } else {
                [values addObject:[XFXML stringValueOfNode:v] ?: @""];
            }
        }
        if (valueEls.count == 0) {
            NSString *valueAttr = [[h attributeForName:@"value"] stringValue];
            if (valueAttr.length) {
                XFXPath *xp = [XFXPath xpathWithString:valueAttr element:h error:NULL];
                [values addObject:xp ?: (id)valueAttr];
            }
        }
        entry[@"values"] = values;
        if (entry[@"name"] || entry[@"nameExpr"]) {
            [headers addObject:entry];
        }
    }
    sub.headers = headers;
    return sub;
}

/// XsltForms_submission: `@instance`, else the instance holding the
/// submitted node (`ref`), else the model's default instance (G-08).
- (XFInstance *)targetInstance
{
    if (self.instanceID.length) {
        return [self.model instanceWithIdentifier:self.instanceID];
    }
    NSXMLNode *node = [self submissionNode];
    XFInstance *owning = node ? [self.model instanceContainingNode:node] : nil;
    return owning ?: [self.model defaultInstance];
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
    // no ref: the default instance root (XSLTForms model.getInstance()),
    // independent of @instance which only names the replacement target
    return [[self.model defaultInstance] documentElement];
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
    NSString *xml = [self serializeNodeAsXML:node method:method];
    // XsltForms_submission.xml2data: a JSON / CSV @mediatype converts the
    // (relevance-pruned) XML serialization (G-97)
    NSString *mt = [[[self.mediatype componentsSeparatedByString:@";"].firstObject lowercaseString]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    BOOL urlencoded = [self.serialization isEqualToString:@"application/x-www-form-urlencoded"]
        || [method isEqualToString:@"urlencoded-post"] || [method isEqualToString:@"get"] || [method isEqualToString:@"delete"];
    if (!urlencoded && xml.length && node
        && ([mt isEqualToString:@"application/json"] || [mt isEqualToString:@"text/json"] || [mt isEqualToString:@"text/csv"])) {
        NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL];
        if ([doc rootElement]) {
            if ([mt isEqualToString:@"text/csv"]) {
                return [XFInstance csvStringFromNode:[doc rootElement] separator:self.separator];
            }
            return [XFInstance jsonStringFromNode:[doc rootElement]];
        }
    }
    return xml;
}

- (NSString *)serializeNodeAsXML:(NSXMLNode *)node method:(NSString *)method
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
    if ((self.relevant || self.cdataSectionElements.count) && [node kind] == NSXMLElementKind) {
        self.cdataTexts = [NSMutableArray array];
        NSXMLElement *copy = [self relevantCopy:(NSXMLElement *)node];
        NSString *xml = copy ? [copy XMLString] : @"";
        NSUInteger i = 0;
        for (NSString *text in self.cdataTexts) {
            NSString *section = [NSString stringWithFormat:@"<![CDATA[%@]]>",
                                 [text stringByReplacingOccurrencesOfString:@"]]>" withString:@"]]]]><![CDATA[>"]];
            xml = [xml stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"XFCDATASECTION%lu", (unsigned long)i]
                                                 withString:section];
            i++;
        }
        self.cdataTexts = nil;
        return xml;
    }
    if ([node isKindOfClass:[NSXMLElement class]]) {
        return [(NSXMLElement *)node XMLString];
    }
    return [node XMLString] ?: [XFXML stringValueOfNode:node];
}

- (NSXMLElement *)relevantCopy:(NSXMLElement *)element
{
    XFNodeState *state = [XFNodeState existingStateOnNode:element];
    if (self.relevant && state && !state.relevant) {
        return nil;
    }
    NSXMLElement *copy = [[NSXMLElement alloc] initWithName:[element name] URI:[element URI]];
    for (NSXMLNode *ns in [element namespaces]) {
        [copy addNamespace:[ns copy]];
    }
    for (NSXMLNode *attr in [element attributes]) {
        // non-relevant attributes are pruned too (XSLTForms, G-58)
        XFNodeState *as = [XFNodeState existingStateOnNode:attr];
        if (self.relevant && as && !as.relevant) {
            continue;
        }
        NSXMLNode *ac = [attr copy];
        [copy addAttribute:ac];
    }
    BOOL cdata = [self.cdataSectionElements containsObject:[element localName] ?: @""];
    for (NSXMLNode *child in [element children]) {
        if ([child kind] == NSXMLElementKind) {
            NSXMLElement *cc = self.relevant ? [self relevantCopy:(NSXMLElement *)child] : [self relevantCopy:(NSXMLElement *)child];
            if (cc) {
                [copy addChild:cc];
            }
        } else if ([child kind] == NSXMLTextKind) {
            if (cdata) {
                // @cdata-section-elements (G-58): GNUstep ignores
                // NSXMLNodeIsCDATA, so the text is swapped for a token that
                // serializeNode: replaces with a CDATA section
                NSString *token = [NSString stringWithFormat:@"XFCDATASECTION%lu", (unsigned long)self.cdataTexts.count];
                [self.cdataTexts addObject:[child stringValue] ?: @""];
                [copy addChild:[NSXMLNode textWithStringValue:token]];
            } else {
                [copy addChild:[child copy]];
            }
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
        // attributes carry MIPs too (XsltForms_instance.validation_), G-58
        for (NSXMLNode *attr in [(NSXMLElement *)node attributes]) {
            XFNodeState *as = [XFNodeState existingStateOnNode:attr];
            if (as && !as.valid && as.relevant) {
                return NO;
            }
        }
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
    if (ctx[@"message"] == nil) {
        ctx[@"message"] = [NSString stringWithFormat:@"%@%@", type,
                           ctx[@"response-reason-phrase"] ? [NSString stringWithFormat:@": %@", ctx[@"response-reason-phrase"]] : @""];
    }
    self.lastEventContext = ctx;
    [XFXMLEvents dispatch:self name:@"xforms-submit-error" context:ctx];
}

/// The request exactly as `submit` sends it — method mapping, media
/// type rules, SOAPAction, evaluated xf:header list with @combine,
/// Accept defaults, preemptive-authentication flag. Shared by the live
/// path and previewRequest.
- (XFSubmissionRequest *)buildRequestWithMethod:(NSString *)method
                                         action:(NSString *)action
                                           body:(NSString *)body
                                       bodyData:(NSData *)bodyData
                                      mediaType:(NSString *)mediaType
{
    XFSubmissionRequest *req = [[XFSubmissionRequest alloc] init];
    // XSLTForms openRequest(method.split("-").pop()): the XForms methods
    // urlencoded-post / multipart-post / form-data-post are HTTP POST (G-07)
    req.method = [[method componentsSeparatedByString:@"-"] lastObject] ?: method;
    req.URLString = action;
    req.body = body;
    req.bodyData = bodyData;
    if ([method isEqualToString:@"urlencoded-post"]
        || [self.serialization isEqualToString:@"application/x-www-form-urlencoded"]) {
        req.mediaType = @"application/x-www-form-urlencoded";
    } else {
        req.mediaType = mediaType ?: @"application/xml";
    }
    // XSLTForms submit(): headers are evaluated per @nodeset node, values
    // joined with ",", same-named headers combined per @combine (G-17).
    NSMutableDictionary *hdrs = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *hdrOrder = [NSMutableArray array];
    // mediatype="…;action=urn:x" → SOAPAction header (XSLTForms, G-58)
    NSArray *mtParts = [self.mediatype componentsSeparatedByString:@";"];
    for (NSString *param in (mtParts.count > 1 ? [mtParts subarrayWithRange:NSMakeRange(1, mtParts.count - 1)] : @[])) {
        NSArray *kv = [param componentsSeparatedByString:@"="];
        if (kv.count == 2 && [[kv[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:@"action"]) {
            hdrs[@"SOAPAction"] = [kv[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            [hdrOrder addObject:@"SOAPAction"];
        }
    }
    XFExprContext *hctx = [self rootContext];
    for (NSDictionary *h in self.headers) {
        NSArray<NSXMLNode *> *hnodes = @[];
        XFBinding *nodeset = h[@"nodeset"];
        if (nodeset) {
            hnodes = [nodeset evaluateInContext:hctx error:NULL].nodes ?: @[];
        } else if (hctx.contextNode) {
            hnodes = @[ hctx.contextNode ];
        }
        for (NSXMLNode *hn in hnodes) {
            XFExprContext *nctx = [hctx cloneWithNode:hn position:1 nodeList:hnodes];
            NSString *name = h[@"name"];
            XFXPath *nameExpr = h[@"nameExpr"];
            if (nameExpr) {
                name = [nameExpr stringValueInContext:nctx error:NULL];
            }
            if (name.length == 0) {
                continue;
            }
            NSMutableArray *parts = [NSMutableArray array];
            for (id v in h[@"values"]) {
                if ([v isKindOfClass:[XFXPath class]]) {
                    [parts addObject:[(XFXPath *)v stringValueInContext:nctx error:NULL] ?: @""];
                } else {
                    [parts addObject:[v description]];
                }
            }
            NSString *hvalue = [parts componentsJoinedByString:@","];
            NSString *key = nil;
            for (NSString *k in hdrOrder) {
                if ([k caseInsensitiveCompare:name] == NSOrderedSame) { key = k; break; }
            }
            if (key) {
                NSString *combine = h[@"combine"];
                if ([combine isEqualToString:@"prepend"]) {
                    hdrs[key] = [NSString stringWithFormat:@"%@,%@", hvalue, hdrs[key]];
                } else if ([combine isEqualToString:@"replace"]) {
                    hdrs[key] = hvalue;
                } else {
                    hdrs[key] = [NSString stringWithFormat:@"%@,%@", hdrs[key], hvalue];
                }
            } else {
                [hdrOrder addObject:name];
                hdrs[name] = hvalue;
            }
        }
    }
    // default Accept header (XSLTForms): XML for replace="instance",
    // text/plain for other GET/DELETE submissions
    BOOL hasAccept = NO;
    for (NSString *k in hdrs) {
        if ([k caseInsensitiveCompare:@"Accept"] == NSOrderedSame) hasAccept = YES;
    }
    if (!hasAccept) {
        BOOL replaceInstance = [[self.replace lowercaseString] isEqualToString:@"instance"];
        if ([method isEqualToString:@"get"] || [method isEqualToString:@"delete"]) {
            hdrs[@"Accept"] = replaceInstance ? @"application/xml,text/xml" : @"text/plain";
        } else if (replaceInstance) {
            hdrs[@"Accept"] = @"application/xml,text/xml";
        }
    }
    req.headers = hdrs;
    // preemptive Basic only when the author says so (Orbeon's
    // xxf:preemptive-authentication spelling, any prefix)
    for (NSXMLNode *attr in [self.element attributes]) {
        if ([[attr localName] isEqualToString:@"preemptive-authentication"]) {
            req.preemptiveAuth = [[attr stringValue] isEqualToString:@"true"];
        }
    }
    return req;
}

/// The exact request `submit` would send from the CURRENT instance
/// state — the designer's submission tester shows this. No events are
/// dispatched (xforms-submit-serialize included), no validation gate
/// runs, and no submission state changes: a pure preview
- (XFSubmissionRequest *)previewRequest
{
    NSString *method = [self resolvedMethod];
    NSString *action = [self resolvedResource];
    NSXMLNode *node = [self submissionNode];
    if (([method isEqualToString:@"get"] || [method isEqualToString:@"delete"]) &&
        ![self.serialization isEqualToString:@"none"] && node) {
        NSString *qs = [self serializeNode:node method:method];
        if (qs.length) {
            action = [action stringByAppendingFormat:@"%@%@",
                      [action rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&",
                      qs];
        }
    }
    NSString *body = @"";
    NSData *bodyData = nil;
    NSString *mediaType = self.mediatype;
    if (![self.serialization isEqualToString:@"none"]) {
        if ([self isMultipartSerialization] && node
            && !([method isEqualToString:@"get"] || [method isEqualToString:@"delete"])) {
            NSString *mt = nil;
            bodyData = [self multipartBodyFromNode:node mediaType:&mt];
            mediaType = self.mediatype.length ? self.mediatype : mt;
            body = [[NSString alloc] initWithData:bodyData encoding:NSISOLatin1StringEncoding] ?: @"";
        } else {
            body = [self serializeNode:node method:method] ?: @"";
            bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
        }
    }
    return [self buildRequestWithMethod:method action:action
                                   body:body bodyData:bodyData mediaType:mediaType];
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

    // one transport per DOCUMENT by default: its cookie jar makes
    // "login submission, then call the API" work
    id<XFSubmissionTransport> transport = self.transport ?: self.model.transport;
    if (transport == nil && [self.model.owner isKindOfClass:[XFProcessor class]]) {
        transport = [(XFProcessor *)self.model.owner defaultTransport];
    }
    if (transport == nil) {
        transport = [[XFHTTPSubmissionTransport alloc] init];
    }

    XFSubmissionRequest *req = [self buildRequestWithMethod:method
                                                     action:action
                                                       body:body
                                                   bodyData:bodyData
                                                  mediaType:mediaType];

    if (![method isEqualToString:@"get"] && ![method isEqualToString:@"delete"]
        && node == nil && ![self.serialization isEqualToString:@"none"]) {
        [self fail:evcontext type:@"no-data"];
        [du closeAction:@"submission"];
        self.pending = NO;
        return;
    }

    if (self.asynchronous) {
        [du closeAction:@"submission"];
        // The request runs off the main thread and the finish lands back
        // on it through the RUN LOOP (performSelectorOnMainThread), not
        // the main dispatch queue: a gnustep-base built without
        // GS_USE_LIBDISPATCH_RUNLOOP never drains that queue from
        // NSRunLoop, so a main-queue hop would hang waitUntilFinished:
        // and every host that spins the loop for async submissions.
        [self performSelectorInBackground:@selector(runAsyncRequest:)
                               withObject:@{ @"transport": transport,
                                             @"request": req,
                                             @"context": evcontext }];
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
    // XSLTForms synthesises the reason phrase from the status code (G-58)
    evcontext[@"response-reason-phrase"] = resp.errorType
        ?: (resp.statusCode > 0 ? [NSHTTPURLResponse localizedStringForStatusCode:resp.statusCode] : @"");
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
            // XFSubmission.js: replace="text" without a target is a no-op
            // followed by xforms-submit-done (G-59)
            return YES;
        }
        [XFXML setStringValue:resp.body ?: @"" ofNode:target];
        [self.model addChange:target];
    } else {
        // instance; JSON / CSV responses (by Content-Type, else by the
        // instance's mediatype) are converted like instance @src (G-55)
        NSString *body = resp.body ?: @"";
        NSString *ct = [[resp.mediaType componentsSeparatedByString:@";"].firstObject lowercaseString] ?: @"";
        NSString *mt = ([ct containsString:@"json"] || [ct isEqualToString:@"text/csv"]) ? ct : (inst.mediatype ?: @"");
        if ([mt containsString:@"json"]) {
            NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
            NSString *xml = [XFInstance xmlStringFromJSONData:data error:&parse];
            if (xml == nil) {
                evcontext[@"error-type"] = @"parse-error";
                [self fail:evcontext type:@"parse-error"];
                return NO;
            }
            body = xml;
        } else if ([mt isEqualToString:@"text/csv"]) {
            body = [XFInstance xmlStringFromCSV:body separator:inst.csvSeparator ?: @"," header:inst.csvHeader];
        }
        BOOL ok;
        if (target && target != [inst documentElement]) {
            ok = [inst replaceNode:target withXMLString:body error:&parse];
        } else {
            ok = [inst replaceWithXMLString:body error:&parse];
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

/// Background side of an asynchronous submission (see runWithContextNode:).
- (void)runAsyncRequest:(NSDictionary *)job
{
    @autoreleasepool {
        id<XFSubmissionTransport> transport = job[@"transport"];
        NSError *net = nil;
        XFSubmissionResponse *resp = [transport performRequest:job[@"request"] error:&net];
        NSMutableDictionary *done = [NSMutableDictionary dictionary];
        if (resp) {
            done[@"response"] = resp;
        }
        if (net) {
            done[@"error"] = net;
        }
        done[@"context"] = job[@"context"];
        [self performSelectorOnMainThread:@selector(finishAsyncRequest:)
                               withObject:done
                            waitUntilDone:NO];
    }
}

- (void)finishAsyncRequest:(NSDictionary *)done
{
    [self finishWithResponse:done[@"response"]
                       error:done[@"error"]
                     context:done[@"context"]];
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
