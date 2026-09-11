#import "XFDRichTextField.h"
#import "XFDXPathField.h"
#import <XFormsKit/XFormsKit.h>

#pragma mark - Fragment helpers

/// Parse `fragment` with the label vocabulary bound (XHTML as the default
/// namespace, xf: for XForms — XFHostEdit rebinds to the document's real
/// prefix at commit time). nil when it does not parse.
static NSXMLElement *XFDParseFragment(NSString *fragment, NSError **error)
{
    NSString *wrapped = [NSString stringWithFormat:
        @"<xfd-wrap xmlns=\"%@\" xmlns:xf=\"%@\">%@</xfd-wrap>",
        XFXHTMLNamespaceURI, XFXFormsNamespaceURI, fragment ?: @""];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:wrapped
                                                          options:0 error:error];
    return [doc rootElement];
}

NSString *XFDEscapeXML(NSString *text)
{
    NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        switch (c) {
            case '&': [out appendString:@"&amp;"]; break;
            case '<': [out appendString:@"&lt;"]; break;
            case '>': [out appendString:@"&gt;"]; break;
            default: [out appendFormat:@"%C", c]; break;
        }
    }
    return out;
}

static NSString * const XFDTokenOpen = @"⟦";
static NSString * const XFDTokenClose = @"⟧";

/// A dynamic output simple enough to ride through the rich editor as a
/// `⟦expr⟧` token: `<xf:output value="…"/>` — exactly that attribute, no
/// children, and an expression free of the bracket characters.
static BOOL XFDOutputElementIsToken(NSXMLElement *e)
{
    if (![[e localName] isEqualToString:@"output"]) {
        return NO;
    }
    NSString *uri = [e URI] ?: @"";
    if (![uri isEqualToString:XFXFormsNamespaceURI]
        && !(uri.length == 0 && [[e prefix] isEqualToString:@"xf"])) {
        return NO;
    }
    if ([e children].count || [e attributes].count != 1) {
        return NO;
    }
    NSString *value = [[e attributeForName:@"value"] stringValue];
    return value.length > 0
        && [value rangeOfString:XFDTokenOpen].location == NSNotFound
        && [value rangeOfString:XFDTokenClose].location == NSNotFound;
}

/// YES when the fragment stays inside what the rich view can show and
/// give back losslessly: the XFRichText subset, attribute-free, nothing
/// namespaced — except simple xf:output values, which become ⟦expr⟧
/// tokens. NO also for a fragment that does not parse.
static BOOL XFDFragmentSubtreeIsRichEditable(NSXMLElement *el)
{
    static NSSet *allowed;
    if (allowed == nil) {
        allowed = [NSSet setWithArray:@[ @"p", @"div", @"blockquote",
            @"h1", @"h2", @"h3", @"ul", @"ol", @"li",
            @"strong", @"b", @"em", @"i", @"u", @"s", @"strike", @"del", @"br" ]];
    }
    for (NSXMLNode *c in [el children]) {
        if ([c kind] == NSXMLTextKind) {
            continue;
        }
        if ([c kind] != NSXMLElementKind) {
            return NO;   // comments / PIs would be dropped
        }
        NSXMLElement *e = (NSXMLElement *)c;
        if (XFDOutputElementIsToken(e)) {
            continue;
        }
        if ([e prefix].length || ![allowed containsObject:[e localName] ?: @""]
            || [e attributes].count) {
            return NO;
        }
        if (!XFDFragmentSubtreeIsRichEditable(e)) {
            return NO;
        }
    }
    return YES;
}

#pragma mark - Output tokens (⟦expr⟧ ↔ xf:output)

static void XFDTokenizeIn(NSXMLElement *el)
{
    NSArray *kids = [[el children] copy];
    for (NSXMLNode *c in kids) {
        if ([c kind] != NSXMLElementKind) {
            continue;
        }
        NSXMLElement *e = (NSXMLElement *)c;
        if (XFDOutputElementIsToken(e)) {
            NSUInteger i = [e index];
            NSString *expr = [[e attributeForName:@"value"] stringValue];
            [e detach];
            [el insertChild:[NSXMLNode textWithStringValue:
                [NSString stringWithFormat:@"%@%@%@", XFDTokenOpen, expr, XFDTokenClose]]
                    atIndex:i];
        } else {
            XFDTokenizeIn(e);
        }
    }
}

