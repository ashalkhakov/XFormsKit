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
#import <Foundation/NSXMLDocument.h>
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLNode.h>

@interface XFInstance ()
@property (nonatomic, strong, readwrite) NSXMLDocument *document;
@property (nonatomic, strong, readwrite) NSXMLDocument *originalDocument;
@end

@implementation XFInstance

+ (instancetype)instanceWithElement:(NSXMLElement *)instanceElement
                              error:(NSError **)error
{
    XFInstance *instance = [[self alloc] init];
    NSXMLNode *idAttr = [instanceElement attributeForName:@"id"];
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

    NSXMLElement *dataRoot = nil;
    for (NSXMLNode *child in [instanceElement children]) {
        if ([child kind] == NSXMLElementKind) {
            dataRoot = (NSXMLElement *)child;
            break;
        }
    }
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
    NSXMLElement *copy = [dataRoot copy];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:copy];
    [doc setVersion:@"1.0"];
    [doc setCharacterEncoding:@"UTF-8"];
    instance.document = doc;
    instance.originalDocument = [doc copy];
    return instance;
}

- (NSXMLElement *)documentElement
{
    return [self.document rootElement];
}

- (BOOL)loadFromSrc:(NSError **)error
{
    if (self.src.length == 0) {
        return YES;
    }
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
    NSXMLDocument *doc = nil;
    NSString *mt = self.mediatype ?: @"";
    if ([mt isEqualToString:@"application/json"] || [mt isEqualToString:@"text/json"]) {
        NSString *xml = [[self class] xmlStringFromJSONData:data error:&inner];
        doc = xml ? [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:&inner] : nil;
    } else if ([mt isEqualToString:@"text/csv"]) {
        NSString *csv = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
            ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        NSString *xml = [[self class] xmlStringFromCSV:csv ?: @"" separator:self.csvSeparator ?: @"," header:self.csvHeader];
        doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:&inner];
    } else {
        doc = [[NSXMLDocument alloc] initWithData:data options:0 error:&inner];
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
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:&inner];
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

- (BOOL)replaceNode:(NSXMLNode *)node withXMLString:(NSString *)xml error:(NSError **)error
{
    if (node == nil || node == [self documentElement] || [node parent] == nil
        || [node parent] == self.document) {
        return [self replaceWithXMLString:xml error:error];
    }
    NSError *inner = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:&inner];
    NSXMLElement *fresh = [doc rootElement];
    if (fresh == nil) {
        if (error) {
            *error = inner ?: [NSError errorWithDomain:XFErrorDomain
                                                  code:XFErrorDocument
                                              userInfo:@{ NSLocalizedDescriptionKey:
                                                              @"could not parse targetref replacement" }];
        }
        return NO;
    }
    NSXMLElement *clone = [fresh copy];
    NSXMLNode *parent = [node parent];
    if ([parent kind] != NSXMLElementKind) {
        return [self replaceWithXMLString:xml error:error];
    }
    NSUInteger idx = [node index];
    [(NSXMLElement *)parent removeChildAtIndex:idx];
    [(NSXMLElement *)parent insertChild:clone atIndex:idx];
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
    NSXMLElement *root = [self documentElement];
    if (root) {
        [self validateNode:root readonly:NO notRelevant:NO];
    }
}

- (BOOL)booleanMIP:(XFMIPBinding *)mip
              node:(NSXMLNode *)node
          position:(NSUInteger)position
          nodeList:(NSArray<NSXMLNode *> *)nodeList
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
    XFXPathValue *value = [mip evaluateInContext:ctx node:node model:self.model error:NULL];
    return value ? [value booleanValue] : fallback;
}

- (void)validateNode:(NSXMLNode *)node readonly:(BOOL)readonly notRelevant:(BOOL)notRelevant
{
    XFNodeState *state = [XFNodeState existingStateOnNode:node];
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
            for (NSXMLNode *n in bind.nodes) {
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
            if (![XFType value:value conformsToTypeNamed:state.typeName]) {
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
        XFNodeState *inherited = state ?: ((notRelevant || readonly) ? [XFNodeState stateOnNode:node] : nil);
        if (inherited) {
            inherited.relevant = !notRelevant;
            inherited.readonly = readonly;
        }
    }

    if ([node kind] == NSXMLElementKind) {
        NSXMLElement *element = (NSXMLElement *)node;
        for (NSXMLNode *attr in [element attributes]) {
            NSString *name = [attr name];
            if ([name hasPrefix:@"xmlns"]) {
                continue;
            }
            [self validateNode:attr readonly:readonly notRelevant:notRelevant];
        }
        for (NSXMLNode *child in [element children]) {
            if ([child kind] == NSXMLElementKind) {
                [self validateNode:child readonly:readonly notRelevant:notRelevant];
            }
        }
    }
}

@end
