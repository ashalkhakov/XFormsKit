#import "XFAppKitPriv.h"

void XFAppKitHasRichTextEditorFile(void) {}

#pragma mark - XFRichTextEditor

@implementation XFRichTextEditor

static const CGFloat kRichToolbarHeight = 24;

- (instancetype)initWithFrame:(NSRect)frame baseFont:(NSFont *)font
{
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }
    _baseFont = font ?: [NSFont systemFontOfSize:13];

    CGFloat x = 0;
    _blockPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 110, kRichToolbarHeight) pullsDown:NO];
    NSArray *blocks = @[ @"Paragraph", @"Heading 1", @"Heading 2", @"Heading 3", @"• List", @"1. List" ];
    NSArray *kinds = @[ @"p", @"h1", @"h2", @"h3", @"ul", @"ol" ];
    for (NSUInteger i = 0; i < blocks.count; i++) {
        [_blockPopup addItemWithTitle:blocks[i]];
        [[_blockPopup lastItem] setRepresentedObject:kinds[i]];
    }
    [_blockPopup setTarget:self];
    [_blockPopup setAction:@selector(blockChanged:)];
    [self addSubview:_blockPopup];
    x += 116;

    NSArray *labels = @[ @"B", @"I", @"U", @"S" ];
    NSArray *actions = @[ NSStringFromSelector(@selector(toggleRichBold:)),
                          NSStringFromSelector(@selector(toggleRichItalic:)),
                          NSStringFromSelector(@selector(toggleRichUnderline:)),
                          NSStringFromSelector(@selector(toggleRichStrike:)) ];
    NSFontManager *fm = [NSFontManager sharedFontManager];
    for (NSUInteger i = 0; i < labels.count; i++) {
        NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(x, 0, 28, kRichToolbarHeight)];
        [b setTitle:labels[i]];
        [b setBezelStyle:NSRoundedBezelStyle];
        NSFont *bf = [NSFont systemFontOfSize:12];
        if (i == 0) bf = [fm convertFont:bf toHaveTrait:NSBoldFontMask] ?: bf;
        if (i == 1) bf = [fm convertFont:bf toHaveTrait:NSItalicFontMask] ?: bf;
        [b setFont:bf];
        [b setTarget:self];
        [b setAction:NSSelectorFromString(actions[i])];
        [b setRefusesFirstResponder:YES];
        [self addSubview:b];
        x += 30;
    }
    [_blockPopup setRefusesFirstResponder:YES];

    NSRect body = NSMakeRect(0, kRichToolbarHeight + 2,
                             NSWidth(frame), NSHeight(frame) - kRichToolbarHeight - 2);
    _scrollView = [[NSScrollView alloc] initWithFrame:body];
    [_scrollView setHasVerticalScroller:YES];
    [_scrollView setBorderType:NSBezelBorder];
    [_scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    _textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(body), NSHeight(body))];
    [_textView setRichText:YES];
    [_textView setAllowsUndo:YES];
    [_textView setTypingAttributes:@{ NSFontAttributeName: _baseFont }];
    [_textView setAutoresizingMask:NSViewWidthSizable];
    [_textView setVerticallyResizable:YES];
    [_textView setHorizontallyResizable:NO];
    [[_textView textContainer] setWidthTracksTextView:YES];
    [_scrollView setDocumentView:_textView];
    [self addSubview:_scrollView];
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)setHTML:(NSString *)html
{
    NSAttributedString *rich = [XFRichText attributedStringFromHTML:html ?: @"" baseFont:self.baseFont];
    [[self.textView textStorage] setAttributedString:rich];
    [self.textView setTypingAttributes:@{ NSFontAttributeName: self.baseFont }];
}

- (NSString *)HTML
{
    return [XFRichText htmlFromAttributedString:[self.textView textStorage]];
}

#pragma mark inline formatting

