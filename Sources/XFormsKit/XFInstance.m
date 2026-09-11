#import "XFInstance.h"
#import "XFXMLEvents.h"
#import "XFErrors.h"
#import "XFXML.h"
#import "XFModel.h"
#import "XFBind.h"
#import "XFNodeState.h"
#import "XFMIPBinding.h"
#import "XFExprContext.h"
#import "XFXPathValue.h"
#import "XFType.h"
#import <XFormsKit/XFXMLTypes.h>

@interface XFInstance ()
@property (nonatomic, strong, readwrite) XFXMLDocument *document;
@property (nonatomic, strong, readwrite) XFXMLDocument *originalDocument;
@end

@implementation XFInstance

+ (instancetype)instanceWithElement:(XFXMLElement *)instanceElement
                              error:(NSError **)error
{
    XFInstance *instance = [[self alloc] init];
    XFXMLNode *idAttr = [instanceElement attributeForName:@"id"];
    instance.identifier = idAttr ? [idAttr stringValue] : nil;
    instance.element = instanceElement;
    // @resource is the XForms 1.1 alias of @src (G-55)
    instance.src = [[instanceElement attributeForName:@"src"] stringValue]
        ?: [[instanceElement attributeForName:@"resource"] stringValue];
    instance.readonly = [[[instanceElement attributeForName:@"readonly"] stringValue] isEqualToString:@"true"];
    instance.csvSeparator = @",";
    NSString *mediatype = [[instanceElement attributeForName:@"mediatype"] stringValue];
    if (mediatype.length) {
        NSArray *parts = [mediatype componentsSeparatedByString:@";"];
        instance.mediatype = [parts.firstObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        for (NSString *param in [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)]) {
            NSArray *kv = [param componentsSeparatedByString:@"="];
            NSString *k = [kv.firstObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *v = kv.count > 1 ? [kv[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] : @"";
            if ([k isEqualToString:@"header"]) {
                instance.csvHeader = [v isEqualToString:@"present"];
            } else if ([k isEqualToString:@"separator"]) {
                instance.csvSeparator = [v stringByRemovingPercentEncoding] ?: v;
            }
        }
    }

    XFXMLElement *dataRoot = nil;
    NSUInteger elementChildren = 0;
    for (XFXMLNode *child in [instanceElement children]) {
        if ([child kind] == XFXMLElementKind) {
            elementChildren++;
            if (dataRoot == nil) {
                dataRoot = (XFXMLElement *)child;
            }
        }
    }
    // more than one top-level element is not a document — the exception
    // fires at construct, once listeners exist (3.3.2.g/h)
    instance.inlineContentMalformed = elementChildren > 1;
    if (dataRoot == nil && instance.src.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorDocument
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"xf:instance has no inline document element" }];
        }
        return nil;
    }
    if (dataRoot == nil) {
        return instance;
    }

    // Detach a deep copy so the live instance is a standalone document.
    XFXMLElement *copy = [dataRoot copy];
    XFXMLDocument *doc = [[XFXMLDocument alloc] initWithRootElement:copy];
    [doc setVersion:@"1.0"];
    [doc setCharacterEncoding:@"UTF-8"];
    instance.document = doc;
    instance.originalDocument = [doc copy];
    return instance;
}

- (XFXMLElement *)documentElement
{
    return [self.document rootElement];
}

- (void)reloadInlineDocument
{
    XFXMLElement *dataRoot = nil;
    for (XFXMLNode *child in [self.element children]) {
        if ([child kind] == XFXMLElementKind) {
            dataRoot = (XFXMLElement *)child;
            break;
        }
    }
    if (dataRoot == nil) {
        self.document = nil;
        self.originalDocument = nil;
        return;
    }
    XFXMLDocument *doc = [[XFXMLDocument alloc] initWithRootElement:[dataRoot copy]];
    [doc setVersion:@"1.0"];
    [doc setCharacterEncoding:@"UTF-8"];
    self.document = doc;
    self.originalDocument = [doc copy];
}

