#import "XFSelectControl.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFXPathValue.h"
#import "XFXML.h"
#import "XFNamespaces.h"
#import "XFXMLEvents.h"

@interface XFItemsetTemplate : NSObject
@property (nonatomic, strong) XFBinding *nodeset;
@property (nonatomic, strong, nullable) XFBinding *labelBinding;
@property (nonatomic, strong, nullable) XFBinding *valueBinding;
@property (nonatomic, copy, nullable) NSString *labelLiteral;
@property (nonatomic, copy, nullable) NSString *valueLiteral;
@end

@implementation XFItemsetTemplate
@end

@implementation XFItem
@end

@interface XFSelectControl ()
@property (nonatomic, copy, readwrite) NSArray<XFItem *> *items;
@property (nonatomic, copy) NSArray<XFItem *> *staticItems;
@property (nonatomic, copy) NSArray<XFItemsetTemplate *> *itemsets;
@end

@implementation XFSelectControl

+ (XFItem *)itemFromElement:(NSXMLElement *)element error:(NSError **)error
{
    XFItem *item = [[XFItem alloc] init];
    NSXMLElement *labelEl = [XFXML firstElementWithLocalName:@"label"
                                               namespaceURI:XFXFormsNamespaceURI
                                                     inNode:element];
    NSXMLElement *valueEl = [XFXML firstElementWithLocalName:@"value"
                                               namespaceURI:XFXFormsNamespaceURI
                                                     inNode:element];
    item.label = labelEl ? [XFXML stringValueOfNode:labelEl] : @"";
    item.value = valueEl ? [XFXML stringValueOfNode:valueEl] : item.label;
    (void)error;
    return item;
}

+ (instancetype)selectWithElement:(NSXMLElement *)element
                            model:(id)model
                            error:(NSError **)error
{
    NSError *inner = nil;
    XFBinding *binding = [XFControl bindingOnElement:element preferredAttribute:@"ref" error:&inner];
    if (inner) {
        if (error) {
            *error = inner;
        }
        return nil;
    }
    XFSelectControl *select = [[self alloc] initWithElement:element
                                                    binding:binding
                                                      label:[XFControl labelForElement:element]];
    select.owner = model;
    select.multiple = [[element localName] isEqualToString:@"select"];
    NSMutableArray *statics = [NSMutableArray array];
    NSMutableArray *sets = [NSMutableArray array];
    for (NSXMLNode *child in [element children]) {
        if ([child kind] != NSXMLElementKind) {
            continue;
        }
        NSXMLElement *el = (NSXMLElement *)child;
        if ([XFXML element:el hasLocalName:@"item" namespaceURI:XFXFormsNamespaceURI]) {
            [statics addObject:[self itemFromElement:el error:&inner]];
        } else if ([XFXML element:el hasLocalName:@"itemset" namespaceURI:XFXFormsNamespaceURI]) {
            XFItemsetTemplate *t = [[XFItemsetTemplate alloc] init];
            NSString *ns = [[el attributeForName:@"nodeset"] stringValue]
                ?: [[el attributeForName:@"ref"] stringValue];
            if (ns.length) {
                t.nodeset = [XFBinding bindingWithExpression:ns error:&inner];
                if (t.nodeset == nil) {
                    if (error) {
                        *error = inner;
                    }
                    return nil;
                }
            }
            NSXMLElement *labelEl = [XFXML firstElementWithLocalName:@"label"
                                                       namespaceURI:XFXFormsNamespaceURI
                                                             inNode:el];
            NSXMLElement *valueEl = [XFXML firstElementWithLocalName:@"value"
                                                       namespaceURI:XFXFormsNamespaceURI
                                                             inNode:el];
            NSString *lref = labelEl ? [[labelEl attributeForName:@"ref"] stringValue] : nil;
            NSString *vref = valueEl ? [[valueEl attributeForName:@"ref"] stringValue] : nil;
            if (lref.length) {
                t.labelBinding = [XFBinding bindingWithExpression:lref error:&inner];
            } else {
                t.labelLiteral = labelEl ? [XFXML stringValueOfNode:labelEl] : nil;
            }
            if (vref.length) {
                t.valueBinding = [XFBinding bindingWithExpression:vref error:&inner];
            } else {
                t.valueLiteral = valueEl ? [XFXML stringValueOfNode:valueEl] : nil;
            }
            [sets addObject:t];
        }
    }
    select.staticItems = statics;
    select.itemsets = sets;
    select.items = statics;
    return select;
}

- (void)rebuildItemsWithContext:(XFExprContext *)context error:(NSError **)error
{
    NSMutableArray<XFItem *> *out = [NSMutableArray arrayWithArray:self.staticItems];
    for (XFItemsetTemplate *t in self.itemsets) {
        if (t.nodeset == nil) {
            continue;
        }
        NSArray<NSXMLNode *> *nodes = [t.nodeset evaluateInContext:context error:error].nodes ?: @[];
        NSUInteger i = 1;
        for (NSXMLNode *node in nodes) {
            XFExprContext *itemCtx = [context cloneWithNode:node position:i nodeList:nodes];
            XFItem *item = [[XFItem alloc] init];
            if (t.labelBinding) {
                item.label = [t.labelBinding stringValueInContext:itemCtx error:NULL] ?: @"";
            } else {
                item.label = t.labelLiteral ?: [XFXML stringValueOfNode:node];
            }
            if (t.valueBinding) {
                item.value = [t.valueBinding stringValueInContext:itemCtx error:NULL] ?: @"";
            } else if (t.valueLiteral.length) {
                item.value = t.valueLiteral;
            } else {
                item.value = item.label;
            }
            [out addObject:item];
            i++;
        }
    }
    self.items = out;
    [self markSelectedFromString:self.stringValue];
}

- (void)markSelectedFromString:(NSString *)value
{
    NSArray *wanted = @[];
    if (self.multiple) {
        wanted = [value length] ? [value componentsSeparatedByCharactersInSet:
                                   [NSCharacterSet characterSetWithCharactersInString:@" \t\n"]]
                                : @[];
    } else if (value) {
        wanted = @[ value ];
    }
    NSMutableArray *sel = [NSMutableArray array];
    for (XFItem *item in self.items) {
        item.selected = [wanted containsObject:item.value];
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

- (BOOL)selectValue:(NSString *)value
{
    if (self.multiple) {
        NSMutableArray *sel = [self.selectedValues mutableCopy] ?: [NSMutableArray array];
        if (![sel containsObject:value]) {
            [sel addObject:value];
        }
        self.selectedValues = sel;
    } else {
        self.selectedValues = value ? @[ value ] : @[];
    }
    NSString *joined = [self joinedSelection];
    if (![self commitStringValue:joined error:NULL]) {
        return NO;
    }
    [self markSelectedFromString:joined];
    [XFXMLEvents dispatch:self name:@"xforms-select"];
    return YES;
}

- (BOOL)toggleValue:(NSString *)value
{
    if (!self.multiple) {
        return [self selectValue:value];
    }
    NSMutableArray *sel = [self.selectedValues mutableCopy] ?: [NSMutableArray array];
    if ([sel containsObject:value]) {
        [sel removeObject:value];
        [XFXMLEvents dispatch:self name:@"xforms-deselect"];
    } else {
        [sel addObject:value];
        [XFXMLEvents dispatch:self name:@"xforms-select"];
    }
    self.selectedValues = sel;
    NSString *joined = [self joinedSelection];
    if (![self commitStringValue:joined error:NULL]) {
        return NO;
    }
    [self markSelectedFromString:joined];
    return YES;
}

@end
