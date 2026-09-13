#import "XFAppKitPriv.h"

void XFAppKitHasEditingFile(void) {}

@implementation XFFormView (XFEditing)

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
    [self endEditingInProgress];
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


- (void)commitControl:(XFControl *)control value:(NSString *)value
{
    [self.processor setValue:value ofControl:control error:NULL];
    [self reloadFromProcessor];
}


/// Ends an edit that is still in progress, so whatever runs next sees
/// what was typed.
///
/// Clicking a button, a checkbox or a popup does not move the first
/// responder on AppKit: the textarea — or the field editor a text field
/// is being typed into — keeps it, nothing ends the editing, and the
/// action goes ahead against the previous value. `Samples/dialog.xhtml`
/// shows it: type a note, click "Done", and the dialog closes with the
/// note lost. Tab escaped this only because the Tab handler drops the
/// first responder itself.
///
/// Two rules for callers. Look the sender's control up FIRST: committing
/// can rebuild the widgets, and the control object outlives that while
/// its view does not. And call this from an action, never from the focus
/// path — a text field reports the start of its own editing through
/// `widgetDidFocus:`, so ending the edit there takes the focus straight
/// back off the field just clicked into and nothing can be typed at all.
- (void)endEditingInProgress
{
    NSWindow *window = [self window];
    NSResponder *responder = [window firstResponder];
    if (![responder isKindOfClass:[NSTextView class]]) {
        return;
    }
    NSTextView *editor = (NSTextView *)responder;
    if ([editor isFieldEditor]) {
        [window endEditingFor:nil];          // controlTextDidEndEditing: commits
    } else if ([self widgetForTextView:editor] != nil) {
        [window makeFirstResponder:nil];     // textDidEndEditing: commits
    }
}

- (void)controlTextDidBeginEditing:(NSNotification *)note
{
    [self widgetDidFocus:[note object]];
}

- (void)controlTextDidEndEditing:(NSNotification *)note
{
    // focus stays on Return; leaving the field is a blur (DOMFocusOut)
    NSNumber *movement = [note userInfo][@"NSTextMovement"];
    if (movement && [movement integerValue] == NSReturnTextMovement) {
        self.pendingActivate = [self controlForSender:[note object]];
        return;
    }
    XFControl *control = [self controlForSender:[note object]];
    // a commit that rebuilds the widgets swallows AppKit's own Tab
    // movement — remember it so the reload can replay it (G-63)
    if (movement && [movement integerValue] == NSTabTextMovement) {
        self.pendingTabControl = control;
        self.pendingTabDirection = 1;
    } else if (movement && [movement integerValue] == NSBacktabTextMovement) {
        self.pendingTabControl = control;
        self.pendingTabDirection = -1;
    }
    if (control && control == self.processor.focusedControl) {
        [self.processor blurFocusedControl];
    }
}

- (void)textDidBeginEditing:(NSNotification *)note
{
    XFWidget *w = [self widgetForTextView:[note object]];
    if (w) {
        [self.processor focusControl:w.control fromUI:YES];
    }
}

- (void)textChanged:(NSTextField *)sender
{
    XFControl *control = [self controlForSender:sender];
    if (control) {
        [self.delayTimer invalidate];
        self.delayTimer = nil;
        BOOL activate = (self.pendingActivate == control);
        self.pendingActivate = nil;
        // No change event without a change (DOM semantics): the widgets
        // survive, so a Tab that got the action here moves natively
        if (!activate && [[sender stringValue] isEqualToString:control.stringValue ?: @""]) {
            if (control == self.pendingTabControl) {
                // no rebuild: AppKit's own movement machinery handles this Tab
                self.pendingTabControl = nil;
                self.pendingTabDirection = 0;
            }
            return;
        }
        [self.processor setValue:[sender stringValue] ofControl:control error:NULL];
        if (activate) {
            // Return in an input: DOMActivate after the value change
            [XFXMLEvents dispatch:control name:@"DOMActivate"];
            [self.processor refreshControls];
        }
        [self reloadFromProcessor];
        [self notifyDocumentReplaceIfNeeded];
    }
}

#pragma mark - Incremental commits

/// incremental="true": commit on every keystroke without rebuilding the
/// form (a rebuild would replace the field being edited). Other widgets are
/// refreshed in place; layout changes (relevance) are applied by the rebuild
/// on the final commit (Return / focus loss).
- (void)commitIncremental:(XFControl *)control value:(NSString *)value editingView:(NSView *)editing
{
    if (control.delay > 0) {
        // XsltForms_input.keyUpIncremental: with @delay the commit waits
        // until the keys stop for that long (G-40)
        [self.delayTimer invalidate];
        __weak XFFormView *weakSelf = self;
        NSDictionary *info = @{ @"control": control, @"value": value ?: @"", @"view": editing ?: [NSNull null] };
        self.delayTimer = [NSTimer scheduledTimerWithTimeInterval:control.delay
                                                           target:weakSelf
                                                         selector:@selector(delayedCommit:)
                                                         userInfo:info
                                                          repeats:NO];
        return;
    }
    [self commitIncrementalNow:control value:value editingView:editing];
}