- (BOOL)loadFromSrc:(NSError **)error
{
    if (self.src.length == 0) {
        return YES;
    }
    // debugConsole: "Loading src"
    XFTraceWrite(XFTraceKindModel, nil, self.element, @"Loading %@", self.src);
    NSURL *url = [NSURL URLWithString:self.src];
    if (url == nil || url.scheme == nil) {
        if (self.baseURL) {
            url = [NSURL URLWithString:self.src relativeToURL:self.baseURL];
        } else {
            url = [NSURL fileURLWithPath:self.src];
        }
    }
    NSError *inner = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&inner];
    if (data == nil) {
        if (error) {
            *error = inner ?: [NSError errorWithDomain:XFErrorDomain
                                                  code:XFErrorDocument
                                              userInfo:@{ NSLocalizedDescriptionKey:
                                                              [NSString stringWithFormat:@"could not load instance src %@", self.src] }];
        }
        return NO;
    }
    XFXMLDocument *doc = nil;
    NSString *mt = self.mediatype ?: @"";
    if ([mt isEqualToString:@"application/json"] || [mt isEqualToString:@"text/json"]) {
        NSString *xml = [[self class] xmlStringFromJSONData:data error:&inner];
        doc = xml ? [[XFXMLDocument alloc] initWithXMLString:xml options:0 error:&inner] : nil;
    } else if ([mt isEqualToString:@"text/csv"]) {
        NSString *csv = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
            ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        NSString *xml = [[self class] xmlStringFromCSV:csv ?: @"" separator:self.csvSeparator ?: @"," header:self.csvHeader];
        doc = [[XFXMLDocument alloc] initWithXMLString:xml options:0 error:&inner];
    } else {
        doc = [[XFXMLDocument alloc] initWithData:data options:0 error:&inner];
    }
    if (doc == nil || [doc rootElement] == nil) {
        if (error) {
            *error = inner ?: [NSError errorWithDomain:XFErrorDomain
                                                  code:XFErrorDocument
                                              userInfo:@{ NSLocalizedDescriptionKey:
                                                              [NSString stringWithFormat:@"could not parse instance src %@", self.src] }];
        }
        return NO;
    }
    self.document = doc;
    self.originalDocument = [doc copy];
    return YES;
}

- (void)construct
{
    if (self.inlineContentMalformed) {
        // XForms 1.1 4.2.1: inline content that is not exactly one
        // element is a link failure; event('resource-uri') names the
        // form document holding it (3.3.2.h reads it in the handler)
        NSString *uri = [self.baseURL absoluteString]
            ?: [NSString stringWithFormat:@"#%@", self.identifier ?: @"instance"];
        [XFXMLEvents raise:@"xforms-link-exception" on:self.element ?: (id)self.model
                   message:@"xf:instance inline content has more than one root element"
                   context:@{ @"resource-uri": uri }];
    }
    if (self.src.length && self.document == nil) {
        NSError *inner = nil;
        if (![self loadFromSrc:&inner]) {
            // XsltForms_instance: globals.error(element, "xforms-link-exception", "Fatal error loading " + src)
            [XFXMLEvents raise:@"xforms-link-exception" on:self.element ?: (id)self.model
                       message:[NSString stringWithFormat:@"Fatal error loading %@ (%@)", self.src,
                                inner.localizedDescription ?: @""]];
        }
    }
}

- (void)reset
{
    self.document = [self.originalDocument copy];
}

- (BOOL)replaceWithXMLString:(NSString *)xml error:(NSError **)error
{
    if (xml.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorDocument
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"empty instance replacement" }];
        }
        return NO;
    }
    NSError *inner = nil;
    XFXMLDocument *doc = [[XFXMLDocument alloc] initWithXMLString:xml options:0 error:&inner];
    if (doc == nil || [doc rootElement] == nil) {
        if (error) {
            *error = inner ?: [NSError errorWithDomain:XFErrorDomain
                                                  code:XFErrorDocument
                                              userInfo:@{ NSLocalizedDescriptionKey:
                                                              @"could not parse instance replacement" }];
        }
        return NO;
    }
    self.document = doc;
    return YES;
}

