#import "XFAppKitPriv.h"

void XFAppKitHasLayoutFile(void) {}

@implementation XFFormView (XFLayout)

#pragma mark - Block controls

/// Block placement of a control (label column + field column), the
/// XFormsKit default for a control that stands on its own line.
- (CGFloat)layoutControl:(XFControl *)control atY:(CGFloat)y indent:(CGFloat)indent
{
    if ([control isKindOfClass:[XFVarControl class]] || [control isKindOfClass:[XFDialog class]]) {
        return y;   // xf:var has no widget; xf:dialog is presented by the host (G-93)
    }
    if (!control.relevant) {
        // XSLTForms marks a non-relevant control xforms-disabled, which is
        // display:none for the whole control incl. its label, so it takes no
        // space. The form is rebuilt on every change, so it reappears later.
        return y;
    }
    if ([control isKindOfClass:[XFGroup class]]) {
        return [self layoutGroup:(XFGroup *)control atY:y indent:indent];
    }
    if ([control isKindOfClass:[XFRepeat class]]) {
        return [self layoutRepeat:(XFRepeat *)control atY:y indent:indent];
    }
    if ([control isKindOfClass:[XFSwitch class]]) {
        XFSwitch *sw = (XFSwitch *)control;
        if (sw.selectedCase) {
            return [self layoutControl:sw.selectedCase atY:y indent:indent];
        }
        return y;
    }
    if ([control isKindOfClass:[XFCase class]]) {
        return [self layoutNodes:[(XFCase *)control hostNodes] atY:y indent:indent font:nil];
    }

    if ([control isKindOfClass:[XFSelectControl class]]) {
        XFSelectControl *select = (XFSelectControl *)control;
        if (select.multiple || [select.appearance isEqualToString:@"full"]) {
            CGFloat cursor = y;
            if (control.label.length) {
                NSTextField *caption = [self makeLabel:control.label];
                [caption setFrame:NSMakeRect(kMargin + indent, cursor, kLabelWidth + kFieldWidth, kRowHeight)];
                [self addSubview:caption];
                [self noteRight:NSMaxX([caption frame])];
                cursor += kRowHeight + 4;
            }
            NSString *lastGroup = nil;
            for (XFItem *item in select.items) {
                if (item.groupLabel.length && ![item.groupLabel isEqualToString:lastGroup]) {
                    NSTextField *head = [self makeLabel:item.groupLabel];
                    [head setFrame:NSMakeRect(kMargin + indent, cursor, kLabelWidth + kFieldWidth, kRowHeight)];
                    [self addSubview:head];
                    cursor += kRowHeight + 2;
                    lastGroup = item.groupLabel;
                }
                NSButton *box = [[NSButton alloc] initWithFrame:NSZeroRect];
                [box setButtonType:select.multiple ? NSSwitchButton : NSRadioButton];
                [box setTitle:item.label ?: item.value ?: @""];
                [box setState:item.selected ? NSOnState : NSOffState];
                [box setTarget:self];
                [box setAction:@selector(checkClicked:)];
                XFWidget *w = [self addWidget:control view:box height:kRowHeight atY:cursor indent:indent];
                w.view.toolTip = item.value;
                (void)w;
                cursor += kRowHeight + 4;
            }
            return cursor + kRowGap;
        }
    }

    CGFloat height = kRowHeight;
    NSView *view = [self makeViewForControl:control height:&height];
    XFWidget *w = [self addWidget:control view:view height:height atY:y indent:indent];
    if ([view isKindOfClass:[NSButton class]] && [control isKindOfClass:[XFInputControl class]]) {
        w.labelField = nil;
    }
    return y + height + kRowGap;
}

