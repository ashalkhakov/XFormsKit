#import "XFDXPathField.h"
#import "XFDXPathPicker.h"
#import "XFDXPathTextStorage.h"
#import "XFDExpressionField.h"
#import "XFDFieldBinding.h"
#import <XFormsKit/XFXMLTypes.h>

@interface XFDXPathField () <NSTextFieldDelegate, XFDBindableField>
@property (nonatomic, strong) XFDExpressionField *field;
@property (nonatomic, strong) NSButton *pickButton;
@property (nonatomic, assign, readwrite, getter=isValid) BOOL valid;
@end

@implementation XFDXPathField {
    NSMutableDictionary<NSString *, XFDFieldBinding *> *_bindings;
}

+ (void)initialize
{
    if (self == [XFDXPathField class]) {
        [self exposeBinding:NSValueBinding];
        [self exposeBinding:NSEnabledBinding];
    }
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self buildSubviews];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self buildSubviews];
    }
    return self;
}

- (void)buildSubviews
{
    if (self.field != nil) {
        return;
    }
    _valid = YES;
    _bindings = [NSMutableDictionary dictionary];
    NSRect bounds = [self bounds];
    CGFloat buttonWidth = 22;
    self.field = [[XFDExpressionField alloc] initWithFrame:
        NSMakeRect(0, 0, NSWidth(bounds) - buttonWidth - 4, NSHeight(bounds))];
    [self.field setAutoresizingMask:NSViewWidthSizable];
    [self.field setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [self.field setTarget:self];
    [self.field setAction:@selector(fieldEdited:)];
    [self.field setDelegate:self];   // live re-validate + highlight
    [self addSubview:self.field];

    self.pickButton = [[NSButton alloc] initWithFrame:
        NSMakeRect(NSWidth(bounds) - buttonWidth, 0, buttonWidth, NSHeight(bounds))];
    [self.pickButton setAutoresizingMask:NSViewMinXMargin];
    [self.pickButton setTitle:@"…"];
    [self.pickButton setBezelStyle:NSRoundedBezelStyle];
    [[self.pickButton cell] setControlSize:NSSmallControlSize];
    [self.pickButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [self.pickButton setTarget:self];
    [self.pickButton setAction:@selector(pickClicked:)];
    [self addSubview:self.pickButton];
}

#pragma mark value / validation

- (NSString *)stringValue
{
    return [self.field stringValue];
}

- (void)setStringValue:(NSString *)value
{
    [self.field setStringValue:value ?: @""];
    [self validate];
}

- (void)setEnabled:(BOOL)enabled
{
    [self.field setEnabled:enabled];
    [self.pickButton setEnabled:enabled];
}

- (void)validate
{
    NSString *expression = [self.field stringValue];
    XFXMLElement *host = [self.provider hostElementForXPathField:self];
    if (expression.length == 0 || host == nil) {
        self.valid = YES;
        [self.field setToolTip:nil];
        [self.field setInvalid:NO];
        return;
    }
    NSError *error = nil;
    XFXPath *compiled = [XFXPath xpathWithString:expression element:host error:&error];
    self.valid = (compiled != nil);
    if (compiled == nil) {
        [self.field setToolTip:[error localizedDescription] ?: @"Invalid XPath"];
    } else {
        [self.field setToolTip:nil];
    }
    [self.field setInvalid:compiled == nil];
}

- (void)controlTextDidChange:(NSNotification *)note
{
    if ([note object] == self.field) {
        [self validate];
    }
}

#pragma mark bindings

- (void)bind:(NSString *)binding toObject:(id)object withKeyPath:(NSString *)keyPath
     options:(NSDictionary *)options
{
    if (!XFDFieldBind(self, _bindings, binding, object, keyPath, options)) {
        [super bind:binding toObject:object withKeyPath:keyPath options:options];
    }
}

- (void)unbind:(NSString *)binding
{
    if (!XFDFieldUnbind(_bindings, binding)) {
        [super unbind:binding];
    }
}

- (NSDictionary *)infoForBinding:(NSString *)binding
{
    return _bindings[binding] ? _bindings[binding].info : [super infoForBinding:binding];
}

- (void)setBoundValue:(id)value
{
    [self setStringValue:[value isKindOfClass:[NSString class]] ? value : @""];
}

/// The expression given to the bound object; NO when refused.
- (BOOL)commitEditing
{
    XFDFieldBinding *binding = _bindings[NSValueBinding];
    return binding == nil || [binding commitValue:[self stringValue]];
}

/// Editing ends only once the bound object has taken the expression.
- (BOOL)control:(id)control textShouldEndEditing:(NSText *)text
{
    (void)control;
    (void)text;
    return [self commitEditing];
}

- (void)sendAction
{
    if (self.target != nil && self.action != NULL) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.target performSelector:self.action withObject:self];
#pragma clang diagnostic pop
    }
}

- (void)fieldEdited:(id)sender
{
    (void)sender;
    [self validate];
    [self sendAction];
}

#pragma mark picker

+ (NSString *)runPickerForProcessor:(XFProcessor *)processor
                        contextNode:(XFXMLNode *)contextNode
                        hostElement:(XFXMLElement *)hostElement
                              title:(NSString *)title
{
    return [XFDXPathPicker runForProcessor:processor
                               contextNode:contextNode
                               hostElement:hostElement
                                     title:title
                                   initial:@""
                               expectation:XFDXPathExpectAny];
}

+ (NSString *)runPickerForProcessor:(XFProcessor *)processor
                        contextNode:(XFXMLNode *)contextNode
                        hostElement:(XFXMLElement *)hostElement
                              title:(NSString *)title
                            initial:(NSString *)initial
                        expectation:(XFDXPathExpectation)expectation
{
    return [XFDXPathPicker runForProcessor:processor
                               contextNode:contextNode
                               hostElement:hostElement
                                     title:title
                                   initial:initial
                               expectation:expectation];
}

- (void)pickClicked:(id)sender
{
    (void)sender;
    XFProcessor *processor = [self.provider processorForXPathField:self];
    XFXMLElement *host = [self.provider hostElementForXPathField:self];
    if (processor == nil || host == nil) {
        XFDBeep();
        return;
    }
    NSString *path = [XFDXPathPicker
        runForProcessor:processor
            contextNode:[self.provider contextNodeForXPathField:self]
            hostElement:host
                  title:[NSString stringWithFormat:@"Path for %@", [host name] ?: @"element"]
                initial:[self.field stringValue]
            expectation:self.expectation];
    if (path == nil) {
        return;
    }
    [self.field setStringValue:path];
    [self validate];
    if (![self commitEditing]) {
        return;
    }
    [self sendAction];
}

@end
