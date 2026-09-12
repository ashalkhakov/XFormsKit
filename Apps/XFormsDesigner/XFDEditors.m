#import "XFDEditors.h"
#import <XFormsKit/XFXMLTypes.h>
#import "XFDDocument.h"

@interface XFDElementEditor ()
@property (nonatomic, strong, readwrite) XFXMLElement *element;
@property (nonatomic, strong, readwrite) XFDDocument *document;
@end

@implementation XFDElementEditor

+ (instancetype)editorForElement:(XFXMLElement *)element document:(XFDDocument *)document
{
    if (element == nil || document == nil) {
        return nil;
    }
    XFDElementEditor *e = [[self alloc] init];
    e.element = element;
    e.document = document;
    return e;
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
    [self.document.hostEdit setAttribute:name value:value onElement:self.element];
}

- (NSString *)identifier { return [self attribute:@"id"]; }
- (void)setIdentifier:(NSString *)v { [self setAttribute:@"id" value:v]; }

- (NSString *)supportText:(NSString *)name
{
    return [self.document.hostEdit supportChildText:name onElement:self.element] ?: @"";
}

- (void)setSupportText:(NSString *)name to:(NSString *)text
{
    [self.document.hostEdit setSupportChild:name text:text onElement:self.element];
}

- (NSString *)labelText { return [self supportText:@"label"]; }
- (void)setLabelText:(NSString *)v { [self setSupportText:@"label" to:v]; }
- (NSString *)hintText { return [self supportText:@"hint"]; }
- (void)setHintText:(NSString *)v { [self setSupportText:@"hint" to:v]; }
- (NSString *)helpText { return [self supportText:@"help"]; }
- (void)setHelpText:(NSString *)v { [self setSupportText:@"help" to:v]; }
- (NSString *)alertText { return [self supportText:@"alert"]; }
- (void)setAlertText:(NSString *)v { [self setSupportText:@"alert" to:v]; }

- (NSString *)supportXML:(NSString *)name
{
    return [self.document.hostEdit supportChildXML:name onElement:self.element];
}

- (void)setSupportXML:(NSString *)name to:(NSString *)xml
{
    [self.document.hostEdit setSupportChild:name contentXML:xml
                                  onElement:self.element error:NULL];
}

- (NSString *)labelXML { return [self supportXML:@"label"]; }
- (void)setLabelXML:(NSString *)v { [self setSupportXML:@"label" to:v]; }
- (NSString *)hintXML { return [self supportXML:@"hint"]; }
- (void)setHintXML:(NSString *)v { [self setSupportXML:@"hint" to:v]; }
- (NSString *)helpXML { return [self supportXML:@"help"]; }
- (void)setHelpXML:(NSString *)v { [self setSupportXML:@"help" to:v]; }
- (NSString *)alertXML { return [self supportXML:@"alert"]; }
- (void)setAlertXML:(NSString *)v { [self setSupportXML:@"alert" to:v]; }

@end

/* ---------------------------------------------------------------- */

@implementation XFDControlEditor

- (NSString *)ref { return [self attribute:@"ref"]; }
- (void)setRef:(NSString *)v { [self setAttribute:@"ref" value:v]; }
- (NSString *)valueExpression { return [self attribute:@"value"]; }
- (void)setValueExpression:(NSString *)v { [self setAttribute:@"value" value:v]; }
- (NSString *)bind { return [self attribute:@"bind"]; }
- (void)setBind:(NSString *)v { [self setAttribute:@"bind" value:v]; }
- (NSString *)model { return [self attribute:@"model"]; }
- (void)setModel:(NSString *)v { [self setAttribute:@"model" value:v]; }
- (NSString *)submission { return [self attribute:@"submission"]; }
- (void)setSubmission:(NSString *)v { [self setAttribute:@"submission" value:v]; }
- (NSString *)appearance { return [self attribute:@"appearance"]; }
- (void)setAppearance:(NSString *)v { [self setAttribute:@"appearance" value:v]; }
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

@end

@implementation XFDBindEditor

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
    return [self.document.hostEdit supportChildAttribute:attr child:child
                                               onElement:self.element] ?: @"";
}

- (void)setChildAttribute:(NSString *)attr of:(NSString *)child to:(NSString *)v
{
    [self.document.hostEdit setSupportChildAttribute:attr child:child
                                               value:v onElement:self.element];
}

- (NSString *)labelRef { return [self childAttribute:@"ref" of:@"label"]; }
- (void)setLabelRef:(NSString *)v { [self setChildAttribute:@"ref" of:@"label" to:v]; }
- (NSString *)valueRef { return [self childAttribute:@"ref" of:@"value"]; }
- (void)setValueRef:(NSString *)v { [self setChildAttribute:@"ref" of:@"value" to:v]; }

@end