- (CGFloat)layoutGroup:(XFGroup *)group atY:(CGFloat)y indent:(CGFloat)indent
{
    NSBox *box = [[NSBox alloc] initWithFrame:NSZeroRect];
    [box setTitle:group.label ?: @""];
    [box setTitlePosition:group.label.length ? NSAtTop : NSNoTitle];
    CGFloat inner = y + (group.label.length ? 22 : 8);
    CGFloat start = inner;
    CGFloat outerRight = self.maxRight;
    self.maxRight = 0;
    inner = [self layoutNodes:group.hostNodes atY:inner indent:indent + kIndent font:nil];
    // the box must enclose the last line of its content: its height runs
    // from the box top (title included) to the content bottom plus padding
    (void)start;
    CGFloat h = (inner - y) + 10;
    // Wide enough to enclose the widest child (children are indented by
    // kIndent, so the box must extend that far past them on the right too),
    // and never narrower than one standard row.
    CGFloat left = kMargin + indent;
    CGFloat right = MAX(self.maxRight + kIndent, left + kIndent + kLabelWidth + 8 + kFieldWidth + kIndent);
    [box setFrame:NSMakeRect(left, y, right - left, MAX(h, 28))];
    self.maxRight = MAX(outerRight, right);
    // Children already added to the form; the box is a visual frame behind them.
    [self addSubview:box positioned:NSWindowBelow relativeTo:nil];
    if (!group.relevant) {
        [box setHidden:YES];
    }
    return inner + kRowGap;
}

- (CGFloat)layoutRepeat:(XFRepeat *)repeat atY:(CGFloat)y indent:(CGFloat)indent
{
    CGFloat cursor = y;
    NSUInteger i = 0;
    for (XFRepeatItem *item in repeat.items) {
        if (repeat.label.length && i == 0) {
            NSTextField *cap = [self makeLabel:repeat.label];
            [cap setFrame:NSMakeRect(kMargin + indent, cursor, kLabelWidth + kFieldWidth, kRowHeight)];
            [self addSubview:cap];
            [self noteRight:NSMaxX([cap frame])];
            cursor += kRowHeight + 4;
        }
        // The item's content is the repeat's host markup instantiated for
        // its node (G-20): host blocks keep their structure, controls in
        // <td>/<p>/<span> flow where the markup puts them.
        cursor = [self layoutNodes:item.hostNodes atY:cursor indent:indent + kIndent font:nil];
        i++;
    }
    return cursor;
}

#pragma mark - Host markup (G-20)

- (NSFont *)bodyFont
{
    return [NSFont systemFontOfSize:0];
}

- (NSFont *)fontForTag:(NSString *)tag base:(NSFont *)base
{
    NSFont *font = base ?: [self bodyFont];
    NSFontManager *fm = [NSFontManager sharedFontManager];
    if ([tag isEqualToString:@"b"] || [tag isEqualToString:@"strong"] || [tag isEqualToString:@"th"]) {
        return [fm convertFont:font toHaveTrait:NSBoldFontMask];
    }
    if ([tag isEqualToString:@"i"] || [tag isEqualToString:@"em"] || [tag isEqualToString:@"cite"]
        || [tag isEqualToString:@"var"]) {
        return [fm convertFont:font toHaveTrait:NSItalicFontMask];
    }
    if ([tag isEqualToString:@"code"] || [tag isEqualToString:@"tt"] || [tag isEqualToString:@"kbd"]
        || [tag isEqualToString:@"samp"] || [tag isEqualToString:@"pre"]) {
        return [NSFont userFixedPitchFontOfSize:[font pointSize]];
    }
    if ([tag isEqualToString:@"small"]) {
        return [fm convertFont:font toSize:MAX(9, [font pointSize] - 2)];
    }
    if ([tag isEqualToString:@"big"]) {
        return [fm convertFont:font toSize:[font pointSize] + 2];
    }
    return font;
}

- (NSFont *)headingFontForLevel:(NSInteger)level
{
    CGFloat base = [[self bodyFont] pointSize];
    CGFloat size = base;
    switch (level) {
        case 1: size = base + 9; break;
        case 2: size = base + 6; break;
        case 3: size = base + 3; break;
        default: size = base + 1; break;
    }
    return [NSFont boldSystemFontOfSize:size];
}

- (CGFloat)lineHeightForFont:(NSFont *)font
{
    CGFloat h = ceil([font ascender] - [font descender] + [font leading]);
    return MAX(h + 4, kRowHeight);
}

