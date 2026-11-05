#import "XFDEditors.h"
#import <AppKit/AppKit.h>
#import <XFormsKit/XFXMLTypes.h>
#import <XFormsKit/XFXML.h>
#import "XFDFormEditor.h"
#import "XFDInspectorSpecs.h"
#import "XFDIDRefField.h"
#import "XFDRichFragment.h"

NSString *const XFDEditorErrorDomain = @"XFDEditorErrorDomain";

static NSString *const XFDDefaultAppearanceTitle = @"(default)";
static NSString *const XFDNoReplaceTitle = @"none";

static NSError *XFDEditorError(NSInteger code, NSString *description, NSString *suggestion)
{
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:description
                                                                   forKey:NSLocalizedDescriptionKey];
    if (suggestion.length) {
        info[NSLocalizedRecoverySuggestionErrorKey] = suggestion;
    }
    return [NSError errorWithDomain:XFDEditorErrorDomain code:code userInfo:info];
}

/// Whether `name` is an NCName: a name without a colon (XML Names §3).
static BOOL XFDIsNCName(NSString *name)
{
    if (name.length == 0) {
        return NO;
    }
    NSMutableCharacterSet *start = [NSMutableCharacterSet letterCharacterSet];
    [start addCharactersInString:@"_"];
    NSMutableCharacterSet *rest = [start mutableCopy];
    [rest formUnionWithCharacterSet:[NSCharacterSet decimalDigitCharacterSet]];
    [rest formUnionWithCharacterSet:[NSCharacterSet nonBaseCharacterSet]];
    [rest addCharactersInString:@".-·"];
    if (![start characterIsMember:[name characterAtIndex:0]]) {
        return NO;
    }
    for (NSUInteger i = 1; i < name.length; i++) {
        if (![rest characterIsMember:[name characterAtIndex:i]]) {
            return NO;
        }
    }
    return YES;
}

/// Whether a content fragment has markup (an element) rather than text.
static BOOL XFDContentHasMarkup(XFXMLElement *wrapper)
{
    for (XFXMLNode *child in [wrapper children]) {
        if ([child kind] == XFXMLElementKind) {
            return YES;
        }
    }
    return NO;
}

@interface XFDElementEditor ()
@property (nonatomic, strong, readwrite) XFXMLElement *element;
@property (nonatomic, strong, readwrite) XFDFormEditor *formEditor;
/// What -reload changes, so that every property depends on it.
@property (nonatomic, readonly) NSUInteger revision;
/// `block`, one of its own writes.
- (void)write:(void (^)(void))block;
@end

@implementation XFDElementEditor {
    NSUInteger _revision;
    /// Its own writes in progress: their news is not a reload.
    NSUInteger _writing;
}

/// The class for an element's kind.
+ (Class)editorClassForElement:(XFXMLElement *)element
{
    if (![XFXML element:element hasLocalName:[element localName] namespaceURI:XFXFormsNamespaceURI]) {
        return [XFDElementEditor class];
    }
    NSString *local = [element localName];
    if ([XFDControlKinds() containsObject:local]) {
        return [XFDControlEditor class];
    }
    NSDictionary *classes = @{ @"bind": [XFDBindEditor class],
                               @"submission": [XFDSubmissionEditor class],
                               @"instance": [XFDInstanceEditor class],
                               @"item": [XFDItemEditor class],
                               @"itemset": [XFDItemsetEditor class] };
    if (classes[local] != nil) {
        return classes[local];
    }
    if (XFDActionSpecs()[local] != nil) {
        return [XFDActionEditor class];
    }
    return [XFDElementEditor class];
}

+ (instancetype)editorForElement:(XFXMLElement *)element formEditor:(XFDFormEditor *)formEditor
{
    if (element == nil || formEditor == nil) {
        return nil;
    }
    Class cls = self == [XFDElementEditor class] ? [self editorClassForElement:element] : self;
    XFDElementEditor *e = [[cls alloc] init];
    e.element = element;
    e.formEditor = formEditor;
    return e;
}

