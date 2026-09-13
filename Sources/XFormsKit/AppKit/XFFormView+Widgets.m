#import "XFAppKitPriv.h"
#import <XFormsKit/XFDateDisplay.h>

void XFAppKitHasWidgetsFile(void) {}

@implementation XFFormView (XFWidgets)

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
        if ([control.appearance isEqualToString:@"minimal"]) {
            // XSLTForms renders a minimal trigger as a link (G-43)
            [button setBordered:NO];
        }
        if (control.accesskey.length) {
            [button setKeyEquivalent:[control.accesskey lowercaseString]];
            [button setKeyEquivalentModifierMask:NSCommandKeyMask];
        }
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
        // XFRange.js: the value is committed on release unless incremental (G-45)
        [slider setContinuous:control.incremental];
        [slider setTarget:self];
        [slider setAction:@selector(sliderChanged:)];
        return slider;
    }

    if ([control isKindOfClass:[XFSelectControl class]]) {
        XFSelectControl *select = (XFSelectControl *)control;
        if ([select.appearance isEqualToString:@"compact"]
            || (select.multiple && [select.appearance isEqualToString:@"minimal"])) {
            // select1-select.xsl: compact = a list box (multi-select for
            // xf:select), G-43
            *height = MIN(MAX((CGFloat)select.items.count, 3), 8) * 18 + 4;
            return [self makeListBoxForSelect:select];
        }
        if (select.multiple || [select.appearance isEqualToString:@"full"]) {
            return nil;
        }
        NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [popup setTarget:self];
        [popup setAction:@selector(popupChanged:)];
        [self populatePopup:popup forSelect:select];
        return popup;
    }

    if ([control isKindOfClass:[XFTextareaControl class]]
        && [[control.mediatype lowercaseString] isEqualToString:@"application/xhtml+xml"]) {
        // rich text editing (XForms 1.1 §8.1.5; the TinyMCE sample, G-45)
        CGFloat h = (control.rows > 0 ? control.rows * 16 + 8 : kTextareaHeight) + 26;
        XFRichTextEditor *editor = [[XFRichTextEditor alloc]
            initWithFrame:NSMakeRect(0, 0, kFieldWidth, h) baseFont:[self bodyFont]];
        [editor setHTML:control.stringValue ?: @""];
        [editor.textView setDelegate:self];
        [editor.textView setEditable:!control.readonly];
        *height = h;
        return editor;
    }

    if ([control isKindOfClass:[XFTextareaControl class]]) {
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        [scroll setHasVerticalScroller:YES];
        [scroll setBorderType:NSBezelBorder];
        CGFloat h = control.rows > 0 ? control.rows * 16 + 8 : kTextareaHeight;   // @rows (G-63)
        NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, kFieldWidth, h)];
        [tv setString:control.stringValue ?: @""];
        [tv setDelegate:self];
        [tv setEditable:!control.readonly];
        [scroll setDocumentView:tv];
        *height = h;
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
            // years 1..9999 only: GNUstep's NSDatePicker formatting
            // iterates the Gregorian calendar year by year and a far
            // date hangs the layout (the parse guard should never let
            // one through; this is the belt to its braces)
            if (date != nil
                && [date timeIntervalSince1970] > -62135596800.0
                && [date timeIntervalSince1970] < 253402300800.0) {
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
            // XFOutput.js writes an <img>: the picture shows at its
            // NATURAL size, capped to a sane page width. A tiny swatch
            // (a 1x1 data-URI test pixel) scales UP to a visible square:
            // NSImageView's default proportionally-DOWN scaling would
            // paint it as one invisible pixel in an unmarked hole.
            NSData *data = [output imageData];
            NSImage *picture = data.length ? [[NSImage alloc] initWithData:data] : nil;
            CGFloat w = 96, h = 72;   // the empty slot (the bezel shows it)
            if (picture != nil) {
                NSSize natural = [picture size];
                CGSize shown = [XFOutputControl displaySizeForImageOfNaturalSize:
                    CGSizeMake(natural.width, natural.height)];
                w = shown.width;
                h = shown.height;
            }
            NSImageView *img = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
            [img setEditable:NO];
            [img setImageScaling:NSImageScaleProportionallyUpOrDown];
            if (picture != nil) {
                [img setImage:picture];
            } else {
                // nothing decodable: show the slot, not blank nothing
                [img setImageFrameStyle:NSImageFrameGrayBezel];
            }
            *height = h;
            return img;
        }
    }

    if ([control isKindOfClass:[XFOutputControl class]] && [(XFOutputControl *)control displaysHTML]) {
        // mediatype="application/xhtml+xml": rendered through the same
        // converter as the rich textarea — identical on Apple and GNUstep,
        // no WebKit (G-44)
        NSTextField *field = [self textFieldEditable:NO secure:NO];
        [field setAttributedStringValue:
            [XFRichText decoratedString:
                [XFRichText attributedStringFromHTML:control.stringValue ?: @""]
                           baseFont:[self bodyFont]]];
        return field;
    }

    BOOL editable = [control isKindOfClass:[XFInputControl class]];
    BOOL secure = [control isKindOfClass:[XFSecretControl class]];
    NSTextField *field = [self textFieldEditable:editable secure:secure];
    [field setStringValue:[self displayValueOf:control]];
    if (editable) {
        // @placeholder, numeric right-alignment, @cols (G-41, G-63); a
        // minimal-appearance hint doubles as the placeholder where the
        // widget supports one (@placeholder wins when both are given)
        NSString *placeholder = control.placeholder.length ? control.placeholder
            : (control.hintMinimal ? control.hint : nil);
        if (placeholder.length && [[field cell] respondsToSelector:@selector(setPlaceholderString:)]) {
            [(NSTextFieldCell *)[field cell] setPlaceholderString:placeholder];
        }
        if ([self isNumericControl:control]) {
            [field setAlignment:NSRightTextAlignment];
        }
    }
    return field;
}

