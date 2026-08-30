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

static const CGFloat kLabelWidth = 110.0;
static const CGFloat kRowHeight = 24.0;
static const CGFloat kTextareaHeight = 72.0;
static const CGFloat kRowGap = 8.0;
static const CGFloat kMargin = 12.0;
static const CGFloat kIndent = 16.0;
static const CGFloat kFieldWidth = 280.0;

@interface XFWidget : NSObject
@property (nonatomic, strong) XFControl *control;
@property (nonatomic, strong) NSView *view;
@property (nonatomic, strong) NSTextField *labelField;
@property (nonatomic, assign) CGFloat height;
@end

@implementation XFWidget
@end

@interface XFFormView () <NSTextViewDelegate>
@property (nonatomic, strong, readwrite) XFProcessor *processor;
@property (nonatomic, strong) NSMutableArray<XFWidget *> *widgets;
@property (nonatomic, assign) CGFloat nextY;
@property (nonatomic, assign) CGFloat contentHeight;
@end

@implementation XFFormView

- (instancetype)initWithProcessor:(XFProcessor *)processor
{
    self = [super initWithFrame:NSMakeRect(0, 0, 620, 240)];
    if (self) {
        _processor = processor;
        _widgets = [NSMutableArray array];
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
    return w;
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
    }
    [field setTarget:self];
    [field setAction:@selector(textChanged:)];
    return field;
}

- (CGFloat)layoutControl:(XFControl *)control atY:(CGFloat)y indent:(CGFloat)indent
{
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
        CGFloat cursor = y;
        for (XFControl *child in [(XFCase *)control children]) {
            cursor = [self layoutControl:child atY:cursor indent:indent];
        }
        return cursor;
    }

    if ([control isKindOfClass:[XFUploadControl class]]) {
        XFUploadControl *upload = (XFUploadControl *)control;
        NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
        NSString *title = upload.fileName.length ? upload.fileName : @"Choose File…";
        [button setTitle:title];
        [button setBezelStyle:NSRoundedBezelStyle];
        [button setTarget:self];
        [button setAction:@selector(uploadClicked:)];
        [self addWidget:control view:button height:kRowHeight atY:y indent:indent];
        return y + kRowHeight + kRowGap;
    }

    if ([control isKindOfClass:[XFTriggerControl class]]) {
        NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
        [button setTitle:control.label ?: @"OK"];
        [button setBezelStyle:NSRoundedBezelStyle];
        [button setTarget:self];
        [button setAction:@selector(buttonClicked:)];
        [self addWidget:control view:button height:kRowHeight atY:y indent:indent];
        return y + kRowHeight + kRowGap;
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
        [self addWidget:control view:slider height:kRowHeight atY:y indent:indent];
        return y + kRowHeight + kRowGap;
    }

    if ([control isKindOfClass:[XFSelectControl class]]) {
        XFSelectControl *select = (XFSelectControl *)control;
        if (select.multiple || [select.appearance isEqualToString:@"full"]) {
            CGFloat cursor = y;
            if (control.label.length) {
                NSTextField *caption = [self makeLabel:control.label];
                [caption setFrame:NSMakeRect(kMargin + indent, cursor, kLabelWidth + kFieldWidth, kRowHeight)];
                [self addSubview:caption];
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
        [self addWidget:control view:popup height:kRowHeight atY:y indent:indent];
        return y + kRowHeight + kRowGap;
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
        [self addWidget:control view:scroll height:kTextareaHeight atY:y indent:indent];
        return y + kTextareaHeight + kRowGap;
    }

    if ([control isKindOfClass:[XFLabelControl class]]) {
        NSTextField *field = [self makeLabel:control.stringValue];
        [self addWidget:control view:field height:kRowHeight atY:y indent:indent];
        return y + kRowHeight + kRowGap;
    }

    if ([control isKindOfClass:[XFInputControl class]] && [self isBooleanControl:control]) {
        NSButton *box = [[NSButton alloc] initWithFrame:NSZeroRect];
        [box setButtonType:NSSwitchButton];
        [box setTitle:control.label ?: @""];
        BOOL on = [control.stringValue isEqualToString:@"true"] || [control.stringValue isEqualToString:@"1"];
        [box setState:on ? NSOnState : NSOffState];
        [box setTarget:self];
        [box setAction:@selector(boolClicked:)];
        XFWidget *w = [self addWidget:control view:box height:kRowHeight atY:y indent:indent];
        w.labelField = nil;
        return y + kRowHeight + kRowGap;
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
            [self addWidget:control view:picker height:kRowHeight atY:y indent:indent];
            return y + kRowHeight + kRowGap;
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
            [self addWidget:control view:img height:72 atY:y indent:indent];
            return y + 72 + kRowGap;
        }
    }

    BOOL editable = [control isKindOfClass:[XFInputControl class]];
    BOOL secure = [control isKindOfClass:[XFSecretControl class]];
    NSTextField *field = [self textFieldEditable:editable secure:secure];
    [field setStringValue:control.stringValue ?: @""];
    [self addWidget:control view:field height:kRowHeight atY:y indent:indent];
    return y + kRowHeight + kRowGap;
}