- (BOOL)replaceNode:(XFXMLNode *)node withXMLString:(NSString *)xml error:(NSError **)error
{
    if (node == nil || node == [self documentElement] || [node parent] == nil
        || [node parent] == self.document) {
        return [self replaceWithXMLString:xml error:error];
    }
    NSError *inner = nil;
    XFXMLDocument *doc = [[XFXMLDocument alloc] initWithXMLString:xml options:0 error:&inner];
    XFXMLElement *fresh = [doc rootElement];
    if (fresh == nil) {
        if (error) {
            *error = inner ?: [NSError errorWithDomain:XFErrorDomain
                                                  code:XFErrorDocument
                                              userInfo:@{ NSLocalizedDescriptionKey:
                                                              @"could not parse targetref replacement" }];
        }
        return NO;
    }
    XFXMLElement *clone = [fresh copy];
    XFXMLNode *parent = [node parent];
    if ([parent kind] != XFXMLElementKind) {
        return [self replaceWithXMLString:xml error:error];
    }
    NSUInteger idx = [node index];
    [(XFXMLElement *)parent removeChildAtIndex:idx];
    [(XFXMLElement *)parent insertChild:clone atIndex:idx];
    return YES;
}

#pragma mark - foreign data (G-55)

static NSString *XFXMLEscape(NSString *s)
{
    NSMutableString *out = [s mutableCopy] ?: [NSMutableString string];
    [out replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, out.length)];
    return out;
}

static BOOL XFIsJSONName(NSString *name)
{
    if (name.length == 0) {
        return NO;
    }
    NSCharacterSet *start = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_"];
    NSCharacterSet *rest = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_-.0123456789"];
    if (![start characterIsMember:[name characterAtIndex:0]]) {
        return NO;
    }
    return [[name substringFromIndex:1] rangeOfCharacterFromSet:[rest invertedSet]].location == NSNotFound;
}

/// XsltForms_browser.json2xml(name, json, root, inarray)
static void XFJSON2XML(NSString *name, id json, BOOL root, BOOL inarray, NSMutableString *ret)
{
    NSString *fullname = @"";
    if ([name isEqualToString:@"________"] || (name.length && ![name hasPrefix:@"exml:"] && !XFIsJSONName(name))) {
        fullname = [NSString stringWithFormat:@" exml:fullname=\"%@\"", XFXMLEscape(name)];
        name = @"________";
    }
    if (root) {
        [ret appendString:@"<exml:anonymous xmlns:exml=\"http://www.agencexml.com/exml\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:exsi=\"http://www.agencexml.com/exi\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns=\"\">"];
    }
    if ([json isKindOfClass:[NSArray class]]) {
        NSArray *arr = json;
        NSString *n = name.length ? name : @"exml:anonymous";
        if (inarray) {
            [ret appendString:@"<exml:anonymous exsi:maxOccurs=\"unbounded\">"];
        }
        if (arr.count == 0) {
            [ret appendFormat:@"<%@%@ exsi:maxOccurs=\"unbounded\" xsi:nil=\"true\"/>", n, fullname];
        } else {
            for (id item in arr) {
                XFJSON2XML(n, item, NO, YES, ret);
            }
        }
        if (inarray) {
            [ret appendString:@"</exml:anonymous>"];
        }
    } else {
        NSString *xsdtype = @"";
        BOOL isObject = [json isKindOfClass:[NSDictionary class]];
        if ([json isKindOfClass:[NSString class]]) {
            xsdtype = @" xsi:type=\"xsd:string\"";
        } else if ([json isKindOfClass:[NSNumber class]]) {
            const char *t = [json objCType];
            xsdtype = (strcmp(t, @encode(BOOL)) == 0 || strcmp(t, "c") == 0 || strcmp(t, "B") == 0)
                ? @" xsi:type=\"xsd:boolean\"" : @" xsi:type=\"xsd:double\"";
        }
        if (name.length == 0) {
            if (root && xsdtype.length) {
                [ret deleteCharactersInRange:NSMakeRange(ret.length - 1, 1)];
                [ret appendFormat:@"%@>", xsdtype];
            }
        } else {
            [ret appendFormat:@"<%@%@%@%@>", name, fullname, inarray ? @" exsi:maxOccurs=\"unbounded\"" : @"", xsdtype];
        }
        if (isObject) {
            NSDictionary *dict = json;
            for (NSString *key in dict) {
                XFJSON2XML(key, dict[key], NO, NO, ret);
            }
        } else if ([json isKindOfClass:[NSNull class]]) {
            // null → empty element
        } else if ([json isKindOfClass:[NSNumber class]]) {
            const char *t = [json objCType];
            if (strcmp(t, @encode(BOOL)) == 0 || strcmp(t, "c") == 0 || strcmp(t, "B") == 0) {
                [ret appendString:[json boolValue] ? @"true" : @"false"];
            } else {
                [ret appendString:[json stringValue]];
            }
        } else {
            [ret appendString:XFXMLEscape([json description])];
        }
        if (name.length) {
            [ret appendFormat:@"</%@>", name];
        }
    }
    if (root) {
        [ret appendString:@"</exml:anonymous>"];
    }
}

