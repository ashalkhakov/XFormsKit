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
#import "XFMarkupParts.h"
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
/// The same split for the markup of hint/help/alert, so an xf:output
/// inside one re-renders on refresh (9.3.1 gives them the label's content
/// model). nil where the child holds no markup.
@property (nonatomic, copy) NSArray *hintMarkupParts;
@property (nonatomic, copy) NSArray *helpMarkupParts;
@property (nonatomic, copy) NSArray *alertMarkupParts;
/// And for their plain text, which takes xf:output too: flattening the
/// element instead would drop every output's value.
@property (nonatomic, copy) NSArray *hintTextParts;
@property (nonatomic, copy) NSArray *helpTextParts;
@property (nonatomic, copy) NSArray *alertTextParts;
@property (nonatomic, assign) BOOL supportIsDynamic;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *mipEvents;
@property (nonatomic, assign) BOOL mipKnown;
@end

@implementation XFControl {
    BOOL _checkedModelIDREF;
    BOOL _raisedDatatypeRestriction;
}

- (instancetype)initWithElement:(XFXMLElement *)element
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
    XFXMLElement *el = [XFXML childElementWithLocalName:name
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

/// XsltForms_label: a label with ref/value/bind is a bound element
/// refreshed with the control; inline markup is text and nested
/// xf:output elements are evaluated in place (label.xsl) (G-23).
- (void)loadLabelParts
{
    self.labelParts = nil;
    self.labelIsDynamic = NO;
    XFXMLElement *el = [XFXML childElementWithLocalName:@"label"
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

- (void)collectLabelPartsOf:(XFXMLElement *)el into:(NSMutableArray *)parts
{
    for (XFXMLNode *child in [el children]) {
        XFXMLNodeKind kind = [child kind];
        if (kind == XFXMLTextKind) {
            [parts addObject:[child stringValue] ?: @""];
        } else if (kind == XFXMLElementKind) {
            XFXMLElement *c = (XFXMLElement *)child;
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
    XFXMLElement *element = self.element;
    self.navindex = [[[element attributeForName:@"navindex"] stringValue] integerValue];
    self.mediatype = [[element attributeForName:@"mediatype"] stringValue];
    self.accesskey = [[element attributeForName:@"accesskey"] stringValue];
    self.placeholder = [[element attributeForName:@"placeholder"] stringValue];
    self.rows = [[[element attributeForName:@"rows"] stringValue] integerValue];
    self.cols = [[[element attributeForName:@"cols"] stringValue] integerValue];
    self.inputmode = [[element attributeForName:@"inputmode"] stringValue];
    XFXMLElement *help = [XFXML childElementWithLocalName:@"help" namespaceURI:XFXFormsNamespaceURI ofElement:element];
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
    XFXMLElement *hintEl = [XFXML childElementWithLocalName:@"hint"
                                               namespaceURI:XFXFormsNamespaceURI
                                                  ofElement:self.element];
    self.hintMinimal = [[[hintEl attributeForName:@"appearance"] stringValue]
                           isEqualToString:@"minimal"];
    // Text and markup both as parts, for the same reason the label is: an
    // xf:output in any of them re-renders on refresh (9.3.1). The text is
    // what every host shows; the markup is what a host that draws XHTML
    // shows instead, and is nil unless the form wrote formatting.
    self.hintTextParts = [self textPartsOfChild:@"hint"];
    self.helpTextParts = [self textPartsOfChild:@"help"];
    self.alertTextParts = [self textPartsOfChild:@"alert"];
    self.hintMarkupParts = [self markupPartsOfChild:@"hint"];
    self.helpMarkupParts = [self markupPartsOfChild:@"help"];
    self.alertMarkupParts = [self markupPartsOfChild:@"alert"];
    self.supportIsDynamic = NO;
    for (NSArray *parts in @[ self.hintTextParts ?: @[], self.helpTextParts ?: @[],
                              self.alertTextParts ?: @[], self.hintMarkupParts ?: @[],
                              self.helpMarkupParts ?: @[], self.alertMarkupParts ?: @[] ]) {
        self.supportIsDynamic |= [XFMarkupParts partsAreDynamic:parts];
    }
    // A literal joins once, for good; a dynamic one is joined again on
    // every refresh, and until the first one it reads as empty.
    [self refreshSupportTextAndMarkupInContext:nil];
}

/// The plain-text parts of a support child, or nil when it is bound (its
/// value comes from the node, not from the element's content).
- (NSArray *)textPartsOfChild:(NSString *)name
{
    XFXMLElement *el = [XFXML childElementWithLocalName:name
                                          namespaceURI:XFXFormsNamespaceURI
                                             ofElement:self.element];
    if (el == nil || [el attributeForName:@"ref"] || [el attributeForName:@"value"]) {
        return nil;
    }
    return [XFMarkupParts textPartsOfElement:el];
}

/// The markup parts of a support child, or nil when it is bound (a hint
/// with ref/value is its node's string value — text, never markup) or
/// holds no formatting.
- (NSArray *)markupPartsOfChild:(NSString *)name
{
    XFXMLElement *el = [XFXML childElementWithLocalName:name
                                          namespaceURI:XFXFormsNamespaceURI
                                             ofElement:self.element];
    if (el == nil || [el attributeForName:@"ref"] || [el attributeForName:@"value"]) {
        return nil;
    }
    return [XFMarkupParts partsOfElement:el];
}

- (void)refreshSupportTextAndMarkupInContext:(XFExprContext *)ctx
{
    // a bound hint/help/alert wins: refreshSupportInContext: sets those
    if (self.hintBinding == nil) {
        self.hint = [self joined:self.hintTextParts context:ctx];
    }
    if (self.helpBinding == nil) {
        self.help = [self joined:self.helpTextParts context:ctx];
    }
    if (self.alertBinding == nil) {
        self.alert = [self joined:self.alertTextParts context:ctx];
    }
    self.hintMarkup = [XFMarkupParts markupFromParts:self.hintMarkupParts context:ctx];
    self.helpMarkup = [XFMarkupParts markupFromParts:self.helpMarkupParts context:ctx];
    self.alertMarkup = [XFMarkupParts markupFromParts:self.alertMarkupParts context:ctx];
}

/// Empty reads as absent, the way the flattening it replaced had it: hosts
/// test `hint.length` and an empty xf:hint must not make a badge.
- (NSString *)joined:(NSArray *)parts context:(XFExprContext *)ctx
{
    NSString *s = [XFMarkupParts textFromParts:parts context:ctx];
    return s.length ? s : nil;
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
    if (self.supportIsDynamic) {
        [self refreshSupportTextAndMarkupInContext:ctx];
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
    XFXMLElement *element = self.element;
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

+ (BOOL)isControlElement:(XFXMLElement *)element
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

+ (BOOL)isStandaloneLabelElement:(XFXMLElement *)element
{
    if (![XFXML element:element hasLocalName:@"label" namespaceURI:XFXFormsNamespaceURI]) {
        return NO;
    }
    NSString *ref = [[element attributeForName:@"ref"] stringValue];
    NSString *value = [[element attributeForName:@"value"] stringValue];
    if (ref.length || value.length) {
        return YES;
    }
    XFXMLNode *parent = [element parent];
    NSString *pname = [parent kind] == XFXMLElementKind ? [(XFXMLElement *)parent localName] : @"";
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

+ (BOOL)shouldInstantiateElement:(XFXMLElement *)element
{
    return [self isControlElement:element] || [self isStandaloneLabelElement:element];
}

+ (NSString *)labelForElement:(XFXMLElement *)element
{
    // only a direct child: a repeat/group must not borrow the label of the
    // first control nested in its markup (G-20)
    XFXMLElement *label =
        [XFXML childElementWithLocalName:@"label"
                           namespaceURI:XFXFormsNamespaceURI
                              ofElement:element];
    return label ? [XFXML stringValueOfNode:label] : nil;
}

+ (XFBinding *)bindingOnElement:(XFXMLElement *)element
              preferredAttribute:(NSString *)preferred
                          error:(NSError **)error
{
    // bind="id" wins over ref/nodeset/value (toScriptBinding.xsl), G-21
    return [XFBinding bindingForElement:element attribute:preferred error:error];
}

+ (instancetype)controlWithElement:(XFXMLElement *)element
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
    XFXMLElement *element = self.element;
    return [element attributeForName:@"value"] != nil
        && [element attributeForName:@"ref"] == nil
        && [element attributeForName:@"bind"] == nil;
}

- (void)applyMIPsFromBoundNode
{
    [self applyMIPsFromNode:self.boundNode];
}

- (void)applyMIPsFromNode:(XFXMLNode *)node
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

- (void)enforceDatatypeRestriction:(NSSet<NSString *> *)allowed
{
    if (_raisedDatatypeRestriction || self.boundNode == nil) {
        return;
    }
    // the bind's type, else the node's literal xsi:type (the
    // XsltForms_browser.getType convention)
    NSString *typeName = [XFNodeState existingStateOnNode:self.boundNode].typeName;
    if (typeName.length == 0 && [self.boundNode kind] == XFXMLElementKind) {
        typeName = [[(XFXMLElement *)self.boundNode attributeForLocalName:@"type"
                        URI:@"http://www.w3.org/2001/XMLSchema-instance"] stringValue]
            ?: [[(XFXMLElement *)self.boundNode attributeForName:@"xsi:type"] stringValue];
    }
    if (typeName.length == 0) {
        return;   // an untyped node is not a declared violation
    }
    NSString *local = [[typeName componentsSeparatedByString:@":"] lastObject];
    if ([allowed containsObject:local]) {
        return;
    }
    _raisedDatatypeRestriction = YES;
    [XFXMLEvents raise:@"xforms-binding-exception" on:self.element
               message:[NSString stringWithFormat:
                        @"%@ cannot bind to datatype '%@'", [self.element localName], typeName]];
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
        // an UNBOUND control can still carry a model IDREF — one that
        // names no model raises xforms-binding-exception (4.5.1.a1);
        // bound controls get the same check from XFBinding
        if (!_checkedModelIDREF) {
            _checkedModelIDREF = YES;
            NSString *mid = [[self.element attributeForName:@"model"] stringValue];
            if (mid.length) {
                BOOL found = NO;
                XFProcessor *processor = [self processor];
                NSArray<XFModel *> *models = processor ? processor.models
                    : ([self.owner isKindOfClass:[XFModel class]] ? @[ (XFModel *)self.owner ] : @[]);
                for (XFModel *m in models) {
                    if ([m.identifier isEqualToString:mid]) {
                        found = YES;
                        break;
                    }
                }
                if (!found) {
                    [XFXMLEvents raise:@"xforms-binding-exception" on:self.element
                               message:[NSString stringWithFormat:@"no model with id '%@'", mid]];
                }
            }
        }
        return;
    }
    NSError *inner = nil;
    XFXMLNode *node = [self.binding boundNodeInContext:context error:&inner];
    if (inner != nil) {
        // a failing UI binding expression is an xforms-binding-exception
        // (7.5.b — the same failure inside a model item property raises
        // xforms-compute-exception instead)
        [XFXMLEvents raise:@"xforms-binding-exception" on:self.element
                   message:inner.localizedDescription];
        if (error) {
            *error = inner;
        }
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
        if (inner != nil) {
            [XFXMLEvents raise:@"xforms-binding-exception" on:self.element
                       message:inner.localizedDescription];
            if (error) {
                *error = inner;
            }
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
    // XsltForms_globals.build walks the WHOLE host DOM with one context
    // chain — embedded subform content INHERITS the embedding context
    // node, and a model-less binding evaluates from it whatever instance
    // document it belongs to (writers.xhtml: books.xhtml's repeat lists
    // the clicked writer's own books). Only an explicit model= switches
    // the context (XsltForms_binding.bind_evaluate → XFBinding
    // contextForEvaluation:); the subform's own instances stay reachable
    // through instance('id') and subform-instance().
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