- (void)delayedCommit:(NSTimer *)timer
{
    NSDictionary *info = [timer userInfo];
    self.delayTimer = nil;
    id view = info[@"view"];
    [self commitIncrementalNow:info[@"control"] value:info[@"value"]
                   editingView:[view isKindOfClass:[NSView class]] ? view : nil];
}

- (void)commitIncrementalNow:(XFControl *)control value:(NSString *)value editingView:(NSView *)editing
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

/// Textareas: Tab / Shift-Tab move the focus like everywhere else in the
/// form (the HTML behaviour XSLTForms gets for free).
- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    if (commandSelector == @selector(insertNewline:)) {
        XFWidget *w = [self widgetForTextView:textView];
        if ([w.view isKindOfClass:[XFRichTextEditor class]]) {
            return [(XFRichTextEditor *)w.view handleNewline];
        }
        return NO;
    }
    if (commandSelector != @selector(insertTab:) && commandSelector != @selector(insertBacktab:)) {
        return NO;
    }
    XFControl *control = [self widgetForTextView:textView].control;
    self.pendingTabControl = control;
    self.pendingTabDirection = commandSelector == @selector(insertTab:) ? 1 : -1;
    // end the editing (commits and may rebuild), then move on the new widgets
    [[textView window] makeFirstResponder:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyPendingTab) object:nil];
    [self performSelector:@selector(applyPendingTab) withObject:nil afterDelay:0];
    return YES;
}

- (void)textDidChange:(NSNotification *)note
{
    NSTextView *tv = [note object];
    XFWidget *w = [self widgetForTextView:tv];
    if (w && w.control.incremental) {
        NSString *value = [w.view isKindOfClass:[XFRichTextEditor class]]
            ? [(XFRichTextEditor *)w.view HTML] : [tv string];
        [self commitIncremental:w.control value:value editingView:w.view];
    }
}

- (void)refreshWidgetsInPlaceExcept:(NSView *)editing
{
    // SVG re-resolves its AVTs and gathered output values (G-20 phase 3)
    for (XFSVGView *svg in self.svgViews) {
        [svg rebuild];
    }
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
                BOOL found = NO;
                for (NSMenuItem *item in [popup itemArray]) {
                    if (selected && [[item representedObject] isEqual:selected]) {
                        [popup selectItem:item];
                        found = YES;
                        break;
                    }
                }
                if (!found) {
                    if ([[popup itemAtIndex:0] representedObject] != nil || [[popup itemTitleAtIndex:0] length]) {
                        [popup insertItemWithTitle:@"" atIndex:0];
                    }
                    [popup selectItemAtIndex:0];
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
            } else if ([view isKindOfClass:[XFRichTextEditor class]]) {
                XFRichTextEditor *editor = (XFRichTextEditor *)view;
                if (![[editor HTML] isEqualToString:control.stringValue ?: @""]) {
                    [editor setHTML:control.stringValue ?: @""];
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
        [self updateBadgesForWidget:w];
        [w.labelField setHidden:!control.relevant];
        if (w.labelField && [w.labelField respondsToSelector:@selector(setTextColor:)]) {
            [w.labelField setTextColor:control.valid ? [NSColor controlTextColor] : XFInvalidTextColor()];
        }
    }
}

- (void)textDidEndEditing:(NSNotification *)note
{
    NSTextView *tv = [note object];
    XFWidget *w = [self widgetForTextView:tv];
    if (w == nil) {
        return;
    }
    NSString *value = [w.view isKindOfClass:[XFRichTextEditor class]]
        ? [(XFRichTextEditor *)w.view HTML] : [tv string];
    // no change event without a change (same as the text fields)
    if ([value isEqualToString:w.control.stringValue ?: @""]) {
        if (w.control == self.pendingTabControl) {
            self.pendingTabControl = nil;
            self.pendingTabDirection = 0;
        }
        return;
    }
    [self commitControl:w.control value:value];
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
    [self endEditingInProgress];
    [self widgetDidFocus:sender];
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
    [self endEditingInProgress];
    [self widgetDidFocus:sender];
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
    [self endEditingInProgress];
    [self widgetDidFocus:sender];
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
    [self endEditingInProgress];
    [self widgetDidFocus:sender];
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
    [self endEditingInProgress];
    [self widgetDidFocus:sender];
    if (control) {
        // XSLTForms: a checkbox click is a value change + DOMActivate (G-42)
        [self.processor setValue:([sender state] == NSOnState) ? @"true" : @"false" ofControl:control error:NULL];
        [XFXMLEvents dispatch:control name:@"DOMActivate"];
        [self.processor refreshControls];
        [self reloadFromProcessor];
        [self notifyDocumentReplaceIfNeeded];
    }
}

- (void)dateChanged:(NSDatePicker *)sender
{
    XFControl *control = [self controlForSender:sender];
    [self endEditingInProgress];
    [self widgetDidFocus:sender];
    if ([control isKindOfClass:[XFInputControl class]]) {
        if ([(XFInputControl *)control commitDateValue:[sender dateValue] error:NULL]) {
            [self.processor controlDidChangeValue:control];
        }
        [self reloadFromProcessor];
    }
}

@end
