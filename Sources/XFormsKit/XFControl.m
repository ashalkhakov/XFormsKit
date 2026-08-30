#import "XFControl.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFXML.h"
#import "XFNamespaces.h"
#import "XFInputControl.h"
#import "XFOutputControl.h"
#import "XFGroup.h"
#import "XFRepeat.h"
#import "XFSwitch.h"
#import "XFTriggerControl.h"
#import "XFSubmitControl.h"
#import "XFSecretControl.h"
#import "XFTextareaControl.h"
#import "XFSelectControl.h"
#import "XFRangeControl.h"
#import "XFLabelControl.h"
#import "XFNodeState.h"
#import "XFModel.h"
#import "XFErrors.h"

@implementation XFControl

- (instancetype)initWithElement:(NSXMLElement *)element
                        binding:(XFBinding *)binding
                          label:(NSString *)label
{
    self = [super init];
    if (self) {
        _element = element;
        _binding = binding;
        _label = [label copy];
        _stringValue = @"";
        _relevant = YES;
        _readonly = NO;
        _required = NO;
        _valid = YES;
        _identifier = [[element attributeForName:@"id"] stringValue];
        _appearance = [[element attributeForName:@"appearance"] stringValue];
        NSXMLElement *hint =
            [XFXML firstElementWithLocalName:@"hint"
                               namespaceURI:XFXFormsNamespaceURI
                                     inNode:element];
        _hint = hint ? [XFXML stringValueOfNode:hint] : nil;
    }
    return self;
}

+ (BOOL)isControlElement:(NSXMLElement *)element
{
    static NSSet *names;
    @synchronized(self) {
        if (names == nil) {
            names = [NSSet setWithObjects:
                     @"input", @"output", @"secret", @"textarea",
                     @"trigger", @"submit", @"select", @"select1", @"range",
                     @"group", @"repeat", @"switch",
                     nil];
        }
    }
    return [XFXML element:element hasLocalName:[element localName] namespaceURI:XFXFormsNamespaceURI]
        && [names containsObject:[element localName]];
}

+ (BOOL)isStandaloneLabelElement:(NSXMLElement *)element
{
    if (![XFXML element:element hasLocalName:@"label" namespaceURI:XFXFormsNamespaceURI]) {
        return NO;
    }
    NSString *ref = [[element attributeForName:@"ref"] stringValue];
    NSString *value = [[element attributeForName:@"value"] stringValue];
    if (ref.length || value.length) {
        return YES;
    }
    NSXMLNode *parent = [element parent];
    NSString *pname = [parent kind] == NSXMLElementKind ? [(NSXMLElement *)parent localName] : @"";
    static NSSet *captionParents;
    @synchronized(self) {
        if (captionParents == nil) {
            captionParents = [NSSet setWithObjects:
                              @"input", @"output", @"secret", @"textarea",
                              @"trigger", @"submit", @"select", @"select1", @"range",
                              @"group", @"repeat", @"switch", @"case", @"item",
                              nil];
        }
    }
    return ![captionParents containsObject:pname];
}

+ (BOOL)shouldInstantiateElement:(NSXMLElement *)element
{
    return [self isControlElement:element] || [self isStandaloneLabelElement:element];
}

+ (NSString *)labelForElement:(NSXMLElement *)element
{
    NSXMLElement *label =
        [XFXML firstElementWithLocalName:@"label"
                           namespaceURI:XFXFormsNamespaceURI
                                 inNode:element];
    return label ? [XFXML stringValueOfNode:label] : nil;
}

+ (XFBinding *)bindingOnElement:(NSXMLElement *)element
              preferredAttribute:(NSString *)preferred
                          error:(NSError **)error
{
    NSString *attr = preferred;
    if (attr.length == 0 || [element attributeForName:attr] == nil) {
        if ([element attributeForName:@"nodeset"]) {
            attr = @"nodeset";
        } else if ([element attributeForName:@"ref"]) {
            attr = @"ref";
        } else if ([element attributeForName:@"value"]) {
            attr = @"value";
        } else {
            return nil;
        }
    }
    NSString *expr = [[element attributeForName:attr] stringValue];
    if (expr.length == 0) {
        return nil;
    }
    return [XFBinding bindingWithExpression:expr error:error];
}

+ (instancetype)controlWithElement:(NSXMLElement *)element
                             model:(id)model
                             error:(NSError **)error
{
    if (![self shouldInstantiateElement:element]) {
        return nil;
    }
    NSString *name = [element localName];
    if ([name isEqualToString:@"label"]) {
        return [XFLabelControl labelWithElement:element model:model error:error];
    }
    if ([name isEqualToString:@"group"]) {
        return [XFGroup groupWithElement:element model:model error:error];
    }
    if ([name isEqualToString:@"repeat"]) {
        return [XFRepeat repeatWithElement:element model:model error:error];
    }
    if ([name isEqualToString:@"switch"]) {
        return [XFSwitch switchWithElement:element model:model error:error];
    }
    if ([name isEqualToString:@"select"] || [name isEqualToString:@"select1"]) {
        return [XFSelectControl selectWithElement:element model:model error:error];
    }
    if ([name isEqualToString:@"range"]) {
        return [XFRangeControl rangeWithElement:element model:model error:error];
    }
    if ([name isEqualToString:@"trigger"]) {
        return [XFTriggerControl triggerWithElement:element model:model error:error];
    }
    if ([name isEqualToString:@"submit"]) {
        return [XFSubmitControl submitWithElement:element model:model error:error];
    }
    NSString *preferred = [name isEqualToString:@"output"] && [element attributeForName:@"value"] ? @"value" : @"ref";
    NSError *inner = nil;
    XFBinding *binding = [self bindingOnElement:element preferredAttribute:preferred error:&inner];
    if (inner) {
        if (error) {
            *error = inner;
        }
        return nil;
    }
    Class cls = [XFOutputControl class];
    if ([name isEqualToString:@"input"]) {
        cls = [XFInputControl class];
    } else if ([name isEqualToString:@"secret"]) {
        cls = [XFSecretControl class];
    } else if ([name isEqualToString:@"textarea"]) {
        cls = [XFTextareaControl class];
    }
    XFControl *control = [[cls alloc] initWithElement:element
                                              binding:binding
                                                label:[self labelForElement:element]];
    control.owner = model;
    return control;
}

- (void)applyMIPsFromBoundNode
{
    XFNodeState *state = [XFNodeState existingStateOnNode:self.boundNode];
    if (state) {
        self.relevant = state.relevant;
        self.readonly = state.readonly;
        self.required = state.required;
        self.valid = state.valid;
    } else if (self.boundNode == nil && self.binding != nil) {
        self.relevant = NO;
    }
}

- (BOOL)commitStringValue:(NSString *)value error:(NSError **)error
{
    if (self.boundNode == nil) {
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorBinding
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"control has no bound node" }];
        }
        return NO;
    }
    [XFXML setStringValue:value ?: @"" ofNode:self.boundNode];
    self.stringValue = value ?: @"";
    return YES;
}

- (void)focus
{
    self.focused = YES;
}

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    if (self.binding == nil) {
        return;
    }
    NSError *inner = nil;
    NSXMLNode *node = [self.binding boundNodeInContext:context error:&inner];
    if (inner && error) {
        *error = inner;
        return;
    }
    self.boundNode = node;
    [self applyMIPsFromBoundNode];
    NSString *value = [self.binding stringValueInContext:context error:&inner];
    if (inner && error) {
        *error = inner;
        return;
    }
    self.stringValue = value ?: @"";
}

@end
