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
#import "XFUploadControl.h"
#import "XFNodeState.h"
#import "XFModel.h"
#import "XFErrors.h"
#import "XFXMLEvents.h"
#import "XFDeferredUpdates.h"

@interface XFControl ()
@property (nonatomic, copy, readwrite) NSString *identifier;
@property (nonatomic, copy, readwrite) NSString *label;
@property (nonatomic, strong, readwrite) XFBinding *binding;
@property (nonatomic, strong) XFBinding *hintBinding;
@property (nonatomic, strong) XFBinding *helpBinding;
@property (nonatomic, strong) XFBinding *alertBinding;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *mipEvents;
@property (nonatomic, assign) BOOL mipKnown;
@end

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
        _incremental = [[[element attributeForName:@"incremental"] stringValue] isEqualToString:@"true"];
        _mipEvents = @[];
        [self loadSupportChildren];
    }
    return self;
}

- (XFBinding *)bindingFromChild:(NSString *)name
{
    NSXMLElement *el = [XFXML firstElementWithLocalName:name
                                          namespaceURI:XFXFormsNamespaceURI
                                                inNode:self.element];
    if (el == nil) {
        return nil;
    }
    NSString *expr = [[el attributeForName:@"ref"] stringValue]
        ?: [[el attributeForName:@"value"] stringValue];
    if (expr.length == 0) {
        return nil;
    }
    return [XFBinding bindingWithExpression:expr error:NULL];
}

- (NSString *)literalFromChild:(NSString *)name
{
    NSXMLElement *el = [XFXML firstElementWithLocalName:name
                                          namespaceURI:XFXFormsNamespaceURI
                                                inNode:self.element];
    if (el == nil) {
        return nil;
    }
    if ([el attributeForName:@"ref"] || [el attributeForName:@"value"]) {
        return nil;
    }
    NSString *s = [XFXML stringValueOfNode:el];
    return s.length ? s : nil;
}

- (void)loadSupportChildren
{
    self.hintBinding = [self bindingFromChild:@"hint"];
    self.helpBinding = [self bindingFromChild:@"help"];
    self.alertBinding = [self bindingFromChild:@"alert"];
    if (self.hint == nil) {
        self.hint = [self literalFromChild:@"hint"];
    }
    self.help = [self literalFromChild:@"help"];
    self.alert = [self literalFromChild:@"alert"];
}

- (void)refreshSupportInContext:(XFExprContext *)ctx
{
    if (self.hintBinding) {
        self.hint = [self.hintBinding stringValueInContext:ctx error:NULL];
    }
    if (self.helpBinding) {
        self.help = [self.helpBinding stringValueInContext:ctx error:NULL];
    }
    if (self.alertBinding) {
        self.alert = [self.alertBinding stringValueInContext:ctx error:NULL];
    }
}

- (BOOL)modelIsReady
{
    id owner = self.owner;
    if ([owner respondsToSelector:@selector(ready)]) {
        return [owner ready];
    }
    if ([owner respondsToSelector:@selector(model)]) {
        id model = [owner model];
        if ([model respondsToSelector:@selector(ready)]) {
            return [model ready];
        }
    }
    return YES;
}

- (void)recordMIP:(NSString *)name
{
    NSMutableArray *evs = [self.mipEvents mutableCopy] ?: [NSMutableArray array];
    [evs addObject:name];
    self.mipEvents = evs;
    [XFXMLEvents dispatch:self name:name];
}

- (BOOL)reconfigureFromElement:(NSError **)error
{
    NSXMLElement *element = self.element;
    if (element == nil) {
        return NO;
    }
    self.identifier = [[element attributeForName:@"id"] stringValue];
    self.appearance = [[element attributeForName:@"appearance"] stringValue];
    self.incremental = [[[element attributeForName:@"incremental"] stringValue] isEqualToString:@"true"];
    self.label = [[self class] labelForElement:element];
    [self loadSupportChildren];
    NSString *preferred = [[element localName] isEqualToString:@"output"]
        && [element attributeForName:@"value"] ? @"value" : @"ref";
    if ([element attributeForName:@"nodeset"]) {
        preferred = @"nodeset";
    }
    NSError *inner = nil;
    XFBinding *binding = [[self class] bindingOnElement:element preferredAttribute:preferred error:&inner];
    if (inner && error) {
        *error = inner;
        return NO;
    }
    self.binding = binding;
    return YES;
}

- (void)showHelp
{
    [XFXMLEvents dispatch:self name:@"xforms-help"];
}

- (void)showHint
{
    [XFXMLEvents dispatch:self name:@"xforms-hint"];
}

+ (BOOL)isControlElement:(NSXMLElement *)element
{
    static NSSet *names;
    @synchronized(self) {
        if (names == nil) {
            names = [NSSet setWithObjects:
                     @"input", @"output", @"secret", @"textarea", @"upload",
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
                              @"upload",
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
    if ([name isEqualToString:@"upload"]) {
        return [XFUploadControl uploadWithElement:element model:model error:error];
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

- (BOOL)usesValueBinding
{
    NSXMLElement *element = self.element;
    return [element attributeForName:@"value"] != nil
        && [element attributeForName:@"ref"] == nil
        && [element attributeForName:@"bind"] == nil;
}

- (void)applyMIPsFromBoundNode
{
    [self applyMIPsFromNode:self.boundNode];
}

- (void)applyMIPsFromNode:(NSXMLNode *)node
{
    XFNodeState *state = [XFNodeState existingStateOnNode:node];
    BOOL relevant = YES;
    BOOL readonly = NO;
    BOOL required = NO;
    BOOL valid = YES;
    if (state) {
        relevant = state.relevant;
        readonly = state.readonly;
        required = state.required;
        valid = state.valid;
    } else if (node == nil && self.binding != nil) {
        // A single-node binding that selects nothing makes the control
        // non-relevant (XForms 1.1 8.1.1). A `value` binding has no node of
        // its own; callers pass the in-scope evaluation context node instead.
        relevant = NO;
    }
    BOOL known = self.mipKnown;
    BOOL ready = [self modelIsReady];
    void (^flip)(BOOL *, BOOL, NSString *, NSString *) = ^(BOOL *slot, BOOL value, NSString *onT, NSString *onF) {
        BOOL old = *slot;
        *slot = value;
        if (!ready) {
            return;
        }
        if (!known || old != value) {
            [self recordMIP:value ? onT : onF];
        }
    };
    BOOL rel = self.relevant, ro = self.readonly, req = self.required, val = self.valid;
    flip(&rel, relevant, @"xforms-enabled", @"xforms-disabled");
    flip(&ro, readonly, @"xforms-readonly", @"xforms-readwrite");
    flip(&req, required, @"xforms-required", @"xforms-optional");
    flip(&val, valid, @"xforms-valid", @"xforms-invalid");
    self.relevant = rel;
    self.readonly = ro;
    self.required = req;
    self.valid = val;
    if (ready) {
        self.mipKnown = YES;
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
    [self refreshSupportInContext:context];
}

@end