/// Toggle `marker` over the selection (or the typing attributes when the
/// selection is empty); bold/italic also swap the font of each run.
- (void)toggleMarker:(NSString *)marker
{
    NSTextView *tv = self.textView;
    NSRange sel = [tv selectedRange];
    BOOL fontTrait = [marker isEqualToString:XFRichBoldAttributeName]
        || [marker isEqualToString:XFRichItalicAttributeName];
    if (sel.length == 0) {
        NSMutableDictionary *typing = [[tv typingAttributes] mutableCopy] ?: [NSMutableDictionary dictionary];
        BOOL on = [typing[marker] boolValue] || [typing[marker] integerValue];
        if ([marker isEqualToString:(NSString *)NSUnderlineStyleAttributeName]
            || [marker isEqualToString:(NSString *)NSStrikethroughStyleAttributeName]) {
            if (on) [typing removeObjectForKey:marker];
            else typing[marker] = @(NSUnderlineStyleSingle);
        } else {
            if (on) [typing removeObjectForKey:marker];
            else typing[marker] = @YES;
        }
        if (fontTrait) {
            typing[NSFontAttributeName] =
                [XFRichText fontForBlock:typing[XFRichBlockAttributeName]
                                    bold:[typing[XFRichBoldAttributeName] boolValue]
                                  italic:[typing[XFRichItalicAttributeName] boolValue]
                                baseFont:self.baseFont];
        }
        [tv setTypingAttributes:typing];
        return;
    }
    NSTextStorage *storage = [tv textStorage];
    BOOL on = [storage attribute:marker atIndex:sel.location effectiveRange:NULL] != nil;
    [storage beginEditing];
    NSUInteger i = sel.location;
    while (i < NSMaxRange(sel)) {   // no GNUstep enumerateAttributesInRange:
        NSRange range;
        NSMutableDictionary *a = [[storage attributesAtIndex:i effectiveRange:&range] mutableCopy];
        range = NSIntersectionRange(range, sel);
        if (on) {
            [a removeObjectForKey:marker];
        } else if ([marker isEqualToString:(NSString *)NSUnderlineStyleAttributeName]
                   || [marker isEqualToString:(NSString *)NSStrikethroughStyleAttributeName]) {
            a[marker] = @(NSUnderlineStyleSingle);
        } else {
            a[marker] = @YES;
        }
        if (fontTrait) {
            a[NSFontAttributeName] = [XFRichText fontForBlock:a[XFRichBlockAttributeName]
                                                         bold:[a[XFRichBoldAttributeName] boolValue]
                                                       italic:[a[XFRichItalicAttributeName] boolValue]
                                                     baseFont:self.baseFont];
        }
        [storage setAttributes:a range:range];
        i = NSMaxRange(range);
    }
    [storage endEditing];
    [self noteEdited];
}

- (void)toggleRichBold:(id)sender { (void)sender; [self toggleMarker:XFRichBoldAttributeName]; }
- (void)toggleRichItalic:(id)sender { (void)sender; [self toggleMarker:XFRichItalicAttributeName]; }
- (void)toggleRichUnderline:(id)sender { (void)sender; [self toggleMarker:(NSString *)NSUnderlineStyleAttributeName]; }
- (void)toggleRichStrike:(id)sender { (void)sender; [self toggleMarker:(NSString *)NSStrikethroughStyleAttributeName]; }

#pragma mark block formatting

static NSString *XFRichListPrefix(NSString *text)
{
    if ([text hasPrefix:@"• "]) {
        return @"• ";
    }
    NSUInteger d = 0;
    while (d < text.length && [text characterAtIndex:d] >= '0' && [text characterAtIndex:d] <= '9') {
        d++;
    }
    if (d > 0 && d < text.length && [text characterAtIndex:d] == '.') {
        NSUInteger end = d + 1;
        if (end < text.length && [text characterAtIndex:end] == ' ') {
            end++;
        }
        return [text substringToIndex:end];
    }
    return nil;
}

