#import "XFSelectControl.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFXPathValue.h"
#import "XFXML.h"
#import "XFNamespaces.h"
#import "XFXMLEvents.h"
#import "XFModel.h"
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLNode.h>
#import <Foundation/NSXMLDocument.h>

typedef NS_ENUM(NSInteger, XFSelectTemplateKind) {
    XFSelectTemplateItem = 0,
    XFSelectTemplateItemset,
    XFSelectTemplateChoices
};

@interface XFSelectTemplate : NSObject
@property (nonatomic, assign) XFSelectTemplateKind kind;
@property (nonatomic, copy, nullable) NSString *groupLabel;
@property (nonatomic, strong, nullable) XFBinding *nodeset;
@property (nonatomic, strong, nullable) XFBinding *labelBinding;
@property (nonatomic, strong, nullable) XFBinding *valueBinding;
@property (nonatomic, strong, nullable) XFBinding *copiedBinding;
@property (nonatomic, copy, nullable) NSString *labelLiteral;
@property (nonatomic, copy, nullable) NSString *valueLiteral;
@property (nonatomic, copy) NSArray<XFSelectTemplate *> *children;
@end

@implementation XFSelectTemplate
@end

@implementation XFItem
- (BOOL)usesCopy { return self.copiedNode != nil; }
@end

@interface XFSelectControl ()
@property (nonatomic, copy, readwrite) NSArray<XFItem *> *items;
@property (nonatomic, copy) NSArray<XFSelectTemplate *> *templates;
@property (nonatomic, assign, readwrite) BOOL usesCopy;
@end

@implementation XFSelectControl

- (BOOL)isBlockLevel
{
    // full appearance = a list of check boxes / radio buttons (XSLTForms
    // renders it as a block of <span>s per item)
    return self.multiple || [self.appearance isEqualToString:@"full"];
}

static XFBinding *XFChildBinding(NSXMLElement *parent, NSString *local, NSError **error)
{
    NSXMLElement *el = [XFXML firstElementWithLocalName:local
                                          namespaceURI:XFXFormsNamespaceURI
                                                inNode:parent];
    if (el == nil) {
        return nil;
    }
    NSString *expr = [[el attributeForName:@"ref"] stringValue]
        ?: [[el attributeForName:@"value"] stringValue];
    if (expr.length == 0) {
        return nil;
    }
    return [XFBinding bindingWithExpression:expr element:el error:error];
}

static NSString *XFChildLiteral(NSXMLElement *parent, NSString *local)
{
    NSXMLElement *el = [XFXML firstElementWithLocalName:local
                                          namespaceURI:XFXFormsNamespaceURI
                                                inNode:parent];
    if (el == nil) {
        return nil;
    }
    if ([el attributeForName:@"ref"] || [el attributeForName:@"value"]) {
        return nil;
    }
    NSString *s = [XFXML stringValueOfNode:el];
    return s.length ? s : nil;
}