+ (NSString *)xmlStringFromJSONData:(NSData *)data error:(NSError **)error
{
    id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:error];
    if (json == nil) {
        return nil;
    }
    NSMutableString *ret = [NSMutableString string];
    XFJSON2XML(@"", json, YES, NO, ret);
    return ret;
}

#pragma mark - xml2json / xml2csv (G-97)

static NSString * const XFEXMLNS = @"http://www.agencexml.com/exml";
static NSString * const XFEXINS = @"http://www.agencexml.com/exi";

static NSString *XFJSONQuote(NSString *s)
{
    NSData *d = [NSJSONSerialization dataWithJSONObject:@[ s ?: @"" ] options:0 error:NULL];
    NSString *arr = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"[\"\"]";
    return [arr substringWithRange:NSMakeRange(1, arr.length - 2)];
}

static NSString *XFJSONName(XFXMLElement *el)
{
    NSString *lname = [el localName] ?: [el name];
    if ([lname isEqualToString:@"________"]) {
        lname = [[el attributeForLocalName:@"fullname" URI:XFEXMLNS] stringValue] ?: lname;
    }
    return lname;
}

static BOOL XFJSONIsAnonymous(XFXMLElement *el)
{
    return [[el localName] isEqualToString:@"anonymous"] && [[el URI] isEqualToString:XFEXMLNS];
}

static NSArray<XFXMLElement *> *XFChildElements(XFXMLNode *node)
{
    NSMutableArray *out = [NSMutableArray array];
    for (XFXMLNode *c in [node children]) {
        if ([c kind] == XFXMLElementKind) {
            [out addObject:c];
        }
    }
    return out;
}

static void XFNode2JSONValue(XFXMLElement *el, NSMutableString *out);

