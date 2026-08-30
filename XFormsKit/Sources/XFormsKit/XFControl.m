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
#import "XFVarControl.h"
#import "XFDialog.h"
#import "XFUploadControl.h"
#import "XFNodeState.h"
#import "XFModel.h"
#import "XFProcessor.h"
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
/// The label as parts: NSString literals and XFBinding for nested
/// xf:output elements / the label's own ref|value|bind (G-23).
@property (nonatomic, copy) NSArray *labelParts;
@property (nonatomic, assign) BOOL labelIsDynamic;
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
        _delay = [[[element attributeForName:@"delay"] stringValue] doubleValue] / 1000.0;
        [self loadHostAttributes];
        _mipEvents = @[];
        [self loadSupportChildren];
    }
    return self;
}

- (XFBinding *)bindingFromChild:(NSString *)name
{
    NSXMLElement *el = [XFXML childElementWithLocalName:name
                                          namespaceURI:XFXFormsNamespaceURI
                                             ofElement:self.element];
    if (el == nil) {
        return nil;
    }
    NSString *expr = [[el attributeForName:@"ref"] stringValue]
        ?: [[el attributeForName:@"value"] stringValue];
    if (expr.length == 0) {
        return nil;
    }
    return [XFBinding bindingWithExpression:expr element:el error:NULL];
}

- (NSString *)literalFromChild:(NSString *)name
{
    NSXMLElement *el = [XFXML childElementWithLocalName:name
                                          namespaceURI:XFXFormsNamespaceURI
                                             ofElement:self.element];
    if (el == nil) {
        return nil;
    }
    if ([el attributeForName:@"ref"] || [el attributeForName:@"value"]) {
        return nil;
    }
    NSString *s = [XFXML stringValueOfNode:el];
    return s.length ? s : nil;
}

/// XsltForms_label: a label with ref/value/bind is a bound element
/// refreshed with the control; inline markup is text and nested
/// xf:output elements are evaluated in place (label.xsl) (G-23).
- (void)loadLabelParts
{
    self.labelParts = nil;
    self.labelIsDynamic = NO;
    NSXMLElement *el = [XFXML childElementWithLocalName:@"label"
                                          namespaceURI:XFXFormsNamespaceURI
                                             ofElement:self.element];
    if (el == nil) {
        return;
    }
    XFBinding *own = [XFBinding bindingForElement:el attribute:@"ref" error:NULL];
    if (own == nil && [el attributeForName:@"value"]) {
        own = [XFBinding bindingForElement:el attribute:@"value" error:NULL];
    }
    if (own) {
        self.labelParts = @[ own ];
        self.labelIsDynamic = YES;
        return;
    }
    NSMutableArray *parts = [NSMutableArray array];
    [self collectLabelPartsOf:el into:parts];
    self.labelParts = parts;
}

- (void)collectLabelPartsOf:(NSXMLElement *)el into:(NSMutableArray *)parts
{
    for (NSXMLNode *child in [el children]) {
        NSXMLNodeKind kind = [child kind];
        if (kind == NSXMLTextKind) {
            [parts addObject:[child stringValue] ?: @""];
        } else if (kind == NSXMLElementKind) {
            NSXMLElement *c = (NSXMLElement *)child;
            if ([XFXML element:c hasLocalName:@"output" namespaceURI:XFXFormsNamespaceURI]) {
                NSString *attr = [c attributeForName:@"value"] && ![c attributeForName:@"ref"] ? @"value" : @"ref";
                XFBinding *b = [XFBinding bindingForElement:c attribute:attr error:NULL];
                if (b) {
                    [parts addObject:b];
                    self.labelIsDynamic = YES;
                }
            } else {
                [self collectLabelPartsOf:c into:parts];
            }
        }
    }
}

- (XFExprContext *)childContextFrom:(XFExprContext *)ctx
{
    // XsltForms_globals.build: children evaluate against the element's
    // bound node (`element.node || ctx`) — labels, hints, items, itemsets
    if (self.boundNode && ctx.contextNode != self.boundNode) {
        XFExprContext *c = [ctx cloneWithNode:self.boundNode position:1 nodeList:@[ self.boundNode ]];
        return c;
    }
    return ctx;
}

- (NSString *)labelInContext:(XFExprContext *)ctx
{
    if (!self.labelIsDynamic) {
        return self.label;
    }
    XFExprContext *labelCtx = [self childContextFrom:ctx];
    NSMutableString *text = [NSMutableString string];
    for (id part in self.labelParts) {
        if ([part isKindOfClass:[XFBinding class]]) {
            [text appendString:[(XFBinding *)part stringValueInContext:labelCtx error:NULL] ?: @""];
        } else {
            [text appendString:part];
        }
    }
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)loadHostAttributes
{
    NSXMLElement *element = self.element;
    self.navindex = [[[element attributeForName:@"navindex"] stringValue] integerValue];
    self.accesskey = [[element attributeForName:@"accesskey"] stringValue];
    self.placeholder = [[element attributeForName:@"placeholder"] stringValue];
    self.rows = [[[element attributeForName:@"rows"] stringValue] integerValue];
    self.cols = [[[element attributeForName:@"cols"] stringValue] integerValue];
    self.inputmode = [[element attributeForName:@"inputmode"] stringValue];
    NSXMLElement *help = [XFXML childElementWithLocalName:@"help" namespaceURI:XFXFormsNamespaceURI ofElement:element];
    self.helpHref = [[help attributeForName:@"href"] stringValue];
}