- (void)blockChanged:(id)sender
{
    (void)sender;
    NSString *kind = [[self.blockPopup selectedItem] representedObject] ?: @"p";
    NSTextView *tv = self.textView;
    NSTextStorage *storage = [tv textStorage];
    NSRange paragraphs = [[storage string] paragraphRangeForRange:[tv selectedRange]];
    [storage beginEditing];
    // walk paragraph by paragraph (ranges shift as prefixes change)
    NSUInteger loc = paragraphs.location;
    NSUInteger endLoc = NSMaxRange(paragraphs);
    while (loc < storage.length && loc < endLoc) {
        NSRange para = [[storage string] paragraphRangeForRange:NSMakeRange(loc, 0)];
        NSRange body = para;
        while (NSMaxRange(body) > body.location) {   // exclude the trailing \n
            unichar c = [[storage string] characterAtIndex:NSMaxRange(body) - 1];
            if (c == '\n') body.length--;
            else break;
        }
        NSString *text = [[storage string] substringWithRange:body];
        NSString *oldPrefix = XFRichListPrefix(text);
        BOOL list = [kind isEqualToString:@"ul"] || [kind isEqualToString:@"ol"];
        NSInteger delta = 0;
        if (oldPrefix && (!list)) {
            [storage deleteCharactersInRange:NSMakeRange(body.location, oldPrefix.length)];
            delta -= (NSInteger)oldPrefix.length;
        } else if (list) {
            NSString *want = [kind isEqualToString:@"ul"] ? @"• " : @"1. ";
            if (oldPrefix == nil) {
                [storage insertAttributedString:
                    [[NSAttributedString alloc] initWithString:want
                        attributes:@{ NSFontAttributeName: self.baseFont }]
                                        atIndex:body.location];
                delta += (NSInteger)want.length;
            }
        }
        body.length = (NSUInteger)((NSInteger)body.length + delta);
        endLoc = (NSUInteger)((NSInteger)endLoc + delta);
        // block attribute + fonts over the paragraph body
        NSRange target = NSMakeRange(body.location, body.length);
        if (target.length == 0 && body.location >= storage.length) {
            break;
        }
        NSUInteger ai = target.location;
        while (ai < NSMaxRange(target)) {
            NSRange range;
            NSMutableDictionary *a = [[storage attributesAtIndex:ai effectiveRange:&range] mutableCopy];
            range = NSIntersectionRange(range, target);
            if ([kind isEqualToString:@"p"]) {
                [a removeObjectForKey:XFRichBlockAttributeName];
            } else {
                a[XFRichBlockAttributeName] = kind;
            }
            a[NSFontAttributeName] = [XFRichText fontForBlock:kind
                                                         bold:[a[XFRichBoldAttributeName] boolValue]
                                                       italic:[a[XFRichItalicAttributeName] boolValue]
                                                     baseFont:self.baseFont];
            [storage setAttributes:a range:range];
            ai = NSMaxRange(range);
        }
        loc = NSMaxRange(para) == para.location ? para.location + 1
            : (NSUInteger)((NSInteger)NSMaxRange(para) + delta);
    }
    [self renumberLists:storage];
    [storage endEditing];
    // an empty caret paragraph (empty document, or the line after a
    // trailing newline) gets its bullet right away — outside the editing
    // batch: moving the selection mid-batch asks the layout manager for
    // glyphs it has not generated yet (GNUstep raises)
    BOOL isList = [kind isEqualToString:@"ul"] || [kind isEqualToString:@"ol"];
    if (isList) {
        NSRange sel2 = [tv selectedRange];
        NSRange para2 = storage.length ? [[storage string] paragraphRangeForRange:sel2] : NSMakeRange(0, 0);
        NSRange body2 = para2;
        while (body2.length && [[storage string] characterAtIndex:NSMaxRange(body2) - 1] == '\n') {
            body2.length--;
        }
        if (body2.length == 0) {
            NSString *want = [kind isEqualToString:@"ul"] ? @"• " : @"1. ";
            NSDictionary *attrs = @{ NSFontAttributeName: self.baseFont, XFRichBlockAttributeName: kind };
            [storage insertAttributedString:[[NSAttributedString alloc] initWithString:want attributes:attrs]
                                    atIndex:body2.location];
            [self renumberLists:storage];
            [tv setSelectedRange:NSMakeRange(body2.location + want.length, 0)];
        }
    }
    // typing attributes for an empty paragraph / caret
    NSMutableDictionary *typing = [[tv typingAttributes] mutableCopy] ?: [NSMutableDictionary dictionary];
    if ([kind isEqualToString:@"p"]) {
        [typing removeObjectForKey:XFRichBlockAttributeName];
    } else {
        typing[XFRichBlockAttributeName] = kind;
    }
    typing[NSFontAttributeName] = [XFRichText fontForBlock:kind
                                                      bold:[typing[XFRichBoldAttributeName] boolValue]
                                                    italic:[typing[XFRichItalicAttributeName] boolValue]
                                                  baseFont:self.baseFont];
    [tv setTypingAttributes:typing];
    [self noteEdited];
}