#pragma mark - Reuse across layout passes

- (NSString *)variantForControl:(XFControl *)control
{
    // The same decisions as -makeViewForControl:height:, in the same
    // order, reduced to a name: two passes agree on the variant exactly
    // when the factory would build the same kind of view.
    if ([control isKindOfClass:[XFUploadControl class]]) return @"upload";
    if ([control isKindOfClass:[XFTriggerControl class]]) return @"trigger";
    if ([control isKindOfClass:[XFRangeControl class]]) return @"range";
    if ([control isKindOfClass:[XFSelectControl class]]) {
        XFSelectControl *select = (XFSelectControl *)control;
        if ([select.appearance isEqualToString:@"compact"]
            || (select.multiple && [select.appearance isEqualToString:@"minimal"])) {
            return @"listbox";
        }
        if (select.multiple || [select.appearance isEqualToString:@"full"]) {
            return @"select-item";
        }
        return @"popup";
    }
    if ([control isKindOfClass:[XFTextareaControl class]]) {
        return [[control.mediatype lowercaseString] isEqualToString:@"application/xhtml+xml"]
            ? @"richtext" : @"textarea";
    }
    if ([control isKindOfClass:[XFLabelControl class]]) return @"label";
    if ([control isKindOfClass:[XFInputControl class]]) {
        if ([self isBooleanControl:control]) return @"bool";
        XFDateType dateType = [(XFInputControl *)control resolvedDateType];
        if (dateType != XFDateTypeNone && [NSDatePicker class]) {
            return [NSString stringWithFormat:@"date-%ld", (long)dateType];
        }
    }
    if ([control isKindOfClass:[XFOutputControl class]]) {
        XFOutputControl *output = (XFOutputControl *)control;
        if (output.displaysImage) return @"image";
        if (output.displaysHTML) return @"html";
        return @"output";
    }
    if ([control isKindOfClass:[XFSecretControl class]]) return @"secret";
    if ([control isKindOfClass:[XFInputControl class]]) return @"input";
    return @"text";
}

