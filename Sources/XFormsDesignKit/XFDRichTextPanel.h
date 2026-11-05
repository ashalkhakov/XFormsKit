/* The rich text field's editor: one fragment, as rich text and as source
   (XFDRichTextPanel.xib).
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>

/// The "…" modal: one fragment, two views. Rich is XFRichTextEditor
/// (blocks + inline styling) with simple xf:output values shown as tinted
/// ⟦expr⟧ tokens and an "Insert Output…" button running the shared node
/// picker; Source is the raw XML, parse-gated. The segmented control
/// switches views, converting on the way; a fragment the rich view cannot
/// represent keeps Source selected with an explanation instead of
/// dropping markup.
@interface XFDRichTextPanel : NSObject
{
    IBOutlet NSPanel *_panel;
    IBOutlet NSSegmentedControl *_viewControl;
    IBOutlet NSButton *_insertOutputButton;
    IBOutlet NSTabView *_tabs;
    IBOutlet NSView *_richHost;
    XFRichTextEditor *_richEditor;
    IBOutlet NSTextView *_sourceView;
    IBOutlet NSTextField *_statusField;
    IBOutlet NSButton *_okButton;
    NSArray *_topLevelObjects;
    NSString *_result;
    XFProcessor *_processor;
    XFXMLNode *_contextNode;
    XFXMLElement *_hostElement;
    BOOL _adjustingSelection;
}
+ (NSString *)runWithFragment:(NSString *)fragment
                        title:(NSString *)title
                    processor:(XFProcessor *)processor
                  contextNode:(XFXMLNode *)contextNode
                  hostElement:(XFXMLElement *)hostElement;
@end