#pragma mark Observing

+ (NSSet<NSString *> *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    NSSet *paths = [super keyPathsForValuesAffectingValueForKey:key];
    if ([key isEqualToString:@"revision"] || [key isEqualToString:@"element"]
        || [key isEqualToString:@"formEditor"]) {
        return paths;
    }
    return [paths setByAddingObject:@"revision"];
}

+ (NSSet *)keyPathsForValuesAffectingTitle { return [NSSet setWithObject:@"identifier"]; }

+ (NSSet *)keyPathsForValuesAffectingLabelText { return [NSSet setWithObjects:@"labelContent", @"labelXML", nil]; }
+ (NSSet *)keyPathsForValuesAffectingLabelXML { return [NSSet setWithObjects:@"labelContent", @"labelText", nil]; }
+ (NSSet *)keyPathsForValuesAffectingLabelContent { return [NSSet setWithObjects:@"labelText", @"labelXML", nil]; }
+ (NSSet *)keyPathsForValuesAffectingHintText { return [NSSet setWithObjects:@"hintContent", @"hintXML", nil]; }
+ (NSSet *)keyPathsForValuesAffectingHintXML { return [NSSet setWithObjects:@"hintContent", @"hintText", nil]; }
+ (NSSet *)keyPathsForValuesAffectingHintContent { return [NSSet setWithObjects:@"hintText", @"hintXML", nil]; }
+ (NSSet *)keyPathsForValuesAffectingHelpText { return [NSSet setWithObjects:@"helpContent", @"helpXML", nil]; }
+ (NSSet *)keyPathsForValuesAffectingHelpXML { return [NSSet setWithObjects:@"helpContent", @"helpText", nil]; }
+ (NSSet *)keyPathsForValuesAffectingHelpContent { return [NSSet setWithObjects:@"helpText", @"helpXML", nil]; }
+ (NSSet *)keyPathsForValuesAffectingAlertText { return [NSSet setWithObjects:@"alertContent", @"alertXML", nil]; }
+ (NSSet *)keyPathsForValuesAffectingAlertXML { return [NSSet setWithObjects:@"alertContent", @"alertText", nil]; }
+ (NSSet *)keyPathsForValuesAffectingAlertContent { return [NSSet setWithObjects:@"alertText", @"alertXML", nil]; }

- (NSUInteger)revision
{
    return _revision;
}

- (void)reload
{
    if (_writing > 0) {
        return;
    }
    [self willChangeValueForKey:@"revision"];
    _revision++;
    [self didChangeValueForKey:@"revision"];
}

- (void)write:(void (^)(void))block
{
    _writing++;
    block();
    _writing--;
}

#pragma mark Attributes and support children

- (BOOL)takesBoundControl
{
    return self.element == self.formEditor.selection && [self.formEditor selectedInstanceDataNode] != nil;
}

- (NSString *)title
{
    NSString *name = [self.element name] ?: [self.element localName] ?: @"?";
    NSString *identifier = [[self.element attributeForName:@"id"] stringValue];
    return identifier.length ? [NSString stringWithFormat:@"%@ — %@", name, identifier] : name;
}

- (NSString *)attribute:(NSString *)name
{
    if ([name hasPrefix:@"ev:"]) {
        // namespace-aware: the document may declare XML Events under any
        // prefix (writes are normalized by XFHostEdit)
        return [XFXML attributeValue:[name substringFromIndex:3]
                        namespaceURI:XFXMLEventsNamespaceURI
                           onElement:self.element] ?: @"";
    }
    return [[self.element attributeForName:name] stringValue] ?: @"";
}

- (void)setAttribute:(NSString *)name value:(NSString *)value
{
    if ([[self attribute:name] isEqualToString:value ?: @""]) {
        return;
    }
    [self write:^{
        [self.formEditor.hostEdit setAttribute:name value:value ?: @"" onElement:self.element];
    }];
}

- (NSString *)identifier { return [self attribute:@"id"]; }
- (void)setIdentifier:(NSString *)v { [self setAttribute:@"id" value:v]; }