/// The members of an object / items of the root: consecutive siblings
/// sharing a name and exsi:maxOccurs="unbounded" form one array.
static void XFNode2JSONMembers(XFXMLNode *node, NSMutableString *out, BOOL named)
{
    NSArray<XFXMLElement *> *children = XFChildElements(node);
    NSUInteger i = 0;
    BOOL first = YES;
    while (i < children.count) {
        XFXMLElement *c = children[i];
        BOOL unbounded = [[[c attributeForLocalName:@"maxOccurs" URI:XFEXINS] stringValue] isEqualToString:@"unbounded"];
        NSString *name = XFJSONName(c);
        // plain instance data (no exsi markers): repeated siblings are an array
        BOOL repeated = i + 1 < children.count && [XFJSONName(children[i + 1]) isEqualToString:name];
        if (!first) {
            [out appendString:@","];
        }
        first = NO;
        if (named && !XFJSONIsAnonymous(c)) {
            [out appendFormat:@"%@:", XFJSONQuote(name)];
        }
        if (unbounded || repeated) {
            [out appendString:@"["];
            BOOL nilArray = [[[c attributeForLocalName:@"nil" URI:@"http://www.w3.org/2001/XMLSchema-instance"] stringValue] isEqualToString:@"true"];
            NSUInteger j = i;
            BOOL firstItem = YES;
            while (j < children.count && [XFJSONName(children[j]) isEqualToString:name]
                   && (!unbounded || [[[children[j] attributeForLocalName:@"maxOccurs" URI:XFEXINS] stringValue] isEqualToString:@"unbounded"])) {
                if (!nilArray) {
                    if (!firstItem) {
                        [out appendString:@","];
                    }
                    firstItem = NO;
                    XFNode2JSONValue(children[j], out);
                }
                j++;
            }
            [out appendString:@"]"];
            i = j;
        } else {
            XFNode2JSONValue(c, out);
            i++;
        }
    }
}

static void XFNode2JSONValue(XFXMLElement *el, NSMutableString *out)
{
    NSString *xsdtype = [[el attributeForLocalName:@"type" URI:@"http://www.w3.org/2001/XMLSchema-instance"] stringValue] ?: @"";
    NSString *local = [xsdtype componentsSeparatedByString:@":"].lastObject ?: @"";
    NSString *text = [XFXML stringValueOfNode:el] ?: @"";
    if ([local isEqualToString:@"string"]) {
        [out appendString:XFJSONQuote(text)];
    } else if ([local isEqualToString:@"double"] || [local isEqualToString:@"decimal"] || [local isEqualToString:@"integer"]) {
        NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [out appendString:[[NSScanner scannerWithString:t] scanDouble:NULL] && t.length ? t : @"null"];
    } else if ([local isEqualToString:@"boolean"]) {
        [out appendString:[text isEqualToString:@"true"] || [text isEqualToString:@"1"] ? @"true" : @"false"];
    } else if (XFChildElements(el).count) {
        [out appendString:@"{"];
        XFNode2JSONMembers(el, out, YES);
        [out appendString:@"}"];
    } else if (xsdtype.length == 0 && text.length == 0) {
        [out appendString:@"null"];
    } else {
        [out appendString:XFJSONQuote(text)];
    }
}

+ (NSString *)jsonStringFromNode:(XFXMLNode *)node
{
    XFXMLElement *root = [node kind] == XFXMLDocumentKind ? [(XFXMLDocument *)node rootElement] : (XFXMLElement *)node;
    if ([root kind] != XFXMLElementKind) {
        return @"null";
    }
    NSMutableString *out = [NSMutableString string];
    if (XFJSONIsAnonymous(root)) {
        // the json2xml wrapper: a typed root is a scalar, else an object
        // (or an array of anonymous items)
        NSArray<XFXMLElement *> *children = XFChildElements(root);
        NSString *xsdtype = [[root attributeForLocalName:@"type" URI:@"http://www.w3.org/2001/XMLSchema-instance"] stringValue];
        if (children.count == 0 && xsdtype.length) {
            XFNode2JSONValue(root, out);
        } else if (children.count && XFJSONIsAnonymous(children.firstObject)) {
            [out appendString:@"["];
            XFNode2JSONMembers(root, out, NO);
            [out appendString:@"]"];
        } else {
            [out appendString:@"{"];
            XFNode2JSONMembers(root, out, YES);
            [out appendString:@"}"];
        }
    } else {
        [out appendString:@"{"];
        XFNode2JSONMembers([root parent] ?: root, out, YES);
        [out appendString:@"}"];
        if ([root parent] == nil || [[root parent] kind] == XFXMLDocumentKind) {
            // a plain instance root: {"root": {...}}
            out = [NSMutableString stringWithFormat:@"{%@:", XFJSONQuote(XFJSONName(root))];
            XFNode2JSONValue(root, out);
            [out appendString:@"}"];
        }
    }
    return out;
}

