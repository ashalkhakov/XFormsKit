#import "XFFormView.h"
#import "XFProcessor.h"
#import <objc/runtime.h>

static const void *kXFBoundControlKey = &kXFBoundControlKey;
#import "XFControl.h"
#import "XFInputControl.h"
#import "XFOutputControl.h"
#import "XFSecretControl.h"
#import "XFTextareaControl.h"
#import "XFTriggerControl.h"
#import "XFSubmitControl.h"
#import "XFSelectControl.h"
#import "XFRangeControl.h"
#import "XFLabelControl.h"
#import "XFUploadControl.h"
#import "XFGroup.h"
#import "XFRepeat.h"
#import "XFSwitch.h"
#import "XFNodeState.h"
#import "XFXMLEvents.h"
#import "XFModel.h"
#import "XFSubmission.h"
#import "XFHostNode.h"
#import "XFTableModel.h"

static const CGFloat kLabelWidth = 110.0;
static const CGFloat kRowHeight = 24.0;
static const CGFloat kTextareaHeight = 72.0;
static const CGFloat kRowGap = 8.0;
static const CGFloat kMargin = 12.0;
static const CGFloat kIndent = 16.0;
static const CGFloat kFieldWidth = 280.0;
static const CGFloat kInlineFieldWidth = 140.0;
static const CGFloat kLineGap = 2.0;
static const CGFloat kWrapWidth = 620.0;

typedef NS_ENUM(NSInteger, XFAtomKind) {
    XFAtomText,
    XFAtomControl,
    XFAtomBreak,
    XFAtomSpace,   // horizontal gap (between table cells)
};

/// One piece of an inline run: a styled text fragment, an inline control
/// or a line break (the flattened form of an XFHostNode inline subtree).
@interface XFLayoutAtom : NSObject
@property (nonatomic, assign) XFAtomKind kind;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSFont *font;
@property (nonatomic, strong) XFControl *control;
@property (nonatomic, assign) BOOL preformatted;
@end

@implementation XFLayoutAtom
@end

@interface XFWidget : NSObject
@property (nonatomic, strong) XFControl *control;
@property (nonatomic, strong) NSView *view;
@property (nonatomic, strong) NSTextField *labelField;
@property (nonatomic, assign) CGFloat height;
@end

@implementation XFWidget
@end


static const CGFloat kTableRowHeight = 22.0;
static const CGFloat kTableHeaderHeight = 20.0;
static const CGFloat kTableMinColumnWidth = 60.0;
static const CGFloat kTableMaxColumnWidth = 240.0;

@class XFFormView;

/// Data source / delegate of one host `<table>` shown as a cell-based
/// NSTableView (G-20 phase 2). Cells come from XFTableModel: a control-only
/// cell gets the matching NSCell (text, secure, popup, button, switch,
/// slider), anything else is static text.
@interface XFTableAdapter : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, weak) XFFormView *formView;
@property (nonatomic, strong) XFTableModel *model;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSCell *> *cells;
@property (nonatomic, assign) BOOL selecting;
- (instancetype)initWithModel:(XFTableModel *)model formView:(XFFormView *)formView;
- (NSSize)build;
- (void)refreshInPlace;
@end

@interface XFFormView () <NSTextViewDelegate, NSTextFieldDelegate>
@property (nonatomic, strong, readwrite) XFProcessor *processor;
@property (nonatomic, strong) NSMutableArray<XFWidget *> *widgets;
@property (nonatomic, assign) CGFloat nextY;
@property (nonatomic, assign) CGFloat contentHeight;
/// Right-most edge laid out so far (group boxes and the form width follow it).
@property (nonatomic, assign) CGFloat maxRight;
/// Right edge inline runs wrap at.
@property (nonatomic, assign) CGFloat wrapRight;
/// One adapter per host table in the current layout.
@property (nonatomic, strong) NSMutableArray<XFTableAdapter *> *tables;
- (CGFloat)widthOfText:(NSString *)text font:(NSFont *)font;
- (NSFont *)bodyFont;
- (void)tableAdapter:(XFTableAdapter *)adapter didCommitControl:(XFControl *)control value:(NSString *)value;
- (void)tableAdapter:(XFTableAdapter *)adapter didActivateTrigger:(XFTriggerControl *)trigger;
- (void)tableAdapter:(XFTableAdapter *)adapter didSelectRow:(XFTableRow *)row;
@end

@implementation XFFormView