/// XsltForms_input.InputMode
- (NSString *)applyInputMode:(NSString *)value
{
    NSString *mode = self.inputmode;
    if (mode.length == 0 || value == nil) {
        return value;
    }
    if ([mode isEqualToString:@"lowerCase"]) {
        return [value lowercaseString];
    }
    if ([mode isEqualToString:@"upperCase"]) {
        return [value uppercaseString];
    }
    if ([mode isEqualToString:@"titleCase"]) {
        return value.length ? [[[value substringToIndex:1] uppercaseString] stringByAppendingString:[[value substringFromIndex:1] lowercaseString]] : value;
    }
    if ([mode isEqualToString:@"digits"]) {
        return [[value componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
    }
    return value;
}

- (void)loadSupportChildren
{
    [self loadLabelParts];
    self.hintBinding = [self bindingFromChild:@"hint"];
    self.helpBinding = [self bindingFromChild:@"help"];
    self.alertBinding = [self bindingFromChild:@"alert"];
    if (self.hint == nil) {
        self.hint = [self literalFromChild:@"hint"];
    }
    self.help = [self literalFromChild:@"help"];
    self.alert = [self literalFromChild:@"alert"];
}

- (void)refreshSupportInContext:(XFExprContext *)context
{
    if (self.labelIsDynamic) {
        self.label = [self labelInContext:context];
    }
    XFExprContext *ctx = [self childContextFrom:context];
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
    if ([self isTrigger]) {
        return;   // XsltForms_control.eventDispatch: !this.isTrigger
    }
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
    self.delay = [[[element attributeForName:@"delay"] stringValue] doubleValue] / 1000.0;
    [self loadHostAttributes];
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
                     @"group", @"repeat", @"switch", @"var", @"dialog", @"component",
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
                              @"group", @"repeat", @"switch", @"case", @"item", @"dialog", @"component",
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
    // only a direct child: a repeat/group must not borrow the label of the
    // first control nested in its markup (G-20)
    NSXMLElement *label =
        [XFXML childElementWithLocalName:@"label"
                           namespaceURI:XFXFormsNamespaceURI
                              ofElement:element];
    return label ? [XFXML stringValueOfNode:label] : nil;
}

+ (XFBinding *)bindingOnElement:(NSXMLElement *)element
              preferredAttribute:(NSString *)preferred
                          error:(NSError **)error
{
    // bind="id" wins over ref/nodeset/value (toScriptBinding.xsl), G-21
    return [XFBinding bindingForElement:element attribute:preferred error:error];
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
    if ([name isEqualToString:@"var"]) {
        return [XFVarControl varWithElement:element model:model error:error];
    }
    if ([name isEqualToString:@"group"]) {
        return [XFGroup groupWithElement:element model:model error:error];
    }
    if ([name isEqualToString:@"dialog"]) {
        return [XFDialog dialogWithElement:element model:model error:error];
    }
    if ([name isEqualToString:@"component"]) {
        return [XFComponentControl componentWithElement:element model:model error:error];
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

- (XFProcessor *)processor
{
    id owner = self.owner;
    if ([owner isKindOfClass:[XFProcessor class]]) {
        return owner;
    }
    if ([owner isKindOfClass:[XFModel class]] && [[(XFModel *)owner owner] isKindOfClass:[XFProcessor class]]) {
        return (XFProcessor *)[(XFModel *)owner owner];
    }
    return nil;
}

- (void)focus
{
    // xforms-focus default action → XsltForms_control.focus (G-24)
    XFProcessor *processor = [self processor];
    if (processor) {
        [processor focusControl:self fromUI:NO];
    } else {
        self.focused = YES;
    }
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
    // XsltForms_control.refresh reads the bound node with getValue — the
    // RAW text (an eval-typed node shows "5+5" while the XPath layer sees
    // 10); only a computed value (@value, no node) takes the XPath string
    NSString *value;
    if (node) {
        value = [XFXML stringValueOfNode:node];
    } else {
        value = [self.binding stringValueInContext:context error:&inner];
        if (inner && error) {
            *error = inner;
            return;
        }
    }
    self.stringValue = value ?: @"";
}


- (BOOL)isValueControl
{
    return YES;
}

- (BOOL)isBlockLevel
{
    return NO;
}

- (BOOL)isTrigger
{
    return NO;
}

- (void)refreshInContext:(XFExprContext *)context error:(NSError **)error
{
    // subform content evaluates against the subform's own model (G-90)
    XFProcessor *processor = [self processor];
    if (processor) {
        context = [processor contextForControl:self inherited:context];
    }
    self.inScopeContextNode = context.contextNode;
    [self refreshWithContext:context error:error];
    // label/hint/help/alert bindings follow the control (every subclass)
    [self refreshSupportInContext:context];
    if (![self isValueControl]) {
        return;
    }
    // XsltForms_control.refresh: changed = value !== currentValue; the event
    // is not sent when the control was rebound to another node (nodeChanged)
    NSString *value = self.stringValue ?: @"";
    BOOL known = self.currentValue != nil;
    BOOL nodeChanged = known && self.currentNode != self.boundNode;
    BOOL changed = known && ![value isEqualToString:self.currentValue];
    self.currentValue = value;
    self.currentNode = self.boundNode;
    if (changed && !nodeChanged && [self modelIsReady]) {
        [XFXMLEvents dispatch:self name:@"xforms-value-changed"];
    }
}

@end