+ (XFSelectTemplate *)templateFromElement:(NSXMLElement *)element
                               groupLabel:(NSString *)groupLabel
                                    error:(NSError **)error
{
    XFSelectTemplate *t = [[XFSelectTemplate alloc] init];
    t.groupLabel = groupLabel;
    NSError *inner = nil;
    if ([XFXML element:element hasLocalName:@"item" namespaceURI:XFXFormsNamespaceURI]) {
        t.kind = XFSelectTemplateItem;
        t.labelBinding = XFChildBinding(element, @"label", &inner);
        t.valueBinding = XFChildBinding(element, @"value", &inner);
        t.copiedBinding = XFChildBinding(element, @"copy", &inner);
        t.labelLiteral = XFChildLiteral(element, @"label");
        t.valueLiteral = XFChildLiteral(element, @"value");
    } else if ([XFXML element:element hasLocalName:@"itemset" namespaceURI:XFXFormsNamespaceURI]) {
        t.kind = XFSelectTemplateItemset;
        NSString *ns = [[element attributeForName:@"nodeset"] stringValue]
            ?: [[element attributeForName:@"ref"] stringValue];
        if (ns.length) {
            t.nodeset = [XFBinding bindingWithExpression:ns element:element error:&inner];
            if (t.nodeset == nil) {
                if (error) { *error = inner; }
                return nil;
            }
        }
        t.labelBinding = XFChildBinding(element, @"label", &inner);
        t.valueBinding = XFChildBinding(element, @"value", &inner);
        t.copiedBinding = XFChildBinding(element, @"copy", &inner);
        t.labelLiteral = XFChildLiteral(element, @"label");
        t.valueLiteral = XFChildLiteral(element, @"value");
    } else if ([XFXML element:element hasLocalName:@"choices" namespaceURI:XFXFormsNamespaceURI]) {
        t.kind = XFSelectTemplateChoices;
        t.labelLiteral = [XFControl labelForElement:element] ?: XFChildLiteral(element, @"label");
        NSMutableArray *kids = [NSMutableArray array];
        for (NSXMLNode *child in [element children]) {
            if ([child kind] != NSXMLElementKind) continue;
            NSXMLElement *el = (NSXMLElement *)child;
            if ([XFXML element:el hasLocalName:@"label" namespaceURI:XFXFormsNamespaceURI]) {
                continue;
            }
            XFSelectTemplate *kid = [self templateFromElement:el
                                                   groupLabel:t.labelLiteral
                                                        error:&inner];
            if (inner) {
                if (error) { *error = inner; }
                return nil;
            }
            if (kid) {
                [kids addObject:kid];
            }
        }
        t.children = kids;
    } else {
        return nil;
    }
    if (inner) {
        if (error) { *error = inner; }
        return nil;
    }
    return t;
}

+ (instancetype)selectWithElement:(NSXMLElement *)element
                            model:(id)model
                            error:(NSError **)error
{
    NSError *inner = nil;
    XFBinding *binding = [XFControl bindingOnElement:element preferredAttribute:@"ref" error:&inner];
    if (inner) {
        if (error) { *error = inner; }
        return nil;
    }
    XFSelectControl *select = [[self alloc] initWithElement:element
                                                    binding:binding
                                                      label:[XFControl labelForElement:element]];
    select.owner = model;
    select.multiple = [[element localName] isEqualToString:@"select"];
    NSMutableArray *templates = [NSMutableArray array];
    for (NSXMLNode *child in [element children]) {
        if ([child kind] != NSXMLElementKind) continue;
        NSXMLElement *el = (NSXMLElement *)child;
        if ([XFXML element:el hasLocalName:@"label" namespaceURI:XFXFormsNamespaceURI]
            || [XFXML element:el hasLocalName:@"hint" namespaceURI:XFXFormsNamespaceURI]
            || [XFXML element:el hasLocalName:@"help" namespaceURI:XFXFormsNamespaceURI]
            || [XFXML element:el hasLocalName:@"alert" namespaceURI:XFXFormsNamespaceURI]) {
            continue;
        }
        XFSelectTemplate *t = [self templateFromElement:el groupLabel:nil error:&inner];
        if (inner) {
            if (error) { *error = inner; }
            return nil;
        }
        if (t) {
            [templates addObject:t];
        }
    }
    select.templates = templates;
    select.items = @[];
    return select;
}

- (void)emitItemFromTemplate:(XFSelectTemplate *)t
                     context:(XFExprContext *)context
                      source:(NSXMLNode *)source
                       into:(NSMutableArray<XFItem *> *)out
{
    XFItem *item = [[XFItem alloc] init];
    item.groupLabel = t.groupLabel;
    item.sourceNode = source;
    if (t.labelBinding) {
        item.label = [t.labelBinding stringValueInContext:context error:NULL] ?: @"";
    } else if (t.labelLiteral.length) {
        item.label = t.labelLiteral;
    } else if (source) {
        item.label = [XFXML stringValueOfNode:source];
    } else {
        item.label = @"";
    }
    if (t.copiedBinding) {
        item.copiedNode = [t.copiedBinding boundNodeInContext:context error:NULL];
        if (item.copiedNode == nil) {
            XFXPathValue *v = [t.copiedBinding evaluateInContext:context error:NULL];
            item.copiedNode = v.firstNode;
        }
        item.value = item.copiedNode ? [item.copiedNode XMLString] : item.label;
        self.usesCopy = YES;
    } else if (t.valueBinding) {
        item.value = [t.valueBinding stringValueInContext:context error:NULL] ?: @"";
    } else if (t.valueLiteral.length) {
        item.value = t.valueLiteral;
    } else {
        item.value = item.label;
    }
    [out addObject:item];
}