- (instancetype)initWithProcessor:(XFProcessor *)processor
{
    self = [super initWithFrame:NSMakeRect(0, 0, 620, 240)];
    if (self) {
        _processor = processor;
        _widgets = [NSMutableArray array];
        _tables = [NSMutableArray array];
        [self setAutoresizingMask:NSViewNotSizable];
        [self rebuild];
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (NSTextField *)makeLabel:(NSString *)text
{
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [field setStringValue:text ?: @""];
    [field setBezeled:NO];
    [field setDrawsBackground:NO];
    [field setEditable:NO];
    [field setSelectable:NO];
    return field;
}

- (BOOL)isBooleanControl:(XFControl *)control
{
    XFNodeState *state = [XFNodeState existingStateOnNode:control.boundNode];
    NSString *type = state.typeName ?: @"";
    if ([type rangeOfString:@"boolean"].location != NSNotFound) {
        return YES;
    }
    NSString *v = control.stringValue ?: @"";
    return [v isEqualToString:@"true"] || [v isEqualToString:@"false"];
}

- (void)applyEnabled:(NSView *)view control:(XFControl *)control
{
    BOOL on = control.relevant && !control.readonly;
    if ([view respondsToSelector:@selector(setEnabled:)]) {
        [(NSControl *)view setEnabled:on];
    }
    [view setHidden:!control.relevant];
    if ([view respondsToSelector:@selector(setToolTip:)]) {
        NSMutableArray *bits = [NSMutableArray array];
        if (control.hint.length) [bits addObject:control.hint];
        if (!control.valid && control.alert.length) [bits addObject:control.alert];
        if (bits.count) {
            [view setToolTip:[bits componentsJoinedByString:@"\n"]];
        }
    }
}

- (XFWidget *)addWidget:(XFControl *)control view:(NSView *)view height:(CGFloat)height
                  atY:(CGFloat)y indent:(CGFloat)indent
{
    XFWidget *w = [[XFWidget alloc] init];
    w.control = control;
    w.view = view;
    w.height = height;
    if (control.label.length && ![control isKindOfClass:[XFTriggerControl class]]
        && ![control isKindOfClass:[XFGroup class]]) {
        NSString *caption = control.required
            ? [NSString stringWithFormat:@"%@ *", control.label]
            : control.label;
        NSTextField *label = [self makeLabel:caption];
        if (!control.valid && [label respondsToSelector:@selector(setTextColor:)]) {
            [label setTextColor:[NSColor redColor]];
        }
        [label setFrame:NSMakeRect(kMargin + indent, y, kLabelWidth, kRowHeight)];
        [self addSubview:label];
        w.labelField = label;
        [view setFrame:NSMakeRect(kMargin + indent + kLabelWidth + 8, y, kFieldWidth, height)];
    } else {
        [view setFrame:NSMakeRect(kMargin + indent, y, kLabelWidth + 8 + kFieldWidth, height)];
    }
    [self addSubview:view];
    [self.widgets addObject:w];
    objc_setAssociatedObject(view, kXFBoundControlKey, control, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self applyEnabled:view control:control];
    [self noteRight:NSMaxX([view frame])];
    return w;
}

- (void)noteRight:(CGFloat)right
{
    if (right > self.maxRight) {
        self.maxRight = right;
    }
}

- (XFControl *)controlForSender:(id)sender
{
    id walk = sender;
    while (walk) {
        XFControl *bound = objc_getAssociatedObject(walk, kXFBoundControlKey);
        if (bound) {
            return bound;
        }
        if ([walk respondsToSelector:@selector(superview)]) {
            walk = [walk superview];
        } else {
            break;
        }
    }
    XFWidget *w = [self widgetForControlView:sender];
    return w.control;
}

- (NSTextField *)textFieldEditable:(BOOL)editable secure:(BOOL)secure
{
    NSTextField *field = secure ? [[NSSecureTextField alloc] initWithFrame:NSZeroRect]
                                : [[NSTextField alloc] initWithFrame:NSZeroRect];
    [field setEditable:editable];
    if (!editable) {
        [field setBezeled:NO];
        [field setDrawsBackground:NO];
    } else {
        // Commit when focus leaves the field too, not only on Return
        // (XSLTForms commits xf:input on the DOM change event).
        [[field cell] setSendsActionOnEndEditing:YES];
    }
    [field setTarget:self];
    [field setAction:@selector(textChanged:)];
    [field setDelegate:self];
    return field;
}

#pragma mark - Widgets

/// A single AppKit view for a non-container control, or nil for controls
/// that need several views (full-appearance selects) or are containers.
- (NSView *)makeViewForControl:(XFControl *)control height:(CGFloat *)height
{
    *height = kRowHeight;

    if ([control isKindOfClass:[XFUploadControl class]]) {
        XFUploadControl *upload = (XFUploadControl *)control;
        NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
        NSString *title = upload.fileName.length ? upload.fileName : @"Choose File…";
        [button setTitle:title];
        [button setBezelStyle:NSRoundedBezelStyle];
        [button setTarget:self];
        [button setAction:@selector(uploadClicked:)];
        return button;
    }

    if ([control isKindOfClass:[XFTriggerControl class]]) {
        NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
        [button setTitle:control.label ?: @"OK"];
        [button setBezelStyle:NSRoundedBezelStyle];
        [button setTarget:self];
        [button setAction:@selector(buttonClicked:)];
        return button;
    }

    if ([control isKindOfClass:[XFRangeControl class]]) {
        XFRangeControl *range = (XFRangeControl *)control;
        NSSlider *slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
        [slider setMinValue:range.start];
        [slider setMaxValue:range.end];
        [slider setAltIncrementValue:range.step];
        [slider setDoubleValue:range.numericValue];
        [slider setTarget:self];
        [slider setAction:@selector(sliderChanged:)];
        return slider;
    }

    if ([control isKindOfClass:[XFSelectControl class]]) {
        XFSelectControl *select = (XFSelectControl *)control;
        if (select.multiple || [select.appearance isEqualToString:@"full"]) {
            return nil;
        }
        NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [popup setTarget:self];
        [popup setAction:@selector(popupChanged:)];
        NSInteger selected = -1;
        NSInteger i = 0;
        NSString *lastGroup = nil;
        for (XFItem *item in select.items) {
            if (item.groupLabel.length && ![item.groupLabel isEqualToString:lastGroup]) {
                [popup addItemWithTitle:item.groupLabel];
                [[popup lastItem] setEnabled:NO];
                lastGroup = item.groupLabel;
                i++;
            }
            [popup addItemWithTitle:item.label ?: item.value ?: @""];
            [[popup lastItem] setRepresentedObject:item.value];
            if (item.selected) {
                selected = i;
            }
            i++;
        }
        if (selected >= 0) {
            [popup selectItemAtIndex:selected];
        }
        return popup;
    }

    if ([control isKindOfClass:[XFTextareaControl class]]) {
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        [scroll setHasVerticalScroller:YES];
        [scroll setBorderType:NSBezelBorder];
        NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, kFieldWidth, kTextareaHeight)];
        [tv setString:control.stringValue ?: @""];
        [tv setDelegate:self];
        [tv setEditable:!control.readonly];
        [scroll setDocumentView:tv];
        *height = kTextareaHeight;
        return scroll;
    }

    if ([control isKindOfClass:[XFLabelControl class]]) {
        return [self makeLabel:control.stringValue];
    }

    if ([control isKindOfClass:[XFInputControl class]] && [self isBooleanControl:control]) {
        NSButton *box = [[NSButton alloc] initWithFrame:NSZeroRect];
        [box setButtonType:NSSwitchButton];
        [box setTitle:control.label ?: @""];
        BOOL on = [control.stringValue isEqualToString:@"true"] || [control.stringValue isEqualToString:@"1"];
        [box setState:on ? NSOnState : NSOffState];
        [box setTarget:self];
        [box setAction:@selector(boolClicked:)];
        return box;
    }

    if ([control isKindOfClass:[XFInputControl class]]) {
        XFInputControl *input = (XFInputControl *)control;
        XFDateType dateType = [input resolvedDateType];
        if (dateType != XFDateTypeNone && [NSDatePicker class]) {
            NSDatePicker *picker = [[NSDatePicker alloc] initWithFrame:NSZeroRect];
            [picker setDatePickerStyle:NSTextFieldAndStepperDatePickerStyle];
            NSUInteger elements = NSYearMonthDayDatePickerElementFlag;
            if (dateType == XFDateTypeTime) {
                elements = NSHourMinuteSecondDatePickerElementFlag;
            } else if (dateType == XFDateTypeDateTime) {
                elements = NSYearMonthDayDatePickerElementFlag
                    | NSHourMinuteSecondDatePickerElementFlag;
            }
            [picker setDatePickerElements:elements];
            [picker setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
            NSDate *date = [input dateValue];
            if (date) {
                [picker setDateValue:date];
            }
            [picker setTarget:self];
            [picker setAction:@selector(dateChanged:)];
            return picker;
        }
    }

    if ([control isKindOfClass:[XFOutputControl class]]) {
        XFOutputControl *output = (XFOutputControl *)control;
        if (output.displaysImage) {
            NSImageView *img = [[NSImageView alloc] initWithFrame:NSZeroRect];
            NSData *data = [output imageData];
            if (data) {
                NSImage *picture = [[NSImage alloc] initWithData:data];
                if (picture) {
                    [img setImage:picture];
                }
            }
            *height = 72;
            return img;
        }
    }

    BOOL editable = [control isKindOfClass:[XFInputControl class]];
    BOOL secure = [control isKindOfClass:[XFSecretControl class]];
    NSTextField *field = [self textFieldEditable:editable secure:secure];
    [field setStringValue:control.stringValue ?: @""];
    return field;
}

/// YES when the widget shows the control's label itself (no separate caption).
- (BOOL)viewCarriesLabel:(NSView *)view control:(XFControl *)control
{
    if ([control isKindOfClass:[XFTriggerControl class]] || [control isKindOfClass:[XFGroup class]]) {
        return YES;
    }
    return [view isKindOfClass:[NSButton class]] && [control isKindOfClass:[XFInputControl class]];
}

#pragma mark - Block controls

/// Block placement of a control (label column + field column), the
/// XFormsKit default for a control that stands on its own line.
- (CGFloat)layoutControl:(XFControl *)control atY:(CGFloat)y indent:(CGFloat)indent
{
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
    CGFloat h = (inner - start) + 12;
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
            if (!atom.control.relevant) {
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
        CGFloat h = (inner - start) + 12;
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
    [self noteRight:left + width];
    return cursor + size.height + kRowGap;
}

- (void)tableAdapter:(XFTableAdapter *)adapter didCommitControl:(XFControl *)control value:(NSString *)value
{
    (void)adapter;
    if ([control isKindOfClass:[XFSelectControl class]]) {
        if ([(XFSelectControl *)control selectValue:value]) {
            [self.processor controlDidChangeValue:control];
        }
    } else {
        [self.processor setValue:value ofControl:control error:NULL];
    }
    // the table view is mid-tracking: rebuild once the event is done
    [self performSelector:@selector(reloadFromProcessor) withObject:nil afterDelay:0];
}

- (void)tableAdapter:(XFTableAdapter *)adapter didActivateTrigger:(XFTriggerControl *)trigger
{
    (void)adapter;
    [trigger activate];
    [self.processor refreshControls];
    [self performSelector:@selector(reloadAfterTrigger) withObject:nil afterDelay:0];
}

- (void)reloadAfterTrigger
{
    [self reloadFromProcessor];
    [self notifyDocumentReplaceIfNeeded];
}

- (void)tableAdapter:(XFTableAdapter *)adapter didSelectRow:(XFTableRow *)row
{
    (void)adapter;
    if (row.repeat && row.repeatItem && row.repeat.index != row.repeatItem.position) {
        // XsltForms_repeat.selectItem: clicking into an item moves the index
        [row.repeat setIndex:row.repeatItem.position];
        [self.processor refreshControls];
        if (self.instanceChangedHandler) {
            self.instanceChangedHandler();
        }
        for (XFTableAdapter *t in self.tables) {
            [t refreshInPlace];
        }
    }
}

- (XFHostNode *)textNode:(NSString *)text
{
    XFHostNode *n = [XFHostNode nodeWithKind:XFHostNodeKindText tag:@"#text"];
    n.text = text;
    return n;
}

- (void)rebuild
{
    for (NSView *view in [[self subviews] copy]) {
        [view removeFromSuperview];
    }
    [self.widgets removeAllObjects];
    for (XFTableAdapter *t in self.tables) {
        [t.tableView setDataSource:nil];
        [t.tableView setDelegate:nil];
    }
    [self.tables removeAllObjects];
    self.maxRight = 0;
    self.wrapRight = MAX(kWrapWidth, [self frame].size.width) - kMargin;
    CGFloat y = kMargin;
    y = [self layoutNodes:self.processor.hostNodes atY:y indent:0 font:nil];
    if (self.widgets.count == 0 && self.processor.controls.count == 0) {
        NSTextField *empty = [self makeLabel:@"No XForms controls in the host body."];
        [empty setFrame:NSMakeRect(kMargin, y, 400, 40)];
        [self addSubview:empty];
        y += 48;
    }
    self.contentHeight = y + kMargin;
    [self setFrame:NSMakeRect(0, 0, MAX(kWrapWidth, self.maxRight + kMargin), MAX(self.contentHeight, 80))];
    [self setNeedsDisplay:YES];
}

- (XFWidget *)widgetForView:(id)sender
{
    for (XFWidget *w in self.widgets) {
        if (w.view == sender || [w.view isKindOfClass:[NSScrollView class]] ) {
            if (w.view == sender) {
                return w;
            }
        }
    }
    return nil;
}

- (XFWidget *)widgetForControlView:(NSView *)view
{
    for (XFWidget *w in self.widgets) {
        if (w.view == view) {
            return w;
        }
    }
    return nil;
}

- (void)commitControl:(XFControl *)control value:(NSString *)value
{
    [self.processor setValue:value ofControl:control error:NULL];
    [self reloadFromProcessor];
}

- (void)uploadClicked:(NSButton *)sender
{
    XFControl *bound = [self controlForSender:sender];
    if (![bound isKindOfClass:[XFUploadControl class]]) {
        return;
    }
    XFUploadControl *upload = (XFUploadControl *)bound;
    if (![NSOpenPanel class]) {
        return;
    }
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:NO];
    [panel setCanChooseFiles:YES];
    NSInteger code = [panel runModal];
    if (code != NSOKButton) {
        return;
    }
    NSURL *url = nil;
    if ([panel respondsToSelector:@selector(URLs)]) {
        url = [[panel URLs] firstObject];
    }
    if (url == nil && [panel respondsToSelector:@selector(filename)]) {
        url = [NSURL fileURLWithPath:[panel filename]];
    }
    if (url && [upload commitFileAtURL:url error:NULL]) {
        [self.processor controlDidChangeValue:upload];
        [self reloadFromProcessor];
    }
}

- (void)textChanged:(NSTextField *)sender
{
    XFControl *control = [self controlForSender:sender];
    if (control) {
        [self commitControl:control value:[sender stringValue]];
    }
}

#pragma mark - Incremental commits

/// incremental="true": commit on every keystroke without rebuilding the
/// form (a rebuild would replace the field being edited). Other widgets are
/// refreshed in place; layout changes (relevance) are applied by the rebuild
/// on the final commit (Return / focus loss).
- (void)commitIncremental:(XFControl *)control value:(NSString *)value editingView:(NSView *)editing
{
    if (![self.processor setValue:value ofControl:control error:NULL]) {
        return;
    }
    [self refreshWidgetsInPlaceExcept:editing];
    if (self.instanceChangedHandler) {
        self.instanceChangedHandler();
    }
}

- (void)controlTextDidChange:(NSNotification *)note
{
    NSTextField *field = [note object];
    if (![field isKindOfClass:[NSTextField class]]) {
        return;
    }
    XFControl *control = [self controlForSender:field];
    if (control.incremental) {
        [self commitIncremental:control value:[field stringValue] editingView:field];
    }
}

- (void)textDidChange:(NSNotification *)note
{
    NSTextView *tv = [note object];
    for (XFWidget *w in self.widgets) {
        if ([w.view isKindOfClass:[NSScrollView class]]
            && [(NSScrollView *)w.view documentView] == tv) {
            if (w.control.incremental) {
                [self commitIncremental:w.control value:[tv string] editingView:w.view];
            }
            return;
        }
    }
}

- (void)refreshWidgetsInPlaceExcept:(NSView *)editing
{
    for (XFTableAdapter *t in self.tables) {
        [t refreshInPlace];
    }
    for (XFWidget *w in self.widgets) {
        XFControl *control = w.control;
        NSView *view = w.view;
        if (view != editing) {
            if ([view isKindOfClass:[NSPopUpButton class]] && [control isKindOfClass:[XFSelectControl class]]) {
                NSPopUpButton *popup = (NSPopUpButton *)view;
                NSString *selected = [(XFSelectControl *)control selectedValues].firstObject;
                for (NSMenuItem *item in [popup itemArray]) {
                    if ([[item representedObject] isEqual:selected]) {
                        [popup selectItem:item];
                        break;
                    }
                }
            } else if ([view isKindOfClass:[NSButton class]] && [control isKindOfClass:[XFSelectControl class]]) {
                NSString *value = [view toolTip];
                BOOL on = value && [[(XFSelectControl *)control selectedValues] containsObject:value];
                [(NSButton *)view setState:on ? NSOnState : NSOffState];
            } else if ([view isKindOfClass:[NSButton class]] && [control isKindOfClass:[XFInputControl class]]) {
                BOOL on = [control.stringValue isEqualToString:@"true"] || [control.stringValue isEqualToString:@"1"];
                [(NSButton *)view setState:on ? NSOnState : NSOffState];
            } else if ([view isKindOfClass:[NSSlider class]] && [control isKindOfClass:[XFRangeControl class]]) {
                [(NSSlider *)view setDoubleValue:[(XFRangeControl *)control numericValue]];
            } else if ([view isKindOfClass:[NSDatePicker class]] && [control isKindOfClass:[XFInputControl class]]) {
                NSDate *date = [(XFInputControl *)control dateValue];
                if (date) {
                    [(NSDatePicker *)view setDateValue:date];
                }
            } else if ([view isKindOfClass:[NSScrollView class]]) {
                NSTextView *tv = [(NSScrollView *)view documentView];
                if ([tv isKindOfClass:[NSTextView class]]
                    && ![[tv string] isEqualToString:control.stringValue ?: @""]) {
                    [tv setString:control.stringValue ?: @""];
                }
            } else if ([view isKindOfClass:[NSTextField class]]
                       && ![control isKindOfClass:[XFTriggerControl class]]) {
                NSTextField *field = (NSTextField *)view;
                if (![[field stringValue] isEqualToString:control.stringValue ?: @""]) {
                    [field setStringValue:control.stringValue ?: @""];
                }
            }
        }
        [self applyEnabled:view control:control];
        [w.labelField setHidden:!control.relevant];
        if (w.labelField && [w.labelField respondsToSelector:@selector(setTextColor:)]) {
            [w.labelField setTextColor:control.valid ? [NSColor controlTextColor] : [NSColor redColor]];
        }
    }
}

- (void)textDidEndEditing:(NSNotification *)note
{
    NSTextView *tv = [note object];
    for (XFWidget *w in self.widgets) {
        if ([w.view isKindOfClass:[NSScrollView class]]
            && [(NSScrollView *)w.view documentView] == tv) {
            [self commitControl:w.control value:[tv string]];
            return;
        }
    }
}

- (void)notifyDocumentReplaceIfNeeded
{
    if (self.documentReplaceHandler == nil) {
        return;
    }
    for (XFModel *model in self.processor.models ?: (self.processor.model ? @[ self.processor.model ] : @[])) {
        for (XFSubmission *sub in model.submissions) {
            if (sub.lastAllReplacement.length) {
                NSString *xml = sub.lastAllReplacement;
                sub.lastAllReplacement = nil;
                self.documentReplaceHandler(xml);
                return;
            }
        }
    }
}

- (void)buttonClicked:(NSButton *)sender
{
    XFControl *control = [self controlForSender:sender];
    if ([control isKindOfClass:[XFTriggerControl class]]) {
        [(XFTriggerControl *)control activate];
        [self.processor refreshControls];
        [self reloadFromProcessor];
        [self notifyDocumentReplaceIfNeeded];
    }
}

- (void)sliderChanged:(NSSlider *)sender
{
    XFControl *control = [self controlForSender:sender];
    if ([control isKindOfClass:[XFRangeControl class]]) {
        if ([(XFRangeControl *)control commitNumericValue:[sender doubleValue] error:NULL]) {
            [self.processor controlDidChangeValue:control];
        }
        [self reloadFromProcessor];
    }
}

- (void)popupChanged:(NSPopUpButton *)sender
{
    XFControl *control = [self controlForSender:sender];
    if ([control isKindOfClass:[XFSelectControl class]]) {
        NSString *value = [[sender selectedItem] representedObject];
        if ([(XFSelectControl *)control selectValue:value ?: [sender titleOfSelectedItem]]) {
            [self.processor controlDidChangeValue:control];
        }
        [self reloadFromProcessor];
    }
}

- (void)checkClicked:(NSButton *)sender
{
    XFControl *control = [self controlForSender:sender];
    if ([control isKindOfClass:[XFSelectControl class]]) {
        if ([(XFSelectControl *)control toggleValue:[sender toolTip] ?: [sender title]]) {
            [self.processor controlDidChangeValue:control];
        }
        [self reloadFromProcessor];
    }
}

- (void)boolClicked:(NSButton *)sender
{
    XFControl *control = [self controlForSender:sender];
    if (control) {
        [self commitControl:control value:([sender state] == NSOnState) ? @"true" : @"false"];
    }
}

- (void)dateChanged:(NSDatePicker *)sender
{
    XFControl *control = [self controlForSender:sender];
    if ([control isKindOfClass:[XFInputControl class]]) {
        if ([(XFInputControl *)control commitDateValue:[sender dateValue] error:NULL]) {
            [self.processor controlDidChangeValue:control];
        }
        [self reloadFromProcessor];
    }
}

- (void)reloadFromProcessor
{
    [self.processor refreshControls];
    [self rebuild];
    if (self.instanceChangedHandler) {
        self.instanceChangedHandler();
    }
}

@end

#pragma mark - XFTableAdapter

@implementation XFTableAdapter

- (instancetype)initWithModel:(XFTableModel *)model formView:(XFFormView *)formView
{
    self = [super init];
    if (self) {
        _model = model;
        _formView = formView;
        _cells = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)identifierForColumn:(NSUInteger)column
{
    return [NSString stringWithFormat:@"%lu", (unsigned long)column];
}

- (NSUInteger)columnIndexOf:(NSTableColumn *)column
{
    return (NSUInteger)[[column identifier] integerValue];
}

- (XFTableCell *)cellAtRow:(NSInteger)row column:(NSTableColumn *)column
{
    if (row < 0 || (NSUInteger)row >= self.model.rows.count || column == nil) {
        return nil;
    }
    NSUInteger col = [self columnIndexOf:column];
    XFTableCell *cell = [self.model.rows[(NSUInteger)row] cellAtColumn:col];
    // a spanned cell shows its content in its first column only
    return (cell && cell.column == col) ? cell : nil;
}

- (CGFloat)preferredWidthForColumn:(NSUInteger)col
{
    XFFormView *fv = self.formView;
    NSFont *font = [fv bodyFont];
    CGFloat width = kTableMinColumnWidth;
    NSString *title = col < self.model.columnTitles.count ? self.model.columnTitles[col] : nil;
    if (title.length) {
        width = MAX(width, [fv widthOfText:title font:font] + 16);
    }
    for (XFTableRow *row in self.model.rows) {
        XFTableCell *cell = [row cellAtColumn:col];
        if (cell == nil || cell.column != col) {
            continue;
        }
        XFControl *control = cell.control;
        if (control == nil) {
            width = MAX(width, [fv widthOfText:cell.text font:font] + 12);
        } else if ([control isKindOfClass:[XFSelectControl class]]) {
            for (XFItem *item in [(XFSelectControl *)control items]) {
                width = MAX(width, [fv widthOfText:item.label ?: item.value ?: @"" font:font] + 36);
            }
        } else if ([control isKindOfClass:[XFTriggerControl class]]) {
            width = MAX(width, [fv widthOfText:control.label ?: @"" font:font] + 28);
        } else if ([control isKindOfClass:[XFOutputControl class]]) {
            width = MAX(width, [fv widthOfText:control.stringValue ?: @"" font:font] + 12);
        } else {
            width = MAX(width, kInlineFieldWidth);
        }
    }
    return MIN(width, kTableMaxColumnWidth);
}

- (NSSize)build
{
    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView = table;
    [table setRowHeight:kTableRowHeight];
    [table setAllowsColumnReordering:NO];
    [table setAllowsColumnSelection:NO];
    [table setAllowsEmptySelection:YES];
    [table setAllowsMultipleSelection:NO];
    [table setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
    CGFloat width = 0;
    for (NSUInteger col = 0; col < self.model.columnCount; col++) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:[self identifierForColumn:col]];
        NSString *title = col < self.model.columnTitles.count ? self.model.columnTitles[col] : @"";
        [[column headerCell] setStringValue:title ?: @""];
        CGFloat w = [self preferredWidthForColumn:col];
        [column setWidth:w];
        [column setMinWidth:kTableMinColumnWidth];
        [column setEditable:YES];
        [table addTableColumn:column];
        width += w + [table intercellSpacing].width;
    }
    BOOL hasHeader = self.model.columnTitles != nil;
    if (!hasHeader) {
        [table setHeaderView:nil];
    }
    [table setDataSource:self];
    [table setDelegate:self];
    // a repeat's current item is the selected row, and vice versa
    [self selectCurrentRow];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [scroll setBorderType:NSBezelBorder];
    [scroll setHasVerticalScroller:NO];
    [scroll setHasHorizontalScroller:NO];
    [scroll setDocumentView:table];
    self.scrollView = scroll;

    CGFloat rows = MAX((CGFloat)self.model.rows.count, 1);
    CGFloat height = rows * (kTableRowHeight + [table intercellSpacing].height)
        + (hasHeader ? kTableHeaderHeight : 0) + 4;
    [table setFrame:NSMakeRect(0, 0, width, height)];
    return NSMakeSize(width + 4, height);
}

- (void)selectCurrentRow
{
    XFTableRow *selected = [self.model selectedRow];
    NSUInteger idx = selected ? [self.model.rows indexOfObjectIdenticalTo:selected] : NSNotFound;
    self.selecting = YES;
    if (idx != NSNotFound) {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
    } else {
        [self.tableView deselectAll:nil];
    }
    self.selecting = NO;
}

- (void)refreshInPlace
{
    [self.tableView reloadData];
    [self selectCurrentRow];
}

#pragma mark data source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    (void)tableView;
    return (NSInteger)self.model.rows.count;
}