/// Text width for layout; falls back to an estimate when the backend has
/// no font metrics (headless GNUstep) so runs still wrap sensibly.
- (CGFloat)widthOfText:(NSString *)text font:(NSFont *)font
{
    CGFloat measured = [text sizeWithAttributes:@{ NSFontAttributeName: font }].width;
    CGFloat estimate = text.length * [font pointSize] * 0.55;
    return ceil(MAX(measured, estimate));
}

- (NSTextField *)makeText:(NSString *)text font:(NSFont *)font
{
    NSTextField *field = [self makeLabel:text];
    [field setFont:font];
    [field setSelectable:YES];
    return field;
}

/// Flatten an inline subtree into atoms (text with font, controls, breaks).
- (void)collectAtomsFrom:(NSArray<XFHostNode *> *)nodes
                    font:(NSFont *)font
                    into:(NSMutableArray<XFLayoutAtom *> *)atoms
{
    for (XFHostNode *node in nodes) {
        XFLayoutAtom *atom = [[XFLayoutAtom alloc] init];
        switch (node.kind) {
            case XFHostNodeKindText:
                atom.kind = XFAtomText;
                atom.text = node.text ?: @"";
                atom.font = font;
                atom.preformatted = node.preformatted;
                [atoms addObject:atom];
                break;
            case XFHostNodeKindBreak:
                atom.kind = XFAtomBreak;
                [atoms addObject:atom];
                break;
            case XFHostNodeKindControl:
                if (node.control) {
                    atom.kind = XFAtomControl;
                    atom.control = node.control;
                    [atoms addObject:atom];
                }
                break;
            case XFHostNodeKindInline:
                [self collectAtomsFrom:node.children font:[self fontForTag:node.tag base:font] into:atoms];
                break;
            case XFHostNodeKindTableCell: {
                // cells flattened into the row's run, separated by a gap
                NSFont *f = node.header ? [self fontForTag:@"th" base:font] : font;
                [self collectAtomsFrom:node.children font:f into:atoms];
                XFLayoutAtom *gap = [[XFLayoutAtom alloc] init];
                gap.kind = XFAtomSpace;
                [atoms addObject:gap];
                break;
            }
            default:
                // a block nested in inline context: flatten its content
                [self collectAtomsFrom:node.children font:[self fontForTag:node.tag base:font] into:atoms];
                break;
        }
    }
}

/// Inline placement of a control: caption (natural width) + widget, both
/// on the current line.
- (CGFloat)placeInlineControl:(XFControl *)control
                            x:(CGFloat *)x
                            y:(CGFloat)y
                         left:(CGFloat)left
                   lineHeight:(CGFloat *)lineHeight
                       lineY:(CGFloat *)lineY
{
    CGFloat height = kRowHeight;
    NSView *view = [self makeViewForControl:control height:&height];
    if (view == nil) {
        return y;
    }
    NSTextField *caption = nil;
    CGFloat captionWidth = 0;
    if (control.label.length && ![self viewCarriesLabel:view control:control]) {
        NSString *text = control.required
            ? [NSString stringWithFormat:@"%@ *", control.label]
            : control.label;
        caption = [self makeLabel:text];
        captionWidth = [self widthOfText:text font:[caption font] ?: [self bodyFont]] + 6;
    }
    CGFloat width;
    if ([view isKindOfClass:[NSTextField class]] && ![(NSTextField *)view isEditable]) {
        NSTextField *tf = (NSTextField *)view;
        width = MAX([self widthOfText:[tf stringValue] font:[tf font] ?: [self bodyFont]] + 4, 8);
    } else if ([view isKindOfClass:[NSPopUpButton class]]) {
        CGFloat widest = 0;
        for (NSMenuItem *item in [(NSPopUpButton *)view itemArray]) {
            widest = MAX(widest, [self widthOfText:[item title] font:[self bodyFont]]);
        }
        width = widest + 40;
    } else if ([view isKindOfClass:[NSButton class]]) {
        [(NSControl *)view sizeToFit];
        NSString *title = [(NSButton *)view title] ?: @"";
        width = MAX(ceil([view frame].size.width) + 8, [self widthOfText:title font:[self bodyFont]] + 30);
    } else if ([view isKindOfClass:[NSScrollView class]]) {
        width = kFieldWidth;
    } else if ([view isKindOfClass:[NSImageView class]]) {
        width = 96;
    } else {
        width = kInlineFieldWidth;
    }
    CGFloat total = captionWidth + width;
    if (*x + total > self.wrapRight && *x > left) {
        *lineY += *lineHeight + kLineGap;
        *lineHeight = 0;
        *x = left;
    }
    XFWidget *w = [[XFWidget alloc] init];
    w.control = control;
    w.view = view;
    w.height = height;
    if (caption) {
        if (!control.valid && [caption respondsToSelector:@selector(setTextColor:)]) {
            [caption setTextColor:[NSColor redColor]];
        }
        [caption setFrame:NSMakeRect(*x, *lineY, captionWidth, kRowHeight)];
        [self addSubview:caption];
        w.labelField = caption;
        *x += captionWidth;
    }
    [view setFrame:NSMakeRect(*x, *lineY, width, height)];
    [self addSubview:view];
    [self.widgets addObject:w];
    [self registerKeyView:XFKeyViewOf(view) control:control];
    objc_setAssociatedObject(view, kXFBoundControlKey, control, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self applyEnabled:view control:control];
    *x += width + 6;
    [self noteRight:*x];
    *lineHeight = MAX(*lineHeight, height);
    return *lineY;
}