NSString *XFDTokenizeFragment(NSString *fragment)
{
    NSXMLElement *wrap = XFDParseFragment(fragment, NULL);
    if (wrap == nil) {
        return fragment;
    }
    XFDTokenizeIn(wrap);
    NSMutableString *out = [NSMutableString string];
    for (NSXMLNode *c in [wrap children]) {
        [out appendString:[c XMLString] ?: @""];
    }
    return out;
}

static void XFDDetokenizeIn(NSXMLElement *el)
{
    NSArray *kids = [[el children] copy];
    for (NSXMLNode *c in kids) {
        if ([c kind] == NSXMLElementKind) {
            XFDDetokenizeIn((NSXMLElement *)c);
            continue;
        }
        if ([c kind] != NSXMLTextKind) {
            continue;
        }
        NSString *text = [c stringValue] ?: @"";
        if ([text rangeOfString:XFDTokenOpen].location == NSNotFound) {
            continue;
        }
        NSMutableArray *replacement = [NSMutableArray array];
        NSUInteger pos = 0;
        while (pos < text.length) {
            NSRange open = [text rangeOfString:XFDTokenOpen options:0
                                         range:NSMakeRange(pos, text.length - pos)];
            if (open.location == NSNotFound) {
                break;
            }
            NSUInteger after = NSMaxRange(open);
            NSRange close = [text rangeOfString:XFDTokenClose options:0
                                          range:NSMakeRange(after, text.length - after)];
            if (close.location == NSNotFound) {
                break;   // unmatched bracket: stays literal text
            }
            if (open.location > pos) {
                [replacement addObject:[NSXMLNode textWithStringValue:
                    [text substringWithRange:NSMakeRange(pos, open.location - pos)]]];
            }
            NSString *expr = [text substringWithRange:
                NSMakeRange(after, close.location - after)];
            if (expr.length) {
                NSXMLElement *output = [NSXMLElement elementWithName:@"xf:output"];
                [output addAttribute:[NSXMLNode attributeWithName:@"value" stringValue:expr]];
                [replacement addObject:output];
            }
            pos = NSMaxRange(close);
        }
        if (replacement.count == 0 && pos == 0) {
            continue;   // only unmatched brackets
        }
        if (pos < text.length) {
            [replacement addObject:[NSXMLNode textWithStringValue:
                [text substringFromIndex:pos]]];
        }
        NSUInteger i = [c index];
        [c detach];
        for (NSXMLNode *node in replacement) {
            [el insertChild:node atIndex:i++];
        }
    }
}

NSString *XFDDetokenizeFragment(NSString *fragment)
{
    if ([fragment rangeOfString:XFDTokenOpen].location == NSNotFound) {
        return fragment;
    }
    NSXMLElement *wrap = XFDParseFragment(fragment, NULL);
    if (wrap == nil) {
        return fragment;
    }
    XFDDetokenizeIn(wrap);
    NSMutableString *out = [NSMutableString string];
    for (NSXMLNode *c in [wrap children]) {
        [out appendString:[c XMLString] ?: @""];
    }
    return out;
}

static BOOL XFDFragmentIsRichEditable(NSString *fragment)
{
    NSXMLElement *wrap = XFDParseFragment(fragment, NULL);
    return wrap != nil && XFDFragmentSubtreeIsRichEditable(wrap);
}

/// XFRichText serializes a single plain paragraph as `<p>text</p>`; label
/// content is inline, so one lone paragraph sheds its wrapper.
static NSString *XFDUnwrapSingleParagraph(NSString *html)
{
    if ([html hasPrefix:@"<p>"] && [html hasSuffix:@"</p>"]
        && [html rangeOfString:@"<p>" options:0
                         range:NSMakeRange(1, html.length - 1)].location == NSNotFound) {
        return [html substringWithRange:NSMakeRange(3, html.length - 7)];
    }
    return html;
}