- (BOOL)isBooleanInput:(XFControl *)control
{
    if (![control isKindOfClass:[XFInputControl class]]) {
        return NO;
    }
    XFNodeState *state = [XFNodeState existingStateOnNode:control.boundNode];
    NSString *type = state.typeName ?: @"";
    if ([type rangeOfString:@"boolean"].location != NSNotFound) {
        return YES;
    }
    NSString *v = control.stringValue ?: @"";
    return [v isEqualToString:@"true"] || [v isEqualToString:@"false"];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)tableView;
    XFTableCell *cell = [self cellAtRow:row column:column];
    if (cell == nil) {
        return @"";
    }
    XFControl *control = cell.control;
    if (control == nil) {
        return cell.text;
    }
    if (!control.relevant) {
        return @"";
    }
    if ([control isKindOfClass:[XFTriggerControl class]]) {
        return @(NSOffState);
    }
    if ([control isKindOfClass:[XFSelectControl class]]) {
        NSInteger i = 0;
        for (XFItem *item in [(XFSelectControl *)control items]) {
            if (item.selected) {
                return @(i);
            }
            i++;
        }
        return @(-1);
    }
    if ([self isBooleanInput:control]) {
        BOOL on = [control.stringValue isEqualToString:@"true"] || [control.stringValue isEqualToString:@"1"];
        return @(on ? NSOnState : NSOffState);
    }
    if ([control isKindOfClass:[XFRangeControl class]]) {
        return @([(XFRangeControl *)control numericValue]);
    }
    if ([control isKindOfClass:[XFOutputControl class]] && control.label.length
        && ![self labelIsColumnTitle:control.label column:column]) {
        // XSLTForms shows the label inside the cell: "M: 0"
        return [NSString stringWithFormat:@"%@ %@", control.label, control.stringValue ?: @""];
    }
    return control.stringValue ?: @"";
}