- (CGFloat)heightForWidget:(XFWidget *)w
{
    XFControl *control = w.control;
    NSString *variant = w.variant;
    if ([variant isEqualToString:@"listbox"]) {
        NSUInteger n = [(XFSelectControl *)control items].count;
        return MIN(MAX((CGFloat)n, 3), 8) * 18 + 4;
    }
    if ([variant isEqualToString:@"richtext"]) {
        return (control.rows > 0 ? control.rows * 16 + 8 : kTextareaHeight) + 26;
    }
    if ([variant isEqualToString:@"textarea"]) {
        return control.rows > 0 ? control.rows * 16 + 8 : kTextareaHeight;
    }
    if ([variant isEqualToString:@"image"]) {
        return [w.view frame].size.height;
    }
    return kRowHeight;
}

- (void)populatePopup:(NSPopUpButton *)popup forSelect:(XFSelectControl *)select
{
    // What the menu should hold: group headers (disabled) and items, in
    // order; compared against what it holds so an unchanged item list --
    // the usual case, and the case when the popup itself sent the action
    // being handled -- keeps its NSMenuItems.
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableArray<id> *values = [NSMutableArray array];
    NSInteger selected = -1;
    NSString *lastGroup = nil;
    for (XFItem *item in select.items) {
        if (item.groupLabel.length && ![item.groupLabel isEqualToString:lastGroup]) {
            [titles addObject:item.groupLabel];
            [values addObject:[NSNull null]];
            lastGroup = item.groupLabel;
        }
        [titles addObject:item.label ?: item.value ?: @""];
        [values addObject:item.value ?: [NSNull null]];
        if (item.selected) {
            selected = (NSInteger)titles.count - 1;
        }
    }
    NSArray<NSMenuItem *> *have = [popup itemArray];
    NSUInteger skip = 0;
    if (have.count > titles.count && [[have[0] title] length] == 0 && [have[0] representedObject] == nil) {
        skip = 1;   // the blank "no value" entry (G-25)
    }
    BOOL same = have.count == titles.count + skip;
    for (NSUInteger i = 0; same && i < titles.count; i++) {
        NSMenuItem *item = have[i + skip];
        id value = values[i] == [NSNull null] ? nil : values[i];
        same = [[item title] isEqualToString:titles[i]]
            && (value == nil ? [item representedObject] == nil : [[item representedObject] isEqual:value])
            && [item isEnabled] == (values[i] != [NSNull null]);
    }
    if (!same) {
        [popup removeAllItems];
        for (NSUInteger i = 0; i < titles.count; i++) {
            [popup addItemWithTitle:titles[i]];
            if (values[i] == [NSNull null]) {
                [[popup lastItem] setEnabled:NO];
            } else {
                [[popup lastItem] setRepresentedObject:values[i]];
            }
        }
        skip = 0;
    }
    if (selected >= 0) {
        if (skip) {
            [popup removeItemAtIndex:0];
        }
        [popup selectItemAtIndex:selected];
    } else {
        // XsltForms_select.setValue: an empty / unknown value shows a
        // blank first option instead of the first item (G-25)
        if (!skip) {
            [popup insertItemWithTitle:@"" atIndex:0];
        }
        [popup selectItemAtIndex:0];
    }
}