#pragma mark - Modal editor panel

/// The "…" modal: one fragment, two views. Rich is XFRichTextEditor
/// (blocks + inline styling) with simple xf:output values shown as tinted
/// ⟦expr⟧ tokens and an "Insert Output…" button running the shared node
/// picker; Source is the raw XML, parse-gated. The segmented control
/// switches views, converting on the way; a fragment the rich view cannot
/// represent keeps Source selected with an explanation instead of
/// dropping markup.
@interface XFDRichTextPanel : NSObject
{
    NSPanel *_panel;
    NSSegmentedControl *_viewControl;
    NSButton *_insertOutputButton;
    NSTabView *_tabs;
    XFRichTextEditor *_richEditor;
    NSTextView *_sourceView;
    NSTextField *_statusField;
    NSButton *_okButton;
    NSString *_result;
    XFProcessor *_processor;
    NSXMLNode *_contextNode;
    NSXMLElement *_hostElement;
    BOOL _adjustingSelection;
}
+ (NSString *)runWithFragment:(NSString *)fragment
                        title:(NSString *)title
                    processor:(XFProcessor *)processor
                  contextNode:(NSXMLNode *)contextNode
                  hostElement:(NSXMLElement *)hostElement;
@end

@implementation XFDRichTextPanel

- (void)buildPanelWithTitle:(NSString *)title
{
    const CGFloat W = 520, H = 380;
    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, W, H)
                                        styleMask:NSTitledWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    [_panel setTitle:title];
    NSView *content = [_panel contentView];

    _viewControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(12, H - 34, 160, 24)];
    [_viewControl setSegmentCount:2];
    [_viewControl setLabel:@"Rich" forSegment:0];
    [_viewControl setLabel:@"Source" forSegment:1];
    [_viewControl setTarget:self];
    [_viewControl setAction:@selector(viewChanged:)];
    [content addSubview:_viewControl];

    _insertOutputButton = [[NSButton alloc] initWithFrame:NSMakeRect(184, H - 36, 130, 28)];
    [_insertOutputButton setTitle:@"Insert Output…"];
    [_insertOutputButton setBezelStyle:NSRoundedBezelStyle];
    [[_insertOutputButton cell] setControlSize:NSSmallControlSize];
    [_insertOutputButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [_insertOutputButton setTarget:self];
    [_insertOutputButton setAction:@selector(insertOutputClicked:)];
    [content addSubview:_insertOutputButton];

    _tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(12, 70, W - 24, H - 112)];
    [_tabs setTabViewType:NSNoTabsNoBorder];

    NSTabViewItem *richItem = [[NSTabViewItem alloc] initWithIdentifier:@"rich"];
    _richEditor = [[XFRichTextEditor alloc] initWithFrame:NSMakeRect(0, 0, W - 24, H - 112)
                                                 baseFont:[NSFont systemFontOfSize:13]];
    [_richEditor setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[_richEditor textView] setDelegate:(id)self];
    [richItem setView:_richEditor];
    [_tabs addTabViewItem:richItem];

    NSTabViewItem *sourceItem = [[NSTabViewItem alloc] initWithIdentifier:@"source"];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, W - 24, H - 112)];
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];
    _sourceView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, W - 24, H - 112)];
    [_sourceView setFont:[NSFont userFixedPitchFontOfSize:11]];
    [_sourceView setRichText:NO];
    [_sourceView setAutoresizingMask:NSViewWidthSizable];
    [_sourceView setVerticallyResizable:YES];
    [_sourceView setHorizontallyResizable:NO];
    [[_sourceView textContainer] setWidthTracksTextView:YES];
    [_sourceView setDelegate:(id)self];
    [scroll setDocumentView:_sourceView];
    [sourceItem setView:scroll];
    [_tabs addTabViewItem:sourceItem];
    [content addSubview:_tabs];

    _statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 44, W - 24, 17)];
    [_statusField setEditable:NO];
    [_statusField setBordered:NO];
    [_statusField setDrawsBackground:NO];
    [_statusField setFont:[NSFont systemFontOfSize:11]];
    [content addSubview:_statusField];

    NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(W - 190, 8, 84, 28)];
    [cancel setTitle:@"Cancel"];
    [cancel setBezelStyle:NSRoundedBezelStyle];
    [cancel setTarget:self];
    [cancel setAction:@selector(cancelClicked:)];
    [content addSubview:cancel];
    _okButton = [[NSButton alloc] initWithFrame:NSMakeRect(W - 100, 8, 84, 28)];
    [_okButton setTitle:@"OK"];
    [_okButton setBezelStyle:NSRoundedBezelStyle];
    [_okButton setTarget:self];
    [_okButton setAction:@selector(okClicked:)];
    [content addSubview:_okButton];
}