- (BOOL)validateIdentifier:(id *)value error:(NSError **)error
{
    NSString *identifier = [*value isKindOfClass:[NSString class]] ? *value : @"";
    if (identifier.length == 0) {
        return YES;
    }
    if (!XFDIsNCName(identifier)) {
        if (error) {
            *error = XFDEditorError(1, [NSString stringWithFormat:@"‘%@’ is not an id.", identifier],
                                    @"An id starts with a letter or an underscore, and has letters, digits, "
                                    @"periods, hyphens and underscores; no spaces or colons.");
        }
        return NO;
    }
    XFXMLElement *other = [XFXML elementWithID:identifier inNode:self.formEditor.processor.hostDocument];
    if (other != nil && other != self.element) {
        if (error) {
            *error = XFDEditorError(2, [NSString stringWithFormat:@"Another element has the id ‘%@’.", identifier],
                                    [NSString stringWithFormat:@"%@ has it already. Ids are unique in a form.",
                                        [other name] ?: @"An element"]);
        }
        return NO;
    }
    return YES;
}

- (NSString *)supportText:(NSString *)name
{
    return [self.formEditor.hostEdit supportChildText:name onElement:self.element] ?: @"";
}

- (void)setSupportText:(NSString *)name to:(NSString *)text
{
    [self write:^{
        [self.formEditor.hostEdit setSupportChild:name text:text onElement:self.element];
    }];
}

- (NSString *)supportXML:(NSString *)name
{
    return [self.formEditor.hostEdit supportChildXML:name onElement:self.element];
}

- (void)setSupportXML:(NSString *)name to:(NSString *)xml
{
    [self write:^{
        [self.formEditor.hostEdit setSupportChild:name contentXML:xml
                                      onElement:self.element error:NULL];
    }];
}

- (NSString *)supportContent:(NSString *)name
{
    return [self supportXML:name] ?: @"";
}

- (void)setSupportContent:(NSString *)name to:(NSString *)content
{
    if ([[self supportContent:name] isEqualToString:content ?: @""]) {
        return;
    }
    XFXMLElement *parsed = content.length ? XFDParseFragment(content, NULL) : nil;
    if (parsed == nil || !XFDContentHasMarkup(parsed)) {
        // plain text (or empty, which removes the child): kept as text
        [self setSupportText:name to:parsed ? [XFXML stringValueOfNode:parsed] : @""];
    } else {
        [self setSupportXML:name to:content];
    }
}

- (NSString *)labelText { return [self supportText:@"label"]; }
- (void)setLabelText:(NSString *)v { [self setSupportText:@"label" to:v]; }
- (NSString *)hintText { return [self supportText:@"hint"]; }
- (void)setHintText:(NSString *)v { [self setSupportText:@"hint" to:v]; }
- (NSString *)helpText { return [self supportText:@"help"]; }
- (void)setHelpText:(NSString *)v { [self setSupportText:@"help" to:v]; }
- (NSString *)alertText { return [self supportText:@"alert"]; }
- (void)setAlertText:(NSString *)v { [self setSupportText:@"alert" to:v]; }

- (NSString *)labelXML { return [self supportXML:@"label"]; }
- (void)setLabelXML:(NSString *)v { [self setSupportXML:@"label" to:v]; }
- (NSString *)hintXML { return [self supportXML:@"hint"]; }
- (void)setHintXML:(NSString *)v { [self setSupportXML:@"hint" to:v]; }
- (NSString *)helpXML { return [self supportXML:@"help"]; }
- (void)setHelpXML:(NSString *)v { [self setSupportXML:@"help" to:v]; }
- (NSString *)alertXML { return [self supportXML:@"alert"]; }
- (void)setAlertXML:(NSString *)v { [self setSupportXML:@"alert" to:v]; }

