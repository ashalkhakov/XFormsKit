#import "XFDRichTextField.h"
#import "XFDRichTextPanel.h"
#import "XFDRichFragment.h"
#import "XFDXPathField.h"
#import "XFDFieldBinding.h"
#import <XFormsKit/XFormsKit.h>

#pragma mark - The field component

@interface XFDRichTextField () <NSTextFieldDelegate, XFDBindableField>
@property (nonatomic, strong) NSTextField *field;
@property (nonatomic, strong) NSButton *editButton;
@property (nonatomic, copy) NSString *xml;          /* rich fragment, nil = plain */
@property (nonatomic, assign) BOOL enabled;
@end

@implementation XFDRichTextField {
    NSMutableDictionary<NSString *, XFDFieldBinding *> *_bindings;
}

+ (void)initialize
{
    if (self == [XFDRichTextField class]) {
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
    _enabled = YES;
    _bindings = [NSMutableDictionary dictionary];
    NSRect bounds = [self bounds];
    CGFloat buttonWidth = 22;
    self.field = [[NSTextField alloc] initWithFrame:
        NSMakeRect(0, 0, NSWidth(bounds) - buttonWidth - 4, NSHeight(bounds))];
    [self.field setAutoresizingMask:NSViewWidthSizable];
    [[self.field cell] setControlSize:NSSmallControlSize];
    [self.field setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [[self.field cell] setScrollable:YES];
    [[self.field cell] setSendsActionOnEndEditing:YES];
    [self.field setTarget:self];
    [self.field setAction:@selector(fieldEdited:)];
    [self addSubview:self.field];

    self.editButton = [[NSButton alloc] initWithFrame:
        NSMakeRect(NSWidth(bounds) - buttonWidth, 0, buttonWidth, NSHeight(bounds))];
    [self.editButton setAutoresizingMask:NSViewMinXMargin];
    [self.editButton setTitle:@"…"];
    [self.editButton setBezelStyle:NSRoundedBezelStyle];
    [[self.editButton cell] setControlSize:NSSmallControlSize];
    [self.editButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [self.editButton setTarget:self];
    [self.editButton setAction:@selector(editClicked:)];
    [self addSubview:self.editButton];
}

#pragma mark value

- (BOOL)isRich
{
    return self.xml != nil;
}

- (void)applyMode
{
    BOOL rich = [self isRich];
    [self.field setEditable:self.enabled && !rich];
    [self.field setEnabled:self.enabled];
    [self.field setToolTip:rich ? @"Rich content — edit with the … button" : nil];
    [self.editButton setEnabled:self.enabled];
}

- (void)setPlainText:(NSString *)text xml:(NSString *)xml
{
    BOOL rich = xml != nil && [xml rangeOfString:@"<"].location != NSNotFound;
    self.xml = rich ? xml : nil;
    [self.field setStringValue:text ?: @""];
    [self applyMode];
}

- (NSString *)xmlValue
{
    return self.xml;
}

- (NSString *)stringValue
{
    return [self.field stringValue];
}

- (void)setStringValue:(NSString *)value
{
    [self setPlainText:value xml:nil];
}

- (void)setEnabled:(BOOL)enabled
{
    self.enabled = enabled;
    [self applyMode];
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

/// The content shown: rich when it has markup, else its text.
- (void)setBoundValue:(id)value
{
    NSString *content = [value isKindOfClass:[NSString class]] ? value : @"";
    XFXMLElement *wrap = content.length ? XFDParseFragment(content, NULL) : nil;
    BOOL plain = YES;
    for (XFXMLNode *c in [wrap children]) {
        if ([c kind] != XFXMLTextKind) {
            plain = NO;
            break;
        }
    }
    if (wrap == nil && content.length) {
        // not content XML: shown as it is, to be corrected in the panel
        [self setPlainText:content xml:content];
    } else if (plain) {
        [self setPlainText:[wrap stringValue] ?: @"" xml:nil];
    } else {
        [self setPlainText:[wrap stringValue] ?: @"" xml:content];
    }
}

/// The value as content XML: the fragment when rich, the text escaped
/// when plain.
- (NSString *)contentValue
{
    return [self isRich] ? self.xml : XFDEscapeXML([self.field stringValue] ?: @"");
}

/// The content given to the bound object; NO when refused.
- (BOOL)commitEditing
{
    XFDFieldBinding *binding = _bindings[NSValueBinding];
    return binding == nil || [binding commitValue:[self contentValue]];
}

#pragma mark editing

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
    if ([self isRich]) {
        return;   // not editable then; stray action sends change nothing
    }
    if ([self commitEditing]) {
        [self sendAction];
    }
}

- (void)editClicked:(id)sender
{
    (void)sender;
    NSString *fragment = [self isRich] ? self.xml : XFDEscapeXML([self.field stringValue]);
    NSString *edited = [XFDRichTextPanel
        runWithFragment:fragment
                  title:@"Edit Text"
              processor:[self.provider processorForRichTextField:self]
            contextNode:[self.provider contextNodeForRichTextField:self]
            hostElement:[self.provider hostElementForRichTextField:self]];
    if (edited == nil || [edited isEqualToString:fragment]) {
        return;
    }
    XFXMLElement *wrap = XFDParseFragment(edited, NULL);
    BOOL plain = YES;
    for (XFXMLNode *c in [wrap children]) {
        if ([c kind] != XFXMLTextKind) {
            plain = NO;
            break;
        }
    }
    if (wrap != nil && plain) {
        // markup-free fragment: back to an in-place editable plain field
        [self setPlainText:[wrap stringValue] ?: @"" xml:nil];
    } else {
        [self setPlainText:[wrap stringValue] ?: [self.field stringValue] xml:edited];
    }
    if ([self commitEditing]) {
        [self sendAction];
    }
}

@end
