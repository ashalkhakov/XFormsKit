/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDRichTextPanel.h"
#import "XFDRichFragment.h"
#import "XFDXPathField.h"

// Its outlets (its XIB's connections), on the ivars above.
@interface XFDRichTextPanel ()
@property (nonatomic, strong) IBOutlet NSPanel *panel;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *viewControl;
@property (nonatomic, strong) IBOutlet NSButton *insertOutputButton;
@property (nonatomic, strong) IBOutlet NSTabView *tabs;
@property (nonatomic, strong) IBOutlet NSView *richHost;
@property (nonatomic, strong) IBOutlet NSTextView *sourceView;
@property (nonatomic, strong) IBOutlet NSTextField *statusField;
@property (nonatomic, strong) IBOutlet NSButton *okButton;
@end

@implementation XFDRichTextPanel

/// The panel from its XIB (XFDRichTextPanel.xib), the rich editor (made
/// with its base font, which a XIB cannot give it) in its host.
- (BOOL)loadPanelWithTitle:(NSString *)title
{
    NSArray *objects = nil;
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"XFDRichTextPanel"
                                          bundle:[NSBundle bundleForClass:[XFDRichTextPanel class]]];
    if (![nib instantiateWithOwner:self topLevelObjects:&objects] || _panel == nil) {
        NSLog(@"XFormsDesignKit: XFDRichTextPanel did not load");
        return NO;
    }
    _topLevelObjects = objects;
    [_panel setTitle:title];
    _richEditor = [[XFRichTextEditor alloc] initWithFrame:[_richHost bounds]
                                                 baseFont:[NSFont systemFontOfSize:13]];
    [_richEditor setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[_richEditor textView] setDelegate:(id)self];
    [_richHost addSubview:_richEditor];
    [_sourceView setFont:[NSFont userFixedPitchFontOfSize:11]];
    [[_sourceView textContainer] setWidthTracksTextView:YES];
    return YES;
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

- (IBAction)viewChanged:(id)sender
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

- (IBAction)insertOutputClicked:(id)sender
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

- (IBAction)okClicked:(id)sender
{
    (void)sender;
    _result = [self onRichView]
        ? [self fragmentFromRichView]
        : [[_sourceView string] copy];
    [NSApp stopModal];
}

- (IBAction)cancelClicked:(id)sender
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
                  contextNode:(XFXMLNode *)contextNode
                  hostElement:(XFXMLElement *)hostElement
{
    XFDRichTextPanel *panel = [[XFDRichTextPanel alloc] init];
    panel->_processor = processor;
    panel->_contextNode = contextNode;
    panel->_hostElement = hostElement;
    if (![panel loadPanelWithTitle:title]) {
        return nil;
    }
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
