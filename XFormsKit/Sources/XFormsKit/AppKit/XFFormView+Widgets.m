#import "XFAppKitPriv.h"

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
        } else {
            // XsltForms_select.setValue: an empty / unknown value shows a
            // blank first option instead of the first item (G-25)
            [popup insertItemWithTitle:@"" atIndex:0];
            [popup selectItemAtIndex:0];
        }
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

    if ([control isKindOfClass:[XFOutputControl class]] && [(XFOutputControl *)control displaysHTML]) {
        // mediatype="application/xhtml+xml": rendered through the same
        // converter as the rich textarea — identical on Apple and GNUstep,
        // no WebKit (G-44)
        NSTextField *field = [self textFieldEditable:NO secure:NO];
        [field setAttributedStringValue:
            [XFRichText attributedStringFromHTML:control.stringValue ?: @"" baseFont:[self bodyFont]]];
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
    return value;
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
        [self.processor controlDidChangeValue:upload];
        [self reloadFromProcessor];
    }
}

@end