- (void)expandTemplate:(XFSelectTemplate *)t
               context:(XFExprContext *)context
                 error:(NSError **)error
                  into:(NSMutableArray<XFItem *> *)out
{
    if (t.kind == XFSelectTemplateChoices) {
        for (XFSelectTemplate *kid in t.children) {
            [self expandTemplate:kid context:context error:error into:out];
        }
        return;
    }
    if (t.kind == XFSelectTemplateItem) {
        [self emitItemFromTemplate:t context:context source:context.contextNode into:out];
        return;
    }
    if (t.nodeset == nil) {
        return;
    }
    NSArray<NSXMLNode *> *nodes = [t.nodeset evaluateInContext:context error:error].nodes ?: @[];
    NSUInteger i = 1;
    for (NSXMLNode *node in nodes) {
        XFExprContext *itemCtx = [context cloneWithNode:node position:i nodeList:nodes];
        [self emitItemFromTemplate:t context:itemCtx source:node into:out];
        i++;
    }
}

- (void)rebuildItemsWithContext:(XFExprContext *)context error:(NSError **)error
{
    self.usesCopy = NO;
    NSMutableArray<XFItem *> *out = [NSMutableArray array];
    for (XFSelectTemplate *t in self.templates) {
        [self expandTemplate:t context:context error:error into:out];
    }
    self.items = out;
    [self markSelected];
}

- (NSString *)xmlOfNode:(NSXMLNode *)node
{
    if ([node kind] == NSXMLElementKind) {
        return [(NSXMLElement *)node XMLString];
    }
    return [node XMLString] ?: [XFXML stringValueOfNode:node];
}

- (BOOL)copyMatches:(NSXMLNode *)a other:(NSXMLNode *)b
{
    if (a == nil || b == nil) {
        return NO;
    }
    if ([a kind] == NSXMLElementKind && [b kind] == NSXMLElementKind) {
        NSXMLElement *ea = (NSXMLElement *)a;
        NSXMLElement *eb = (NSXMLElement *)b;
        if (![[ea localName] isEqualToString:[eb localName]]) {
            return NO;
        }
        return [[XFXML stringValueOfNode:ea] isEqualToString:[XFXML stringValueOfNode:eb]];
    }
    return [[self xmlOfNode:a] isEqualToString:[self xmlOfNode:b]];
}

- (void)markSelected
{
    NSArray *wanted = @[];
    if (!self.usesCopy) {
        if (self.multiple) {
            wanted = self.stringValue.length
                ? [self.stringValue componentsSeparatedByCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]]
                : @[];
        } else if (self.stringValue) {
            wanted = @[ self.stringValue ];
        }
    }
    NSMutableArray *sel = [NSMutableArray array];
    NSArray *boundChildren = nil;
    if (self.usesCopy && [self.boundNode kind] == NSXMLElementKind) {
        NSMutableArray *kids = [NSMutableArray array];
        for (NSXMLNode *c in [(NSXMLElement *)self.boundNode children]) {
            if ([c kind] == NSXMLElementKind) {
                [kids addObject:c];
            }
        }
        boundChildren = kids;
    }
    for (XFItem *item in self.items) {
        if (item.usesCopy) {
            BOOL hit = NO;
            for (NSXMLNode *c in boundChildren) {
                if ([self copyMatches:item.copiedNode other:c]) {
                    hit = YES;
                    break;
                }
            }
            item.selected = hit;
        } else {
            item.selected = item.value && [wanted containsObject:item.value];
        }
        if (item.selected && item.value) {
            [sel addObject:item.value];
        }
    }
    self.selectedValues = sel;
}

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    [super refreshWithContext:context error:error];
    [self rebuildItemsWithContext:context error:error];
}

- (NSString *)joinedSelection
{
    if (!self.multiple) {
        return self.selectedValues.firstObject ?: @"";
    }
    return [self.selectedValues componentsJoinedByString:@" "];
}

- (void)notifyModel
{
    id owner = self.owner;
    if ([owner isKindOfClass:[XFModel class]] && self.boundNode) {
        [(XFModel *)owner addChange:self.boundNode];
    }
}

