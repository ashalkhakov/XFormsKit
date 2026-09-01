#import "XFOutputControl.h"
#import "XFXML.h"
#import "XFNamespaces.h"
#import "XFXMLEvents.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFXPathValue.h"
#import "XFNodeState.h"

@implementation XFOutputControl {
    XFBinding *_mediatypeBinding;
    BOOL _raisedOutputError;
}

- (instancetype)initWithElement:(NSXMLElement *)element
                        binding:(XFBinding *)binding
                          label:(NSString *)label
{
    self = [super initWithElement:element binding:binding label:label];
    if (self) {
        _mediaType = [[element attributeForName:@"mediatype"] stringValue];
        // the xf:mediatype CHILD element (static text, or computed via
        // ref/value) OVERRIDES the mediatype attribute (8.1.5.1.a)
        NSXMLElement *mtEl = [XFXML firstElementWithLocalName:@"mediatype"
                                                 namespaceURI:XFXFormsNamespaceURI
                                                       inNode:element];
        if (mtEl != nil) {
            _mediatypeBinding = [XFBinding bindingForElement:mtEl attribute:@"ref" error:NULL];
            NSString *lit = [XFXML stringValueOfNode:mtEl];
            if (_mediatypeBinding == nil && lit.length) {
                _mediaType = lit;
            }
        }
    }
    return self;
}

- (NSString *)resolvedMediaType
{
    if (self.mediaType.length) {
        return [self.mediaType lowercaseString];
    }
    XFNodeState *state = [XFNodeState existingStateOnNode:self.boundNode];
    if (state.mediaType.length) {
        return [state.mediaType lowercaseString];
    }
    if (state.typeName.length && [[state.typeName lowercaseString] rangeOfString:@"base64"].location != NSNotFound) {
        return @"application/octet-stream";
    }
    return @"text/plain";
}

- (BOOL)displaysImage
{
    NSString *mt = [self resolvedMediaType];
    return [mt hasPrefix:@"image/"] || [mt isEqualToString:@"application/octet-stream"];
}

- (BOOL)displaysHTML
{
    NSString *mt = [self resolvedMediaType];
    return [mt isEqualToString:@"text/html"]
        || [mt isEqualToString:@"application/xhtml+xml"]
        || [mt isEqualToString:@"application/xml+xhtml"];
}

- (NSData *)imageData
{
    NSString *value = self.stringValue ?: @"";
    if (value.length == 0) {
        XFNodeState *state = [XFNodeState existingStateOnNode:self.boundNode];
        if (state.fileData.length) {
            return state.fileData;
        }
        return nil;
    }
    if ([value hasPrefix:@"data:"]) {
        NSRange comma = [value rangeOfString:@","];
        if (comma.location == NSNotFound) {
            return nil;
        }
        NSString *b64 = [value substringFromIndex:comma.location + 1];
        return [[NSData alloc] initWithBase64EncodedString:b64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
    }
    if ([value hasPrefix:@"http://"] || [value hasPrefix:@"https://"] || [value hasPrefix:@"file:"]) {
        NSURL *url = [NSURL URLWithString:value];
        if (url) {
            return [NSData dataWithContentsOfURL:url];
        }
    }
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:value
                                                          options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (decoded.length) {
        return decoded;
    }
    return [value dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    if (self.binding == nil) {
        return;
    }
    NSError *inner = nil;
    XFXPathValue *value = [self.binding evaluateInContext:context error:&inner];
    if (inner) {
        // a failing binding/@value expression on a UI control raises
        // xforms-binding-exception (7.5.b, 7.8.3.e)
        [XFXMLEvents raise:@"xforms-binding-exception" on:self.element
                   message:inner.localizedDescription];
        if (error) {
            *error = inner;
        }
        return;
    }
    self.boundNode = value.firstNode;
    self.stringValue = [value stringValue] ?: @"";
    if (_mediatypeBinding != nil) {
        // the child's ref is relative to the output's BOUND node
        // (ref="../@mediatype" beside the bound @filename)
        XFExprContext *mtCtx = self.boundNode
            ? [context cloneWithNode:self.boundNode position:1 nodeList:@[ self.boundNode ]]
            : context;
        NSString *mt = [_mediatypeBinding stringValueInContext:mtCtx error:NULL];
        if (mt.length) {
            self.mediaType = mt;
        }
    }
    // XForms 1.1 4.5.5: rendering under a mediatype the processor cannot
    // handle dispatches xforms-output-error. A token with no type/subtype
    // shape is never renderable (4.5.5.a "unknownMediatype")
    if (!_raisedOutputError && self.mediaType.length
        && [self.mediaType rangeOfString:@"/"].location == NSNotFound) {
        _raisedOutputError = YES;
        [XFXMLEvents raise:@"xforms-output-error" on:self.element
                   message:[NSString stringWithFormat:@"Unsupported mediatype %@", self.mediaType]];
    }
    if (self.boundNode == nil && self.usesValueBinding) {
        // `value` computes a string, not a node: relevance/readonly follow the
        // context node the expression was evaluated against (as XSLTForms
        // does for xf:output/@value), not the empty result node-set.
        [self applyMIPsFromNode:context.contextNode];
    } else {
        [self applyMIPsFromBoundNode];
    }
}

@end
