/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDInspectorPages.h"
#import "XFDAttributesInspector.h"
#import "XFDFormEditor.h"
#import "XFDEditors.h"
#import "XFDInstanceXMLEditor.h"
#import "XFDSubmissionTester.h"

@implementation XFDInspectorPage

- (XFDFormEditor *)formEditor
{
    return self.inspector.formEditor;
}

- (XFDElementEditor *)editor
{
    return [self.editorController content];
}

- (void)showElement:(XFXMLElement *)element
{
    XFDElementEditor *editor = self.editor;
    if (element != nil && editor.element == element) {
        [editor reload];
        return;
    }
    // what the old editor's fields show is theirs to give, before it goes
    [self.editorController commitEditing];
    [self.editorController setContent:[XFDElementEditor editorForElement:element formEditor:self.formEditor]];
    [self editorDidChange];
}

- (void)editorDidChange
{
}

#pragma mark The fields' providers

- (XFXMLElement *)hostElementForXPathField:(XFDXPathField *)field
{
    (void)field;
    return self.editor.element;
}

- (XFProcessor *)processorForXPathField:(XFDXPathField *)field
{
    (void)field;
    return self.formEditor.processor;
}

- (XFXMLNode *)contextNodeForXPathField:(XFDXPathField *)field
{
    (void)field;
    return [self.formEditor contextNodeForSelectionNodeset:NO];
}

- (XFXMLElement *)hostElementForRichTextField:(XFDRichTextField *)field
{
    (void)field;
    return self.editor.element;
}

- (XFProcessor *)processorForRichTextField:(XFDRichTextField *)field
{
    (void)field;
    return self.formEditor.processor;
}

/// Outputs inside a label, hint, help or alert evaluate against the
/// control's OWN bound node (the engine's childContextFrom:), so the
/// picker's Relative style starts there.
- (XFXMLNode *)contextNodeForRichTextField:(XFDRichTextField *)field
{
    (void)field;
    return [self.formEditor contextNodeForSelectionContent];
}

- (XFProcessor *)processorForIDRefField:(XFDIDRefField *)field
{
    (void)field;
    return self.formEditor.processor;
}

@end

#pragma mark - Control

@implementation XFDControlPage

/// A repeat's ref selects the nodeset it iterates; every other control
/// binds one node.
- (void)editorDidChange
{
    XFDControlEditor *editor = (XFDControlEditor *)self.editor;
    self.controlRefField.expectation = editor.refSelectsNodeSet ? XFDXPathExpectNodeSet : XFDXPathExpectNode;
}

- (IBAction)createBindFromRef:(id)sender
{
    (void)sender;
    if (![self.formEditor createBindFromSelectedRef:NULL]) {
        XFDBeep();
    }
}

@end

#pragma mark - Bind

@implementation XFDBindPage

/// The nodeset in the outer bind's context; the model item properties
/// per bound node.
- (XFXMLNode *)contextNodeForXPathField:(XFDXPathField *)field
{
    return [self.formEditor contextNodeForSelectionNodeset:field == self.bindNodesetField];
}

@end

#pragma mark - Submission

@implementation XFDSubmissionPage

- (IBAction)testSubmission:(id)sender
{
    (void)sender;
    [XFDSubmissionTester runForProcessor:self.formEditor.processor
                       initialSubmission:[[self.editor.element attributeForName:@"id"] stringValue]];
}

@end

#pragma mark - Instance

@implementation XFDInstancePage

- (IBAction)editInstanceXML:(id)sender
{
    (void)sender;
    NSError *error = nil;
    if (![XFDInstanceXMLEditor editInstanceOfElement:self.editor.element
                                        inFormEditor:self.formEditor error:&error]
        && error != nil) {
        [self.inspector presentError:error];
    }
}

@end

#pragma mark - Item, Itemset

@implementation XFDItemPage
@end

@implementation XFDItemsetPage
@end

#pragma mark - Any other element

@implementation XFDElementPage

- (IBAction)elementCreateBoundControl:(id)sender
{
    if (!self.editor.takesBoundControl) {
        XFDBeep();
        return;
    }
    NSView *anchor = [sender isKindOfClass:[NSView class]] ? sender : self.hostNewControlButton;
    NSPoint where = [[anchor superview] convertPoint:[anchor frame].origin toView:nil];
    NSEvent *down = [NSEvent mouseEventWithType:NSLeftMouseDown
                                       location:where
                                  modifierFlags:0
                                      timestamp:0
                                   windowNumber:[[anchor window] windowNumber]
                                        context:nil
                                    eventNumber:0
                                     clickCount:1
                                       pressure:1];
    [NSMenu popUpContextMenu:self.controlKindMenu withEvent:down forView:anchor];
}

- (IBAction)boundControlKindPicked:(id)sender
{
    [self createBoundControlOfKind:[sender title]];
}

- (void)createBoundControlOfKind:(NSString *)kind
{
    if ([self.formEditor createControlOfKind:kind boundToSelectedDataNode:NULL] == nil) {
        XFDBeep();
    }
}

@end
