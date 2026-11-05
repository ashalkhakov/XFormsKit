/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDIdentityInspector.h"
#import "XFDEditors.h"

@implementation XFDIdentityInspector

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
    [self show];
}

- (XFDElementEditor *)editor
{
    return [self.editorController content];
}

/// The selection shown: its editor, or the same one reloaded.
- (void)show
{
    if (![self isViewLoaded]) {
        return;
    }
    XFXMLElement *selection = self.formEditor.selection;
    if (selection != nil && self.editor.element == selection) {
        [self.editor reload];
        return;
    }
    [self.editorController commitEditing];
    [self.editorController setContent:[XFDElementEditor editorForElement:selection formEditor:self.formEditor]];
}

- (void)formEditorSelectionDidChange:(XFDFormEditor *)editor
{
    (void)editor;
    [self show];
}

- (void)formEditor:(XFDFormEditor *)editor hostDidChange:(XFXMLElement *)element
{
    (void)editor;
    (void)element;
    [self show];
}

- (void)formEditorProcessorWasReplaced:(XFDFormEditor *)editor
{
    (void)editor;
    [self show];
}

@end