- (BOOL)writeSelection:(NSArray<XFItem *> *)selected error:(NSError **)error
{
    NSMutableArray *vals = [NSMutableArray array];
    NSMutableArray *copies = [NSMutableArray array];
    BOOL anyCopy = NO;
    for (XFItem *item in selected) {
        if (item.value) {
            [vals addObject:item.value];
        }
        if (item.copiedNode) {
            anyCopy = YES;
            [copies addObject:item.copiedNode];
        }
    }
    self.selectedValues = vals;
    if (anyCopy) {
        if (self.boundNode == nil || [self.boundNode kind] != NSXMLElementKind) {
            if (error) {
                *error = [NSError errorWithDomain:@"XFormsKit"
                                             code:2
                                         userInfo:@{ NSLocalizedDescriptionKey:
                                                         @"xf:copy requires an element bound node" }];
            }
            return NO;
        }
        NSXMLElement *el = (NSXMLElement *)self.boundNode;
        NSArray *children = [[el children] copy];
        for (NSXMLNode *c in children) {
            [el removeChildAtIndex:[c index]];
        }
        for (NSXMLNode *src in copies) {
            NSXMLNode *clone = [src copy];
            [el addChild:clone];
        }
        self.stringValue = [self joinedSelection];
        [self notifyModel];
        return YES;
    }
    NSString *joined = [self joinedSelection];
    if (![self commitStringValue:joined error:error]) {
        return NO;
    }
    [self notifyModel];
    return YES;
}

- (NSArray<XFItem *> *)selectedItems
{
    NSMutableArray *out = [NSMutableArray array];
    for (XFItem *item in self.items) {
        if (item.selected) {
            [out addObject:item];
        }
    }
    return out;
}

- (XFItem *)itemWithValue:(NSString *)value
{
    for (XFItem *item in self.items) {
        if (value && [item.value isEqualToString:value]) {
            return item;
        }
        if (value && [item.label isEqualToString:value]) {
            return item;
        }
    }
    return nil;
}

- (BOOL)selectItem:(XFItem *)item
{
    if (item == nil) {
        return NO;
    }
    NSArray *selected;
    if (self.multiple) {
        NSMutableArray *cur = [[self selectedItems] mutableCopy];
        if (![cur containsObject:item]) {
            [cur addObject:item];
        }
        selected = cur;
    } else {
        selected = @[ item ];
    }
    if (![self writeSelection:selected error:NULL]) {
        return NO;
    }
    [self markSelected];
    [XFXMLEvents dispatch:self name:@"xforms-select"];
    return YES;
}

- (BOOL)toggleItem:(XFItem *)item
{
    if (item == nil) {
        return NO;
    }
    if (!self.multiple) {
        return [self selectItem:item];
    }
    NSMutableArray *cur = [[self selectedItems] mutableCopy];
    if ([cur containsObject:item]) {
        [cur removeObject:item];
        [XFXMLEvents dispatch:self name:@"xforms-deselect"];
    } else {
        [cur addObject:item];
        [XFXMLEvents dispatch:self name:@"xforms-select"];
    }
    if (![self writeSelection:cur error:NULL]) {
        return NO;
    }
    [self markSelected];
    return YES;
}

- (BOOL)selectValue:(NSString *)value
{
    XFItem *item = [self itemWithValue:value];
    if (item == nil) {
        if (self.multiple) {
            NSMutableArray *sel = [self.selectedValues mutableCopy] ?: [NSMutableArray array];
            if (value && ![sel containsObject:value]) {
                [sel addObject:value];
            }
            self.selectedValues = sel;
        } else {
            self.selectedValues = value ? @[ value ] : @[];
        }
        BOOL ok = [self commitStringValue:[self joinedSelection] error:NULL];
        [self markSelected];
        if (ok) {
            [XFXMLEvents dispatch:self name:@"xforms-select"];
        }
        return ok;
    }
    return [self selectItem:item];
}

- (BOOL)toggleValue:(NSString *)value
{
    XFItem *item = [self itemWithValue:value];
    if (item == nil) {
        return [self selectValue:value];
    }
    return [self toggleItem:item];
}

@end