- (BOOL)labelIsColumnTitle:(NSString *)label column:(NSTableColumn *)column
{
    NSUInteger col = [self columnIndexOf:column];
    NSString *title = col < self.model.columnTitles.count ? self.model.columnTitles[col] : nil;
    return [title isEqualToString:label];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)tableView;
    XFTableCell *cell = [self cellAtRow:row column:column];
    XFControl *control = cell.control;
    XFFormView *fv = self.formView;
    if (control == nil || fv == nil || !control.relevant) {
        return;
    }
    if (row >= 0 && (NSUInteger)row < self.model.rows.count) {
        [fv tableAdapter:self didSelectRow:self.model.rows[(NSUInteger)row]];
    }
    if ([control isKindOfClass:[XFTriggerControl class]]) {
        [fv tableAdapter:self didActivateTrigger:(XFTriggerControl *)control];
        return;
    }
    if (control.readonly) {
        return;
    }
    if ([control isKindOfClass:[XFSelectControl class]]) {
        NSInteger idx = [value integerValue];
        NSArray *items = [(XFSelectControl *)control items];
        if (idx >= 0 && (NSUInteger)idx < items.count) {
            XFItem *item = items[(NSUInteger)idx];
            [fv tableAdapter:self didCommitControl:control value:item.value ?: @""];
        }
        return;
    }
    if ([self isBooleanInput:control]) {
        BOOL on = [value integerValue] == NSOnState;
        [fv tableAdapter:self didCommitControl:control value:on ? @"true" : @"false"];
        return;
    }
    if ([control isKindOfClass:[XFRangeControl class]]) {
        [fv tableAdapter:self didCommitControl:control value:[NSString stringWithFormat:@"%g", [value doubleValue]]];
        return;
    }
    [fv tableAdapter:self didCommitControl:control value:[value description] ?: @""];
}