/// Consecutive "ol" paragraphs get 1., 2., … (display only; the serializer
/// strips the prefixes).
- (void)renumberLists:(NSTextStorage *)storage
{
    NSString *string = [storage string];
    NSUInteger loc = 0;
    NSUInteger number = 1;
    while (loc < storage.length) {
        NSRange para = [string paragraphRangeForRange:NSMakeRange(loc, 0)];
        NSRange body = para;
        while (body.length && [string characterAtIndex:NSMaxRange(body) - 1] == '\n') {
            body.length--;
        }
        NSString *block = body.length
            ? [storage attribute:XFRichBlockAttributeName atIndex:body.location effectiveRange:NULL] : nil;
        if ([block isEqualToString:@"ol"]) {
            NSString *text = [string substringWithRange:body];
            NSString *prefix = XFRichListPrefix(text);
            NSString *want = [NSString stringWithFormat:@"%lu. ", (unsigned long)number++];
            if (![prefix isEqualToString:want]) {
                NSDictionary *attrs = [storage attributesAtIndex:body.location effectiveRange:NULL];
                if (prefix) {
                    [storage deleteCharactersInRange:NSMakeRange(body.location, prefix.length)];
                }
                [storage insertAttributedString:
                    [[NSAttributedString alloc] initWithString:want attributes:attrs]
                                        atIndex:body.location];
                string = [storage string];
                para = [string paragraphRangeForRange:NSMakeRange(body.location, 0)];
            }
        } else {
            number = 1;
        }
        if (NSMaxRange(para) <= loc) {
            break;
        }
        loc = NSMaxRange(para);
        string = [storage string];
    }
}

- (BOOL)handleNewline
{
    NSTextView *tv = self.textView;
    NSTextStorage *storage = [tv textStorage];
    NSRange sel = [tv selectedRange];
    NSString *string = [storage string];
    if (storage.length == 0) {
        return NO;
    }
    NSRange para = [string paragraphRangeForRange:sel];
    NSRange body = para;
    while (body.length && [string characterAtIndex:NSMaxRange(body) - 1] == '\n') {
        body.length--;
    }
    NSString *block = body.length
        ? [storage attribute:XFRichBlockAttributeName atIndex:body.location effectiveRange:NULL]
        : [tv typingAttributes][XFRichBlockAttributeName];
    if (!([block isEqualToString:@"ul"] || [block isEqualToString:@"ol"])) {
        return NO;
    }
    NSString *text = [string substringWithRange:body];
    NSString *prefix = XFRichListPrefix(text);
    if (prefix && text.length == prefix.length && NSMaxRange(sel) >= NSMaxRange(body)) {
        // Return on an empty item: leave the list (what every editor does)
        NSRange prefixRange = NSMakeRange(body.location, prefix.length);
        if ([tv shouldChangeTextInRange:prefixRange replacementString:@""]) {
            [storage deleteCharactersInRange:prefixRange];
            // typed text inherits from the character before the caret — the
            // previous item's newline; take the list marker off it so the
            // new paragraph is a plain one
            if (body.location > 0 && [[storage string] characterAtIndex:body.location - 1] == '\n') {
                [storage removeAttribute:XFRichBlockAttributeName
                                   range:NSMakeRange(body.location - 1, 1)];
            }
            [self renumberLists:storage];
            [tv didChangeText];
        }
        // selection first: changing it resets the typing attributes from
        // the neighbouring (list) text
        [tv setSelectedRange:NSMakeRange(body.location, 0)];
        NSMutableDictionary *typing = [[tv typingAttributes] mutableCopy] ?: [NSMutableDictionary dictionary];
        [typing removeObjectForKey:XFRichBlockAttributeName];
        typing[NSFontAttributeName] = [XFRichText fontForBlock:nil
                                                          bold:[typing[XFRichBoldAttributeName] boolValue]
                                                        italic:[typing[XFRichItalicAttributeName] boolValue]
                                                      baseFont:self.baseFont];
        [tv setTypingAttributes:typing];
        return YES;
    }
    // continue the list on the next line
    NSString *want = [block isEqualToString:@"ul"] ? @"• " : @"1. ";
    NSString *insert = [@"\n" stringByAppendingString:want];
    if ([tv shouldChangeTextInRange:sel replacementString:insert]) {
        NSMutableDictionary *attrs = [[storage attributesAtIndex:body.location effectiveRange:NULL] mutableCopy];
        attrs[XFRichBlockAttributeName] = block;
        [storage replaceCharactersInRange:sel
                     withAttributedString:[[NSAttributedString alloc] initWithString:insert attributes:attrs]];
        [tv setSelectedRange:NSMakeRange(sel.location + insert.length, 0)];
        [self renumberLists:storage];
        [tv didChangeText];
    }
    return YES;
}

- (void)noteEdited
{
    // formatting changes go through the same commit as typing
    NSNotification *note = [NSNotification notificationWithName:NSTextDidChangeNotification object:self.textView];
    id delegate = [self.textView delegate];
    if ([delegate respondsToSelector:@selector(textDidChange:)]) {
        [delegate textDidChange:note];
    }
}

@end