- (void)configureWidget:(XFWidget *)w
{
    XFControl *control = w.control;
    NSView *view = w.view;
    NSString *variant = w.variant;
    BOOL editing = view != nil && view == self.reconcileEditingView;

    if ([variant isEqualToString:@"popup"]) {
        [self populatePopup:(NSPopUpButton *)view forSelect:(XFSelectControl *)control];
    } else if ([variant isEqualToString:@"select-item"]) {
        NSButton *box = (NSButton *)view;
        NSString *value = [box toolTip];
        BOOL on = value && [[(XFSelectControl *)control selectedValues] containsObject:value];
        [box setState:on ? NSOnState : NSOffState];
    } else if ([variant isEqualToString:@"listbox"]) {
        NSTableView *table = [(NSScrollView *)view documentView];
        XFListBoxAdapter *adapter = (XFListBoxAdapter *)[table dataSource];
        if ([adapter isKindOfClass:[XFListBoxAdapter class]]) {
            adapter.select = (XFSelectControl *)control;
            if (![self.listBoxes containsObject:adapter]) {
                [self.listBoxes addObject:adapter];
            }
            [table reloadData];
            NSMutableIndexSet *selected = [NSMutableIndexSet indexSet];
            NSUInteger i = 0;
            for (XFItem *item in [(XFSelectControl *)control items]) {
                if (item.selected) {
                    [selected addIndex:i];
                }
                i++;
            }
            adapter.selecting = YES;
            [table selectRowIndexes:selected byExtendingSelection:NO];
            adapter.selecting = NO;
        }
    } else if ([variant isEqualToString:@"bool"]) {
        NSButton *box = (NSButton *)view;
        [box setTitle:control.label ?: @""];
        BOOL on = [control.stringValue isEqualToString:@"true"] || [control.stringValue isEqualToString:@"1"];
        [box setState:on ? NSOnState : NSOffState];
    } else if ([variant isEqualToString:@"trigger"]) {
        NSButton *button = (NSButton *)view;
        [button setTitle:control.label ?: @"OK"];
        [button setBordered:![control.appearance isEqualToString:@"minimal"]];
        [button setKeyEquivalent:control.accesskey.length ? [control.accesskey lowercaseString] : @""];
    } else if ([variant isEqualToString:@"upload"]) {
        XFUploadControl *upload = (XFUploadControl *)control;
        [(NSButton *)view setTitle:upload.fileName.length ? upload.fileName : @"Choose File…"];
    } else if ([variant isEqualToString:@"range"]) {
        XFRangeControl *range = (XFRangeControl *)control;
        NSSlider *slider = (NSSlider *)view;
        [slider setMinValue:range.start];
        [slider setMaxValue:range.end];
        [slider setAltIncrementValue:range.step];
        [slider setContinuous:control.incremental];
        if (!editing) {
            [slider setDoubleValue:range.numericValue];
        }
    } else if ([variant hasPrefix:@"date-"]) {
        NSDate *date = [(XFInputControl *)control dateValue];
        if (date != nil && !editing
            && [date timeIntervalSince1970] > -62135596800.0
            && [date timeIntervalSince1970] < 253402300800.0) {
            [(NSDatePicker *)view setDateValue:date];
        }
    } else if ([variant isEqualToString:@"richtext"]) {
        XFRichTextEditor *editor = (XFRichTextEditor *)view;
        [editor.textView setEditable:!control.readonly];
        if (!editing && ![[editor HTML] isEqualToString:control.stringValue ?: @""]) {
            [editor setHTML:control.stringValue ?: @""];
        }
    } else if ([variant isEqualToString:@"textarea"]) {
        NSTextView *tv = [(NSScrollView *)view documentView];
        [tv setEditable:!control.readonly];
        if (!editing && ![[tv string] isEqualToString:control.stringValue ?: @""]) {
            [tv setString:control.stringValue ?: @""];
        }
    } else if ([variant isEqualToString:@"image"]) {
        NSImageView *img = (NSImageView *)view;
        NSData *data = [(XFOutputControl *)control imageData];
        NSImage *picture = data.length ? [[NSImage alloc] initWithData:data] : nil;
        CGFloat wd = 96, ht = 72;
        if (picture != nil) {
            NSSize natural = [picture size];
            CGSize shown = [XFOutputControl displaySizeForImageOfNaturalSize:
                CGSizeMake(natural.width, natural.height)];
            wd = shown.width;
            ht = shown.height;
        }
        [img setImage:picture];
        [img setImageFrameStyle:picture ? NSImageFrameNone : NSImageFrameGrayBezel];
        [img setFrameSize:NSMakeSize(wd, ht)];
    } else if ([variant isEqualToString:@"html"]) {
        [(NSTextField *)view setAttributedStringValue:
            [XFRichText decoratedString:
                [XFRichText attributedStringFromHTML:control.stringValue ?: @""]
                           baseFont:[self bodyFont]]];
    } else if ([variant isEqualToString:@"label"]) {
        NSTextField *field = (NSTextField *)view;
        if (![[field stringValue] isEqualToString:control.stringValue ?: @""]) {
            [field setStringValue:control.stringValue ?: @""];
        }
    } else if ([view isKindOfClass:[NSTextField class]]) {
        // input, secret, output
        NSTextField *field = (NSTextField *)view;
        NSString *shown = [self displayValueOf:control];
        if (!editing && ![[field stringValue] isEqualToString:shown]) {
            [field setStringValue:shown];
        }
        if ([field isEditable]) {
            // only when changed: on GNUstep every one of these setters
            // aborts an editing session in progress
            NSString *placeholder = control.placeholder.length ? control.placeholder
                : (control.hintMinimal ? control.hint : nil);
            NSTextFieldCell *cell = (NSTextFieldCell *)[field cell];
            if ([cell respondsToSelector:@selector(setPlaceholderString:)]
                && [cell respondsToSelector:@selector(placeholderString)]
                && !(placeholder.length == 0 && [cell placeholderString].length == 0)
                && ![[cell placeholderString] isEqualToString:placeholder]) {
                [cell setPlaceholderString:placeholder.length ? placeholder : nil];
            }
            NSTextAlignment alignment = [self isNumericControl:control] ? NSRightTextAlignment : NSLeftTextAlignment;
            if ([field alignment] != alignment && ([field alignment] != NSNaturalTextAlignment || alignment != NSLeftTextAlignment)) {
                [field setAlignment:alignment];
            }
        }
    }
    [self applyEnabled:view control:control];
}

