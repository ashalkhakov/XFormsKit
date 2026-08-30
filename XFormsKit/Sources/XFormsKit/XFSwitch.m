#import "XFSwitch.h"
#import "XFXML.h"
#import "XFNamespaces.h"
#import "XFXMLEvents.h"
#import "XFExprContext.h"
#import "XFHostNode.h"

@interface XFCase ()
@property (nonatomic, strong) NSMutableArray<XFControl *> *mutableChildren;
@property (nonatomic, copy, readwrite) NSArray<XFHostNode *> *hostNodes;
@end

@implementation XFCase

- (BOOL)isValueControl
{
    return NO;
}

- (BOOL)isBlockLevel
{
    return YES;
}

- (instancetype)initWithElement:(NSXMLElement *)element
                        binding:(XFBinding *)binding
                          label:(NSString *)label
{
    self = [super initWithElement:element binding:binding label:label];
    if (self) {
        _mutableChildren = [NSMutableArray array];
        NSString *sel = [[element attributeForName:@"selected"] stringValue];
        _selected = [sel isEqualToString:@"true"] || [sel isEqualToString:@"1"];
    }
    return self;
}

- (NSArray<XFControl *> *)children
{
    return [self.mutableChildren copy];
}

- (void)addChild:(XFControl *)child
{
    if (child == nil) {
        return;
    }
    child.parentControl = self;
    [self.mutableChildren addObject:child];
}

- (void)removeChild:(XFControl *)child
{
    [self.mutableChildren removeObject:child];
    if (child.parentControl == self) {
        child.parentControl = nil;
    }
}

- (BOOL)rebuildHostNodesWithError:(NSError **)error
{
    NSMutableArray<XFControl *> *found = [NSMutableArray array];
    NSArray *nodes = [XFHostNode hostNodesForChildrenOf:self.element
                                                  model:self.owner
                                               controls:found
                                               existing:[XFHostNode controlMapFor:self.mutableChildren]
                                                  error:error];
    if (nodes == nil) {
        return NO;
    }
    NSMutableArray *children = [NSMutableArray array];
    for (XFControl *control in found) {
        control.parentControl = self;
        if (control.owner == nil) {
            control.owner = self.owner;
        }
        [children addObject:control];
    }
    self.mutableChildren = children;
    self.hostNodes = nodes;
    return YES;
}

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    if (!self.selected) {
        return;
    }
    for (XFControl *child in self.mutableChildren) {
        [child refreshInContext:context error:error];
    }
}

@end

@interface XFSwitch ()
@property (nonatomic, strong) NSMutableArray<XFCase *> *mutableCases;
@property (nonatomic, weak, readwrite) XFCase *selectedCase;
@end

@implementation XFSwitch

- (BOOL)isValueControl
{
    return NO;
}

- (BOOL)isBlockLevel
{
    return YES;
}

+ (instancetype)switchWithElement:(NSXMLElement *)element
                            model:(id)model
                            error:(NSError **)error
{
    XFSwitch *sw = [[self alloc] initWithElement:element binding:nil label:[XFControl labelForElement:element]];
    sw.owner = model;
    sw.mutableCases = [NSMutableArray array];
    for (NSXMLNode *child in [element children]) {
        if ([child kind] != NSXMLElementKind) {
            continue;
        }
        NSXMLElement *el = (NSXMLElement *)child;
        if (![XFXML element:el hasLocalName:@"case" namespaceURI:XFXFormsNamespaceURI]) {
            continue;
        }
        XFCase *caze = [[XFCase alloc] initWithElement:el binding:nil label:[XFControl labelForElement:el]];
        caze.owner = model;
        caze.parentControl = sw;
        // case.xsl copies host markup: controls at any depth (G-20)
        if (![caze rebuildHostNodesWithError:error]) {
            return nil;
        }
        [sw.mutableCases addObject:caze];
    }
    XFCase *selected = nil;
    for (XFCase *c in sw.mutableCases) {
        if (c.selected) {
            selected = c;
            break;
        }
    }
    if (selected == nil) {
        selected = sw.mutableCases.firstObject;
    }
    for (XFCase *c in sw.mutableCases) {
        c.selected = (c == selected);
    }
    sw.selectedCase = selected;
    return sw;
}

- (NSArray<XFCase *> *)cases
{
    return [self.mutableCases copy];
}

- (XFCase *)caseWithIdentifier:(NSString *)identifier
{
    if (identifier.length == 0) {
        return nil;
    }
    for (XFCase *c in self.mutableCases) {
        if ([c.identifier isEqualToString:identifier]) {
            return c;
        }
    }
    return nil;
}

- (void)selectCase:(XFCase *)caze
{
    if (caze == nil || caze == self.selectedCase) {
        return;
    }
    XFCase *previous = self.selectedCase;
    if (previous) {
        previous.selected = NO;
        [XFXMLEvents dispatch:previous name:@"xforms-deselect"];
    }
    caze.selected = YES;
    self.selectedCase = caze;
    [XFXMLEvents dispatch:caze name:@"xforms-select"];
}

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    [self.selectedCase refreshInContext:context error:error];
}

@end
