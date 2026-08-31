#import "XFHostNode.h"
#import "XFControl.h"
#import "XFNamespaces.h"
#import "XFXML.h"
#import "XFSubform.h"
#import "XFProcessor.h"
#import <Foundation/NSXMLElement.h>
#import <dispatch/dispatch.h>
#import <ctype.h>

static NSString * const XFSVGNamespaceURI = @"http://www.w3.org/2000/svg";

@implementation XFHostNode

+ (instancetype)nodeWithKind:(XFHostNodeKind)kind tag:(NSString *)tag
{
    XFHostNode *n = [[self alloc] init];
    n.kind = kind;
    n.tag = tag ?: @"";
    n.children = @[];
    return n;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _children = @[];
        _tag = @"";
    }
    return self;
}

+ (BOOL)isBlockTag:(NSString *)tag
{
    static NSSet *blocks = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        blocks = [NSSet setWithArray:@[
            @"html", @"body", @"div", @"p", @"h1", @"h2", @"h3", @"h4", @"h5", @"h6",
            @"fieldset", @"ul", @"ol", @"li", @"dl", @"dt", @"dd", @"pre",
            @"blockquote", @"section", @"article", @"header", @"footer", @"nav",
            @"main", @"aside", @"form", @"address", @"center", @"figure",
            @"figcaption", @"details", @"summary", @"noscript"
        ]];
    });
    return [blocks containsObject:tag];
}

+ (NSString *)collapseWhitespace:(NSString *)s
{
    NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    BOOL pendingSpace = NO;
    NSUInteger n = s.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if ([ws characterIsMember:c]) {
            pendingSpace = YES;
            continue;
        }
        if (pendingSpace && out.length) {
            [out appendString:@" "];
        } else if (pendingSpace && out.length == 0) {
            [out appendString:@" "];
        }
        pendingSpace = NO;
        [out appendFormat:@"%C", c];
    }
    if (pendingSpace && (out.length || n)) {
        [out appendString:@" "];
    }
    return out;
}

/// Identity key for `existing`: the element's address. (Not
/// valueWithNonretainedObject: — on GNUstep two NSXMLElements with the
/// same content compare equal, so a re-imported copy would match the
/// control of the element it replaced.)
static NSNumber *XFElementKey(NSXMLElement *element)
{
    return @((unsigned long long)(uintptr_t)element);
}

static NSXMLNode *XFCurrentRepeatItemNode = nil;

+ (NSXMLNode *)currentRepeatItemNode
{
    return XFCurrentRepeatItemNode;
}

+ (void)setCurrentRepeatItemNode:(NSXMLNode *)node
{
    XFCurrentRepeatItemNode = node;
}

+ (NSArray<XFHostNode *> *)hostNodesForChildrenOf:(NSXMLElement *)element
                                            model:(id)model
                                         controls:(NSMutableArray<XFControl *> *)controls
                                         existing:(NSDictionary<NSValue *, XFControl *> *)existing
                                            error:(NSError **)error
{
    return [self nodesForChildrenOf:element
                              model:model
                           controls:controls
                           existing:existing
                       preformatted:NO
                              error:error];
}