/// Lay out one inline run (a paragraph's worth of atoms) with word
/// wrapping at `wrapRight`. Returns the y below the last line.
- (CGFloat)layoutAtoms:(NSArray<XFLayoutAtom *> *)atoms atY:(CGFloat)y indent:(CGFloat)indent
{
    CGFloat left = kMargin + indent;
    __block CGFloat x = left;
    __block CGFloat lineY = y;
    __block CGFloat lineHeight = 0;
    BOOL anything = NO;

    NSMutableString *segment = [NSMutableString string];
    __block CGFloat segmentWidth = 0;
    __block NSFont *segmentFont = nil;

    void (^flush)(void) = ^{
        if (segment.length == 0) {
            return;
        }
        NSString *text = segment;
        // leading whitespace at the start of a line is dropped (HTML rules)
        if (x == left) {
            NSUInteger i = 0;
            while (i < text.length && [text characterAtIndex:i] == ' ') {
                i++;
            }
            text = [text substringFromIndex:i];
        }
        if (text.length) {
            CGFloat h = [self lineHeightForFont:segmentFont];
            NSTextField *field = [self makeText:text font:segmentFont];
            CGFloat w = [self widthOfText:text font:segmentFont] + 4;
            [field setFrame:NSMakeRect(x, lineY, w, h)];
            [self addSubview:field];
            x += w;
            [self noteRight:x];
            lineHeight = MAX(lineHeight, h);
        }
        [segment setString:@""];
        segmentWidth = 0;
    };
    void (^newline)(void) = ^{
        flush();
        lineY += MAX(lineHeight, kRowHeight) + kLineGap;
        lineHeight = 0;
        x = left;
    };

    for (XFLayoutAtom *atom in atoms) {
        if (atom.kind == XFAtomBreak) {
            newline();
            anything = YES;
            continue;
        }
        if (atom.kind == XFAtomSpace) {
            flush();
            if (x > left) {
                x += kIndent;
            }
            continue;
        }
        if (atom.kind == XFAtomControl) {
            flush();
            if (!atom.control.relevant || [atom.control isKindOfClass:[XFVarControl class]]
                || [atom.control isKindOfClass:[XFDialog class]]) {
                continue;
            }
            if ([atom.control isBlockLevel]) {
                if (x > left) {
                    newline();
                }
                lineY = [self layoutControl:atom.control atY:lineY indent:indent];
                x = left;
                lineHeight = 0;
            } else {
                [self placeInlineControl:atom.control x:&x y:lineY left:left lineHeight:&lineHeight lineY:&lineY];
            }
            anything = YES;
            continue;
        }
        // text: word by word so lines wrap
        NSFont *font = atom.font ?: [self bodyFont];
        if (segmentFont && segmentFont != font) {
            flush();
        }
        segmentFont = font;
        if (atom.preformatted) {
            NSArray *lines = [atom.text componentsSeparatedByString:@"\n"];
            NSUInteger li = 0;
            for (NSString *line in lines) {
                if (li > 0) {
                    newline();
                }
                if (line.length) {
                    [segment appendString:line];
                    segmentWidth += [self widthOfText:line font:font];
                    anything = YES;
                }
                li++;
            }
            continue;
        }
        NSArray<NSString *> *words = [atom.text componentsSeparatedByString:@" "];
        NSUInteger wi = 0;
        for (NSString *word in words) {
            NSString *piece = wi + 1 < words.count ? [word stringByAppendingString:@" "] : word;
            if (piece.length == 0) {
                wi++;
                continue;
            }
            CGFloat w = [self widthOfText:piece font:font];
            if (x + segmentWidth + w > self.wrapRight && (x > left || segment.length)) {
                newline();
            }
            [segment appendString:piece];
            segmentWidth += w;
            anything = YES;
            wi++;
        }
    }
    flush();
    if (!anything) {
        return y;
    }
    return lineY + MAX(lineHeight, kRowHeight);
}