+ (NSString *)csvStringFromNode:(XFXMLNode *)node separator:(NSString *)separator
{
    XFXMLElement *root = [node kind] == XFXMLDocumentKind ? [(XFXMLDocument *)node rootElement] : (XFXMLElement *)node;
    NSArray<NSString *> *seps = [(separator.length ? separator : @",") componentsSeparatedByString:@" "];
    NSString *fsep = seps.firstObject.length ? seps.firstObject : @",";
    NSString *decsep = seps.count > 1 ? seps[1] : nil;
    NSMutableString *r = [NSMutableString string];
    NSArray<XFXMLElement *> *rows = XFChildElements(root);
    NSRegularExpression *number = [NSRegularExpression regularExpressionWithPattern:@"^[\\-+]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)$" options:0 error:NULL];
    void (^line)(NSArray<NSString *> *) = ^(NSArray<NSString *> *values) {
        NSMutableArray *cells = [NSMutableArray array];
        for (NSString *raw in values) {
            NSString *v = raw;
            if ([v rangeOfString:@"\n"].location != NSNotFound || [v rangeOfString:fsep].location != NSNotFound) {
                v = [NSString stringWithFormat:@"\"%@\"", [v stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
            } else if (decsep.length && [number numberOfMatchesInString:v options:0 range:NSMakeRange(0, v.length)]) {
                v = [v stringByReplacingOccurrencesOfString:@"." withString:decsep];
            }
            [cells addObject:v];
        }
        [r appendString:[cells componentsJoinedByString:fsep]];
        [r appendString:@"\n"];
    };
    if (rows.count) {
        NSMutableArray *head = [NSMutableArray array];
        for (XFXMLElement *f in XFChildElements(rows.firstObject)) {
            [head addObject:XFJSONName(f)];
        }
        line(head);
    }
    for (XFXMLElement *row in rows) {
        NSMutableArray *values = [NSMutableArray array];
        for (XFXMLElement *f in XFChildElements(row)) {
            [values addObject:[XFXML stringValueOfNode:f] ?: @""];
        }
        line(values);
    }
    return r;
}

+ (NSString *)xmlStringFromCSV:(NSString *)csv separator:(NSString *)sep header:(BOOL)head
{
    NSMutableString *r = [NSMutableString stringWithString:
        @"<exml:anonymous xmlns:exml=\"http://www.agencexml.com/exml\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:exsi=\"http://www.agencexml.com/exi\" xmlns=\"\">"];
    NSString *s = [[csv stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
                   stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    if (![s hasSuffix:@"\n"]) {
        s = [s stringByAppendingString:@"\n"];
    }
    if (sep.length == 0) {
        sep = @",";
    }
    NSMutableArray *headers = [NSMutableArray array];
    BOOL first = head;
    NSUInteger col = 0;
    NSMutableString *rowcat = [NSMutableString string];
    NSMutableString *row = [NSMutableString string];
    NSUInteger i = 0, l = s.length;
    while (i < l) {
        NSMutableString *v = [NSMutableString string];
        if ([s characterAtIndex:i] == '"') {
            i++;
            while (i < l) {
                if ([s characterAtIndex:i] != '"') {
                    [v appendFormat:@"%C", [s characterAtIndex:i]];
                    i++;
                } else if (i + 1 < l && [s characterAtIndex:i + 1] == '"') {
                    [v appendString:@"\""];
                    i += 2;
                } else {
                    i++;
                    break;
                }
            }
        } else {
            while (i < l && [s characterAtIndex:i] != '\n'
                   && !(i + sep.length <= l && [[s substringWithRange:NSMakeRange(i, sep.length)] isEqualToString:sep])) {
                [v appendFormat:@"%C", [s characterAtIndex:i]];
                i++;
            }
        }
        if (first) {
            [headers addObject:[v copy]];
        } else {
            [rowcat appendString:v];
            NSString *tag = (head && col < headers.count && XFIsJSONName(headers[col])) ? headers[col] : @"exml:anonymous";
            [row appendFormat:@"<%@>%@</%@>", tag, XFXMLEscape(v), tag];
        }
        if (i < l && [s characterAtIndex:i] == '\n') {
            if (!first && rowcat.length) {
                [r appendFormat:@"<exml:anonymous>%@</exml:anonymous>", row];
            }
            first = NO;
            col = 0;
            [row setString:@""];
            [rowcat setString:@""];
            i++;
        } else {
            col++;
            i += sep.length;
        }
    }
    [r appendString:@"</exml:anonymous>"];
    return r;
}

- (void)revalidate
{
    if (self.readonly) {
        return;   // XsltForms_instance.revalidate: readonly instances are not validated
    }
    XFXMLElement *root = [self documentElement];
    if (root) {
        [self validateNode:root readonly:NO notRelevant:NO];
    }
}

- (BOOL)booleanMIP:(XFMIPBinding *)mip
              node:(XFXMLNode *)node
          position:(NSUInteger)position
          nodeList:(NSArray<XFXMLNode *> *)nodeList
           default:(BOOL)fallback
{
    if (mip == nil) {
        return fallback;
    }
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:node];
    ctx.model = self.model;
    ctx.position = position;
    ctx.nodeList = nodeList;
    ctx.size = nodeList.count;
    NSError *inner = nil;
    XFXPathValue *value = [mip evaluateInContext:ctx node:node model:self.model error:&inner];
    if (value == nil && inner != nil) {
        // an ERROR inside a model item property is a computed-expression
        // failure: xforms-compute-exception (7.5.a — a failing binding
        // expression raises binding-exception instead, 7.5.b)
        [XFXMLEvents raise:@"xforms-compute-exception" on:self.model.element ?: (id)self.model
                   message:inner.localizedDescription];
    }
    return value ? [value booleanValue] : fallback;
}

static NSString * const XFXSINS = @"http://www.w3.org/2001/XMLSchema-instance";

/// XsltForms_browser.getType: the bind's type, else the node's own
/// `xsi:type` (resolved in the node's namespace context) — G-83.
- (NSString *)typeNameForNode:(XFXMLNode *)node state:(XFNodeState *)state
{
    if (state.typeName.length) {
        return state.typeName;
    }
    if ([node kind] != XFXMLElementKind) {
        return nil;
    }
    NSString *qname = [[(XFXMLElement *)node attributeForLocalName:@"type" URI:XFXSINS] stringValue];
    if (qname.length == 0) {
        return nil;
    }
    XFType *type = [XFType typeForQName:qname inElement:(XFXMLElement *)node targetNamespace:nil];
    return type ? [NSString stringWithFormat:@"{%@}%@", type.namespaceURI, type.localName] : qname;
}

/// XsltForms_browser.getNil
static BOOL XFNodeIsNil(XFXMLNode *node)
{
    return [node kind] == XFXMLElementKind
        && [[[(XFXMLElement *)node attributeForLocalName:@"nil" URI:XFXSINS] stringValue] isEqualToString:@"true"];
}

- (void)validateNode:(XFXMLNode *)node readonly:(BOOL)readonly notRelevant:(BOOL)notRelevant
{
    XFNodeState *state = [XFNodeState existingStateOnNode:node];
    NSString *typeName = [self typeNameForNode:node state:state];
    if (state.bindIdentifiers.count > 0) {
        NSString *value = [XFXML stringValueOfNode:node];
        BOOL relevantFound = NO;
        BOOL readonlyFound = NO;
        BOOL required = NO;
        BOOL relevant = !notRelevant;
        BOOL isReadonly = readonly;
        BOOL constraintOK = YES;

        for (NSString *bindID in [state.bindIdentifiers copy]) {
            XFBind *bind = [self.model bindWithIdentifier:bindID];
            if (bind == nil) {
                continue;
            }
            NSUInteger position = 1;
            NSUInteger i = 0;
            for (XFXMLNode *n in bind.nodes) {
                if (n == node) {
                    position = i + 1;
                    break;
                }
                i++;
            }
            required = required || [self booleanMIP:bind.required
                                               node:node
                                           position:position
                                           nodeList:bind.nodes
                                            default:NO];
            if (notRelevant || !relevantFound || bind.relevant) {
                BOOL mipRelevant = [self booleanMIP:bind.relevant
                                               node:node
                                           position:position
                                           nodeList:bind.nodes
                                            default:YES];
                relevant = !notRelevant && mipRelevant;
                relevantFound = relevantFound || (bind.relevant != nil);
            }
            if (readonly || !readonlyFound || bind.readonly || bind.calculate) {
                BOOL mipRO = [self booleanMIP:bind.readonly
                                         node:node
                                     position:position
                                     nodeList:bind.nodes
                                      default:(bind.calculate != nil)];
                isReadonly = readonly || mipRO;
                readonlyFound = readonlyFound || (bind.readonly != nil) || (bind.calculate != nil);
            }
            constraintOK = constraintOK && [self booleanMIP:bind.constraint
                                                       node:node
                                                   position:position
                                                   nodeList:bind.nodes
                                                    default:YES];
        }

        BOOL empty = (value.length == 0);
        BOOL valid = YES;
        if (relevant) {
            if (required && empty) {
                valid = NO;
            }
            if (!constraintOK) {
                valid = NO;
            }
            // xsi:nil="true": only the empty value is valid (validate_)
            if (XFNodeIsNil(node) ? !empty : ![XFType value:value conformsToTypeNamed:typeName]) {
                valid = NO;
            }
        }
        // XsltForms_instance.setProperty_: a MIP flip marks the node changed
        // so dependants re-evaluate in this cycle (G-16)
        BOOL flipped = state.required != required || state.relevant != relevant
            || state.readonly != isReadonly || state.valid != valid;
        state.required = required;
        state.relevant = relevant;
        state.readonly = isReadonly;
        state.constraint = constraintOK;
        state.valid = valid;
        if (flipped && self.model.ready) {
            [self.model addChange:node];
        }
        notRelevant = !relevant;
        readonly = isReadonly;
    } else {
        // XsltForms_instance.validate_ else-branch: unbound nodes always take
        // the inherited values, so a subtree becomes relevant / writable
        // again when its bound ancestor does. Only materialise a state
        // object when something differs from the defaults.
        // An unbound node typed by xsi:type is still validated (validate_
        // else-branch: schtyp.validate(value)) — G-83
        BOOL typed = typeName.length > 0;
        BOOL valid = YES;
        if (typed) {
            NSString *value = [XFXML stringValueOfNode:node];
            valid = XFNodeIsNil(node) ? value.length == 0 : [XFType value:value conformsToTypeNamed:typeName];
        }
        XFNodeState *inherited = state ?: ((notRelevant || readonly || !valid) ? [XFNodeState stateOnNode:node] : nil);
        if (inherited) {
            inherited.relevant = !notRelevant;
            inherited.readonly = readonly;
            if (typed) {
                BOOL flipped = inherited.valid != valid;
                inherited.valid = valid;
                if (flipped && self.model.ready) {
                    [self.model addChange:node];
                }
            }
        }
    }

    if ([node kind] == XFXMLElementKind) {
        XFXMLElement *element = (XFXMLElement *)node;
        for (XFXMLNode *attr in [element attributes]) {
            NSString *name = [attr name];
            if ([name hasPrefix:@"xmlns"]) {
                continue;
            }
            [self validateNode:attr readonly:readonly notRelevant:notRelevant];
        }
        for (XFXMLNode *child in [element children]) {
            if ([child kind] == XFXMLElementKind) {
                [self validateNode:child readonly:readonly notRelevant:notRelevant];
            }
        }
    }
}

@end