/// XSLTForms input mode "digits" / numeric types align right (G-41).
- (BOOL)isNumericControl:(XFControl *)control
{
    XFNodeState *state = [XFNodeState existingStateOnNode:control.boundNode];
    NSString *type = [state.typeName lowercaseString] ?: @"";
    if ([control.inputmode isEqualToString:@"digits"]) {
        return YES;
    }
    for (NSString *n in @[ @"integer", @"decimal", @"double", @"float", @"int", @"long", @"short", @"byte", @"amount" ]) {
        if ([type hasSuffix:n]) {
            return YES;
        }
    }
    return NO;
}

/// XFOutput.js setValue with type.format: numbers normalised to the type's
/// fractionDigits (G-44); everything else as stored.
- (NSString *)displayValueOf:(XFControl *)control
{
    NSString *value = control.stringValue ?: @"";
    if (![control isKindOfClass:[XFOutputControl class]]) {
        return value;
    }
    XFNodeState *state = [XFNodeState existingStateOnNode:control.boundNode];
    XFType *type = state.typeName.length ? [XFType typeNamed:state.typeName] : nil;
    if (type.fractionDigits && value.length) {
        return [type normalizeValue:value];
    }
    // a date belongs in the reader's locale, the way the date picker
    // writes it — the instance keeps the lexical value either way
    NSString *localized = [XFDateDisplay localizedStringForControl:control];
    return localized ?: value;
}


