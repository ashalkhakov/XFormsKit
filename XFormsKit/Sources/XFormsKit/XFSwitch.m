#import "XFSwitch.h"
#import "XFXML.h"
#import "XFNamespaces.h"
#import "XFXMLEvents.h"
#import "XFExprContext.h"
#import "XFBinding.h"
#import "XFDeferredUpdates.h"
#import "XFModel.h"
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

- (instancetype)initWithElement:(XFXMLElement *)element
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
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du pushVariableScope];
    for (XFControl *child in self.mutableChildren) {
        [child refreshInContext:context error:error];
    }
    [du popVariableScope];
}

@end

@interface XFSwitch ()
@property (nonatomic, strong) NSMutableArray<XFCase *> *mutableCases;
@property (nonatomic, weak, readwrite) XFCase *selectedCase;
@property (nonatomic, strong, readwrite) XFBinding *caserefBinding;
@property (nonatomic, strong) XFXMLNode *caserefNode;
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

+ (instancetype)switchWithElement:(XFXMLElement *)element
                            model:(id)model
                            error:(NSError **)error
{
    // switch.xsl: a switch is an XsltForms_group with an optional binding
    // (context + relevance for its cases) and a caseref binding (G-26)
    NSError *inner = nil;
    XFBinding *binding = [XFControl bindingOnElement:element preferredAttribute:@"ref" error:&inner];
    if (inner) {
        if (error) {
            *error = inner;
        }
        return nil;
    }
    XFSwitch *sw = [[self alloc] initWithElement:element binding:binding label:[XFControl labelForElement:element]];
    sw.owner = model;
    NSString *caseref = [[element attributeForName:@"caseref"] stringValue];
    if (caseref.length) {
        sw.caserefBinding = [XFBinding bindingWithExpression:caseref element:element error:&inner];
        if (sw.caserefBinding == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
    }
    sw.mutableCases = [NSMutableArray array];
    for (XFXMLNode *child in [element children]) {
        if ([child kind] != XFXMLElementKind) {
            continue;
        }
        XFXMLElement *el = (XFXMLElement *)child;
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
    [self selectCase:caze writeCaseref:YES];
}

/// XsltForms_toggle.toggle: one action; every other case gets
/// xforms-deselect, the target xforms-select.
- (void)selectCase:(XFCase *)caze writeCaseref:(BOOL)write
{
    if (caze == nil) {
        return;
    }
    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"toggle"];
    for (XFCase *c in self.mutableCases) {
        if (c != caze) {
            c.selected = NO;
            [XFXMLEvents dispatch:c name:@"xforms-deselect"];
        }
    }
    caze.selected = YES;
    self.selectedCase = caze;
    // XForms 2.0 caseref: toggling writes the case id back to the node
    if (write && self.caserefBinding && self.caserefNode && caze.identifier.length
        && ![[XFXML stringValueOfNode:self.caserefNode] isEqualToString:caze.identifier]) {
        [XFXML setStringValue:caze.identifier ofNode:self.caserefNode];
        id owner = self.owner;
        XFModel *model = [owner isKindOfClass:[XFModel class]] ? owner : [owner model];
        [model addChange:self.caserefNode];
        [du addChangedModel:model];
    }
    [XFXMLEvents dispatch:caze name:@"xforms-select"];
    [du closeAction:@"toggle"];
}

- (void)dispatchInitialSelect
{
    if (self.caserefBinding == nil && self.selectedCase) {
        [XFXMLEvents dispatch:self.selectedCase name:@"xforms-select"];
    }
}

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    XFExprContext *childCtx = context;
    if (self.binding) {
        NSError *inner = nil;
        XFXMLNode *node = [self.binding boundNodeInContext:context error:&inner];
        if (inner) {
            if (error) {
                *error = inner;
            }
            return;
        }
        self.boundNode = node;
        [self applyMIPsFromNode:node];
        if (node) {
            childCtx = [context cloneWithNode:node position:1 nodeList:@[ node ]];
        }
    } else {
        self.relevant = YES;
    }
    if (self.caserefBinding) {
        // XsltForms_group.build_: the caseref value selects the case
        self.caserefNode = [self.caserefBinding boundNodeInContext:childCtx error:NULL];
        NSString *cid = self.caserefNode ? [XFXML stringValueOfNode:self.caserefNode] : nil;
        XFCase *wanted = [self caseWithIdentifier:cid];
        if (wanted && wanted != self.selectedCase) {
            [self selectCase:wanted writeCaseref:NO];
        }
    }
    [self.selectedCase refreshInContext:childCtx error:error];
}

@end