- (NSString *)labelContent { return [self supportContent:@"label"]; }
- (void)setLabelContent:(NSString *)v { [self setSupportContent:@"label" to:v]; }
- (NSString *)hintContent { return [self supportContent:@"hint"]; }
- (void)setHintContent:(NSString *)v { [self setSupportContent:@"hint" to:v]; }
- (NSString *)helpContent { return [self supportContent:@"help"]; }
- (void)setHelpContent:(NSString *)v { [self setSupportContent:@"help" to:v]; }
- (NSString *)alertContent { return [self supportContent:@"alert"]; }
- (void)setAlertContent:(NSString *)v { [self setSupportContent:@"alert" to:v]; }

#pragma mark Validation

+ (NSSet<NSString *> *)expressionKeys
{
    return [NSSet set];
}

+ (NSSet<NSString *> *)contentKeys
{
    return [NSSet setWithObjects:@"labelContent", @"hintContent", @"helpContent", @"alertContent",
                                 @"labelXML", @"hintXML", @"helpXML", @"alertXML", nil];
}

- (BOOL)validateExpression:(NSString *)expression error:(NSError **)error
{
    if (expression.length == 0) {
        return YES;
    }
    NSError *parse = nil;
    if ([XFXPath xpathWithString:expression element:self.element error:&parse] != nil) {
        return YES;
    }
    if (error) {
        *error = XFDEditorError(3, [NSString stringWithFormat:@"‘%@’ is not an XPath expression.", expression],
                                [parse localizedDescription]);
    }
    return NO;
}

- (BOOL)validateContent:(NSString *)content error:(NSError **)error
{
    if (content.length == 0) {
        return YES;
    }
    NSError *parse = nil;
    if (XFDParseFragment(content, &parse) != nil) {
        return YES;
    }
    if (error) {
        *error = XFDEditorError(4, @"The content is not well-formed XML.", [parse localizedDescription]);
    }
    return NO;
}

- (BOOL)validateValue:(inout id *)value forKey:(NSString *)key error:(out NSError **)error
{
    NSString *string = [*value isKindOfClass:[NSString class]] ? *value : nil;
    if ([[[self class] expressionKeys] containsObject:key]) {
        return [self validateExpression:string error:error];
    }
    if ([[[self class] contentKeys] containsObject:key]) {
        return [self validateContent:string error:error];
    }
    return [super validateValue:value forKey:key error:error];
}

@end

/* ---------------------------------------------------------------- */

@implementation XFDControlEditor

+ (NSSet<NSString *> *)expressionKeys
{
    return [NSSet setWithObjects:@"ref", @"valueExpression", nil];
}

+ (NSSet *)keyPathsForValuesAffectingBindingStatus
{
    return [NSSet setWithObjects:@"ref", @"bind", @"valueExpression", nil];
}

+ (NSSet *)keyPathsForValuesAffectingBindingStatusColor
{
    return [NSSet setWithObjects:@"ref", @"bind", @"valueExpression", nil];
}

+ (NSSet *)keyPathsForValuesAffectingCanCreateBind
{
    return [NSSet setWithObjects:@"ref", @"bind", nil];
}

+ (NSSet *)keyPathsForValuesAffectingAppearanceTitle
{
    return [NSSet setWithObject:@"appearance"];
}

- (BOOL)takesValueExpression
{
    return [[self.element localName] isEqualToString:@"output"];
}

- (BOOL)takesSubmission
{
    return [[self.element localName] isEqualToString:@"submit"];
}

- (BOOL)refSelectsNodeSet
{
    return [[self.element localName] isEqualToString:@"repeat"];
}

- (NSString *)ref { return [self attribute:@"ref"]; }
- (void)setRef:(NSString *)v { [self setAttribute:@"ref" value:v]; }

// @value is xf:output's computed expression, dead weight elsewhere
- (NSString *)valueExpression
{
    return [self takesValueExpression] ? [self attribute:@"value"] : @"";
}

- (void)setValueExpression:(NSString *)v
{
    if ([self takesValueExpression]) {
        [self setAttribute:@"value" value:v];
    }
}

