/* XFormsDesigner document window — Xcode-style three-pane editor whose
   layout lives in XFDDocumentWindow.xib (one xib serving both toolkits;
   GNUstep loads it through GSXib5; regenerate with tools/genxib.py).

   Left: the host document outline (elements only) over a +/− bottom bar
   whose + pops a menu of the kinds insertable under the selection
   (XFHostEdit's insertion zones). Center: the live XFFormView preview or
   the XML source (Form/Source toggle; Apply is the only full-reload
   path). Right: DMTabBar groups Identity / Attributes / Layout like
   Xcode's Interface Builder; the Attributes group holds a tabless nested
   tab view whose page follows the selected tag's kind — control / bind /
   submission / instance / plain element — filled from and applied to
   XFDEditors facades; every apply writes host XML through XFHostEdit, so
   it is undoable and refreshes the processor in place.

   The selection is the host NSXMLElement, never a runtime control.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>
#import "XFDXPathField.h"
#import "XFDRichTextField.h"
#import "XFDIDRefField.h"
#import "XFDDesignOverlay.h"

@interface XFDWindowController : NSWindowController <NSSplitViewDelegate>

/* Left pane */
@property (nonatomic, strong) IBOutlet NSOutlineView *outline;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *plusMinusControl;

/* Center pane */
@property (nonatomic, strong) IBOutlet NSSegmentedControl *modeControl;
@property (nonatomic, strong) IBOutlet NSButton *designModeCheckbox;
@property (nonatomic, strong) IBOutlet NSTabView *centerTabView;
@property (nonatomic, strong) IBOutlet NSView *previewHost;
@property (nonatomic, strong) IBOutlet NSView *sourceHost;

/* Inspector pane: DMTabBar groups Identity / Attributes / Layout
   (Xcode-IB style); inside Attributes a tabless nested tab view shows
   only the page pertinent to the selected tag. */
@property (nonatomic, strong) IBOutlet id inspectorTabBar;    /* DMTabBar */
@property (nonatomic, strong) IBOutlet NSTabView *inspectorTabView;
@property (nonatomic, strong) IBOutlet NSTabView *inspectorKindTabView;

/* Identity page (all kinds) */
@property (nonatomic, strong) IBOutlet NSTextField *identityTitleField;
@property (nonatomic, strong) IBOutlet NSTextField *identityIdField;

/* Control page */
@property (nonatomic, strong) IBOutlet XFDXPathField *controlRefField;
@property (nonatomic, strong) IBOutlet XFDXPathField *controlValueField;
@property (nonatomic, strong) IBOutlet XFDIDRefField *controlBindField;
@property (nonatomic, strong) IBOutlet NSTextField *controlBindingStatusField;
@property (nonatomic, strong) IBOutlet NSButton *controlCreateBindButton;
@property (nonatomic, strong) IBOutlet NSButton *hostNewControlButton;
@property (nonatomic, strong) IBOutlet XFDIDRefField *controlModelField;
@property (nonatomic, strong) IBOutlet XFDIDRefField *controlSubmissionField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *controlAppearancePopup;
@property (nonatomic, strong) IBOutlet NSButton *controlIncrementalCheckbox;
@property (nonatomic, strong) IBOutlet NSTextField *controlMediatypeField;
@property (nonatomic, strong) IBOutlet XFDRichTextField *controlLabelField;
@property (nonatomic, strong) IBOutlet XFDRichTextField *controlHintField;
@property (nonatomic, strong) IBOutlet XFDRichTextField *controlHelpField;
@property (nonatomic, strong) IBOutlet XFDRichTextField *controlAlertField;

/* Bind page */
@property (nonatomic, strong) IBOutlet XFDXPathField *bindNodesetField;
@property (nonatomic, strong) IBOutlet NSTextField *bindTypeField;
@property (nonatomic, strong) IBOutlet XFDXPathField *bindCalculateField;
@property (nonatomic, strong) IBOutlet XFDXPathField *bindConstraintField;
@property (nonatomic, strong) IBOutlet XFDXPathField *bindRequiredField;
@property (nonatomic, strong) IBOutlet XFDXPathField *bindRelevantField;
@property (nonatomic, strong) IBOutlet XFDXPathField *bindReadonlyField;

/* Submission page */
@property (nonatomic, strong) IBOutlet NSTextField *submissionResourceField;
@property (nonatomic, strong) IBOutlet NSTextField *submissionMethodField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *submissionReplacePopup;
@property (nonatomic, strong) IBOutlet XFDIDRefField *submissionInstanceField;
@property (nonatomic, strong) IBOutlet XFDXPathField *submissionRefField;
@property (nonatomic, strong) IBOutlet XFDIDRefField *submissionBindField;

/* Instance page */
@property (nonatomic, strong) IBOutlet NSTextField *instanceSrcField;

/* Item / Itemset pages */
@property (nonatomic, strong) IBOutlet XFDRichTextField *itemLabelField;
@property (nonatomic, strong) IBOutlet NSTextField *itemValueField;
@property (nonatomic, strong) IBOutlet XFDXPathField *itemsetNodesetField;
@property (nonatomic, strong) IBOutlet XFDIDRefField *itemsetBindField;
@property (nonatomic, strong) IBOutlet XFDXPathField *itemsetLabelRefField;
@property (nonatomic, strong) IBOutlet XFDXPathField *itemsetValueRefField;

/* Action page: one host view; the rows are generated from the per-action
   spec table (XFDActionSpecs) at selection time. */
@property (nonatomic, strong) IBOutlet NSView *actionRowsHost;

/* Events group: hosts the handler table — the actions listening on the
   selected element (they observe their parent implicitly). */
@property (nonatomic, strong) IBOutlet NSView *eventsHost;

@end

/* The controller is split over sibling files; each category interface
   carries the protocols and xib / menu actions its file implements
   (declaring them on the primary class would warn every category
   implementation). */

/* XFDWindowController+Outline.m â the left pane */
/* (the outline's dataSource / delegate wiring is the xib's; adopting the
   AppKit protocols on a category would demand every method in this one
   file) */
@interface XFDWindowController (XFDOutline)
- (IBAction)plusMinusClicked:(NSSegmentedControl *)sender;
- (IBAction)insertElement:(id)sender;
- (IBAction)deleteElement:(id)sender;
- (IBAction)editInstanceXML:(id)sender;
@end

/* XFDWindowController+Inspector.m â the right pane */
@interface XFDWindowController (XFDInspector)
    <XFDXPathFieldProvider, XFDRichTextFieldProvider, XFDIDRefFieldProvider>
- (IBAction)inspectorChanged:(id)sender;
- (IBAction)createBindFromRef:(id)sender;
- (IBAction)elementCreateBoundControl:(id)sender;
- (IBAction)testSubmissionClicked:(id)sender;
@end

/* XFDWindowController+Preview.m â the center pane and design mode */
@interface XFDWindowController (XFDPreview) <XFDDesignOverlayDelegate>
- (IBAction)modeChanged:(NSSegmentedControl *)sender;
- (IBAction)toggleDesignMode:(id)sender;
- (IBAction)applySource:(id)sender;
- (IBAction)resetInstances:(id)sender;
@end