- (CGFloat)layoutRun:(NSArray<XFHostNode *> *)run atY:(CGFloat)y indent:(CGFloat)indent font:(NSFont *)font
{
    NSMutableArray<XFLayoutAtom *> *atoms = [NSMutableArray array];
    [self collectAtomsFrom:run font:font ?: [self bodyFont] into:atoms];
    return [self layoutAtoms:atoms atY:y indent:indent];
}

/// Lay out a sequence of host nodes in block context: consecutive
/// inline-level nodes form one wrapped run, everything else stacks.
- (CGFloat)layoutNodes:(NSArray<XFHostNode *> *)nodes atY:(CGFloat)y indent:(CGFloat)indent font:(NSFont *)font
{
    CGFloat cursor = y;
    NSMutableArray<XFHostNode *> *run = [NSMutableArray array];
    for (XFHostNode *node in nodes) {
        if ([node isInlineLevel]) {
            [run addObject:node];
            continue;
        }
        if (run.count) {
            cursor = [self layoutRun:run atY:cursor indent:indent font:font];
            [run removeAllObjects];
        }
        cursor = [self layoutBlockNode:node atY:cursor indent:indent font:font];
    }
    if (run.count) {
        cursor = [self layoutRun:run atY:cursor indent:indent font:font];
    }
    return cursor;
}