#pragma mark delegate

- (NSCell *)tableView:(NSTableView *)tableView dataCellForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)tableView;
    if (column == nil) {
        return nil;
    }
    NSString *key = [NSString stringWithFormat:@"%ld:%@", (long)row, [column identifier]];
    NSCell *cached = self.cells[key];
    if (cached) {
        return cached;
    }
    XFTableCell *cell = [self cellAtRow:row column:column];
    XFControl *control = cell.control;
    NSCell *made = nil;
    if (control == nil) {
        NSTextFieldCell *tc = [[NSTextFieldCell alloc] initTextCell:@""];
        [tc setEditable:NO];
        [tc setSelectable:NO];
        if (cell.header) {
            [tc setFont:[[NSFontManager sharedFontManager] convertFont:[self.formView bodyFont] toHaveTrait:NSBoldFontMask]];
        }
        made = tc;
    } else if ([control isKindOfClass:[XFTriggerControl class]]) {
        NSButtonCell *bc = [[NSButtonCell alloc] initTextCell:control.label ?: @"OK"];
        [bc setBezelStyle:NSRoundedBezelStyle];
        [bc setButtonType:NSMomentaryPushInButton];
        made = bc;
    } else if ([control isKindOfClass:[XFSelectControl class]]) {
        NSPopUpButtonCell *pc = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
        [pc setBordered:NO];
        for (XFItem *item in [(XFSelectControl *)control items]) {
            [pc addItemWithTitle:item.label ?: item.value ?: @""];
        }
        made = pc;
    } else if ([self isBooleanInput:control]) {
        NSButtonCell *bc = [[NSButtonCell alloc] initTextCell:@""];
        [bc setButtonType:NSSwitchButton];
        made = bc;
    } else if ([control isKindOfClass:[XFRangeControl class]]) {
        NSSliderCell *sc = [[NSSliderCell alloc] init];
        [sc setMinValue:[(XFRangeControl *)control start]];
        [sc setMaxValue:[(XFRangeControl *)control end]];
        made = sc;
    } else if ([control isKindOfClass:[XFSecretControl class]]) {
        NSSecureTextFieldCell *sc = [[NSSecureTextFieldCell alloc] initTextCell:@""];
        [sc setEditable:YES];
        made = sc;
    } else {
        NSTextFieldCell *tc = [[NSTextFieldCell alloc] initTextCell:@""];
        BOOL editable = [control isKindOfClass:[XFInputControl class]]
            || [control isKindOfClass:[XFTextareaControl class]];
        [tc setEditable:editable];
        [tc setSelectable:YES];
        if (editable) {
            [tc setBezeled:YES];
            [tc setDrawsBackground:YES];
        }
        made = tc;
    }
    if (control) {
        [made setEnabled:control.relevant && !control.readonly];
    }
    self.cells[key] = made;
    return made;
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)tableView;
    XFTableCell *cell = [self cellAtRow:row column:column];
    XFControl *control = cell.control;
    if (control == nil || !control.relevant || control.readonly) {
        return NO;
    }
    return [control isKindOfClass:[XFInputControl class]]
        || [control isKindOfClass:[XFSecretControl class]]
        || [control isKindOfClass:[XFTextareaControl class]];
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)tableView;
    XFTableCell *tc = [self cellAtRow:row column:column];
    XFControl *control = tc.control;
    if (control && [cell respondsToSelector:@selector(setTextColor:)] && [cell isKindOfClass:[NSTextFieldCell class]]) {
        [(NSTextFieldCell *)cell setTextColor:control.valid ? [NSColor controlTextColor] : [NSColor redColor]];
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
    (void)note;
    if (self.selecting) {
        return;
    }
    NSInteger row = [self.tableView selectedRow];
    if (row >= 0 && (NSUInteger)row < self.model.rows.count) {
        [self.formView tableAdapter:self didSelectRow:self.model.rows[(NSUInteger)row]];
    }
}

@end