- (BOOL)onRichView
{
    return [_viewControl selectedSegment] == 0;
}

- (void)setStatus:(NSString *)text isError:(BOOL)isError
{
    [_statusField setStringValue:text ?: @""];
    [_statusField setTextColor:isError ? [NSColor redColor] : [NSColor disabledControlTextColor]];
}

/// Every matched ⟦expr⟧ range in the rich view, left to right.
- (NSArray *)tokenRanges
{
    NSString *s = [[_richEditor textView] string];
    NSMutableArray *ranges = [NSMutableArray array];
    NSUInteger pos = 0;
    while (pos < s.length) {
        NSRange open = [s rangeOfString:XFDTokenOpen options:0
                                  range:NSMakeRange(pos, s.length - pos)];
        if (open.location == NSNotFound) {
            break;
        }
        NSUInteger after = NSMaxRange(open);
        NSRange close = [s rangeOfString:XFDTokenClose options:0
                                   range:NSMakeRange(after, s.length - after)];
        if (close.location == NSNotFound) {
            break;
        }
        [ranges addObject:[NSValue valueWithRange:
            NSMakeRange(open.location, NSMaxRange(close) - open.location)]];
        pos = NSMaxRange(close);
    }
    return ranges;
}

/// The full ⟦expr⟧ range the caret sits in (or the selection touches) —
/// NSNotFound when the selection is not on a token. A caret exactly
/// before ⟦ or after ⟧ counts as outside, so adjacent typing stays
/// insertion.
- (NSRange)tokenRangeAtSelection
{
    NSRange sel = [[_richEditor textView] selectedRange];
    for (NSValue *value in [self tokenRanges]) {
        NSRange token = [value rangeValue];
        BOOL hit = sel.length == 0
            ? (sel.location > token.location && sel.location < NSMaxRange(token))
            : NSIntersectionRange(sel, token).length > 0;
        if (hit) {
            return token;
        }
    }
    return NSMakeRange(NSNotFound, 0);
}

/// Pills are ATOMIC: a selection endpoint may never rest inside a token.
/// A caret clicked into one selects the whole pill; a drag partially
/// across one swallows it whole. Arrowing "into" a pill therefore selects
/// it, and the next arrow steps past — the mail-merge field feel.
- (void)enforceAtomicTokenSelection
{
    if (_adjustingSelection || ![self onRichView]) {
        return;
    }
    NSTextView *tv = [_richEditor textView];
    NSRange sel = [tv selectedRange];
    NSRange adjusted = sel;
    for (NSValue *value in [self tokenRanges]) {
        NSRange token = [value rangeValue];
        if (adjusted.length == 0) {
            if (adjusted.location > token.location
                && adjusted.location < NSMaxRange(token)) {
                adjusted = token;
                break;
            }
        } else {
            NSUInteger start = adjusted.location;
            NSUInteger end = NSMaxRange(adjusted);
            if (start > token.location && start < NSMaxRange(token)) {
                start = token.location;
            }
            if (end > token.location && end < NSMaxRange(token)) {
                end = NSMaxRange(token);
            }
            adjusted = NSMakeRange(start, end - start);
        }
    }
    if (!NSEqualRanges(adjusted, sel)) {
        _adjustingSelection = YES;
        [tv setSelectedRange:adjusted];
        _adjustingSelection = NO;
    }
}