+ (NSArray<XFHostNode *> *)nodesForChildrenOf:(NSXMLElement *)element
                                        model:(id)model
                                     controls:(NSMutableArray<XFControl *> *)controls
                                     existing:(NSDictionary<NSValue *, XFControl *> *)existing
                                 preformatted:(BOOL)pre
                                        error:(NSError **)error
{
    NSMutableArray<XFHostNode *> *out = [NSMutableArray array];
    for (NSXMLNode *child in [element children]) {
        // per-item subform content: an imported node owned by another
        // repeat item stays out of this item's tree (writers.xhtml —
        // one shared <group id="subform"/> template, one subform per
        // item, XSLTForms' per-clone IdManager behavior)
        NSXMLNode *owner = [XFSubform ownerNodeOfImportedNode:child];
        if (owner != nil && owner != XFCurrentRepeatItemNode) {
            continue;
        }
        NSXMLNodeKind kind = [child kind];
        if (kind == NSXMLTextKind) {
            NSString *raw = [child stringValue] ?: @"";
            NSString *text = pre ? raw : [self collapseWhitespace:raw];
            if (text.length == 0) {
                continue;
            }
            XFHostNode *t = [self nodeWithKind:XFHostNodeKindText tag:@"#text"];
            t.text = text;
            t.preformatted = pre;
            [out addObject:t];
            continue;
        }
        if (kind == NSXMLCommentKind && [[child stringValue] isEqualToString:XFWhitespaceMarkerText]) {
            // the parser pre-pass marks a whitespace-only gap between two
            // tags; recreate the text node unless the parser kept it
            XFHostNode *last = out.lastObject;
            BOOL kept = last && last.kind == XFHostNodeKindText
                && [[last.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0;
            if (!kept) {
                XFHostNode *t = [self nodeWithKind:XFHostNodeKindText tag:@"#text"];
                t.text = pre ? @"\n" : @" ";
                t.preformatted = pre;
                [out addObject:t];
            }
            continue;
        }
        if (kind != NSXMLElementKind) {
            continue;
        }
        XFHostNode *node = [self nodeForElement:(NSXMLElement *)child
                                          model:model
                                       controls:controls
                                       existing:existing
                                   preformatted:pre
                                          error:error];
        if (node == nil) {
            if (error && *error) {
                return nil;
            }
            continue;
        }
        [out addObject:node];
    }
    // Whitespace-only text is significant only between two inline siblings
    // ("<b>is</b> <xf:output/>"); elsewhere it is layout noise.
    NSMutableArray<XFHostNode *> *kept = [NSMutableArray arrayWithCapacity:out.count];
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSUInteger i = 0; i < out.count; i++) {
        XFHostNode *n = out[i];
        if (n.kind == XFHostNodeKindText && !n.preformatted
            && [[n.text stringByTrimmingCharactersInSet:ws] length] == 0) {
            XFHostNode *prev = i > 0 ? out[i - 1] : nil;
            XFHostNode *next = i + 1 < out.count ? out[i + 1] : nil;
            BOOL between = prev && next && [prev isInlineLevel] && [next isInlineLevel]
                && prev.kind != XFHostNodeKindBreak && next.kind != XFHostNodeKindBreak
                && prev.kind != XFHostNodeKindText && next.kind != XFHostNodeKindText;
            if (!between) {
                continue;
            }
            n.text = @" ";
        }
        [kept addObject:n];
    }
    return kept;
}

+ (XFHostNode *)nodeForElement:(NSXMLElement *)el
                         model:(id)model
                      controls:(NSMutableArray<XFControl *> *)controls
                      existing:(NSDictionary<NSValue *, XFControl *> *)existing
                  preformatted:(BOOL)pre
                         error:(NSError **)error
{
    NSString *uri = [el URI] ?: @"";
    NSString *tag = [[el localName] lowercaseString] ?: @"";

    if ([uri isEqualToString:XFXFormsNamespaceURI]) {
        if ([tag isEqualToString:@"model"]) {
            return nil;
        }
        if (![XFControl shouldInstantiateElement:el]) {
            // label/help/hint/alert/item/itemset/value/actions… belong to
            // their control (or are handlers), never to the layout tree
            return nil;
        }
        XFControl *control = existing[XFElementKey(el)];
        if (control == nil) {
            NSError *inner = nil;
            control = [XFControl controlWithElement:el model:model error:&inner];
            if (control == nil) {
                if (error) {
                    *error = inner;
                }
                return nil;
            }
        }
        [controls addObject:control];
        XFHostNode *node = [self nodeWithKind:XFHostNodeKindControl tag:tag];
        node.element = el;
        node.control = control;
        return node;
    }

    XFHostNode *node = nil;
    if ([tag isEqualToString:@"svg"] || [uri isEqualToString:XFSVGNamespaceURI]) {
        node = [self nodeWithKind:([tag isEqualToString:@"svg"] ? XFHostNodeKindSVG : XFHostNodeKindInline) tag:tag];
    } else if ([tag isEqualToString:@"table"]) {
        node = [self nodeWithKind:XFHostNodeKindTable tag:tag];
    } else if ([tag isEqualToString:@"thead"] || [tag isEqualToString:@"tbody"] || [tag isEqualToString:@"tfoot"]) {
        node = [self nodeWithKind:XFHostNodeKindTableSection tag:tag];
    } else if ([tag isEqualToString:@"tr"]) {
        node = [self nodeWithKind:XFHostNodeKindTableRow tag:tag];
    } else if ([tag isEqualToString:@"td"] || [tag isEqualToString:@"th"]) {
        node = [self nodeWithKind:XFHostNodeKindTableCell tag:tag];
        node.header = [tag isEqualToString:@"th"];
    } else if ([tag isEqualToString:@"br"]) {
        node = [self nodeWithKind:XFHostNodeKindBreak tag:tag];
    } else if ([tag isEqualToString:@"hr"]) {
        node = [self nodeWithKind:XFHostNodeKindRule tag:tag];
    } else if ([tag isEqualToString:@"head"] || [tag isEqualToString:@"script"]
               || [tag isEqualToString:@"style"] || [tag isEqualToString:@"title"]
               || [tag isEqualToString:@"meta"] || [tag isEqualToString:@"link"]) {
        return nil;
    } else if ([tag isEqualToString:@"legend"] || [tag isEqualToString:@"caption"]) {
        // folded into the parent's title below
        return nil;
    } else if ([self isBlockTag:tag]) {
        node = [self nodeWithKind:XFHostNodeKindBlock tag:tag];
        if (tag.length == 2 && [tag characterAtIndex:0] == 'h' && isdigit([tag characterAtIndex:1])) {
            node.headingLevel = [tag characterAtIndex:1] - '0';
        }
    } else {
        node = [self nodeWithKind:XFHostNodeKindInline tag:tag];
    }
    node.element = el;
    BOOL childPre = pre || [tag isEqualToString:@"pre"];
    node.preformatted = childPre;

    if ([tag isEqualToString:@"fieldset"] || [tag isEqualToString:@"table"]) {
        NSString *titleTag = [tag isEqualToString:@"fieldset"] ? @"legend" : @"caption";
        for (NSXMLNode *c in [el children]) {
            if ([c kind] == NSXMLElementKind && [[[c localName] lowercaseString] isEqualToString:titleTag]) {
                node.title = [self collapseWhitespace:[XFXML stringValueOfNode:c]];
                node.title = [node.title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                break;
            }
        }
    }

    NSArray *children = [self nodesForChildrenOf:el
                                           model:model
                                        controls:controls
                                        existing:existing
                                    preformatted:childPre
                                           error:error];
    if (children == nil) {
        return nil;
    }
    for (XFHostNode *c in children) {
        c.parent = node;
    }
    node.children = children;
    // An unknown inline element wrapping blocks behaves like a block.
    if (node.kind == XFHostNodeKindInline) {
        for (XFHostNode *c in children) {
            if (![c isInlineLevel]) {
                node.kind = XFHostNodeKindBlock;
                break;
            }
        }
    }
    return node;
}

+ (NSDictionary<NSValue *, XFControl *> *)controlMapFor:(NSArray<XFControl *> *)controls
{
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (XFControl *c in controls) {
        if (c.element) {
            map[XFElementKey(c.element)] = c;
        }
    }
    return map;
}

- (BOOL)isInlineLevel
{
    switch (self.kind) {
        case XFHostNodeKindText:
        case XFHostNodeKindInline:
        case XFHostNodeKindBreak:
            return YES;
        case XFHostNodeKindControl:
            return ![self.control isBlockLevel];
        default:
            return NO;
    }
}

- (BOOL)containsControls
{
    if (self.kind == XFHostNodeKindControl) {
        return YES;
    }
    for (XFHostNode *c in self.children) {
        if ([c containsControls]) {
            return YES;
        }
    }
    return NO;
}

- (NSArray<XFControl *> *)allControls
{
    NSMutableArray *out = [NSMutableArray array];
    [self collectControlsInto:out];
    return out;
}

- (void)collectControlsInto:(NSMutableArray *)out
{
    if (self.kind == XFHostNodeKindControl && self.control) {
        [out addObject:self.control];
        return;
    }
    for (XFHostNode *c in self.children) {
        [c collectControlsInto:out];
    }
}

- (NSString *)textContent
{
    if (self.kind == XFHostNodeKindText) {
        return self.text ?: @"";
    }
    if (self.kind == XFHostNodeKindControl) {
        return self.control.stringValue ?: @"";
    }
    NSMutableString *s = [NSMutableString string];
    for (XFHostNode *c in self.children) {
        [s appendString:[c textContent]];
    }
    return s;
}

- (NSString *)kindName
{
    switch (self.kind) {
        case XFHostNodeKindBlock: return @"block";
        case XFHostNodeKindInline: return @"inline";
        case XFHostNodeKindText: return @"text";
        case XFHostNodeKindBreak: return @"br";
        case XFHostNodeKindRule: return @"hr";
        case XFHostNodeKindTable: return @"table";
        case XFHostNodeKindTableSection: return @"section";
        case XFHostNodeKindTableRow: return @"row";
        case XFHostNodeKindTableCell: return @"cell";
        case XFHostNodeKindSVG: return @"svg";
        case XFHostNodeKindControl: return @"control";
    }
    return @"?";
}

- (void)appendDescriptionTo:(NSMutableString *)s depth:(NSUInteger)depth
{
    for (NSUInteger i = 0; i < depth; i++) {
        [s appendString:@"  "];
    }
    if (self.kind == XFHostNodeKindText) {
        [s appendFormat:@"text:\"%@\"\n", self.text];
        return;
    }
    [s appendFormat:@"%@:%@", [self kindName], self.tag];
    if (self.title.length) {
        [s appendFormat:@" title=\"%@\"", self.title];
    }
    [s appendString:@"\n"];
    for (XFHostNode *c in self.children) {
        [c appendDescriptionTo:s depth:depth + 1];
    }
}

- (NSString *)treeDescription
{
    NSMutableString *s = [NSMutableString string];
    [self appendDescriptionTo:s depth:0];
    return s;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<XFHostNode %@:%@ %lu children>",
            [self kindName], self.tag, (unsigned long)self.children.count];
}

@end