/// appearance="compact": a single-column table listing the items (G-43).
- (NSView *)makeListBoxForSelect:(XFSelectControl *)select
{
    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"item"];
    [column setWidth:kFieldWidth - 20];
    [table addTableColumn:column];
    [table setHeaderView:nil];
    [table setRowHeight:16];
    [table setAllowsMultipleSelection:select.multiple];
    [table setAllowsEmptySelection:YES];
    XFListBoxAdapter *adapter = [[XFListBoxAdapter alloc] init];
    adapter.select = select;
    adapter.formView = self;
    [table setDataSource:adapter];
    [table setDelegate:adapter];
    [self.listBoxes addObject:adapter];
    NSMutableIndexSet *selected = [NSMutableIndexSet indexSet];
    NSUInteger i = 0;
    for (XFItem *item in select.items) {
        if (item.selected) {
            [selected addIndex:i];
        }
        i++;
    }
    adapter.selecting = YES;
    [table selectRowIndexes:selected byExtendingSelection:NO];
    adapter.selecting = NO;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [scroll setBorderType:NSBezelBorder];
    [scroll setHasVerticalScroller:YES];
    [scroll setDocumentView:table];
    return scroll;
}

- (void)listBox:(XFListBoxAdapter *)adapter didSelectRows:(NSIndexSet *)rows
{
    XFSelectControl *select = adapter.select;
    NSMutableArray *values = [NSMutableArray array];
    [rows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        (void)stop;
        if (idx < select.items.count && select.items[idx].value) {
            [values addObject:select.items[idx].value];
        }
    }];
    [self.processor focusControl:select fromUI:YES];
    BOOL changed = NO;
    if (select.multiple) {
        NSSet *wanted = [NSSet setWithArray:values];
        for (XFItem *item in [select.items copy]) {
            BOOL want = item.value && [wanted containsObject:item.value];
            if (want != item.selected) {
                changed = [select toggleItem:item] || changed;
            }
        }
    } else if (values.count) {
        changed = [select selectValue:values.firstObject];
    }
    if (changed) {
        [self.processor controlDidChangeValue:select];
    }
    [self performSelector:@selector(reloadFromProcessor) withObject:nil afterDelay:0];
}

/// YES when the widget shows the control's label itself (no separate caption).
- (BOOL)viewCarriesLabel:(NSView *)view control:(XFControl *)control
{
    if ([control isKindOfClass:[XFTriggerControl class]] || [control isKindOfClass:[XFGroup class]]) {
        return YES;
    }
    return [view isKindOfClass:[NSButton class]] && [control isKindOfClass:[XFInputControl class]];
}


- (NSArray<NSString *> *)fileTypesForMediaTypes:(NSArray<NSString *> *)mediaTypes
{
    NSDictionary *map = @{
        @"image/png": @[ @"png" ], @"image/jpeg": @[ @"jpg", @"jpeg" ], @"image/gif": @[ @"gif" ],
        @"image/svg+xml": @[ @"svg" ], @"image/*": @[ @"png", @"jpg", @"jpeg", @"gif", @"tif", @"tiff", @"bmp", @"svg" ],
        @"application/pdf": @[ @"pdf" ], @"application/xml": @[ @"xml" ], @"text/xml": @[ @"xml" ],
        @"text/plain": @[ @"txt" ], @"text/csv": @[ @"csv" ], @"text/*": @[ @"txt", @"csv", @"xml", @"html", @"md" ],
        @"application/json": @[ @"json" ], @"application/zip": @[ @"zip" ],
    };
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *mt in mediaTypes) {
        NSArray *exts = map[mt];
        if (exts == nil) {
            return @[];   // unknown type: no filter rather than a wrong one
        }
        [out addObjectsFromArray:exts];
    }
    return out;
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
    // @mediatype → file type filter (G-46)
    NSArray *types = [self fileTypesForMediaTypes:[upload acceptedMediaTypes]];
    if (types.count && [panel respondsToSelector:@selector(setAllowedFileTypes:)]) {
        [panel setAllowedFileTypes:types];
    }
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
        // commitFileData: runs the value-change pipeline itself
        [self reloadFromProcessor];
    }
}

@end