/// The one button serves both directions: on a pill it reads
/// "Edit Output…" and replaces that pill, elsewhere "Insert Output…".
- (void)refreshOutputButton
{
    BOOL onToken = [self onRichView]
        && [self tokenRangeAtSelection].location != NSNotFound;
    [_insertOutputButton setTitle:onToken ? @"Edit Output…" : @"Insert Output…"];
}

- (void)refreshGate
{
    [_insertOutputButton setEnabled:[self onRichView] && _processor != nil];
    [self refreshOutputButton];
    if ([self onRichView]) {
        [_okButton setEnabled:YES];
        [self setStatus:@"" isError:NO];
        return;
    }
    NSError *error = nil;
    BOOL ok = XFDParseFragment([[_sourceView string] copy], &error) != nil;
    [_okButton setEnabled:ok];
    [self setStatus:ok ? @"" : ([error localizedDescription] ?: @"The XML does not parse.")
            isError:!ok];
}

/// Tint every matched ⟦expr⟧ run so tokens read as objects, not typing.
/// Cosmetic only — the brackets are the truth, and the background
/// attribute means nothing to XFRichText's serializer.
- (void)retintTokens
{
    NSTextStorage *storage = [[_richEditor textView] textStorage];
    NSString *s = [storage string];
    [storage removeAttribute:NSBackgroundColorAttributeName
                       range:NSMakeRange(0, s.length)];
    NSColor *tint = [NSColor selectedTextBackgroundColor];
    NSUInteger pos = 0;
    while (pos < s.length) {
        NSRange open = [s rangeOfString:XFDTokenOpen options:0
                                  range:NSMakeRange(pos, s.length - pos)];
        if (open.location == NSNotFound) {
            break;
        }
        NSUInteger after = NSMaxRange(open);
        NSRange close = [s rangeOfString:XFDTokenClose options:0
                                   range:NSMakeRange(after, s.length - after)];
        if (close.location == NSNotFound) {
            break;
        }
        [storage addAttribute:NSBackgroundColorAttributeName value:tint
                        range:NSMakeRange(open.location, NSMaxRange(close) - open.location)];
        pos = NSMaxRange(close);
    }
}

- (void)showRichWithFragment:(NSString *)fragment
{
    [_richEditor setHTML:XFDTokenizeFragment(fragment)];
    [self retintTokens];
    [_viewControl setSelectedSegment:0];
    [_tabs selectTabViewItemAtIndex:0];
}

/// What the rich view holds, as the stored fragment (tokens back to
/// xf:output, a lone paragraph unwrapped — label content is inline).
- (NSString *)fragmentFromRichView
{
    return XFDDetokenizeFragment(XFDUnwrapSingleParagraph([_richEditor HTML]));
}

- (void)viewChanged:(id)sender
{
    (void)sender;
    if ([self onRichView]) {
        // Source → Rich: only when the fragment fits the subset
        NSString *fragment = [[_sourceView string] copy];
        if (!XFDFragmentIsRichEditable(fragment)) {
            [_viewControl setSelectedSegment:1];
            XFDBeep();
            [self setStatus:@"This markup is beyond the rich editor (attributes, foreign tags, …) — edit it as source."
                    isError:NO];
            return;
        }
        [self showRichWithFragment:fragment];
    } else {
        // Rich → Source: serialize what the editor holds
        [_sourceView setString:[self fragmentFromRichView]];
        [_tabs selectTabViewItemAtIndex:1];
    }
    [self refreshGate];
}

- (void)insertOutputClicked:(id)sender
{
    (void)sender;
    if (_processor == nil) {
        XFDBeep();
        return;
    }
    NSRange token = [self tokenRangeAtSelection];
    BOOL editing = token.location != NSNotFound;
    NSString *expr = [XFDXPathField runPickerForProcessor:_processor
                                              contextNode:_contextNode
                                              hostElement:_hostElement
                                                    title:editing ? @"Edit Output" : @"Insert Output"];
    if (expr.length == 0) {
        return;
    }
    NSTextView *tv = [_richEditor textView];
    NSString *pill = [NSString stringWithFormat:@"%@%@%@",
                      XFDTokenOpen, expr, XFDTokenClose];
    if (editing) {
        if ([tv shouldChangeTextInRange:token replacementString:pill]) {
            [[tv textStorage] replaceCharactersInRange:token withString:pill];
            [tv didChangeText];
            [tv setSelectedRange:NSMakeRange(token.location + pill.length, 0)];
        }
    } else {
        [tv insertText:pill];
    }
    [self retintTokens];
    [self refreshOutputButton];
}

