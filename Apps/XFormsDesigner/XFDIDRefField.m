#import "XFDIDRefField.h"

@interface XFDIDRefField ()
@property (nonatomic, strong) NSComboBox *combo;
@property (nonatomic, assign, readwrite, getter=isValid) BOOL valid;
@end

@implementation XFDIDRefField

/// Common event names for the "#event" pseudo-kind: suggestions, never a
/// validity boundary — custom events dispatched by name are legitimate.
static NSArray *XFDCommonEventNames(void)
{
    return @[ @"DOMActivate", @"DOMFocusIn", @"DOMFocusOut",
              @"xforms-value-changed", @"xforms-ready", @"xforms-model-construct-done",
              @"xforms-submit", @"xforms-submit-done", @"xforms-submit-error",
              @"xforms-select", @"xforms-deselect",
              @"xforms-valid", @"xforms-invalid",
              @"xforms-enabled", @"xforms-disabled",
              @"xforms-insert", @"xforms-delete" ];
}

static void XFDCollectIDs(NSXMLElement *element, NSSet *localNames, NSMutableArray *ids)
{
    if (localNames == nil || [localNames containsObject:[element localName] ?: @""]) {
        NSString *identifier = [[element attributeForName:@"id"] stringValue];
        if (identifier.length && ![ids containsObject:identifier]) {
            [ids addObject:identifier];
        }
    }
    for (NSXMLNode *child in [element children]) {
        if ([child kind] == NSXMLElementKind) {
            XFDCollectIDs((NSXMLElement *)child, localNames, ids);
        }
    }
}

+ (NSArray<NSString *> *)identifiersOfKind:(NSString *)kind
                               inProcessor:(XFProcessor *)processor
{
    if ([kind isEqualToString:@"#event"]) {
        return XFDCommonEventNames();
    }
    NSXMLElement *root = [processor.hostDocument rootElement];
    if (root == nil || kind.length == 0) {
        return @[];
    }
    NSMutableArray *ids = [NSMutableArray array];
    if ([kind isEqualToString:@"*"]) {
        // any element with an id (dispatch targets: models, controls,
        // host markup alike)
        XFDCollectIDs(root, nil, ids);
    } else if ([kind isEqualToString:@"#control"]) {
        // focusable form controls (setfocus targets)
        static NSSet *controls;
        if (controls == nil) {
            controls = [NSSet setWithArray:@[ @"input", @"secret", @"textarea",
                @"output", @"upload", @"range", @"trigger", @"submit",
                @"select", @"select1" ]];
        }
        XFDCollectIDs(root, controls, ids);
    } else {
        for (NSXMLElement *e in [XFXML elementsWithLocalName:kind
                                                namespaceURI:XFXFormsNamespaceURI
                                                      inNode:root]) {
            NSString *identifier = [[e attributeForName:@"id"] stringValue];
            if (identifier.length && ![ids containsObject:identifier]) {
                [ids addObject:identifier];
            }
        }
    }
    return ids;
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
    if (self.combo != nil) {
        return;
    }
    _valid = YES;
    self.combo = [[NSComboBox alloc] initWithFrame:[self bounds]];
    [self.combo setAutoresizingMask:NSViewWidthSizable];
    [[self.combo cell] setControlSize:NSSmallControlSize];
    [self.combo setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [self.combo setUsesDataSource:NO];
    [self.combo setCompletes:YES];
    [self.combo setNumberOfVisibleItems:12];
    [[self.combo cell] setSendsActionOnEndEditing:YES];
    [self.combo setTarget:self];
    [self.combo setAction:@selector(comboEdited:)];
    [self addSubview:self.combo];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(comboWillPopUp:)
               name:NSComboBoxWillPopUpNotification object:self.combo];
    [nc addObserver:self selector:@selector(comboSelectionChanged:)
               name:NSComboBoxSelectionDidChangeNotification object:self.combo];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark value / validation

- (NSString *)stringValue
{
    return [self.combo stringValue];
}

- (void)setStringValue:(NSString *)value
{
    [self.combo setStringValue:value ?: @""];
    [self reloadItems];
    [self validate];
}

- (void)setEnabled:(BOOL)enabled
{
    [self.combo setEnabled:enabled];
}

- (void)reloadItems
{
    [self.combo removeAllItems];
    XFProcessor *processor = [self.provider processorForIDRefField:self];
    if (processor != nil) {
        NSArray *ids = [[self class] identifiersOfKind:self.kind inProcessor:processor];
        if (ids.count) {
            [self.combo addItemsWithObjectValues:ids];
        }
    }
}

- (void)validate
{
    NSString *value = [self.combo stringValue];
    XFProcessor *processor = [self.provider processorForIDRefField:self];
    if ([self.kind isEqualToString:@"#event"]) {
        // the dropdown suggests, it never judges: custom event names are
        // exactly what dispatch is for
        processor = nil;
    }
    if (value.length == 0 || processor == nil) {
        self.valid = YES;
        [self.combo setTextColor:[NSColor controlTextColor]];
        [self.combo setToolTip:nil];
        return;
    }
    BOOL live = [[[self class] identifiersOfKind:self.kind inProcessor:processor]
                    containsObject:value];
    self.valid = live;
    if (live) {
        [self.combo setTextColor:[NSColor controlTextColor]];
        [self.combo setToolTip:nil];
    } else {
        [self.combo setTextColor:[NSColor redColor]];
        [self.combo setToolTip:[NSString stringWithFormat:
            @"No %@ with id ‘%@’ exists.", self.kind ?: @"element", value]];
    }
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

- (void)comboEdited:(id)sender
{
    (void)sender;
    [self validate];
    [self sendAction];
}

- (void)comboWillPopUp:(NSNotification *)note
{
    (void)note;
    [self reloadItems];   // the dropdown always shows the CURRENT ids
}

- (void)comboSelectionChanged:(NSNotification *)note
{
    (void)note;
    // inside this notification the combo's stringValue is still the old
    // text — read the picked item directly
    NSInteger index = [self.combo indexOfSelectedItem];
    if (index < 0) {
        return;
    }
    id picked = [self.combo itemObjectValueAtIndex:index];
    [self.combo setStringValue:[picked description] ?: @""];
    [self validate];
    [self sendAction];
}

@end