- (CGFloat)layoutBlockNode:(XFHostNode *)node atY:(CGFloat)y indent:(CGFloat)indent font:(NSFont *)font
{
    switch (node.kind) {
        case XFHostNodeKindControl:
            return [self layoutControl:node.control atY:y indent:indent];

        case XFHostNodeKindRule: {
            NSBox *rule = [[NSBox alloc] initWithFrame:NSMakeRect(kMargin + indent, y + 4, self.wrapRight - kMargin - indent, 2)];
            [rule setBoxType:NSBoxSeparator];
            [rule setTitlePosition:NSNoTitle];
            [self addSubview:rule];
            return y + 10;
        }

        case XFHostNodeKindSVG: {
            // rendered by the SVG renderer (G-20 phase 3); placeholder for now
            NSTextField *ph = [self makeText:@"[SVG]" font:[self fontForTag:@"i" base:font]];
            [ph setFrame:NSMakeRect(kMargin + indent, y, 60, kRowHeight)];
            [self addSubview:ph];
            return y + kRowHeight + kLineGap;
        }

        case XFHostNodeKindTable:
            return [self layoutTable:node atY:y indent:indent font:font];

        case XFHostNodeKindTableSection: {
            // a section outside a table: rows as runs
            return [self layoutNodes:node.children atY:y indent:indent font:font];
        }

        case XFHostNodeKindTableRow:
            return [self layoutRun:node.children atY:y indent:indent font:font];

        case XFHostNodeKindTableCell:
            return [self layoutNodes:node.children atY:y indent:indent font:font];

        case XFHostNodeKindBlock:
        default:
            break;
    }

    NSString *tag = node.tag;
    if ([tag isEqualToString:@"fieldset"]) {
        NSBox *box = [[NSBox alloc] initWithFrame:NSZeroRect];
        [box setTitle:node.title ?: @""];
        [box setTitlePosition:node.title.length ? NSAtTop : NSNoTitle];
        CGFloat inner = y + (node.title.length ? 22 : 8);
        CGFloat start = inner;
        CGFloat outerRight = self.maxRight;
        self.maxRight = 0;
        inner = [self layoutNodes:node.children atY:inner indent:indent + kIndent font:font];
        // the box must enclose the last line of its content: its height runs
    // from the box top (title included) to the content bottom plus padding
    (void)start;
    CGFloat h = (inner - y) + 10;
        CGFloat left = kMargin + indent;
        CGFloat right = MAX(self.maxRight + kIndent, left + kIndent + kLabelWidth + 8 + kFieldWidth + kIndent);
        [box setFrame:NSMakeRect(left, y, right - left, MAX(h, 28))];
        self.maxRight = MAX(outerRight, right);
        [self addSubview:box positioned:NSWindowBelow relativeTo:nil];
        return inner + kRowGap;
    }
    if (node.headingLevel > 0) {
        NSFont *hf = [self headingFontForLevel:node.headingLevel];
        CGFloat cursor = [self layoutNodes:node.children atY:y + 4 indent:indent font:hf];
        return cursor + 6;
    }
    if ([tag isEqualToString:@"pre"]) {
        NSFont *mono = [self fontForTag:@"pre" base:font];
        CGFloat cursor = [self layoutNodes:node.children atY:y indent:indent font:mono];
        return cursor + kRowGap;
    }
    if ([tag isEqualToString:@"li"]) {
        NSTextField *bullet = [self makeText:@"•" font:font ?: [self bodyFont]];
        [bullet setFrame:NSMakeRect(kMargin + indent, y, 14, kRowHeight)];
        [self addSubview:bullet];
        return [self layoutNodes:node.children atY:y indent:indent + 14 font:font];
    }
    if ([tag isEqualToString:@"ul"] || [tag isEqualToString:@"ol"] || [tag isEqualToString:@"blockquote"]
        || [tag isEqualToString:@"dd"]) {
        CGFloat cursor = [self layoutNodes:node.children atY:y indent:indent + kIndent font:font];
        return cursor + kLineGap;
    }
    if ([tag isEqualToString:@"p"]) {
        CGFloat cursor = [self layoutNodes:node.children atY:y indent:indent font:font];
        return cursor > y ? cursor + kRowGap : cursor;
    }
    // div and every other block: children stacked, no extra spacing
    return [self layoutNodes:node.children atY:y indent:indent font:font];
}

/// `<table>` → cell-based NSTableView in a scroll view sized to its content
/// (G-20 phase 2): rows from static <tr>s and from xf:repeat items, header
/// from <thead> or the first row's control labels, tfoot rows appended.
- (CGFloat)layoutTable:(XFHostNode *)node atY:(CGFloat)y indent:(CGFloat)indent font:(NSFont *)font
{
    CGFloat cursor = y;
    if (node.title.length) {
        cursor = [self layoutRun:@[ [self textNode:node.title] ] atY:cursor indent:indent
                            font:[self fontForTag:@"b" base:font]];
    }
    XFTableModel *model = [XFTableModel modelWithTableNode:node];
    if (model.columnCount == 0) {
        return cursor;
    }
    XFTableAdapter *adapter = [[XFTableAdapter alloc] initWithModel:model formView:self];
    NSSize size = [adapter build];
    CGFloat left = kMargin + indent;
    CGFloat width = MIN(size.width, MAX(self.wrapRight - left, 200));
    [adapter.scrollView setFrame:NSMakeRect(left, cursor, width, size.height)];
    [self addSubview:adapter.scrollView];
    [self.tables addObject:adapter];
    if (adapter.tableView) {
        [self.keyViews addObject:adapter.tableView];
    }
    [self noteRight:left + width];
    return cursor + size.height + kRowGap;
}


- (XFHostNode *)textNode:(NSString *)text
{
    XFHostNode *n = [XFHostNode nodeWithKind:XFHostNodeKindText tag:@"#text"];
    n.text = text;
    return n;
}

@end