- (void)okClicked:(id)sender
{
    (void)sender;
    _result = [self onRichView]
        ? [self fragmentFromRichView]
        : [[_sourceView string] copy];
    [NSApp stopModal];
}

- (void)cancelClicked:(id)sender
{
    (void)sender;
    _result = nil;
    [NSApp stopModal];
}

/* informal NSTextDelegate — GNUstep has no such protocol to conform to */
- (void)textDidChange:(NSNotification *)note
{
    (void)note;
    if ([self onRichView]) {
        [self retintTokens];
        [self refreshOutputButton];
    } else {
        [self refreshGate];
    }
}

- (void)textViewDidChangeSelection:(NSNotification *)note
{
    (void)note;
    if ([self onRichView]) {
        [self enforceAtomicTokenSelection];
        [self refreshOutputButton];
    }
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    if (textView == [_richEditor textView] && commandSelector == @selector(insertNewline:)) {
        return [_richEditor handleNewline];
    }
    // deleting against a pill's edge removes the WHOLE pill (a lone
    // bracket would leave a half-token that degrades to literal text)
    if (textView == [_richEditor textView]
        && (commandSelector == @selector(deleteBackward:)
            || commandSelector == @selector(deleteForward:))) {
        NSRange sel = [textView selectedRange];
        if (sel.length == 0) {
            BOOL backward = (commandSelector == @selector(deleteBackward:));
            for (NSValue *value in [self tokenRanges]) {
                NSRange token = [value rangeValue];
                if ((backward && NSMaxRange(token) == sel.location)
                    || (!backward && token.location == sel.location)) {
                    [textView setSelectedRange:token];
                    break;   // default delete now removes the selection
                }
            }
        }
    }
    return NO;
}

+ (NSString *)runWithFragment:(NSString *)fragment
                        title:(NSString *)title
                    processor:(XFProcessor *)processor
                  contextNode:(NSXMLNode *)contextNode
                  hostElement:(NSXMLElement *)hostElement
{
    XFDRichTextPanel *panel = [[XFDRichTextPanel alloc] init];
    panel->_processor = processor;
    panel->_contextNode = contextNode;
    panel->_hostElement = hostElement;
    [panel buildPanelWithTitle:title];
    [panel->_sourceView setString:fragment ?: @""];
    if (XFDFragmentIsRichEditable(fragment)) {
        [panel showRichWithFragment:fragment ?: @""];
    } else {
        [panel->_viewControl setSelectedSegment:1];
        [panel->_tabs selectTabViewItemAtIndex:1];
        [panel setStatus:@"This markup is beyond the rich editor (attributes, foreign tags, …) — edit it as source."
                 isError:NO];
    }
    [panel refreshGate];
    [panel->_panel center];
    [NSApp runModalForWindow:panel->_panel];
    [panel->_panel orderOut:nil];
    return panel->_result;
}

@end

#pragma mark - The field component

@interface XFDRichTextField () <NSTextFieldDelegate>
@property (nonatomic, strong) NSTextField *field;
@property (nonatomic, strong) NSButton *editButton;
@property (nonatomic, copy) NSString *xml;          /* rich fragment, nil = plain */
@property (nonatomic, assign) BOOL enabled;
@end

@implementation XFDRichTextField

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
    [self sendAction];
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
    NSXMLElement *wrap = XFDParseFragment(edited, NULL);
    BOOL plain = YES;
    for (NSXMLNode *c in [wrap children]) {
        if ([c kind] != NSXMLTextKind) {
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
    [self sendAction];
}

@end