- (CGFloat)layoutGroup:(XFGroup *)group atY:(CGFloat)y indent:(CGFloat)indent
{
    NSBox *box = [[NSBox alloc] initWithFrame:NSZeroRect];
    [box setTitle:group.label ?: @""];
    [box setTitlePosition:group.label.length ? NSAtTop : NSNoTitle];
    CGFloat inner = y + (group.label.length ? 22 : 8);
    CGFloat start = inner;
    for (XFControl *child in group.children) {
        inner = [self layoutControl:child atY:inner indent:indent + kIndent];
    }
    CGFloat h = (inner - start) + 12;
    [box setFrame:NSMakeRect(kMargin + indent, y, kLabelWidth + kFieldWidth + 20, MAX(h, 28))];
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
            cursor += kRowHeight + 4;
        }
        for (XFControl *child in item.controls) {
            cursor = [self layoutControl:child atY:cursor indent:indent + kIndent];
        }
        i++;
    }
    return cursor;
}

- (void)rebuild
{
    for (NSView *view in [[self subviews] copy]) {
        [view removeFromSuperview];
    }
    [self.widgets removeAllObjects];
    CGFloat cursor = kMargin;
    // Layout top-down in view coords after we know height; first measure.
    NSMutableArray *top = [NSMutableArray array];
    for (XFControl *c in self.processor.controls) {
        [top addObject:c];
    }
    // Use a dummy bottom-up later; compute height with a dry layout in a temp
    // coordinate that grows upward from 0, then flip.
    CGFloat y = kMargin;
    for (XFControl *c in top) {
        y = [self layoutControl:c atY:y indent:0];
    }
    if (top.count == 0) {
        NSTextField *empty = [self makeLabel:@"No XForms controls in the host body."];
        [empty setFrame:NSMakeRect(kMargin, kMargin, 400, 40)];
        [self addSubview:empty];
        y = kMargin + 48;
    }
    self.contentHeight = y + kMargin;
    [self setFrame:NSMakeRect(0, 0, 620, MAX(self.contentHeight, 80))];
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
        [self.processor refresh:NULL];
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
        [(XFRangeControl *)control commitNumericValue:[sender doubleValue] error:NULL];
        [self.processor refresh:NULL];
        [self reloadFromProcessor];
    }
}

- (void)popupChanged:(NSPopUpButton *)sender
{
    XFControl *control = [self controlForSender:sender];
    if ([control isKindOfClass:[XFSelectControl class]]) {
        NSString *value = [[sender selectedItem] representedObject];
        [(XFSelectControl *)control selectValue:value ?: [sender titleOfSelectedItem]];
        [self.processor refresh:NULL];
        [self reloadFromProcessor];
    }
}

- (void)checkClicked:(NSButton *)sender
{
    XFControl *control = [self controlForSender:sender];
    if ([control isKindOfClass:[XFSelectControl class]]) {
        [(XFSelectControl *)control toggleValue:[sender toolTip] ?: [sender title]];
        [self.processor refresh:NULL];
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
        [(XFInputControl *)control commitDateValue:[sender dateValue] error:NULL];
        [self.processor refresh:NULL];
        [self reloadFromProcessor];
    }
}

- (void)reloadFromProcessor
{
    [self.processor refreshControls];
    [self rebuild];
}

@end