- (NSString *)bind { return [self attribute:@"bind"]; }
- (void)setBind:(NSString *)v { [self setAttribute:@"bind" value:v]; }
- (NSString *)model { return [self attribute:@"model"]; }
- (void)setModel:(NSString *)v { [self setAttribute:@"model" value:v]; }

// @submission is xf:submit's attribute, dead weight elsewhere
- (NSString *)submission
{
    return [self takesSubmission] ? [self attribute:@"submission"] : @"";
}

- (void)setSubmission:(NSString *)v
{
    if ([self takesSubmission]) {
        [self setAttribute:@"submission" value:v];
    }
}

- (NSString *)appearance { return [self attribute:@"appearance"]; }
- (void)setAppearance:(NSString *)v { [self setAttribute:@"appearance" value:v]; }

- (NSString *)appearanceTitle
{
    NSString *appearance = self.appearance;
    return appearance.length ? appearance : XFDDefaultAppearanceTitle;
}

- (void)setAppearanceTitle:(NSString *)title
{
    self.appearance = [title isEqualToString:XFDDefaultAppearanceTitle] ? @"" : title;
}

- (NSString *)mediatype { return [self attribute:@"mediatype"]; }
- (void)setMediatype:(NSString *)v { [self setAttribute:@"mediatype" value:v]; }

- (BOOL)isIncremental
{
    return [[self attribute:@"incremental"] isEqualToString:@"true"];
}

- (void)setIncremental:(BOOL)incremental
{
    [self setAttribute:@"incremental" value:incremental ? @"true" : @""];
}

/// How the control is bound; YES when that is a warning.
- (BOOL)bindingStatusIsWarning:(NSString **)status
{
    NSString *bind = self.bind;
    if (bind.length) {
        if ([[XFDIDRefField identifiersOfKind:@"bind" inProcessor:self.formEditor.processor]
                containsObject:bind]) {
            *status = [NSString stringWithFormat:@"Bound via bind ‘%@’.", bind];
            return NO;
        }
        *status = [NSString stringWithFormat:@"Bind ‘%@’ does not exist.", bind];
        return YES;
    }
    if (self.ref.length) {
        *status = @"Bound in place via ref.";
        return NO;
    }
    if ([self takesValueExpression] && [self attribute:@"value"].length) {
        *status = @"Computed via value expression.";
        return NO;
    }
    if (XFDElementIsUnbound(self.element)) {
        *status = @"Unbound — typed values are not kept.";
        return YES;
    }
    *status = @"";
    return NO;
}

- (NSString *)bindingStatus
{
    NSString *status = nil;
    [self bindingStatusIsWarning:&status];
    return status;
}

- (NSColor *)bindingStatusColor
{
    NSString *status = nil;
    if (![self bindingStatusIsWarning:&status]) {
        return [NSColor disabledControlTextColor];
    }
    // a missing bind is an error, an unbound control a warning
    return self.bind.length ? [NSColor redColor] : XFDWarningColor();
}

- (BOOL)canCreateBind
{
    return self.ref.length > 0 && self.bind.length == 0;
}

@end

@implementation XFDBindEditor

+ (NSSet<NSString *> *)expressionKeys
{
    return [NSSet setWithObjects:@"nodeset", @"calculate", @"constraint", @"required",
                                 @"relevant", @"readonly", nil];
}

- (NSString *)nodeset
{
    NSString *v = [self attribute:@"nodeset"];
    return v.length ? v : [self attribute:@"ref"];
}

- (void)setNodeset:(NSString *)v
{
    // keep whichever spelling the document already uses
    if ([self attribute:@"ref"].length && ![self attribute:@"nodeset"].length) {
        [self setAttribute:@"ref" value:v];
    } else {
        [self setAttribute:@"nodeset" value:v];
    }
}

