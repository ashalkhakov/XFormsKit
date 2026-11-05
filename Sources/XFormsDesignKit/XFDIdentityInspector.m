/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDIdentityInspector.h"
#import "XFDEditors.h"

@implementation XFDIdentityInspector {
    BOOL _updating;
}

- (instancetype)initWithFormEditor:(XFDFormEditor *)formEditor nibName:(NSString *)nibName
{
    if ((self = [super initWithFormEditor:formEditor nibName:nibName])) {
        self.title = @"Identity";
    }
    return self;
}

- (void)viewDidLoadFromNib
{
    // the bold title line, which the XIB leaves out
    [self.identityTitleField setFont:[NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]];
    [self fill];
}

- (void)fill
{
    if (![self isViewLoaded]) {
        return;
    }
    XFDElementEditor *e = [XFDElementEditor editorForElement:self.formEditor.selection
                                                  formEditor:self.formEditor];
    [self.identityTitleField setStringValue:e.title ?: @"No Selection"];
    [self.identityIdField setStringValue:e ? e.identifier : @""];
    [self.identityIdField setEnabled:e != nil];
}

- (void)formEditorSelectionDidChange:(XFDFormEditor *)editor
{
    (void)editor;
    [self fill];
}

- (void)formEditor:(XFDFormEditor *)editor hostDidChange:(XFXMLElement *)element
{
    (void)editor;
    (void)element;
    if (!_updating) {
        [self fill];
    }
}

- (void)formEditorProcessorWasReplaced:(XFDFormEditor *)editor
{
    (void)editor;
    [self fill];
}

- (IBAction)inspectorChanged:(id)sender
{
    (void)sender;
    XFDElementEditor *e = [XFDElementEditor editorForElement:self.formEditor.selection
                                                  formEditor:self.formEditor];
    if (e == nil || [e.identifier isEqualToString:[self.identityIdField stringValue]]) {
        return;
    }
    _updating = YES;
    e.identifier = [self.identityIdField stringValue];
    _updating = NO;
    [self.formEditor selectionMayHaveChanged];
}

@end
