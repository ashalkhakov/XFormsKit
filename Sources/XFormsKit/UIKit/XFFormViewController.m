/* XFFormViewController.m — the iOS form. Rows come from XFFormRows; this
   file is only the table view and the cells that show them.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#import <XFormsKit/XFFormViewController.h>

#if __has_include(<UIKit/UIKit.h>)

#import <XFormsKit/XFFormRows.h>
#import <XFormsKit/XFRichText.h>
#import <XFormsKit/XFDateDisplay.h>
#import <XFormsKit/XFProcessor.h>
#import <XFormsKit/XFControl.h>
#import <XFormsKit/XFGroup.h>
#import <XFormsKit/XFDialog.h>
#import <XFormsKit/XFHostNode.h>
#import <XFormsKit/XFSecretControl.h>
#import <XFormsKit/XFSelectControl.h>
#import <XFormsKit/XFTriggerControl.h>
#import <XFormsKit/XFInputControl.h>
#import <XFormsKit/XFRangeControl.h>
#import <XFormsKit/XFRepeat.h>
#import <XFormsKit/XFUploadControl.h>
#import <XFormsKit/XFSVG.h>
#import <XFormsKit/XFOutputControl.h>
#import <XFormsKit/XFTableModel.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

/// What a cell needs back from the form: cells edit controls, the
/// controller owns the processor and the reload that follows.
@interface XFFormViewController (XFFormCellHost)
- (void)commitControl:(nullable XFControl *)control value:(nullable NSString *)value;
/// A date from a picker: the control formats it for the instance itself.
- (void)commitDate:(NSDate *)date ofInput:(XFInputControl *)input;
/// A number from a slider, likewise.
- (void)commitNumber:(double)value ofRange:(XFRangeControl *)range;
/// Pick one item of a select (appearance minimal or a segmented row).
- (void)selectValue:(nullable NSString *)value ofSelect:(XFSelectControl *)select;
/// Turn one item on or off (appearance full, and every multiple select).
- (void)toggleValue:(nullable NSString *)value ofSelect:(XFSelectControl *)select;
/// The list of items, for a select that shows only its chosen value: the
/// select1 row, and a select inside a table cell or a sentence.
- (void)presentOptionsForSelect:(XFSelectControl *)select;
/// The shared prev / next / Done bar every editable field puts above the
/// keyboard; the rich variant carries bold / italic / underline too.
- (UIToolbar *)keyboardAccessoryView;
- (UIToolbar *)keyboardAccessoryViewForRichText:(BOOL)rich;
/// The rich text view holding the keyboard, which the formatting buttons
/// act on (nil when what is being edited is not rich).
- (void)richEditorDidBeginEditing:(nullable UITextView *)textView;
/// A field took the keyboard: the engine's focus follows it, and the bar
/// re-reads which way it can move.
- (void)fieldDidBeginEditing:(nullable XFControl *)control;
/// And gave it up again.
- (void)fieldDidEndEditing:(nullable XFControl *)control;
@end

/// A cell is bound to a row while it is on screen and forgets it after.
/// The control it shows outlives every cell that ever showed it.
@interface XFFormCell : UITableViewCell
@property (nonatomic, strong, nullable) XFFormRow *row;
@property (nonatomic, weak, nullable) XFFormViewController *formController;
- (void)bindRow:(XFFormRow *)row;
- (void)keepContentHeightOpenAround:(UIView *)widget;
@end

@implementation XFFormCell

- (void)bindRow:(XFFormRow *)row
{
    self.row = row;
    self.textLabel.text = row.label;
    // a nested group has nowhere to go in a two-level table, so its depth
    // becomes an indent instead
    self.indentationLevel = (NSInteger)(row.depth > 1 ? row.depth - 1 : 0);
    self.indentationWidth = 16;
    XFControl *control = row.control;
    self.textLabel.textColor = (control == nil || control.valid)
        ? [UIColor labelColor] : [UIColor systemRedColor];
    self.userInteractionEnabled = control == nil || !control.readonly;
}

/// Makes the content view's height solvable for a widget that is only
/// centred in it.
///
/// These cells keep the stock `textLabel` for the control's label, and
/// that label is not laid out with Auto Layout — so the widget beside it
/// cannot be pinned top AND bottom to the margins without dictating the
/// row height for the label too. Left with a centre, a width and a
/// trailing edge, the content view's height solves to zero, which a
/// self-sizing table view reports before falling back: "constraints
/// ambiguously suggest a height of zero for a table view cell's content
/// view ... using standard height instead". Keeping the widget inside the
/// margins and giving the content view a floor one standard row high
/// makes the height determinate, and still lets a taller widget open the
/// row further.
- (void)keepContentHeightOpenAround:(UIView *)widget
{
    UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
    NSLayoutConstraint *floor =
        [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:44];
    // below required so it never fights UIKit's own cell constraints, far
    // above the fitting-size priority the table view measures with
    floor.priority = UILayoutPriorityRequired - 1;
    [NSLayoutConstraint activateConstraints:@[
        [widget.topAnchor constraintGreaterThanOrEqualToAnchor:margins.topAnchor],
        [margins.bottomAnchor constraintGreaterThanOrEqualToAnchor:widget.bottomAnchor],
        floor,
    ]];
}

@end

#pragma mark - Widgets for inline controls

/// What a view holding inline control widgets must answer, so the widget
/// factory below can wire them up.
@protocol XFInlineWidgetHost <NSObject>
@property (nonatomic, weak, nullable) XFFormViewController *formController;
/// Keep the control this view stands for, for the actions to look up.
- (void)rememberControl:(XFControl *)control forView:(UIView *)view;
- (void)inlineTriggerFired:(UIButton *)sender;
- (void)inlineSelectTapped:(UIButton *)sender;
- (void)inlineSwitchChanged:(UISwitch *)sender;
- (void)inlineFieldDidBegin:(UITextField *)sender;
- (void)inlineFieldDidEnd:(UITextField *)sender;
- (void)inlineFieldChanged:(UITextField *)sender;
@end

/// What a select shows when it is not opened: the labels of the chosen
/// items, or the raw value when an item carries none. Empty when nothing
/// is chosen, which the caller turns into a prompt.
static NSString *XFSelectedLabel(XFSelectControl *select)
{
    NSMutableArray<NSString *> *chosen = [NSMutableArray array];
    for (XFItem *item in select.items) {
        if (item.selected) {
            [chosen addObject:item.label.length ? item.label : (item.value ?: @"")];
        }
    }
    return [chosen componentsJoinedByString:@", "];
}

/// The widget for one INLINE control — a control that sits on a line
/// rather than owning a block.
///
/// Shared by the table grid and the inline flow, so a trigger in a table
/// cell and the same trigger in a sentence are the same button with the
/// same behaviour, and there is one place to fix when a control kind is
/// handled badly.
static UIView *XFInlineWidgetForControl(XFControl *control, id<XFInlineWidgetHost> host)
{
    UIFont *body = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

    if ([control isKindOfClass:[XFTriggerControl class]]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:control.label ?: @" " forState:UIControlStateNormal];
        button.titleLabel.font = body;
        button.enabled = control.relevant && !control.readonly;
        button.contentEdgeInsets = UIEdgeInsetsMake(2, 8, 2, 8);
        button.layer.cornerRadius = 6;
        button.layer.borderWidth = 1;
        button.layer.borderColor = [UIColor separatorColor].CGColor;
        [button addTarget:host action:@selector(inlineTriggerFired:)
         forControlEvents:UIControlEventTouchUpInside];
        [host rememberControl:control forView:button];
        return button;
    }

    if ([XFFormRows kindForControl:control] == XFFormRowKindSwitch) {
        UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
        NSString *value = control.stringValue ?: @"";
        toggle.on = [value isEqualToString:@"true"] || [value isEqualToString:@"1"];
        toggle.enabled = !control.readonly;
        [toggle addTarget:host action:@selector(inlineSwitchChanged:)
         forControlEvents:UIControlEventValueChanged];
        [host rememberControl:control forView:toggle];
        return toggle;
    }

    // A select is a value control, so without this it would fall through
    // to the text field below and show the raw value — balance-table's
    // Withdraw/Deposit column read "true"/"false" and was typeable.
    // AppKit puts a popup button there; the phone equivalent is a button
    // that opens the same options list the select1 ROW opens, which also
    // covers a full-appearance select in a cell too narrow for radios.
    if ([control isKindOfClass:[XFSelectControl class]]) {
        XFSelectControl *select = (XFSelectControl *)control;
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        NSString *chosen = XFSelectedLabel(select);
        [button setTitle:chosen.length ? chosen : @"—" forState:UIControlStateNormal];
        button.titleLabel.font = body;
        button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        button.enabled = control.relevant && !control.readonly;
        button.contentEdgeInsets = UIEdgeInsetsMake(2, 8, 2, 8);
        button.layer.cornerRadius = 6;
        button.layer.borderWidth = 1;
        button.layer.borderColor = [UIColor separatorColor].CGColor;
        [button addTarget:host action:@selector(inlineSelectTapped:)
         forControlEvents:UIControlEventTouchUpInside];
        [host rememberControl:control forView:button];
        return button;
    }

    if ([control isValueControl] && ![control isKindOfClass:[XFOutputControl class]]) {
        UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
        field.text = control.stringValue;
        field.font = body;
        field.borderStyle = UITextBorderStyleRoundedRect;
        field.enabled = !control.readonly;
        field.secureTextEntry = [control isKindOfClass:[XFSecretControl class]];
        field.placeholder = control.placeholder;
        field.inputAccessoryView = [host.formController keyboardAccessoryView];
        [field addTarget:host action:@selector(inlineFieldDidEnd:)
         forControlEvents:UIControlEventEditingDidEnd];
        [field addTarget:host action:@selector(inlineFieldChanged:)
         forControlEvents:UIControlEventEditingChanged];
        [field addTarget:host action:@selector(inlineFieldDidBegin:)
         forControlEvents:UIControlEventEditingDidBegin];
        [host rememberControl:control forView:field];
        return field;
    }

    // an output, or anything with no widget of its own: its value as text
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.font = body;
    label.textColor = [UIColor labelColor];
    label.numberOfLines = 0;
    label.text = [XFDateDisplay localizedStringForControl:control]
        ?: (control.stringValue ?: @"");
    [host rememberControl:control forView:label];
    return label;
}

#pragma mark - Text field

@interface XFTextFieldFormCell : XFFormCell <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *textField;
/// The text a debounced incremental commit will write.
@property (nonatomic, copy, nullable) NSString *pendingValue;
@end

@implementation XFTextFieldFormCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    if (self) {
        _textField = [[UITextField alloc] initWithFrame:CGRectZero];
        _textField.translatesAutoresizingMaskIntoConstraints = NO;
        _textField.textAlignment = NSTextAlignmentRight;
        _textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        _textField.delegate = self;
        // Two events, not one. XForms commits on focus loss by default and
        // on every keystroke when incremental="true" -- the AppKit field
        // makes the same distinction, and binding only DidEnd here left
        // incremental silently not working on iOS.
        [_textField addTarget:self action:@selector(editingDidEnd:)
             forControlEvents:UIControlEventEditingDidEnd];
        [_textField addTarget:self action:@selector(editingChanged:)
             forControlEvents:UIControlEventEditingChanged];
        [self.contentView addSubview:_textField];
        // the stock textLabel keeps the left half; the field takes the rest
        [NSLayoutConstraint activateConstraints:@[
            [_textField.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [_textField.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_textField.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor multiplier:0.55],
        ]];
        [self keepContentHeightOpenAround:_textField];
    }
    return self;
}

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    XFControl *control = row.control;
    self.textField.text = control.stringValue;
    // @placeholder wins; a minimal-appearance hint doubles as one, which is
    // XSLTForms' rule and what the AppKit field does
    self.textField.placeholder = control.placeholder.length ? control.placeholder
        : (control.hintMinimal ? control.hint : nil);
    self.textField.enabled = !control.readonly;
    self.textField.secureTextEntry = [control isKindOfClass:[XFSecretControl class]];
    // iOS has no key-view loop to tab around: the bar above the keyboard
    // is where field-to-field navigation lives, so every editable field
    // carries it
    self.textField.inputAccessoryView = [self.formController keyboardAccessoryView];
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    (void)textField;
    [self.formController fieldDidBeginEditing:self.row.control];
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    (void)textField;
    [self.formController fieldDidEndEditing:self.row.control];
}

- (void)editingDidEnd:(UITextField *)sender
{
    if (!self.row.control.incremental) {
        [self.formController commitControl:self.row.control value:sender.text];
    }
}

/// incremental="true": every keystroke, debounced by @delay where the form
/// asked for one, so a recalculate-heavy form is not rebuilt per character.
- (void)editingChanged:(UITextField *)sender
{
    XFControl *control = self.row.control;
    if (!control.incremental) {
        return;
    }
    NSString *value = sender.text;
    if (control.delay > 0) {
        SEL commit = @selector(commitPendingIncremental);
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:commit object:nil];
        self.pendingValue = value;
        [self performSelector:commit withObject:nil
                   afterDelay:control.delay / 1000.0];
        return;
    }
    [self.formController commitControl:control value:value];
}

- (void)commitPendingIncremental
{
    [self.formController commitControl:self.row.control value:self.pendingValue];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return NO;
}

@end

#pragma mark - Text view (xf:textarea)

/// xf:textarea. A real multi-line editor, and — when the control asks for
/// `mediatype="application/xhtml+xml"` (XForms 1.1 §8.1.5, the TinyMCE
/// sample) — a RICH one: the instance holds markup, and the user edits
/// formatted text rather than the tags.
///
/// Showing the markup verbatim in a one-line field, which is what a
/// textarea used to get here, is wrong twice over: it is not the content
/// the form means to present, and it invites the user to hand-edit XHTML
/// in a text field.
///
/// The conversion both ways is XFRichText, the same converter the AppKit
/// editor uses, so a document round-trips identically on either platform.
@interface XFTextViewFormCell : XFFormCell <UITextViewDelegate>
@property (nonatomic, strong) UILabel *caption;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@property (nonatomic, copy, nullable) NSString *pendingValue;
@end

@implementation XFTextViewFormCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    if (self) {
        _caption = [[UILabel alloc] initWithFrame:CGRectZero];
        _caption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        _caption.textColor = [UIColor secondaryLabelColor];
        _textView = [[UITextView alloc] initWithFrame:CGRectZero];
        _textView.delegate = self;
        _textView.backgroundColor = [UIColor clearColor];
        _textView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _textView.textContainerInset = UIEdgeInsetsMake(4, 0, 4, 0);
        _textView.textContainer.lineFragmentPadding = 0;
        _textView.scrollEnabled = NO;   // the table scrolls, not the field
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:
            @[ _caption, _textView ]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 4;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];
        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        _heightConstraint = [_textView.heightAnchor constraintGreaterThanOrEqualToConstant:88];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:margins.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
            _heightConstraint,
        ]];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

/// The instance holds markup and the user should see it formatted.
+ (BOOL)isRichControl:(XFControl *)control
{
    return [[control.mediatype lowercaseString] isEqualToString:@"application/xhtml+xml"];
}

- (BOOL)isRich
{
    return [[self class] isRichControl:self.row.control];
}

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    XFControl *control = row.control;
    self.textLabel.text = nil;           // the caption above the field instead
    self.caption.text = row.label;
    self.caption.hidden = row.label.length == 0;
    self.textView.editable = !control.readonly;
    // @rows, as the AppKit textarea honours it
    self.heightConstraint.constant = control.rows > 0 ? MAX(control.rows * 22, 44) : 88;
    UIFont *body = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    if ([self isRich]) {
        self.textView.attributedText =
            [XFRichText attributedStringFromMarkup:control.stringValue
                                         plainText:control.stringValue
                                          baseFont:body
                                         textColor:[UIColor labelColor]];
    } else {
        self.textView.font = body;
        self.textView.textColor = [UIColor labelColor];
        self.textView.text = control.stringValue;
    }
    self.textView.inputAccessoryView =
        [self.formController keyboardAccessoryViewForRichText:[self isRich]];
}

/// What the instance should hold for what is on screen now.
- (NSString *)editedValue
{
    return [self isRich] ? [XFRichText htmlFromAttributedString:self.textView.attributedText]
                         : self.textView.text;
}

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    [self.formController fieldDidBeginEditing:self.row.control];
    [self.formController richEditorDidBeginEditing:[self isRich] ? textView : nil];
}

- (void)textViewDidEndEditing:(UITextView *)textView
{
    (void)textView;
    if (!self.row.control.incremental) {
        [self.formController commitControl:self.row.control value:[self editedValue]];
    }
    [self.formController richEditorDidBeginEditing:nil];
    [self.formController fieldDidEndEditing:self.row.control];
}

/// incremental="true", debounced by @delay, exactly as the text field does.
- (void)textViewDidChange:(UITextView *)textView
{
    (void)textView;
    XFControl *control = self.row.control;
    if (!control.incremental) {
        return;
    }
    if (control.delay > 0) {
        SEL commit = @selector(commitPendingIncremental);
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:commit object:nil];
        self.pendingValue = [self editedValue];
        [self performSelector:commit withObject:nil afterDelay:control.delay / 1000.0];
        return;
    }
    [self.formController commitControl:control value:[self editedValue]];
}

- (void)commitPendingIncremental
{
    [self.formController commitControl:self.row.control value:self.pendingValue];
}

@end

#pragma mark - Switch

@interface XFSwitchFormCell : XFFormCell
@property (nonatomic, strong) UISwitch *toggle;
@end

@implementation XFSwitchFormCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    if (self) {
        _toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
        [_toggle addTarget:self action:@selector(toggled:)
          forControlEvents:UIControlEventValueChanged];
        self.accessoryView = _toggle;   // the idiom: a switch is an accessory
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    NSString *value = row.control.stringValue ?: @"";
    self.toggle.on = [value isEqualToString:@"true"] || [value isEqualToString:@"1"];
    self.toggle.enabled = !row.control.readonly;
}

- (void)toggled:(UISwitch *)sender
{
    [self.formController commitControl:self.row.control
                                 value:sender.isOn ? @"true" : @"false"];
}

@end

#pragma mark - Selector, button, value

/// select1: the value on the right and a disclosure, like every other
/// "tap me to choose" row on iOS. The picker itself is phase 5 proper.
@interface XFSelectorFormCell : XFFormCell
@end

@implementation XFSelectorFormCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
    if (self) {
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    NSString *shown = nil;
    if ([row.control isKindOfClass:[XFSelectControl class]]) {
        for (XFItem *item in [(XFSelectControl *)row.control items]) {
            if (item.selected) {
                shown = item.label;
                break;
            }
        }
    }
    self.detailTextLabel.text = shown ?: row.control.stringValue;
}

@end

@interface XFButtonFormCell : XFFormCell
@end

@implementation XFButtonFormCell

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    self.textLabel.textAlignment = NSTextAlignmentCenter;
    self.textLabel.textColor = row.control.readonly ? [UIColor secondaryLabelColor]
                                                    : [UIColor systemBlueColor];
}

@end

@interface XFValueFormCell : XFFormCell
@end

@implementation XFValueFormCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    XFControl *control = row.control;
    // xf:output mediatype="application/xhtml+xml" means the value IS
    // markup and is shown formatted; without a mediatype the same value
    // is shown as the text it is (the TinyMCE sample puts both side by
    // side, and they must not look the same).
    if ([control isKindOfClass:[XFOutputControl class]]
        && [(XFOutputControl *)control displaysHTML]) {
        self.detailTextLabel.numberOfLines = 0;
        self.detailTextLabel.attributedText =
            [XFRichText attributedStringFromMarkup:control.stringValue
                                         plainText:control.stringValue
                                          baseFont:self.detailTextLabel.font
                                         textColor:[UIColor secondaryLabelColor]];
        return;
    }
    self.detailTextLabel.numberOfLines = 1;
    self.detailTextLabel.text =
        [XFDateDisplay localizedStringForControl:control] ?: control.stringValue;
}

@end

#pragma mark - Check and segmented (appearance="full")

/// One item of a full-appearance select. All of them are on the form at
/// once, which is what "full" means; the checkmark is the iOS spelling of
/// the radio button or checkbox the desktop draws.
@interface XFCheckFormCell : XFFormCell
@end

@implementation XFCheckFormCell

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    XFSelectControl *select = (XFSelectControl *)row.control;
    XFItem *item = row.itemIndex < select.items.count ? select.items[row.itemIndex] : nil;
    // the control's own label is the section-ish caption on the first item;
    // every row shows the ITEM's label
    self.textLabel.text = item.label ?: item.value;
    self.accessoryType = item.selected ? UITableViewCellAccessoryCheckmark
                                       : UITableViewCellAccessoryNone;
    self.indentationLevel = (NSInteger)(row.depth > 1 ? row.depth - 1 : 0) + 1;
}

@end

/// A full-appearance select with few enough items to read side by side.
@interface XFSegmentedFormCell : XFFormCell
@property (nonatomic, strong) UISegmentedControl *segments;
@end

@implementation XFSegmentedFormCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    if (self) {
        _segments = [[UISegmentedControl alloc] initWithItems:@[]];
        _segments.translatesAutoresizingMaskIntoConstraints = NO;
        [_segments addTarget:self action:@selector(changed:)
            forControlEvents:UIControlEventValueChanged];
        [self.contentView addSubview:_segments];
        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_segments.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            [_segments.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
        [self keepContentHeightOpenAround:_segments];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    XFSelectControl *select = (XFSelectControl *)row.control;
    [self.segments removeAllSegments];
    NSInteger chosen = UISegmentedControlNoSegment;
    NSUInteger i = 0;
    for (XFItem *item in select.items) {
        [self.segments insertSegmentWithTitle:(item.label ?: item.value)
                                      atIndex:i animated:NO];
        if (item.selected) {
            chosen = (NSInteger)i;
        }
        i++;
    }
    self.segments.selectedSegmentIndex = chosen;
    self.segments.enabled = !select.readonly;
}

- (void)changed:(UISegmentedControl *)sender
{
    XFSelectControl *select = (XFSelectControl *)self.row.control;
    NSInteger index = sender.selectedSegmentIndex;
    if (index >= 0 && (NSUInteger)index < select.items.count) {
        [self.formController selectValue:select.items[(NSUInteger)index].value
                                ofSelect:select];
    }
}

@end

#pragma mark - Upload

/// xf:upload. The row names the chosen file, or invites one.
@interface XFUploadFormCell : XFFormCell
@end

@implementation XFUploadFormCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
    if (self) {
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    XFUploadControl *upload = (XFUploadControl *)row.control;
    self.detailTextLabel.text = upload.fileName.length ? upload.fileName : @"Choose…";
}

@end

#pragma mark - Date and slider

/// xsd:date / time / dateTime. The picker is the cell's inputView, so it
/// rises where the keyboard would and the row keeps its height -- the row
/// shows the value, tapping it brings the wheels up. That is the idiom;
/// an inline picker row is the alternative, and costs a second row kind.
@interface XFDateFormCell : XFFormCell
@property (nonatomic, strong) UIDatePicker *picker;
@end

@implementation XFDateFormCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
    if (self) {
        _picker = [[UIDatePicker alloc] initWithFrame:CGRectZero];
        _picker.preferredDatePickerStyle = UIDatePickerStyleWheels;   // an inputView needs a keyboard-shaped picker
        [_picker addTarget:self action:@selector(picked:)
          forControlEvents:UIControlEventValueChanged];
    }
    return self;
}

- (BOOL)canBecomeFirstResponder
{
    return !self.row.control.readonly;
}

- (UIView *)inputView
{
    return self.picker;
}

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    XFInputControl *input = (XFInputControl *)row.control;
    XFDateType type = [input resolvedDateType];
    self.picker.datePickerMode = type == XFDateTypeTime ? UIDatePickerModeTime
        : (type == XFDateTypeDateTime ? UIDatePickerModeDateAndTime : UIDatePickerModeDate);
    self.picker.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDate *value = [input dateValue];
    if (value != nil) {
        self.picker.date = value;
    }
    // the picker itself is localized; the text beside it must be too, or
    // the row shows the instance's lexical value instead of a date
    self.detailTextLabel.text =
        [XFDateDisplay localizedStringForControl:input] ?: input.stringValue;
}

- (void)picked:(UIDatePicker *)sender
{
    [self.formController commitDate:sender.date ofInput:(XFInputControl *)self.row.control];
}

@end

/// xf:range. The value shows in the detail label as it moves; the write
/// lands when the finger lifts unless the control is incremental, which is
/// XForms' own distinction and the same one the AppKit slider makes.
@interface XFSliderFormCell : XFFormCell
@property (nonatomic, strong) UISlider *slider;
@end

@implementation XFSliderFormCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
    if (self) {
        _slider = [[UISlider alloc] initWithFrame:CGRectZero];
        _slider.translatesAutoresizingMaskIntoConstraints = NO;
        [_slider addTarget:self action:@selector(moved:)
          forControlEvents:UIControlEventValueChanged];
        [_slider addTarget:self action:@selector(finished:)
          forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        [self.contentView addSubview:_slider];
        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_slider.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            [_slider.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_slider.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor multiplier:0.45],
        ]];
        [self keepContentHeightOpenAround:_slider];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    XFRangeControl *range = (XFRangeControl *)row.control;
    self.slider.minimumValue = (float)range.start;
    self.slider.maximumValue = (float)range.end;
    self.slider.value = (float)range.numericValue;
    self.slider.enabled = !range.readonly;
    self.detailTextLabel.text = range.stringValue;
}

/// Quantised to @step: UISlider is continuous and XForms' range is not.
- (double)steppedValue
{
    XFRangeControl *range = (XFRangeControl *)self.row.control;
    double value = (double)self.slider.value;
    if (range.step > 0) {
        value = range.start + round((value - range.start) / range.step) * range.step;
    }
    return MIN(MAX(value, range.start), range.end);
}

- (void)moved:(UISlider *)sender
{
    (void)sender;
    XFRangeControl *range = (XFRangeControl *)self.row.control;
    double value = [self steppedValue];
    self.detailTextLabel.text = [NSString stringWithFormat:@"%g", value];
    if (range.incremental) {
        [self.formController commitNumber:value ofRange:range];
    }
}

- (void)finished:(UISlider *)sender
{
    (void)sender;
    XFRangeControl *range = (XFRangeControl *)self.row.control;
    if (!range.incremental) {
        [self.formController commitNumber:[self steppedValue] ofRange:range];
    }
}

@end

#pragma mark - The options screen (appearance="minimal")

/// The list a minimal-appearance select pushes. "Minimal" means the
/// options are NOT on the form -- a popup menu on the desktop, a screen of
/// its own here, which is what iOS does with a long list and what XLForm
/// calls a push selector.
///
/// A single select picks and pops straight back; a multiple select stays,
/// because the user is not done after one tap.
@interface XFSelectOptionsViewController : UITableViewController
@property (nonatomic, strong) XFSelectControl *select;
@property (nonatomic, weak) XFFormViewController *form;
@end

@implementation XFSelectOptionsViewController

- (instancetype)initWithSelect:(XFSelectControl *)select form:(XFFormViewController *)form
{
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _select = select;
        _form = form;
        self.title = select.label;
    }
    return self;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.select.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"option"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"option"];
    }
    XFItem *item = self.select.items[(NSUInteger)indexPath.row];
    cell.textLabel.text = item.label ?: item.value;
    cell.accessoryType = item.selected ? UITableViewCellAccessoryCheckmark
                                       : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    XFItem *item = self.select.items[(NSUInteger)indexPath.row];
    if (self.select.multiple) {
        [self.form toggleValue:item.value ofSelect:self.select];
        [tableView reloadData];
        return;
    }
    [self.form selectValue:item.value ofSelect:self.select];
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

@end

#pragma mark - Note

/// The hint / alert line under a control. Footnote size, secondary colour
/// for guidance and red for a problem, with no separator of its own so it
/// reads as part of the row above rather than as another row.
@interface XFNoteFormCell : XFFormCell
@property (nonatomic, strong) UILabel *note;
@end

@implementation XFNoteFormCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    if (self) {
        _note = [[UILabel alloc] initWithFrame:CGRectZero];
        _note.translatesAutoresizingMaskIntoConstraints = NO;
        _note.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _note.numberOfLines = 0;
        [self.contentView addSubview:_note];
        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_note.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [_note.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            [_note.topAnchor constraintEqualToAnchor:margins.topAnchor constant:-4],
            [_note.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
        ]];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    self.textLabel.text = nil;
    UIColor *colour = row.noteIsProblem ? [UIColor systemRedColor]
                                        : [UIColor secondaryLabelColor];
    self.note.textColor = colour;
    // a hint or alert may carry host markup (XForms 1.1 §9.3.1); the
    // footnote size and the red stay, the form's emphasis is added
    self.note.attributedText =
        [XFRichText attributedStringFromMarkup:row.noteMarkup
                                     plainText:row.note
                                      baseFont:[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]
                                     textColor:colour];
    self.accessibilityLabel = row.noteIsProblem
        ? [NSString stringWithFormat:@"Error: %@", row.note ?: @""] : row.note;
}

@end

#pragma mark - Repeat add row

/// The row that closes a repeat section: tap it to add one more item.
///
/// A tappable row rather than the table's own insert control, because
/// that control only appears while the table is in editing mode and this
/// form has no Edit button — Contacts and Settings add rows the same way.
/// Removal is the swipe, which needs no mode either.
@interface XFRepeatAddFormCell : XFFormCell
@end

@implementation XFRepeatAddFormCell

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    self.textLabel.text = NSLocalizedString(@"Add item", nil);
    self.textLabel.textColor = [UIColor systemBlueColor];
    self.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
    self.imageView.tintColor = [UIColor systemGreenColor];
    self.accessoryType = UITableViewCellAccessoryNone;
}

@end

#pragma mark - Prose with controls in it

static const CGFloat kXFFlowGap = 4;
static const CGFloat kXFFlowLineGap = 6;

/// A sentence with controls in it, laid out as a line that wraps.
///
/// `<p><xf:output ref="@firstname"/> <xf:output ref="@lastname"/>
/// <xf:trigger><xf:label>Show Books</xf:label></xf:trigger></p>` reads as
/// a name followed by a button, and that is how it is drawn: the words
/// and the widgets share lines and wrap at the edge of the row. The form
/// still scrolls in one direction only.
///
/// Words are laid out one at a time rather than as whole text runs,
/// because a widget can sit in the middle of a sentence and the text
/// either side of it has to break around it. Blocks WITHOUT controls
/// never come here — they are prose, and one label lays them out
/// properly — so the pieces stay few.
@interface XFInlineFlowView : UIView <XFInlineWidgetHost>
@property (nonatomic, weak, nullable) XFFormViewController *formController;
- (void)bindNodes:(NSArray<XFHostNode *> *)nodes context:(nullable XFXMLNode *)context;
@end

@implementation XFInlineFlowView {
    NSMutableArray<UIView *> *_items;
    /// Items that must start a new line (a <br/>).
    NSMutableIndexSet *_breaks;
    NSMapTable<UIView *, XFControl *> *_controlsByView;
    NSString *_shape;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _items = [NSMutableArray array];
        _breaks = [NSMutableIndexSet indexSet];
        _controlsByView = [NSMapTable weakToStrongObjectsMapTable];
    }
    return self;
}

- (void)rememberControl:(XFControl *)control forView:(UIView *)view
{
    [_controlsByView setObject:control forKey:view];
}

#pragma mark building

- (void)bindNodes:(NSArray<XFHostNode *> *)nodes context:(XFXMLNode *)context
{
    (void)context;   // the controls are already bound; the context is the SVG's
    NSMutableString *shape = [NSMutableString string];
    [self appendShapeOf:nodes into:shape];
    if ([shape isEqualToString:_shape]) {
        [self refreshValues];
        return;
    }
    _shape = shape;
    for (UIView *item in _items) {
        [item removeFromSuperview];
    }
    [_items removeAllObjects];
    [_breaks removeAllIndexes];
    _controlsByView = [NSMapTable weakToStrongObjectsMapTable];
    [self appendNodes:nodes];
    [self setNeedsLayout];
}

- (void)appendShapeOf:(NSArray<XFHostNode *> *)nodes into:(NSMutableString *)shape
{
    for (XFHostNode *node in nodes) {
        [shape appendFormat:@"%ld:", (long)node.kind];
        if (node.kind == XFHostNodeKindControl) {
            [shape appendFormat:@"%p.%d;", (void *)node.control, node.control.relevant];
        } else if (node.kind == XFHostNodeKindText) {
            [shape appendFormat:@"%@;", node.textContent ?: @""];
        } else {
            [self appendShapeOf:node.children into:shape];
        }
    }
}

- (void)appendNodes:(NSArray<XFHostNode *> *)nodes
{
    for (XFHostNode *node in nodes) {
        switch (node.kind) {
            case XFHostNodeKindControl: {
                XFControl *control = node.control;
                if (control == nil || !control.relevant) {
                    continue;   // not rendered, as everywhere else
                }
                UIView *widget = XFInlineWidgetForControl(control, self);
                [self addSubview:widget];
                [_items addObject:widget];
                break;
            }
            case XFHostNodeKindText:
                [self appendWordsOf:node.textContent ?: @""];
                break;
            case XFHostNodeKindBreak:
                [_breaks addIndex:_items.count];
                break;
            case XFHostNodeKindInline:
                // the emphasis of a <b> or <em> is not carried into the
                // words yet; the text is what the sentence needs first
                [self appendNodes:node.children];
                break;
            default:
                break;
        }
    }
}

- (void)appendWordsOf:(NSString *)text
{
    UIFont *body = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    // a non-breaking space is a space that must not break; the samples
    // use it to hold a name together, so it joins its neighbours
    NSString *flat = [text stringByReplacingOccurrencesOfString:@"\u00a0" withString:@" "];
    for (NSString *word in [flat componentsSeparatedByCharactersInSet:
             [NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
        if (word.length == 0) {
            continue;
        }
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.font = body;
        label.textColor = [UIColor labelColor];
        label.text = word;
        [self addSubview:label];
        [_items addObject:label];
    }
}

/// Values only, so a field on the line keeps the keyboard through a
/// recalculate (the same rule the grid follows).
- (void)refreshValues
{
    for (UIView *item in _items) {
        XFControl *control = [_controlsByView objectForKey:item];
        if (control == nil) {
            continue;
        }
        if ([item isKindOfClass:[UITextField class]]) {
            UITextField *field = (UITextField *)item;
            if (!field.isFirstResponder) {
                field.text = control.stringValue;
            }
            field.enabled = !control.readonly;
        } else if ([item isKindOfClass:[UISwitch class]]) {
            NSString *value = control.stringValue ?: @"";
            ((UISwitch *)item).on = [value isEqualToString:@"true"]
                                 || [value isEqualToString:@"1"];
        } else if ([item isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)item;
            button.enabled = control.relevant && !control.readonly;
            if ([control isKindOfClass:[XFSelectControl class]]) {
                NSString *chosen = XFSelectedLabel((XFSelectControl *)control);
                [button setTitle:chosen.length ? chosen : @"—" forState:UIControlStateNormal];
            } else {
                [button setTitle:control.label ?: @" " forState:UIControlStateNormal];
            }
        } else if ([item isKindOfClass:[UILabel class]]) {
            ((UILabel *)item).text = [XFDateDisplay localizedStringForControl:control]
                ?: (control.stringValue ?: @"");
        }
    }
}

#pragma mark actions

- (void)inlineTriggerFired:(UIButton *)sender
{
    XFControl *control = [_controlsByView objectForKey:sender];
    if ([control isKindOfClass:[XFTriggerControl class]]) {
        [self.formController.processor activateControl:(XFTriggerControl *)control];
        [self.formController reloadFromProcessor];
    }
}

- (void)inlineSelectTapped:(UIButton *)sender
{
    XFControl *control = [_controlsByView objectForKey:sender];
    if ([control isKindOfClass:[XFSelectControl class]]) {
        [self.formController presentOptionsForSelect:(XFSelectControl *)control];
    }
}

- (void)inlineSwitchChanged:(UISwitch *)sender
{
    [self.formController commitControl:[_controlsByView objectForKey:sender]
                                 value:sender.isOn ? @"true" : @"false"];
}

- (void)inlineFieldDidBegin:(UITextField *)sender
{
    [self.formController fieldDidBeginEditing:[_controlsByView objectForKey:sender]];
}

- (void)inlineFieldDidEnd:(UITextField *)sender
{
    XFControl *control = [_controlsByView objectForKey:sender];
    if (!control.incremental) {
        [self.formController commitControl:control value:sender.text];
    }
    [self.formController fieldDidEndEditing:control];
}

- (void)inlineFieldChanged:(UITextField *)sender
{
    XFControl *control = [_controlsByView objectForKey:sender];
    if (control.incremental) {
        [self.formController commitControl:control value:sender.text];
    }
}

#pragma mark flowing

/// Places every item, wrapping at `width`, and answers the height used.
/// `apply` NO measures without moving anything, which is how the cell
/// answers its own height before it is laid out.
- (CGFloat)flowIntoWidth:(CGFloat)width apply:(BOOL)apply
{
    CGFloat x = 0, y = 0, lineHeight = 0;
    for (NSUInteger i = 0; i < _items.count; i++) {
        UIView *item = _items[i];
        CGSize size = [item sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
        size.width = MIN(size.width, width);
        BOOL forced = [_breaks containsIndex:i];
        if (forced || (x > 0 && x + size.width > width)) {
            x = 0;
            y += lineHeight + kXFFlowLineGap;
            lineHeight = 0;
        }
        if (apply) {
            item.frame = CGRectMake(x, y, size.width, size.height);
        }
        x += size.width + kXFFlowGap;
        lineHeight = MAX(lineHeight, size.height);
    }
    return y + lineHeight;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self flowIntoWidth:self.bounds.size.width apply:YES];
}

- (CGSize)sizeThatFits:(CGSize)size
{
    CGFloat width = size.width > 0 && size.width < CGFLOAT_MAX
        ? size.width : self.bounds.size.width;
    return CGSizeMake(width, [self flowIntoWidth:width apply:NO]);
}

@end

/// The row holding one such sentence.
///
/// Laid out by hand, and it answers its own height through
/// -systemLayoutSizeFittingSize: — the hook the table view uses for an
/// automatic row height. A flowed line's height depends on the width it
/// is given, which an intrinsic content size cannot express.
@interface XFInlineFlowFormCell : XFFormCell
@property (nonatomic, strong) XFInlineFlowView *flow;
@end

@implementation XFInlineFlowFormCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    if (self) {
        _flow = [[XFInlineFlowView alloc] initWithFrame:CGRectZero];
        [self.contentView addSubview:_flow];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    self.textLabel.text = nil;
    self.flow.formController = self.formController;
    [self.flow bindNodes:row.hostNodes context:row.contextNode];
    [self setNeedsLayout];
}

- (UIEdgeInsets)flowInsets
{
    UIEdgeInsets margins = self.contentView.layoutMargins;
    return UIEdgeInsetsMake(MAX(margins.top, 8), margins.left,
                            MAX(margins.bottom, 8), margins.right);
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    UIEdgeInsets insets = [self flowInsets];
    CGFloat width = self.contentView.bounds.size.width - insets.left - insets.right;
    self.flow.frame = CGRectMake(insets.left, insets.top, MAX(width, 1),
                                 [self.flow sizeThatFits:
                                     CGSizeMake(MAX(width, 1), CGFLOAT_MAX)].height);
}

- (CGSize)systemLayoutSizeFittingSize:(CGSize)targetSize
        withHorizontalFittingPriority:(UILayoutPriority)horizontal
              verticalFittingPriority:(UILayoutPriority)vertical
{
    (void)horizontal; (void)vertical;
    UIEdgeInsets insets = [self flowInsets];
    CGFloat width = MAX(targetSize.width - insets.left - insets.right, 1);
    CGFloat height = [self.flow sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height;
    return CGSizeMake(targetSize.width, height + insets.top + insets.bottom);
}

@end

#pragma mark - Rich message sheet

/// Shows one attributed message and nothing else. The text view is not
/// editable and takes no keyboard; it stays selectable so a reader can
/// copy an error out, and scrolls when the message is longer than the
/// sheet.
@interface XFRichMessageViewController : UIViewController
- (instancetype)initWithAttributedText:(NSAttributedString *)text;
@end

@implementation XFRichMessageViewController {
    NSAttributedString *_text;
}

- (instancetype)initWithAttributedText:(NSAttributedString *)text
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _text = [text copy];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    UITextView *body = [[UITextView alloc] initWithFrame:CGRectZero];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    body.editable = NO;
    body.attributedText = _text;
    body.backgroundColor = [UIColor clearColor];
    [self.view addSubview:body];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [body.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [body.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [body.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [body.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
    ]];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(dismissSheet)];
}

- (void)dismissSheet
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Image and table

/// xf:output with an image mediatype. Its value is base64; the value cell
/// would print the base64.
@interface XFImageFormCell : XFFormCell
@property (nonatomic, strong) UIImageView *picture;
@end

@implementation XFImageFormCell {
    NSLayoutConstraint *_width;
    NSLayoutConstraint *_height;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    if (self) {
        _picture = [[UIImageView alloc] initWithFrame:CGRectZero];
        _picture.translatesAutoresizingMaskIntoConstraints = NO;
        _picture.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:_picture];
        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        // The size is set at bind time, from the picture itself: a
        // UIImageView's intrinsic size is the image's own, and
        // Samples/output-image.xhtml carries a REAL 1x1 pixel, which
        // showed as nothing at all. XFOutputControl decides what that
        // should become, so a Mac and a phone show the same square.
        _width = [_picture.widthAnchor constraintEqualToConstant:0];
        _height = [_picture.heightAnchor constraintEqualToConstant:0];
        // the bottom pin is what makes the ROW as tall as the picture, so
        // it yields to a cell whose height is decided elsewhere rather
        // than stretching the picture to fill it
        NSLayoutConstraint *bottom =
            [_picture.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor];
        bottom.priority = UILayoutPriorityRequired - 1;
        [NSLayoutConstraint activateConstraints:@[
            [_picture.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [_picture.trailingAnchor constraintLessThanOrEqualToAnchor:margins.trailingAnchor],
            [_picture.topAnchor constraintEqualToAnchor:margins.topAnchor],
            [margins.bottomAnchor constraintGreaterThanOrEqualToAnchor:_picture.bottomAnchor],
            bottom,
            _width,
            _height,
        ]];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    NSData *data = [(XFOutputControl *)row.control imageData];
    UIImage *picture = data.length ? [UIImage imageWithData:data] : nil;
    self.picture.image = picture;
    self.textLabel.text = picture ? nil : row.label;
    // 96x72 is the empty slot, the same one the AppKit widget leaves
    CGSize shown = picture
        ? [XFOutputControl displaySizeForImageOfNaturalSize:picture.size]
        : CGSizeMake(96, 72);
    _width.constant = shown.width;
    _height.constant = shown.height;
}

@end

/// A host <table> with no controls in it.
///
/// Transposed rather than drawn as a grid: columns on a phone are the
/// horizontal-scrolling problem in miniature, and a form that scrolls
/// sideways is the thing this whole layer exists to avoid. Each body row
/// becomes a block of "Header: value" lines, which is how iOS shows a
/// record anyway. A table WITH controls never reaches here -- XFFormRows
/// walks into it so each control keeps its own editable row.
#pragma mark - Host table as a grid

static const CGFloat kXFGridPad = 8;
static const CGFloat kXFGridMinRowHeight = 36;

/// A host `<table>` drawn as a real grid: columns that line up, headers,
/// and the cells' own controls live inside it.
///
/// Laid out by hand rather than with nested stack views, because columns
/// have to align ACROSS rows — which stacks do not do — and because the
/// width decision is the whole point: columns take their natural widths
/// and share out any slack, and when the total does not fit, the grid
/// scrolls sideways INSIDE this row. The form itself still only scrolls
/// vertically; one wide table moving under the finger is the iOS answer
/// for content that cannot be narrowed, and beats a squeezed, unreadable
/// ten-column table.
@interface XFTableGridView : UIView <XFInlineWidgetHost>
@property (nonatomic, weak, nullable) XFFormViewController *formController;
/// Rebuilds when the table's shape changed, refreshes values otherwise —
/// so a recalculate does not tear down a field being typed into.
- (void)bindModel:(XFTableModel *)model;
@end

@implementation XFTableGridView {
    UIScrollView *_scroll;
    UIView *_content;
    XFTableModel *_model;
    /// Display order: header rows first, then body rows.
    NSArray<XFTableRow *> *_rows;
    /// Parallel to _rows: the view shown in each column.
    NSMutableArray<NSMutableArray<UIView *> *> *_cellViews;
    NSMapTable<UIView *, XFControl *> *_controlsByView;
    NSMutableArray<UIView *> *_separators;
    NSArray<NSNumber *> *_naturalWidths;
    NSArray<NSNumber *> *_rowHeights;
    NSString *_shape;
    CGFloat _height;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _scroll.showsHorizontalScrollIndicator = YES;
        _scroll.alwaysBounceVertical = NO;
        _content = [[UIView alloc] initWithFrame:CGRectZero];
        [_scroll addSubview:_content];
        [self addSubview:_scroll];
        _controlsByView = [NSMapTable weakToStrongObjectsMapTable];
        _cellViews = [NSMutableArray array];
        _separators = [NSMutableArray array];
    }
    return self;
}

#pragma mark shape

/// What the grid is made of. Two models with the same shape can share the
/// views that are already built; anything else has to be rebuilt.
/// A header row standing for the model's column titles.
+ (XFTableRow *)headerRowWithTitles:(NSArray<NSString *> *)titles
{
    NSMutableArray<XFTableCell *> *cells = [NSMutableArray array];
    for (NSUInteger column = 0; column < titles.count; column++) {
        XFTableCell *cell = [[XFTableCell alloc] init];
        cell.column = column;
        cell.colspan = 1;
        cell.header = YES;
        cell.text = titles[column];
        cell.controls = @[];
        [cells addObject:cell];
    }
    XFTableRow *row = [[XFTableRow alloc] init];
    row.cells = cells;
    row.header = YES;
    return row;
}

+ (NSString *)shapeOf:(XFTableModel *)model rows:(NSArray<XFTableRow *> *)rows
{
    NSMutableString *shape = [NSMutableString stringWithFormat:@"%lu/%lu:",
        (unsigned long)model.columnCount, (unsigned long)rows.count];
    for (XFTableRow *row in rows) {
        for (XFTableCell *cell in row.cells) {
            [shape appendFormat:@"%lu.%lu.%d.%p.%d;", (unsigned long)cell.column,
             (unsigned long)cell.colspan, cell.header ? 1 : 0, (void *)cell.control,
             cell.control ? cell.control.relevant : 1];
        }
        [shape appendString:@"|"];
    }
    return shape;
}

- (void)bindModel:(XFTableModel *)model
{
    NSArray<XFTableRow *> *rows =
        [model.headerRows arrayByAddingObjectsFromArray:model.rows];

    // A table with no <th> still has column names: XFTableModel takes
    // them from the labels of the controls in the first body row, which
    // is where a form like balance-table puts them (`<td><xf:input>
    // <xf:label>Date</xf:label>`). AppKit shows them as its NSTableView's
    // column titles; without this the grid showed data with no headings.
    //
    // Synthesised as an ordinary header row rather than special-cased, so
    // measuring, layout and refreshing treat it like any other.
    if (model.headerRows.count == 0 && model.columnTitles.count) {
        rows = [@[ [[self class] headerRowWithTitles:model.columnTitles] ]
                arrayByAddingObjectsFromArray:rows];
    }
    NSString *shape = [[self class] shapeOf:model rows:rows];
    shape = [shape stringByAppendingFormat:@"|titles:%@",
             [(model.columnTitles ?: @[]) componentsJoinedByString:@"\x1f"]];
    _model = model;
    _rows = rows;
    if ([shape isEqualToString:_shape]) {
        [self refreshValues];
        return;
    }
    _shape = shape;
    [self rebuild];
}

- (void)rebuild
{
    for (NSArray<UIView *> *row in _cellViews) {
        for (UIView *view in row) {
            [view removeFromSuperview];
        }
    }
    for (UIView *line in _separators) {
        [line removeFromSuperview];
    }
    [_cellViews removeAllObjects];
    [_separators removeAllObjects];
    _controlsByView = [NSMapTable weakToStrongObjectsMapTable];

    for (XFTableRow *row in _rows) {
        NSMutableArray<UIView *> *views = [NSMutableArray array];
        for (NSUInteger column = 0; column < _model.columnCount; column++) {
            XFTableCell *cell = [row cellAtColumn:column];
            // a colspan's content lives in its first column; the covered
            // ones get nothing rather than a repeat of it
            UIView *view = (cell && cell.column == column)
                ? [self viewForCell:cell header:row.header] : nil;
            if (view) {
                [_content addSubview:view];
            }
            [views addObject:view ?: [[UIView alloc] initWithFrame:CGRectZero]];
        }
        [_cellViews addObject:views];
        if (row != _rows.lastObject) {
            UIView *line = [[UIView alloc] initWithFrame:CGRectZero];
            line.backgroundColor = [UIColor separatorColor];
            [_content addSubview:line];
            [_separators addObject:line];
        }
    }
    _naturalWidths = nil;
    [self measure];
    [self setNeedsLayout];
    [self invalidateIntrinsicContentSize];
}

/// Column widths and row heights, worked out as soon as the views exist.
///
/// It has to happen here rather than in -layoutSubviews: the table view
/// asks a self-sizing cell how tall it is BEFORE laying it out, so a
/// height discovered during layout arrives too late and the row is left
/// at the minimum, clipping everything below the first line.
///
/// Measuring at the NATURAL column widths makes the answer independent of
/// the row's width. Widening a column later only gives text more room, so
/// the height computed here is an upper bound that holds.
- (void)measure
{
    NSArray<NSNumber *> *natural = [self naturalWidths];
    NSMutableArray<NSNumber *> *heights = [NSMutableArray array];
    CGFloat total = 0;
    for (NSUInteger r = 0; r < _cellViews.count; r++) {
        XFTableRow *row = _rows[r];
        CGFloat rowHeight = kXFGridMinRowHeight;
        for (NSUInteger c = 0; c < _cellViews[r].count; c++) {
            XFTableCell *cell = [row cellAtColumn:c];
            if (cell == nil || cell.column != c) {
                continue;
            }
            CGFloat width = 0;
            for (NSUInteger span = 0; span < cell.colspan && c + span < natural.count; span++) {
                width += natural[c + span].doubleValue;
            }
            CGSize fits = [_cellViews[r][c] sizeThatFits:
                CGSizeMake(MAX(width - 2 * kXFGridPad, 1), CGFLOAT_MAX)];
            rowHeight = MAX(rowHeight, fits.height + kXFGridPad);
        }
        [heights addObject:@(rowHeight)];
        total += rowHeight;
    }
    _rowHeights = heights;
    _height = total;
}

#pragma mark cell contents

/// One cell's widget. The grid is one line tall per row, so every control
/// here is an inline one; a cell holding a block keeps the table out of
/// the grid path altogether (XFFormRows tableRendersAsGrid:).
- (UIView *)viewForCell:(XFTableCell *)cell header:(BOOL)header
{
    XFControl *control = cell.control;
    UIFont *body = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    if (control != nil && !control.relevant) {
        // A non-relevant control is not rendered at all — the rest of the
        // form drops such rows, and a grid cell must not offer a field
        // that looks editable but cannot take a value. The column stays,
        // so the row still lines up. (balance-table hides the debit field
        // of a deposit this way.)
        return [[UIView alloc] initWithFrame:CGRectZero];
    }
    if (control == nil) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = cell.text ?: @"";
        label.numberOfLines = 0;
        if (header || cell.header) {
            UIFontDescriptor *bold = [body.fontDescriptor fontDescriptorWithSymbolicTraits:
                body.fontDescriptor.symbolicTraits | UIFontDescriptorTraitBold];
            label.font = bold ? [UIFont fontWithDescriptor:bold size:0] : body;
            label.textColor = [UIColor secondaryLabelColor];
        } else {
            label.font = body;
            label.textColor = [UIColor labelColor];
        }
        return label;
    }

    UIView *widget = XFInlineWidgetForControl(control, self);
    // In a TABLE the control's own xf:label belongs in the cell beside
    // its value — `<td><xf:output><xf:label>M:</xf:label>` shows "M: 0"
    // in a browser. In a sentence it does not: the label of a trigger is
    // its title, and an output in prose is just its value.
    if ([widget isKindOfClass:[UILabel class]] && control.label.length) {
        UILabel *label = (UILabel *)widget;
        NSString *value = cell.text.length ? cell.text : (label.text ?: @"");
        label.text = [NSString stringWithFormat:@"%@ %@", control.label, value];
    }
    return widget;
}

/// Values only — no view is created or destroyed, so a field holding the
/// keyboard keeps it through a recalculate.
- (void)refreshValues
{
    for (NSUInteger r = 0; r < _rows.count && r < _cellViews.count; r++) {
        XFTableRow *row = _rows[r];
        for (NSUInteger c = 0; c < _cellViews[r].count; c++) {
            UIView *view = _cellViews[r][c];
            XFTableCell *cell = [row cellAtColumn:c];
            XFControl *control = [_controlsByView objectForKey:view];
            if (control == nil) {
                if ([view isKindOfClass:[UILabel class]] && cell) {
                    ((UILabel *)view).text = cell.text ?: @"";
                }
                continue;
            }
            if ([view isKindOfClass:[UITextField class]]) {
                UITextField *field = (UITextField *)view;
                if (!field.isFirstResponder) {
                    field.text = control.stringValue;
                }
                field.enabled = !control.readonly;
            } else if ([view isKindOfClass:[UISwitch class]]) {
                NSString *value = control.stringValue ?: @"";
                ((UISwitch *)view).on = [value isEqualToString:@"true"]
                                     || [value isEqualToString:@"1"];
            } else if ([view isKindOfClass:[UIButton class]]) {
                UIButton *button = (UIButton *)view;
                button.enabled = control.relevant && !control.readonly;
                if ([control isKindOfClass:[XFSelectControl class]]) {
                    NSString *chosen = XFSelectedLabel((XFSelectControl *)control);
                    [button setTitle:chosen.length ? chosen : @"—"
                            forState:UIControlStateNormal];
                }
            } else if ([view isKindOfClass:[UILabel class]]) {
                NSString *value = cell.text.length ? cell.text : (control.stringValue ?: @"");
                ((UILabel *)view).text = control.label.length
                    ? [NSString stringWithFormat:@"%@ %@", control.label, value] : value;
            }
        }
    }
}

#pragma mark actions

- (void)rememberControl:(XFControl *)control forView:(UIView *)view
{
    [_controlsByView setObject:control forKey:view];
}

- (void)inlineTriggerFired:(UIButton *)sender
{
    XFControl *control = [_controlsByView objectForKey:sender];
    if ([control isKindOfClass:[XFTriggerControl class]]) {
        [self.formController.processor activateControl:(XFTriggerControl *)control];
        [self.formController reloadFromProcessor];
    }
}

- (void)inlineSelectTapped:(UIButton *)sender
{
    XFControl *control = [_controlsByView objectForKey:sender];
    if ([control isKindOfClass:[XFSelectControl class]]) {
        [self.formController presentOptionsForSelect:(XFSelectControl *)control];
    }
}

- (void)inlineSwitchChanged:(UISwitch *)sender
{
    [self.formController commitControl:[_controlsByView objectForKey:sender]
                                 value:sender.isOn ? @"true" : @"false"];
}

- (void)inlineFieldDidBegin:(UITextField *)sender
{
    [self.formController fieldDidBeginEditing:[_controlsByView objectForKey:sender]];
}

- (void)inlineFieldDidEnd:(UITextField *)sender
{
    XFControl *control = [_controlsByView objectForKey:sender];
    if (!control.incremental) {
        [self.formController commitControl:control value:sender.text];
    }
    [self.formController fieldDidEndEditing:control];
}

- (void)inlineFieldChanged:(UITextField *)sender
{
    XFControl *control = [_controlsByView objectForKey:sender];
    if (control.incremental) {
        [self.formController commitControl:control value:sender.text];
    }
}

#pragma mark layout

/// The width each column wants: the widest thing in it.
- (NSArray<NSNumber *> *)naturalWidths
{
    if (_naturalWidths) {
        return _naturalWidths;
    }
    NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
    for (NSUInteger c = 0; c < _model.columnCount; c++) {
        [widths addObject:@(44.0)];   // a tappable minimum
    }
    for (NSUInteger r = 0; r < _cellViews.count; r++) {
        XFTableRow *row = _rows[r];
        for (NSUInteger c = 0; c < _cellViews[r].count; c++) {
            XFTableCell *cell = [row cellAtColumn:c];
            if (cell == nil || cell.column != c || cell.colspan > 1) {
                continue;   // a spanning cell does not set one column's width
            }
            CGSize fits = [_cellViews[r][c] sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
            CGFloat want = fits.width + 2 * kXFGridPad;
            if (want > widths[c].doubleValue) {
                widths[c] = @(want);
            }
        }
    }
    _naturalWidths = widths;
    return widths;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    _scroll.frame = self.bounds;
    NSArray<NSNumber *> *natural = [self naturalWidths];
    CGFloat total = 0;
    for (NSNumber *width in natural) {
        total += width.doubleValue;
    }
    CGFloat available = self.bounds.size.width;
    // slack is shared out so a narrow table fills the row; a wide one
    // keeps its natural widths and the scroll view takes over
    CGFloat scale = (total > 0 && total < available) ? available / total : 1.0;
    NSMutableArray<NSNumber *> *columnX = [NSMutableArray array];
    CGFloat x = 0;
    for (NSNumber *width in natural) {
        [columnX addObject:@(x)];
        x += width.doubleValue * scale;
    }
    CGFloat contentWidth = MAX(x, available);

    CGFloat y = 0;
    NSUInteger separator = 0;
    for (NSUInteger r = 0; r < _cellViews.count; r++) {
        XFTableRow *row = _rows[r];
        CGFloat rowHeight = r < _rowHeights.count ? _rowHeights[r].doubleValue
                                                  : kXFGridMinRowHeight;
        for (NSUInteger c = 0; c < _cellViews[r].count; c++) {
            XFTableCell *cell = [row cellAtColumn:c];
            UIView *view = _cellViews[r][c];
            if (cell == nil || cell.column != c) {
                view.frame = CGRectZero;
                continue;
            }
            CGFloat width = 0;
            for (NSUInteger span = 0; span < cell.colspan && c + span < natural.count; span++) {
                width += natural[c + span].doubleValue * scale;
            }
            view.frame = CGRectMake(columnX[c].doubleValue + kXFGridPad, y + kXFGridPad / 2,
                                    MAX(width - 2 * kXFGridPad, 1),
                                    rowHeight - kXFGridPad);
        }
        y += rowHeight;
        if (separator < _separators.count) {
            _separators[separator].frame = CGRectMake(0, y, contentWidth,
                                                      row.header ? 1.0 : 0.5);
            separator++;
        }
    }
    _content.frame = CGRectMake(0, 0, contentWidth, y);
    _scroll.contentSize = _content.bounds.size;
}

- (CGSize)intrinsicContentSize
{
    return CGSizeMake(UIViewNoIntrinsicMetric, MAX(_height, kXFGridMinRowHeight));
}

@end

/// A host `<table>`, drawn as a grid by XFTableGridView.
///
/// It used to be transposed into a block of "Title value" text, which was
/// the honest thing to do while only control-free tables reached here.
/// Now that a table of controls does too — the calculator's keypad, a
/// spreadsheet — the grid is what those forms mean, and text cannot
/// stand in for it.
@interface XFTableFormCell : XFFormCell
@property (nonatomic, strong) XFTableGridView *grid;
@end

@implementation XFTableFormCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    if (self) {
        _grid = [[XFTableGridView alloc] initWithFrame:CGRectZero];
        _grid.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_grid];
        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_grid.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [_grid.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            [_grid.topAnchor constraintEqualToAnchor:margins.topAnchor],
            [_grid.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
        ]];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    self.textLabel.text = nil;
    self.grid.formController = self.formController;
    [self.grid bindModel:[XFTableModel modelWithTableNode:row.hostNodes.firstObject]];
}

@end

#pragma mark - Markup

/// Draws an <svg> host node. The renderer is the portable one -- the same
/// XFSVGDocument the AppKit widget draws, through the same CGContext -- so
/// a chart looks the same on both platforms.
@interface XFSVGContentView : UIView
@property (nonatomic, strong, nullable) XFSVGDocument *svgDocument;
@end

@implementation XFSVGContentView

- (void)drawRect:(CGRect)rect
{
    (void)rect;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx == NULL || self.svgDocument == nil) {
        return;
    }
    [self.svgDocument drawInContext:ctx rect:self.bounds];
}

- (CGSize)intrinsicContentSize
{
    return self.svgDocument ? self.svgDocument.size : CGSizeZero;
}

@end

/// Everything the form idiom has no row for: prose, headings, rules,
/// images and SVG. Text becomes one attributed string; an image or a chart
/// becomes a view under it.
@interface XFMarkupFormCell : XFFormCell
@property (nonatomic, strong) UILabel *body;
@property (nonatomic, strong) UIStackView *stack;
@end

@implementation XFMarkupFormCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    if (self) {
        _body = [[UILabel alloc] initWithFrame:CGRectZero];
        _body.numberOfLines = 0;
        _stack = [[UIStackView alloc] initWithArrangedSubviews:@[ _body ]];
        _stack.axis = UILayoutConstraintAxisVertical;
        _stack.spacing = 8;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_stack];
        UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [_stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            [_stack.topAnchor constraintEqualToAnchor:margins.topAnchor],
            [_stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
        ]];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

/// The text style a host tag asks for. The AppKit layout derives fonts
/// from the same tags; here they become Dynamic Type styles, so the form
/// follows the reader's size setting.
+ (UIFont *)fontForTag:(NSString *)tag heading:(NSInteger)level base:(UIFont *)base
{
    if (level == 1) { return [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1]; }
    if (level == 2) { return [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2]; }
    if (level >= 3) { return [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3]; }
    UIFontDescriptor *descriptor = base.fontDescriptor;
    if ([@[ @"b", @"strong", @"th" ] containsObject:tag]) {
        descriptor = [descriptor fontDescriptorWithSymbolicTraits:
            descriptor.symbolicTraits | UIFontDescriptorTraitBold];
    } else if ([@[ @"i", @"em", @"cite", @"var" ] containsObject:tag]) {
        descriptor = [descriptor fontDescriptorWithSymbolicTraits:
            descriptor.symbolicTraits | UIFontDescriptorTraitItalic];
    } else if ([@[ @"code", @"tt", @"kbd", @"samp", @"pre" ] containsObject:tag]) {
        return [UIFont monospacedSystemFontOfSize:base.pointSize weight:UIFontWeightRegular];
    } else {
        return base;
    }
    return [UIFont fontWithDescriptor:descriptor size:0];
}

/// Walks a run of host nodes into one attributed string, collecting any
/// SVG it passes for the caller to place underneath.
+ (void)appendNodes:(NSArray<XFHostNode *> *)nodes
               font:(UIFont *)font
                svg:(NSMutableArray<XFHostNode *> *)svg
               into:(NSMutableAttributedString *)out
{
    for (XFHostNode *node in nodes) {
        switch (node.kind) {
            case XFHostNodeKindText: {
                NSString *text = node.text ?: @"";
                if (text.length) {
                    [out appendAttributedString:[[NSAttributedString alloc]
                        initWithString:text attributes:@{ NSFontAttributeName: font }]];
                }
                break;
            }
            case XFHostNodeKindBreak:
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
                break;
            case XFHostNodeKindRule:
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n———\n"]];
                break;
            case XFHostNodeKindSVG:
                [svg addObject:node];
                break;
            case XFHostNodeKindControl: {
                // an xf:output inside prose reads as its value
                NSString *value = node.control.stringValue ?: @"";
                if (value.length) {
                    [out appendAttributedString:[[NSAttributedString alloc]
                        initWithString:value attributes:@{ NSFontAttributeName: font }]];
                }
                break;
            }
            default: {
                UIFont *inner = [self fontForTag:(node.tag ?: @"")
                                         heading:node.headingLevel base:font];
                BOOL block = node.kind == XFHostNodeKindBlock;
                if (block && out.length) {
                    [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
                }
                [self appendNodes:node.children font:inner svg:svg into:out];
                break;
            }
        }
    }
}

- (void)bindRow:(XFFormRow *)row
{
    [super bindRow:row];
    self.textLabel.text = nil;

    // whatever the last row left behind
    for (UIView *view in [self.stack.arrangedSubviews copy]) {
        if (view != self.body) {
            [self.stack removeArrangedSubview:view];
            [view removeFromSuperview];
        }
    }

    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
    NSMutableArray<XFHostNode *> *svgNodes = [NSMutableArray array];
    UIFont *base = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [[self class] appendNodes:row.hostNodes font:base svg:svgNodes into:text];

    NSString *trimmed = [text.string stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.body.attributedText = text;
    self.body.hidden = trimmed.length == 0;

    for (XFHostNode *node in svgNodes) {
        XFSVGDocument *document = [XFSVGDocument documentWithHostNode:node
                                                            processor:self.formController.processor
                                                          contextNode:row.contextNode];
        XFSVGContentView *view = [[XFSVGContentView alloc] initWithFrame:CGRectZero];
        view.svgDocument = document;
        view.backgroundColor = [UIColor clearColor];
        view.translatesAutoresizingMaskIntoConstraints = NO;
        // the document's own proportions, so the box the renderer is given
        // matches the drawing and nothing is letterboxed or cropped
        CGSize size = document.size;
        CGFloat ratio = size.width > 0 ? size.height / size.width : 1;
        [view.heightAnchor constraintEqualToAnchor:view.widthAnchor
                                        multiplier:MAX(ratio, 0.01)].active = YES;
        [self.stack addArrangedSubview:view];
    }
}

@end

#pragma mark - The controller

/// AppKit ran NSOpenPanel modally and had the URL on the next line; UIKit
/// presents a picker and answers through a delegate. The control it is
/// choosing for rides on the picker rather than on the controller, so
/// there is no state to go stale if a second picker opens or the first is
/// dismissed without an answer.
@interface XFDocumentPicker : UIDocumentPickerViewController
@property (nonatomic, strong, nullable) XFUploadControl *upload;
@end

@implementation XFDocumentPicker
@end

@interface XFFormViewController ()
@property (nonatomic, strong) NSArray<XFFormSection *> *sections;
/// The control whose field currently holds the keyboard, so the accessory
/// bar knows where "previous" and "next" go from.
@property (nonatomic, weak, nullable) XFControl *editingControl;
@property (nonatomic, strong, nullable) UIToolbar *keyboardAccessory;
@property (nonatomic, strong, nullable) UIToolbar *richKeyboardAccessory;
@property (nonatomic, weak, nullable) UITextView *editingRichTextView;
/// One pair per bar: a UIBarButtonItem belongs to a single toolbar, so
/// the plain and the rich bar cannot share them.
@property (nonatomic, strong) NSMutableArray<UIBarButtonItem *> *previousItems;
@property (nonatomic, strong) NSMutableArray<UIBarButtonItem *> *nextItems;
/// Dialogs currently on screen, by identifier, and the dialog each key
/// stands for (a dialog is not itself a good dictionary key).
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIViewController *> *presentedDialogs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, XFDialog *> *dialogsByKey;
@end

@implementation XFFormViewController

- (instancetype)initWithProcessor:(XFProcessor *)processor
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _processor = processor;
        _sections = @[];
        _previousItems = [NSMutableArray array];
        _nextItems = [NSMutableArray array];
        _presentedDialogs = [NSMutableDictionary dictionary];
        _dialogsByKey = [NSMutableDictionary dictionary];
    }
    return self;
}

/// The host hooks the engine calls back through. xf:message becomes an
/// alert, which is the iOS answer and XLForm's too; xf:setfocus makes the
/// control's cell first responder, the way the AppKit view makes its
/// widget one; xf:help shows its text the same way a message does.
- (void)installHostHandlers
{
    if (self.rootGroup != nil) {
        // This controller is showing one container of a form another
        // controller already drives (an xf:dialog it presented). Taking
        // the hooks would leave the form without them once this one is
        // dismissed, and route the form's messages to a dead sheet.
        return;
    }
    __weak XFFormViewController *weakSelf = self;
    self.processor.messageHandler = ^(NSString *text, NSString *level) {
        [weakSelf presentMessage:text level:level];
    };
    self.processor.richMessageHandler = ^(NSString *markup, NSString *text, NSString *level) {
        [weakSelf presentRichMessage:markup text:text level:level];
    };
    self.processor.helpRequestHandler = ^(XFControl *control) {
        if (control.helpMarkup.length) {
            [weakSelf presentRichMessage:control.helpMarkup
                                    text:control.help ?: @"" level:@"modal"];
        } else {
            [weakSelf presentMessage:control.help ?: @"" level:@"modal"];
        }
    };
    self.processor.focusRequestHandler = ^(XFControl *control) {
        [weakSelf focusControl:control];
    };
    self.processor.dialogRequestHandler = ^(XFDialog *dialog, BOOL show) {
        if (show) {
            [weakSelf presentDialog:dialog];
        } else {
            [weakSelf dismissDialog:dialog];
        }
    };
}

/// An ephemeral message is not worth an alert the reader has to dismiss;
/// XForms' own levels say which is which.
- (void)presentMessage:(NSString *)text level:(NSString *)level
{
    if (text.length == 0 || self.view.window == nil) {
        return;
    }
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:nil message:text
                                    preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                             style:UIAlertActionStyleDefault
                                           handler:nil]];
    [[self presentationHost] presentViewController:alert animated:YES completion:nil];
    (void)level;
}

/// A message whose content carries host markup. UIAlertController has no
/// public way to show an attributed message, and faking one by reaching
/// into its label is private API, so a rich message gets the standard
/// iOS alternative instead: a sheet with a Done button, holding the same
/// read-only text view the hint cells use. A plain message still gets the
/// ordinary alert, so nothing changes for the forms that have one.
- (void)presentRichMessage:(NSString *)markup text:(NSString *)text level:(NSString *)level
{
    if (self.view.window == nil) {
        return;
    }
    NSAttributedString *rich =
        [XFRichText attributedStringFromMarkup:markup
                                     plainText:text
                                      baseFont:[UIFont preferredFontForTextStyle:UIFontTextStyleBody]
                                     textColor:[UIColor labelColor]];
    if (rich.length == 0) {
        [self presentMessage:text level:level];
        return;
    }
    XFRichMessageViewController *sheet =
        [[XFRichMessageViewController alloc] initWithAttributedText:rich];
    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:sheet];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [[self presentationHost] presentViewController:nav animated:YES completion:nil];
}

/// The controller anything modal should come from: UIKit refuses to
/// present from a controller that is already presenting, and a form that
/// has an xf:dialog sheet open is exactly that.
- (UIViewController *)presentationHost
{
    UIViewController *host = self;
    while (host.presentedViewController
           && !host.presentedViewController.isBeingDismissed) {
        host = host.presentedViewController;
    }
    return host;
}

#pragma mark - accesskey (hardware keyboards)

/// `accesskey` as ⌘-key commands.
///
/// The AppKit backend gives a trigger's accesskey to the button as its
/// key equivalent; a phone has no keyboard to press it on, but an iPad
/// with one — or a Mac running the app — does, and UIKeyCommand is the
/// only way UIKit offers. Command is the modifier because UIKit will not
/// register an unmodified letter while a text field can be editing.
///
/// Activating a trigger and focusing everything else is what browsers do
/// with accesskey and what XForms 1.1 asks for (the control is given
/// focus; a trigger's focus action is its activation).
- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (NSArray<UIKeyCommand *> *)keyCommands
{
    NSMutableArray<UIKeyCommand *> *commands = [NSMutableArray array];
    NSMutableSet<NSString *> *claimed = [NSMutableSet set];
    for (XFFormSection *section in self.sections) {
        for (XFFormRow *row in section.rows) {
            NSString *key = [self accessKeyOfRow:row];
            if (key == nil || [claimed containsObject:key]) {
                continue;   // first row to claim a key keeps it
            }
            [claimed addObject:key];
            UIKeyCommand *command =
                [UIKeyCommand keyCommandWithInput:key
                                    modifierFlags:UIKeyModifierCommand
                                           action:@selector(performAccessKey:)];
            command.discoverabilityTitle =
                row.control.label.length ? row.control.label : key;
            [commands addObject:command];
        }
    }
    return commands;
}

/// The one character of a row's accesskey, or nil where it has none. A
/// note row is skipped: it stands for the same control as the row above
/// and would claim the key for something that cannot take focus.
- (NSString *)accessKeyOfRow:(XFFormRow *)row
{
    if (row.kind == XFFormRowKindNote || row.control == nil) {
        return nil;
    }
    NSString *key = row.control.accesskey;
    return key.length ? [key substringToIndex:1] : nil;
}

- (void)performAccessKey:(UIKeyCommand *)command
{
    NSString *key = command.input;
    for (XFFormSection *section in self.sections) {
        for (XFFormRow *row in section.rows) {
            if (![[self accessKeyOfRow:row] isEqualToString:key]) {
                continue;
            }
            if (row.kind == XFFormRowKindButton) {
                [self endEditingInProgressBefore:row.control];
                [self.processor activateControl:(XFTriggerControl *)row.control];
                [self reloadFromProcessor];
            } else {
                // through the engine, so the focus events fire and the
                // host hook scrolls the row into view
                [self.processor focusControl:row.control fromUI:NO];
            }
            return;
        }
    }
}

#pragma mark - xf:dialog

/// xf:dialog as a presented sheet.
///
/// A dialog is a group that happens to be hidden until `xf:show`, so it
/// is shown by the same form controller pointed at that group — which is
/// what `rootGroup` is for. A sheet rather than an alert: a dialog holds
/// controls, and an alert cannot.
///
/// Dismissing the sheet by hand has to tell the engine, or the dialog
/// stays "open" and a second xf:show would be a no-op.
- (void)presentDialog:(XFDialog *)dialog
{
    if (self.presentedDialogs[[self keyForDialog:dialog]] || self.view.window == nil) {
        return;
    }
    XFFormViewController *content =
        [[XFFormViewController alloc] initWithProcessor:self.processor];
    content.rootGroup = dialog;
    content.title = dialog.label;
    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:content];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    content.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(dismissFrontDialog)];
    self.presentedDialogs[[self keyForDialog:dialog]] = nav;
    [[self presentationHost] presentViewController:nav animated:YES completion:nil];
}

- (void)dismissDialog:(XFDialog *)dialog
{
    NSString *key = [self keyForDialog:dialog];
    UIViewController *presented = self.presentedDialogs[key];
    if (presented == nil) {
        return;
    }
    [self.presentedDialogs removeObjectForKey:key];
    [presented dismissViewControllerAnimated:YES completion:nil];
}

/// Done in the sheet: hide it through the engine (xforms-dialog-close),
/// which calls back into -dismissDialog: and takes the sheet down.
- (void)dismissFrontDialog
{
    for (NSString *key in [self.presentedDialogs allKeys]) {
        XFDialog *dialog = self.dialogsByKey[key];
        if (dialog.shown) {
            [dialog hide];
            return;
        }
    }
}

- (NSString *)keyForDialog:(XFDialog *)dialog
{
    NSString *key = dialog.identifier.length
        ? dialog.identifier : [NSString stringWithFormat:@"%p", dialog];
    self.dialogsByKey[key] = dialog;
    return key;
}

#pragma mark - Keyboard navigation

- (XFFormRow *)rowAtIndexPath:(NSIndexPath *)path
{
    if (path.section < 0 || (NSUInteger)path.section >= self.sections.count) {
        return nil;
    }
    NSArray<XFFormRow *> *rows = self.sections[(NSUInteger)path.section].rows;
    if (path.row < 0 || (NSUInteger)path.row >= rows.count) {
        return nil;
    }
    return rows[(NSUInteger)path.row];
}

/// The bar above the keyboard: previous field, next field, Done.
///
/// This is the iOS replacement for the key-view loop, not an extra: a
/// phone keyboard covers half the form and has no Tab, so without it the
/// only way from one field to the next is to dismiss the keyboard, scroll
/// and tap. One bar is shared by every field, since only one of them can
/// be first responder at a time.
- (UIToolbar *)keyboardAccessoryView
{
    return [self keyboardAccessoryViewForRichText:NO];
}

/// The rich bar is the plain one plus bold / italic / underline, which is
/// where iOS puts formatting for a text view — there is no menu bar to
/// hang it on, and a rich editor with no way to apply a style is only
/// half an editor.
- (UIToolbar *)keyboardAccessoryViewForRichText:(BOOL)rich
{
    if (rich) {
        if (self.richKeyboardAccessory == nil) {
            self.richKeyboardAccessory = [self buildKeyboardAccessoryRich:YES];
        }
        return self.richKeyboardAccessory;
    }
    if (self.keyboardAccessory == nil) {
        self.keyboardAccessory = [self buildKeyboardAccessoryRich:NO];
    }
    return self.keyboardAccessory;
}

- (void)richEditorDidBeginEditing:(UITextView *)textView
{
    self.editingRichTextView = textView;
}

- (UIBarButtonItem *)formatItem:(NSString *)symbol action:(SEL)action label:(NSString *)label
{
    UIBarButtonItem *item =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:symbol]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:action];
    item.accessibilityLabel = label;
    return item;
}

- (void)toggleRichBold      { [self toggleRichMarker:XFRichBoldAttributeName]; }
- (void)toggleRichItalic    { [self toggleRichMarker:XFRichItalicAttributeName]; }
- (void)toggleRichUnderline { [self toggleRichMarker:XFRichUnderlineAttributeName]; }

/// Flip one of the converter's markers over the selection, then let the
/// presentation be recomputed from the markers — the same two-step the
/// AppKit editor uses, so what the instance gets is identical.
- (void)toggleRichMarker:(NSString *)marker
{
    UITextView *view = self.editingRichTextView;
    NSRange range = view.selectedRange;
    if (view == nil || range.length == 0) {
        return;   // nothing selected: there is nothing to restyle yet
    }
    NSMutableAttributedString *text = [view.attributedText mutableCopy];
    __block BOOL alreadySet = YES;
    [text enumerateAttribute:marker inRange:range options:0
                  usingBlock:^(id value, NSRange sub, BOOL *stop) {
        if (![value boolValue]) {
            alreadySet = NO;
            *stop = YES;
        }
    }];
    if (alreadySet) {
        [text removeAttribute:marker range:range];
    } else {
        [text addAttribute:marker value:@YES range:range];
    }
    view.attributedText =
        [XFRichText decoratedString:text
                           baseFont:[UIFont preferredFontForTextStyle:UIFontTextStyleBody]];
    view.selectedRange = range;   // setting the text clears it
    // the delegate does not fire for a programmatic change
    if ([view.delegate respondsToSelector:@selector(textViewDidChange:)]) {
        [view.delegate textViewDidChange:view];
    }
}

- (UIToolbar *)buildKeyboardAccessoryRich:(BOOL)rich
{
    UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    [bar sizeToFit];
    UIBarButtonItem *previous =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.up"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(focusPreviousField)];
    previous.accessibilityLabel = NSLocalizedString(@"Previous field", nil);
    UIBarButtonItem *next =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(focusNextField)];
    next.accessibilityLabel = NSLocalizedString(@"Next field", nil);
    [self.previousItems addObject:previous];
    [self.nextItems addObject:next];
    UIBarButtonItem *gap =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                      target:nil action:nil];
    UIBarButtonItem *done =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(dismissKeyboard)];
    NSMutableArray<UIBarButtonItem *> *items = [@[ previous, next ] mutableCopy];
    if (rich) {
        [items addObject:gap];
        [items addObject:[self formatItem:@"bold" action:@selector(toggleRichBold)
                                    label:NSLocalizedString(@"Bold", nil)]];
        [items addObject:[self formatItem:@"italic" action:@selector(toggleRichItalic)
                                    label:NSLocalizedString(@"Italic", nil)]];
        [items addObject:[self formatItem:@"underline" action:@selector(toggleRichUnderline)
                                    label:NSLocalizedString(@"Underline", nil)]];
    }
    [items addObject:gap];
    [items addObject:done];
    bar.items = items;
    return bar;
}

/// Every row a keyboard can attach to, in the order the form shows them.
/// A readonly or non-relevant field is skipped, the way the key-view loop
/// skips a disabled widget.
- (NSArray<NSIndexPath *> *)editableFieldPaths
{
    NSMutableArray<NSIndexPath *> *paths = [NSMutableArray array];
    for (NSUInteger section = 0; section < self.sections.count; section++) {
        NSArray<XFFormRow *> *rows = self.sections[section].rows;
        for (NSUInteger row = 0; row < rows.count; row++) {
            XFFormRow *candidate = rows[row];
            if (candidate.kind != XFFormRowKindTextField
                && candidate.kind != XFFormRowKindTextView) {
                continue;
            }
            if (candidate.control.readonly) {
                continue;
            }
            [paths addObject:[NSIndexPath indexPathForRow:(NSInteger)row
                                                inSection:(NSInteger)section]];
        }
    }
    return paths;
}

- (NSInteger)indexOfEditingFieldIn:(NSArray<NSIndexPath *> *)paths
{
    if (self.editingControl == nil) {
        return NSNotFound;
    }
    for (NSUInteger i = 0; i < paths.count; i++) {
        XFFormRow *row = [self rowAtIndexPath:paths[i]];
        if (row.control == self.editingControl) {
            return (NSInteger)i;
        }
    }
    return NSNotFound;
}

- (void)fieldDidBeginEditing:(XFControl *)control
{
    self.editingControl = control;
    if (control) {
        // fromUI: the widget already has the keyboard, so this only moves
        // the engine's focus (DOMFocusOut on the old, DOMFocusIn here) and
        // does not ask the host to focus anything
        [self.processor focusControl:control fromUI:YES];
    }
    [self updateKeyboardAccessoryState];
}

- (void)fieldDidEndEditing:(XFControl *)control
{
    if (self.editingControl == control) {
        self.editingControl = nil;
    }
}

- (void)updateKeyboardAccessoryState
{
    NSArray<NSIndexPath *> *paths = [self editableFieldPaths];
    NSInteger current = [self indexOfEditingFieldIn:paths];
    BOOL known = current != NSNotFound;
    for (UIBarButtonItem *item in self.previousItems) {
        item.enabled = known && current > 0;
    }
    for (UIBarButtonItem *item in self.nextItems) {
        item.enabled = known && current + 1 < (NSInteger)paths.count;
    }
}

- (void)focusPreviousField { [self moveKeyboardFocusBy:-1]; }
- (void)focusNextField     { [self moveKeyboardFocusBy:+1]; }

- (void)moveKeyboardFocusBy:(NSInteger)delta
{
    NSArray<NSIndexPath *> *paths = [self editableFieldPaths];
    NSInteger current = [self indexOfEditingFieldIn:paths];
    if (current == NSNotFound) {
        return;
    }
    NSInteger target = current + delta;
    if (target < 0 || target >= (NSInteger)paths.count) {
        return;
    }
    [self makeFirstResponderAtIndexPath:paths[(NSUInteger)target]];
}

- (void)dismissKeyboard
{
    [self.view endEditing:YES];
    self.editingControl = nil;
}

/// Scrolls the row into view and gives its field the keyboard. Answers NO
/// when the row has nothing that takes one.
///
/// The scroll is unanimated and forced to lay out before the cell is
/// asked for: a row off screen has no cell yet, and an animated scroll
/// would not have created one by the time this returns.
- (BOOL)makeFirstResponderAtIndexPath:(NSIndexPath *)path
{
    [self.tableView scrollToRowAtIndexPath:path
                          atScrollPosition:UITableViewScrollPositionMiddle
                                  animated:NO];
    [self.tableView layoutIfNeeded];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:path];
    if (cell == nil) {
        return NO;
    }
    for (UIView *view in cell.contentView.subviews) {
        if ([view isKindOfClass:[UITextField class]]
            || [view isKindOfClass:[UITextView class]]) {
            return [view becomeFirstResponder];
        }
    }
    return [cell becomeFirstResponder];
}

/// xf:setfocus. The row is found through the rows, scrolled to, and its
/// cell made first responder -- the text field inside it where there is
/// one, since that is what a keyboard attaches to.
- (void)focusControl:(XFControl *)control
{
    for (NSUInteger section = 0; section < self.sections.count; section++) {
        NSArray<XFFormRow *> *rows = self.sections[section].rows;
        for (NSUInteger row = 0; row < rows.count; row++) {
            if (rows[row].control != control || rows[row].kind == XFFormRowKindNote) {
                continue;
            }
            [self makeFirstResponderAtIndexPath:
                [NSIndexPath indexPathForRow:(NSInteger)row inSection:(NSInteger)section]];
            return;
        }
    }
}

/// The focus the form asked for before there was anything to focus.
///
/// `xf:setfocus` in an `xforms-ready` handler runs while the model is
/// being constructed — before this controller exists, let alone its view
/// — so the focusRequestHandler that would have moved the keyboard was
/// not installed yet and the request went nowhere. The engine did record
/// it (`focusedControl`), so the view adopts it once there is a window to
/// focus in. That is what makes first-field work.
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    XFControl *wanted = self.processor.focusedControl;
    if (wanted != nil && self.editingControl == nil) {
        [self focusControl:wanted];
    }
}

- (void)loadView
{
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero
                                              style:UITableViewStyleInsetGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 44;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    for (NSString *identifier in @[ @"text", @"switch", @"selector", @"button",
                                    @"value", @"markup", @"check", @"segmented",
                                    @"date", @"slider", @"upload",
                                    @"image", @"table", @"note", @"repeatadd",
                                    @"textview", @"flow" ]) {
        Class cellClass = [[self class] cellClassForIdentifier:identifier];
        [_tableView registerClass:cellClass forCellReuseIdentifier:identifier];
    }
    self.view = _tableView;
    [self installHostHandlers];
    [self rebuildSections];
}

+ (Class)cellClassForIdentifier:(NSString *)identifier
{
    if ([identifier isEqualToString:@"text"]) { return [XFTextFieldFormCell class]; }
    if ([identifier isEqualToString:@"textview"]) { return [XFTextViewFormCell class]; }
    if ([identifier isEqualToString:@"flow"]) { return [XFInlineFlowFormCell class]; }
    if ([identifier isEqualToString:@"switch"]) { return [XFSwitchFormCell class]; }
    if ([identifier isEqualToString:@"selector"]) { return [XFSelectorFormCell class]; }
    if ([identifier isEqualToString:@"button"]) { return [XFButtonFormCell class]; }
    if ([identifier isEqualToString:@"value"]) { return [XFValueFormCell class]; }
    if ([identifier isEqualToString:@"check"]) { return [XFCheckFormCell class]; }
    if ([identifier isEqualToString:@"segmented"]) { return [XFSegmentedFormCell class]; }
    if ([identifier isEqualToString:@"date"]) { return [XFDateFormCell class]; }
    if ([identifier isEqualToString:@"slider"]) { return [XFSliderFormCell class]; }
    if ([identifier isEqualToString:@"upload"]) { return [XFUploadFormCell class]; }
    if ([identifier isEqualToString:@"image"]) { return [XFImageFormCell class]; }
    if ([identifier isEqualToString:@"table"]) { return [XFTableFormCell class]; }
    if ([identifier isEqualToString:@"note"]) { return [XFNoteFormCell class]; }
    if ([identifier isEqualToString:@"repeatadd"]) { return [XFRepeatAddFormCell class]; }
    return [XFMarkupFormCell class];
}

/// Five kinds are implemented; the rest fall back to something that shows
/// the label and the value rather than to nothing.
+ (NSString *)identifierForRow:(XFFormRow *)row
{
    switch (row.kind) {
        case XFFormRowKindTextField:
            return @"text";
        case XFFormRowKindTextView:
            return @"textview";
        case XFFormRowKindSwitch:
            return @"switch";
        case XFFormRowKindSegmented:
            return @"segmented";
        case XFFormRowKindCheck:
            return @"check";
        case XFFormRowKindDate:
            return @"date";
        case XFFormRowKindSlider:
            return @"slider";
        case XFFormRowKindUpload:
            return @"upload";
        case XFFormRowKindSelector:
            return @"selector";
        case XFFormRowKindButton:
            return @"button";
        case XFFormRowKindValue:
            return @"value";
        case XFFormRowKindImage:
            return @"image";
        case XFFormRowKindTable:
            return @"table";
        case XFFormRowKindNote:
            return @"note";
        case XFFormRowKindMarkup:
            return @"markup";
        case XFFormRowKindRepeatAdd:
            return @"repeatadd";
        case XFFormRowKindInlineFlow:
            return @"flow";
    }
    return @"value";
}

/// The sections the processor's controls describe right now. Pure: the
/// caller decides when to adopt them, which matters for a batch update —
/// the table must not see new counts while it still believes the old
/// ones.
- (NSArray<XFFormSection *> *)sectionsFromProcessor
{
    return self.rootGroup
        ? [XFFormRows sectionsForHostNodes:self.rootGroup.hostNodes]
        : [XFFormRows sectionsForProcessor:self.processor];
}

- (void)rebuildSections
{
    self.sections = [self sectionsFromProcessor];
}

- (void)reloadFromProcessor
{
    NSArray<XFFormSection *> *before = self.sections;
    NSArray<XFFormSection *> *after = [self sectionsFromProcessor];
    // -reloadData rebuilds every visible cell, and a rebuilt cell is not
    // the one holding the keyboard: the field being typed into would lose
    // first responder. With incremental="true" that is once per
    // keystroke, which makes such a field unusable.
    //
    // So while a field is being edited and the form still has the same
    // rows in the same order, the visible cells are re-bound in place
    // instead — every other row still follows the recalculate, and the
    // editor keeps its keyboard, its caret and its selection. A form
    // whose structure changed (relevance, an insert, a delete) still
    // needs the full reload, and gets it.
    if (self.editingControl && [self applyRowUpdatesFrom:before to:after]) {
        return;
    }
    self.sections = after;
    [self.tableView reloadData];
}

/// What identifies a row for diffing: what it shows, for which control.
/// Its label and value are free to change — that is what re-binding
/// applies — but a row with a different key is a different row.
+ (NSArray<NSString *> *)rowKeysOf:(XFFormSection *)section
{
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (XFFormRow *row in section.rows) {
        [keys addObject:[NSString stringWithFormat:@"%ld/%p/%lu",
                         (long)row.kind, (void *)row.control,
                         (unsigned long)row.itemIndex]];
    }
    return keys;
}

/// Applies the change as row insertions and deletions instead of a
/// reload, and answers NO when it cannot.
///
/// A reload rebuilds every visible cell, including the one holding the
/// keyboard. The previous version of this only avoided that when the rows
/// were UNCHANGED — which misses the case that actually happens while
/// typing: an `xf:alert` note row appearing or disappearing as the value
/// goes in and out of validity. Typing the "@" of an email address makes
/// it valid, drops the alert row, and the reload that followed took the
/// keyboard with it, so the field stopped accepting input mid-word.
///
/// Rows are only ever added or removed here, never reordered, so a
/// two-cursor walk is enough — and the cells UIKit does not touch, the
/// editor among them, keep their state.
- (BOOL)applyRowUpdatesFrom:(NSArray<XFFormSection *> *)before
                         to:(NSArray<XFFormSection *> *)after
{
    if (before.count != after.count) {
        return NO;   // a section came or went: start again
    }
    NSArray<NSIndexPath *> *deletes = nil;
    NSArray<NSIndexPath *> *inserts = nil;
    [self rowUpdatesFrom:before to:after deletes:&deletes inserts:&inserts];
    if (deletes.count == 0 && inserts.count == 0) {
        self.sections = after;
        [self refreshVisibleCellsKeepingEditor];
        return YES;
    }
    // a wholesale change is not worth animating row by row
    if (deletes.count + inserts.count > 8) {
        return NO;
    }
    __weak XFFormViewController *weakSelf = self;
    [self.tableView performBatchUpdates:^{
        // adopted INSIDE the block: the table reads the old counts to
        // apply the diff and the new ones to draw the result, and it is
        // this call that separates the two
        weakSelf.sections = after;
        if (deletes.count) {
            [weakSelf.tableView deleteRowsAtIndexPaths:deletes
                                      withRowAnimation:UITableViewRowAnimationFade];
        }
        if (inserts.count) {
            [weakSelf.tableView insertRowsAtIndexPaths:inserts
                                      withRowAnimation:UITableViewRowAnimationFade];
        }
    } completion:^(BOOL finished) {
        (void)finished;
        [weakSelf refreshVisibleCellsKeepingEditor];
    }];
    return YES;
}

/// The row diff itself: which index paths went, which arrived. Rows are
/// only added or removed, never reordered, so one walk of the two key
/// lists settles it.
- (void)rowUpdatesFrom:(NSArray<XFFormSection *> *)before
                    to:(NSArray<XFFormSection *> *)after
               deletes:(NSArray<NSIndexPath *> **)outDeletes
               inserts:(NSArray<NSIndexPath *> **)outInserts
{
    NSMutableArray<NSIndexPath *> *deletes = [NSMutableArray array];
    NSMutableArray<NSIndexPath *> *inserts = [NSMutableArray array];
    if (before.count == after.count) {
        for (NSUInteger s = 0; s < before.count; s++) {
            NSArray<NSString *> *old = [[self class] rowKeysOf:before[s]];
            NSArray<NSString *> *new = [[self class] rowKeysOf:after[s]];
            NSUInteger i = 0, j = 0;
            while (i < old.count || j < new.count) {
                if (i < old.count && j < new.count && [old[i] isEqualToString:new[j]]) {
                    i++; j++;
                    continue;
                }
                if (i < old.count) {
                    NSUInteger at = [new indexOfObject:old[i]
                                               inRange:NSMakeRange(j, new.count - j)];
                    if (at != NSNotFound) {
                        while (j < at) {
                            [inserts addObject:[NSIndexPath indexPathForRow:(NSInteger)j
                                                                 inSection:(NSInteger)s]];
                            j++;
                        }
                        continue;
                    }
                    [deletes addObject:[NSIndexPath indexPathForRow:(NSInteger)i
                                                         inSection:(NSInteger)s]];
                    i++;
                    continue;
                }
                [inserts addObject:[NSIndexPath indexPathForRow:(NSInteger)j
                                                     inSection:(NSInteger)s]];
                j++;
            }
        }
    }
    if (outDeletes) { *outDeletes = deletes; }
    if (outInserts) { *outInserts = inserts; }
}

- (void)refreshVisibleCellsKeepingEditor
{
    for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows) {
        XFFormRow *row = [self rowAtIndexPath:path];
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:path];
        if (row == nil || ![cell isKindOfClass:[XFFormCell class]]) {
            continue;
        }
        if (row.control != nil && row.control == self.editingControl) {
            // the row object is new; the field's text, caret and keyboard
            // are the user's and are left exactly as they are
            ((XFFormCell *)cell).row = row;
            continue;
        }
        [(XFFormCell *)cell bindRow:row];
    }
}

/// A value the user typed or toggled. Recalculation can change relevance
/// anywhere, so the rows are rebuilt afterwards rather than the one cell
/// refreshed.
/// Ends an edit that is still in progress, so whatever runs next sees
/// what was typed.
///
/// Tapping a row, a switch or a segment does not resign the keyboard, so
/// the field being edited keeps it: the action runs against the previous
/// value, and the pending edit lands afterwards — or, if the reload
/// replaced the row, against whatever the reused cell now holds. The
/// AppKit twin of this is `-[XFFormView endEditingInProgress]`, and
/// `Samples/dialog.xhtml` is where it shows: type a note, tap "Done",
/// and the dialog closes without the note.
///
/// `control` is what is about to act; an edit in the same control is
/// left alone, since ending it would only take the keyboard away from
/// the field the user is in.
- (void)endEditingInProgressBefore:(XFControl *)control
{
    if (self.editingControl != nil && self.editingControl != control) {
        [self.view endEditing:YES];
    }
}

- (void)commitControl:(XFControl *)control value:(NSString *)value
{
    if (control == nil) {
        return;
    }
    [self endEditingInProgressBefore:control];
    NSError *error = nil;
    [self.processor setValue:value ofControl:control error:&error];
    [self reloadFromProcessor];
}

- (void)commitDate:(NSDate *)date ofInput:(XFInputControl *)input
{
    [self endEditingInProgressBefore:input];
    if ([input commitDateValue:date error:NULL]) {
        [self.processor controlDidChangeValue:input];
    }
    [self reloadFromProcessor];
}

- (void)commitNumber:(double)value ofRange:(XFRangeControl *)range
{
    [self endEditingInProgressBefore:range];
    if ([range commitNumericValue:value error:NULL]) {
        [self.processor controlDidChangeValue:range];
    }
    [self reloadFromProcessor];
}

- (void)selectValue:(NSString *)value ofSelect:(XFSelectControl *)select
{
    [self endEditingInProgressBefore:select];
    if ([select selectValue:value]) {
        [self.processor controlDidChangeValue:select];
    }
    [self reloadFromProcessor];
}

- (void)toggleValue:(NSString *)value ofSelect:(XFSelectControl *)select
{
    [self endEditingInProgressBefore:select];
    if ([select toggleValue:value]) {
        [self.processor controlDidChangeValue:select];
    }
    [self reloadFromProcessor];
}

/// The list a minimal select opens. Pushed when the host gave us a
/// navigation controller, presented in its own when it did not -- a form
/// embedded in a plain view controller still has to be usable.
- (void)presentOptionsForSelect:(XFSelectControl *)select
{
    XFSelectOptionsViewController *options =
        [[XFSelectOptionsViewController alloc] initWithSelect:select form:self];
    if (self.navigationController != nil) {
        [self.navigationController pushViewController:options animated:YES];
        return;
    }
    UINavigationController *wrapper =
        [[UINavigationController alloc] initWithRootViewController:options];
    [[self presentationHost] presentViewController:wrapper animated:YES completion:nil];
}

/// @mediatype becomes the picker's content types; without one, anything
/// goes. UTTypes rather than the AppKit path's file extensions -- the
/// mapping from a MIME type is what UniformTypeIdentifiers is for.
- (void)presentDocumentPickerForUpload:(XFUploadControl *)upload
{
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    for (NSString *mediaType in [upload acceptedMediaTypes]) {
        if ([mediaType hasSuffix:@"/*"]) {
            NSString *stem = [mediaType substringToIndex:mediaType.length - 2];
            UTType *wildcard = [@{ @"image": UTTypeImage, @"audio": UTTypeAudio,
                                   @"video": UTTypeMovie, @"text": UTTypeText }[stem] copy];
            if (wildcard != nil) {
                [types addObject:wildcard];
            }
            continue;
        }
        UTType *type = [UTType typeWithMIMEType:mediaType];
        if (type != nil) {
            [types addObject:type];
        }
    }
    if (types.count == 0) {
        [types addObject:UTTypeItem];
    }
    XFDocumentPicker *picker =
        [[XFDocumentPicker alloc] initForOpeningContentTypes:types];
    picker.upload = upload;
    picker.allowsMultipleSelection = NO;
    picker.delegate = self;
    [[self presentationHost] presentViewController:picker animated:YES completion:nil];
}

- (BOOL)commitPickedFileAtURL:(NSURL *)url forUpload:(XFUploadControl *)upload
{
    if (url == nil || upload == nil) {
        return NO;
    }
    // a picked document is outside the sandbox until asked for
    BOOL scoped = [url startAccessingSecurityScopedResource];
    BOOL ok = [upload commitFileAtURL:url error:NULL];
    if (scoped) {
        [url stopAccessingSecurityScopedResource];
    }
    if (ok) {
        [self.processor controlDidChangeValue:upload];
    }
    [self reloadFromProcessor];
    return ok;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    if (![controller isKindOfClass:[XFDocumentPicker class]]) {
        return;
    }
    [self commitPickedFileAtURL:urls.firstObject
                      forUpload:[(XFDocumentPicker *)controller upload]];
}

#pragma mark UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.sections[(NSUInteger)section].rows.count;
}

- (nullable NSString *)tableView:(UITableView *)tableView
         titleForHeaderInSection:(NSInteger)section
{
    return self.sections[(NSUInteger)section].title;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    XFFormRow *row = [self rowAtIndexPath:indexPath];
    NSString *identifier = [[self class] identifierForRow:row];
    XFFormCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier
                                                       forIndexPath:indexPath];
    cell.formController = self;
    [cell bindRow:row];
    // a note reads as part of the control above it, not as its own row
    cell.separatorInset = row.kind == XFFormRowKindNote
        ? UIEdgeInsetsMake(0, CGRectGetWidth(tableView.bounds), 0, 0)
        : UIEdgeInsetsZero;
    return cell;
}

#pragma mark UITableViewDelegate

#pragma mark - Repeat add / remove

/// Only a row that stands for one item of a repeat can be swiped away.
/// Everything else — a plain control, a note, the add row — is not
/// editable, so no other row offers a delete it could not perform.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    (void)tableView;
    XFFormRow *row = [self rowAtIndexPath:indexPath];
    return row.repeat != nil && row.repeatPosition > 0;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
           editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [self tableView:tableView canEditRowAtIndexPath:indexPath]
        ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)style
     forRowAtIndexPath:(NSIndexPath *)indexPath
{
    (void)tableView;
    if (style != UITableViewCellEditingStyleDelete) {
        return;
    }
    XFFormRow *row = [self rowAtIndexPath:indexPath];
    [self removeItem:row.repeatPosition ofRepeat:row.repeat];
}

/// Both gestures go through the engine, which mutates the instance,
/// dispatches xforms-insert / xforms-delete and runs one recalculate —
/// so a form that listens for those, or whose binds depend on the
/// nodeset, behaves exactly as it would for its own xf:insert.
///
/// The whole table reloads rather than animating the one row: an insert
/// or a delete can change any other row through a calculate, and the
/// rows are rebuilt from the controls anyway.
- (void)addItemToRepeat:(XFRepeat *)repeat
{
    [self endEditingInProgressBefore:nil];
    if ([repeat insertItemAfterPosition:repeat.items.count]) {
        [self reloadFromProcessor];
    }
}

- (void)removeItem:(NSUInteger)position ofRepeat:(XFRepeat *)repeat
{
    [self endEditingInProgressBefore:nil];
    if ([repeat deleteItemAtPosition:position]) {
        [self reloadFromProcessor];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    XFFormRow *row = [self rowAtIndexPath:indexPath];
    [self endEditingInProgressBefore:row.control];
    if (row.kind == XFFormRowKindRepeatAdd) {
        [self addItemToRepeat:row.repeat];
        return;
    }
    if (row.control == nil) {
        return;
    }
    if (row.kind == XFFormRowKindButton) {
        [self.processor activateControl:(XFTriggerControl *)row.control];
        [self reloadFromProcessor];
        return;
    }
    if (row.kind == XFFormRowKindCheck) {
        XFSelectControl *select = (XFSelectControl *)row.control;
        XFItem *item = row.itemIndex < select.items.count ? select.items[row.itemIndex] : nil;
        // a single select is radio-like: picking is not the same as
        // toggling, or the last item could be turned off and leave nothing
        if (select.multiple) {
            [self toggleValue:item.value ofSelect:select];
        } else {
            [self selectValue:item.value ofSelect:select];
        }
        return;
    }
    if (row.kind == XFFormRowKindSelector) {
        [self presentOptionsForSelect:(XFSelectControl *)row.control];
        return;
    }
    if (row.kind == XFFormRowKindUpload) {
        [self presentDocumentPickerForUpload:(XFUploadControl *)row.control];
        return;
    }
    if (row.kind == XFFormRowKindDate) {
        // the picker is the cell's inputView, so it appears by making the
        // cell first responder -- the same gesture that raises a keyboard
        [[tableView cellForRowAtIndexPath:indexPath] becomeFirstResponder];
    }
}

@end

#endif