- (NSString *)typeName { return [self attribute:@"type"]; }
- (void)setTypeName:(NSString *)v { [self setAttribute:@"type" value:v]; }
- (NSString *)calculate { return [self attribute:@"calculate"]; }
- (void)setCalculate:(NSString *)v { [self setAttribute:@"calculate" value:v]; }
- (NSString *)constraint { return [self attribute:@"constraint"]; }
- (void)setConstraint:(NSString *)v { [self setAttribute:@"constraint" value:v]; }
- (NSString *)required { return [self attribute:@"required"]; }
- (void)setRequired:(NSString *)v { [self setAttribute:@"required" value:v]; }
- (NSString *)relevant { return [self attribute:@"relevant"]; }
- (void)setRelevant:(NSString *)v { [self setAttribute:@"relevant" value:v]; }
- (NSString *)readonly { return [self attribute:@"readonly"]; }
- (void)setReadonly:(NSString *)v { [self setAttribute:@"readonly" value:v]; }

@end

@implementation XFDSubmissionEditor

+ (NSSet<NSString *> *)expressionKeys
{
    return [NSSet setWithObject:@"ref"];
}

+ (NSSet *)keyPathsForValuesAffectingReplaceTitle
{
    return [NSSet setWithObject:@"replace"];
}

- (NSString *)resource
{
    NSString *v = [self attribute:@"resource"];
    return v.length ? v : [self attribute:@"action"];
}

- (void)setResource:(NSString *)v
{
    if ([self attribute:@"action"].length && ![self attribute:@"resource"].length) {
        [self setAttribute:@"action" value:v];
    } else {
        [self setAttribute:@"resource" value:v];
    }
}

- (NSString *)method { return [self attribute:@"method"]; }
- (void)setMethod:(NSString *)v { [self setAttribute:@"method" value:v]; }
- (NSString *)replace { return [self attribute:@"replace"]; }
- (void)setReplace:(NSString *)v { [self setAttribute:@"replace" value:v]; }

- (NSString *)replaceTitle
{
    NSString *replace = self.replace;
    return replace.length ? replace : XFDNoReplaceTitle;
}

- (void)setReplaceTitle:(NSString *)title
{
    self.replace = [title isEqualToString:XFDNoReplaceTitle] ? @"" : title;
}

- (NSString *)instance { return [self attribute:@"instance"]; }
- (void)setInstance:(NSString *)v { [self setAttribute:@"instance" value:v]; }
- (NSString *)ref { return [self attribute:@"ref"]; }
- (void)setRef:(NSString *)v { [self setAttribute:@"ref" value:v]; }
- (NSString *)bind { return [self attribute:@"bind"]; }
- (void)setBind:(NSString *)v { [self setAttribute:@"bind" value:v]; }

@end

@implementation XFDInstanceEditor

- (NSString *)src { return [self attribute:@"src"]; }
- (void)setSrc:(NSString *)v { [self setAttribute:@"src" value:v]; }

@end

@implementation XFDItemEditor

- (NSString *)valueText { return [self supportText:@"value"]; }
- (void)setValueText:(NSString *)v { [self setSupportText:@"value" to:v]; }

@end

@implementation XFDItemsetEditor

+ (NSSet<NSString *> *)expressionKeys
{
    return [NSSet setWithObjects:@"nodeset", @"labelRef", @"valueRef", nil];
}

- (NSString *)nodeset
{
    NSString *v = [self attribute:@"nodeset"];
    return v.length ? v : [self attribute:@"ref"];
}

- (void)setNodeset:(NSString *)v
{
    // keep whichever spelling the document already uses
    if ([self attribute:@"ref"].length && ![self attribute:@"nodeset"].length) {
        [self setAttribute:@"ref" value:v];
    } else {
        [self setAttribute:@"nodeset" value:v];
    }
}

- (NSString *)bind { return [self attribute:@"bind"]; }
- (void)setBind:(NSString *)v { [self setAttribute:@"bind" value:v]; }

- (NSString *)childAttribute:(NSString *)attr of:(NSString *)child
{
    return [self.formEditor.hostEdit supportChildAttribute:attr child:child
                                               onElement:self.element] ?: @"";
}

