/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#import "XFDExpressionField.h"
#import "XFDXPathTextStorage.h"

@interface XFDExpressionField () <NSTextViewDelegate>
@end

@implementation XFDExpressionField {
    NSScrollView *_scroll;
    NSTextView *_textView;
    XFDXPathTextStorage *_storage;
    NSFont *_font;
}

@dynamic stringValue;

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self build];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self build];
    }
    return self;
}

- (void)build
{
    _font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    NSRect bounds = [self bounds];
    _scroll = [[NSScrollView alloc] initWithFrame:bounds];
    [_scroll setBorderType:NSBezelBorder];
    [_scroll setHasVerticalScroller:NO];
    [_scroll setHasHorizontalScroller:NO];
    [_scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_scroll setDrawsBackground:YES];

    NSRect inner = [[_scroll contentView] bounds];
    _textView = [[NSTextView alloc] initWithFrame:inner];
    // the field behaviours: Return ends editing, Tab leaves the control,
    // and there is no rich-text pasting to undo the colouring
    [_textView setFieldEditor:YES];
    [_textView setRichText:NO];
    [_textView setImportsGraphics:NO];
    [_textView setAllowsUndo:YES];
    [_textView setHorizontallyResizable:YES];
    [_textView setVerticallyResizable:NO];
    [[_textView textContainer] setWidthTracksTextView:NO];
    [[_textView textContainer] setContainerSize:NSMakeSize(CGFLOAT_MAX, inner.size.height)];
    [_textView setDelegate:self];
    [_textView setFont:_font];
    [_scroll setDocumentView:_textView];
    [self addSubview:_scroll];

    // ALWAYS highlighted: the storage is the only thing that colours, and
    // it is installed for the life of the control
    _storage = [XFDXPathTextStorage installedInTextView:_textView];
    [self applyBaseAttributes];
}

- (void)applyBaseAttributes
{
    NSMutableDictionary *base = [NSMutableDictionary dictionary];
    if (_font != nil) {
        base[NSFontAttributeName] = _font;
    }
    base[NSForegroundColorAttributeName] = [NSColor controlTextColor];
    _storage.baseAttributes = base;
}

#pragma mark value

- (NSString *)stringValue
{
    return [_textView string] ?: @"";
}

- (void)setStringValue:(NSString *)value
{
    NSString *text = value ?: @"";
    if ([[_textView string] isEqualToString:text]) {
        return;
    }
    // through the storage, so it colours exactly as typing would
    [_storage replaceCharactersInRange:NSMakeRange(0, _storage.length) withString:text];
    [self setNeedsDisplay:YES];
}

- (void)setInvalid:(BOOL)invalid
{
    _invalid = invalid;
    _storage.invalid = invalid;
}

- (void)setFont:(NSFont *)font
{
    _font = font;
    [_textView setFont:font];
    [self applyBaseAttributes];
}

- (void)setEnabled:(BOOL)enabled
{
    [_textView setEditable:enabled];
    [_textView setSelectable:YES];
    [_scroll setBackgroundColor:enabled ? [NSColor textBackgroundColor]
                                        : [NSColor controlBackgroundColor]];
}

- (void)setPlaceholderString:(NSString *)placeholderString
{
    _placeholderString = [placeholderString copy];
    [self setNeedsDisplay:YES];
}

/// NSTextView has no placeholder of its own.
- (void)drawRect:(NSRect)dirty
{
    [super drawRect:dirty];
    if (_placeholderString.length == 0 || [self stringValue].length > 0) {
        return;
    }
    NSDictionary *attrs = @{
        NSFontAttributeName: _font ?: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]],
        NSForegroundColorAttributeName: [NSColor disabledControlTextColor],
    };
    NSRect box = NSInsetRect([self bounds], 6, 0);
    NSSize size = [_placeholderString sizeWithAttributes:attrs];
    box.origin.y = NSMidY([self bounds]) - size.height / 2;
    box.size.height = size.height;
    [_placeholderString drawInRect:box withAttributes:attrs];
}

#pragma mark focus

- (BOOL)acceptsFirstResponder
{
    return [_textView isEditable];
}

- (BOOL)becomeFirstResponder
{
    return [[self window] makeFirstResponder:_textView];
}

#pragma mark NSTextViewDelegate → NSControl's notifications

- (void)textDidChange:(NSNotification *)note
{
    (void)note;
    [self setNeedsDisplay:YES];   // the placeholder may have gone
    if ([self.delegate respondsToSelector:@selector(controlTextDidChange:)]) {
        [self.delegate controlTextDidChange:
            [NSNotification notificationWithName:NSControlTextDidChangeNotification
                                          object:self]];
    }
}

- (void)textDidEndEditing:(NSNotification *)note
{
    (void)note;
    if ([self.delegate respondsToSelector:@selector(controlTextDidEndEditing:)]) {
        [self.delegate controlTextDidEndEditing:
            [NSNotification notificationWithName:NSControlTextDidEndEditingNotification
                                          object:self]];
    }
    if (self.target != nil && self.action != NULL) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.target performSelector:self.action withObject:self];
#pragma clang diagnostic pop
    }
}

@end