- (void)setChildAttribute:(NSString *)attr of:(NSString *)child to:(NSString *)v
{
    if ([[self childAttribute:attr of:child] isEqualToString:v ?: @""]) {
        return;
    }
    [self write:^{
        [self.formEditor.hostEdit setSupportChildAttribute:attr child:child
                                                   value:v ?: @"" onElement:self.element];
    }];
}

- (NSString *)labelRef { return [self childAttribute:@"ref" of:@"label"]; }
- (void)setLabelRef:(NSString *)v { [self setChildAttribute:@"ref" of:@"label" to:v]; }
- (NSString *)valueRef { return [self childAttribute:@"ref" of:@"value"]; }
- (void)setValueRef:(NSString *)v { [self setChildAttribute:@"ref" of:@"value" to:v]; }

@end

/* ---------------------------------------------------------------- */

/// An action's attributes as keys: each a row's value by its attribute
/// name, read, set and validated by the row's kind.
@interface XFDActionAttributes : NSObject
- (instancetype)initWithEditor:(XFDActionEditor *)editor;
@end

@interface XFDActionEditor ()
- (NSDictionary *)rowForAttribute:(NSString *)name;
@end

@implementation XFDActionEditor {
    XFDActionAttributes *_attributes;
}

- (NSArray<NSDictionary *> *)rows
{
    return [XFDActionCommonSpecs() arrayByAddingObjectsFromArray:
        XFDActionSpecs()[[self.element localName]] ?: @[]];
}

- (NSDictionary *)rowForAttribute:(NSString *)name
{
    for (NSDictionary *row in [self rows]) {
        if ([row[@"attr"] isEqualToString:name]) {
            return row;
        }
    }
    return nil;
}

- (id)attributes
{
    if (_attributes == nil) {
        _attributes = [[XFDActionAttributes alloc] initWithEditor:self];
    }
    return _attributes;
}

- (NSString *)inlineContent
{
    return [self.formEditor.hostEdit inlineContentXMLOfElement:self.element] ?: @"";
}

- (void)setInlineContent:(NSString *)content
{
    if ([[self inlineContent] isEqualToString:content ?: @""]) {
        return;
    }
    [self write:^{
        [self.formEditor.hostEdit setInlineContentXML:content ?: @"" onElement:self.element error:NULL];
    }];
}

- (BOOL)validateInlineContent:(id *)value error:(NSError **)error
{
    return [self validateContent:[*value isKindOfClass:[NSString class]] ? *value : nil error:error];
}

@end

@implementation XFDActionAttributes {
    __weak XFDActionEditor *_editor;
}

- (instancetype)initWithEditor:(XFDActionEditor *)editor
{
    if ((self = [super init])) {
        _editor = editor;
    }
    return self;
}

- (id)valueForUndefinedKey:(NSString *)key
{
    XFDActionEditor *editor = _editor;
    NSDictionary *row = [editor rowForAttribute:key];
    NSString *value = [editor attribute:key];
    if ([row[@"kind"] isEqualToString:@"popup"] && value.length == 0) {
        return [row[@"options"] firstObject] ?: @"";
    }
    return value;
}

- (void)setValue:(id)value forUndefinedKey:(NSString *)key
{
    XFDActionEditor *editor = _editor;
    NSDictionary *row = [editor rowForAttribute:key];
    NSString *string = [value isKindOfClass:[NSString class]] ? value : @"";
    if ([row[@"kind"] isEqualToString:@"popup"] && [string isEqualToString:[row[@"options"] firstObject]]) {
        string = @"";
    }
    [self willChangeValueForKey:key];
    [editor setAttribute:key value:string];
    [self didChangeValueForKey:key];
}

- (BOOL)validateValue:(inout id *)value forKey:(NSString *)key error:(out NSError **)error
{
    XFDActionEditor *editor = _editor;
    if ([[editor rowForAttribute:key][@"kind"] isEqualToString:@"xpath"]) {
        return [editor validateExpression:[*value isKindOfClass:[NSString class]] ? *value : nil error:error];
    }
    return YES;
}

@end
