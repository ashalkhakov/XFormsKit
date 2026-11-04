/* The Attributes inspector's pages, one per kind of element: a control,
   a bind, a submission, an instance, an action, an item, an itemset, any
   other element. Each page is its fields (XFDAttributesInspector.xib's
   tab view items, and a page object there with outlets to them): it fills
   them from the selection's editor facade (XFDEditors) and applies them
   to it, and it is what its XPath, rich text and IDREF fields ask for the
   element, processor and context node they evaluate against.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>
#import <XFormsKit/XFXMLTypes.h>
#import "XFDXPathField.h"
#import "XFDRichTextField.h"
#import "XFDIDRefField.h"

NS_ASSUME_NONNULL_BEGIN

@class XFDAttributesInspector, XFDFormEditor, XFDElementEditor;

@interface XFDInspectorPage : NSObject <XFDXPathFieldProvider, XFDRichTextFieldProvider, XFDIDRefFieldProvider>

@property (nonatomic, strong) IBOutlet NSView *view;
@property (nonatomic, weak) IBOutlet XFDAttributesInspector *inspector;
@property (nonatomic, weak, readonly, nullable) XFDFormEditor *formEditor;

/// Its fields given their providers, targets and expectations, once the
/// XIB is loaded.
- (void)setUp;
/// Its fields filled from the selection; applied to it.
- (void)fill;
- (void)apply;

/// The fields of each kind it has (the defaults: none).
- (NSArray<XFDXPathField *> *)xpathFields;
- (NSArray<XFDRichTextField *> *)richTextFields;
/// IDREF fields, each with the kind of id it takes.
- (NSDictionary<NSString *, NSString *> *)idRefFieldKinds;

/// A rich text row applied: rich content through the XML property (the
/// markup kept), plain text through the text property — never the other
/// way round, so a rich label is not flattened by the apply pass.
- (void)applyRichField:(XFDRichTextField *)field name:(NSString *)name toEditor:(XFDElementEditor *)editor;

@end

@interface XFDControlPage : XFDInspectorPage
@property (nonatomic, strong) IBOutlet XFDXPathField *controlRefField;
@property (nonatomic, strong) IBOutlet XFDXPathField *controlValueField;
@property (nonatomic, strong) IBOutlet XFDIDRefField *controlBindField;
@property (nonatomic, strong) IBOutlet NSTextField *controlBindingStatusField;
@property (nonatomic, strong) IBOutlet NSButton *controlCreateBindButton;
@property (nonatomic, strong) IBOutlet XFDIDRefField *controlModelField;
@property (nonatomic, strong) IBOutlet XFDIDRefField *controlSubmissionField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *controlAppearancePopup;
@property (nonatomic, strong) IBOutlet NSButton *controlIncrementalCheckbox;
@property (nonatomic, strong) IBOutlet NSTextField *controlMediatypeField;
@property (nonatomic, strong) IBOutlet XFDRichTextField *controlLabelField;
@property (nonatomic, strong) IBOutlet XFDRichTextField *controlHintField;
@property (nonatomic, strong) IBOutlet XFDRichTextField *controlHelpField;
@property (nonatomic, strong) IBOutlet XFDRichTextField *controlAlertField;
/// The control's ref made a named bind (Create Bind).
- (IBAction)createBindFromRef:(nullable id)sender;
@end

@interface XFDBindPage : XFDInspectorPage
@property (nonatomic, strong) IBOutlet XFDXPathField *bindNodesetField;
@property (nonatomic, strong) IBOutlet NSTextField *bindTypeField;
@property (nonatomic, strong) IBOutlet XFDXPathField *bindCalculateField;
@property (nonatomic, strong) IBOutlet XFDXPathField *bindConstraintField;
@property (nonatomic, strong) IBOutlet XFDXPathField *bindRequiredField;
@property (nonatomic, strong) IBOutlet XFDXPathField *bindRelevantField;
@property (nonatomic, strong) IBOutlet XFDXPathField *bindReadonlyField;
@end

@interface XFDSubmissionPage : XFDInspectorPage
@property (nonatomic, strong) IBOutlet NSTextField *submissionResourceField;
@property (nonatomic, strong) IBOutlet NSTextField *submissionMethodField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *submissionReplacePopup;
@property (nonatomic, strong) IBOutlet XFDIDRefField *submissionInstanceField;
@property (nonatomic, strong) IBOutlet XFDXPathField *submissionRefField;
@property (nonatomic, strong) IBOutlet XFDIDRefField *submissionBindField;
/// The submission tester, on the selected submission.
- (IBAction)testSubmission:(nullable id)sender;
@end

@interface XFDInstancePage : XFDInspectorPage
@property (nonatomic, strong) IBOutlet NSTextField *instanceSrcField;
- (IBAction)editInstanceXML:(nullable id)sender;
@end

/// An action's rows are made for the action selected, from its kind's
/// spec (XFDActionSpecs): `rows` is what is shown, each
/// {attr, kind, view}.
@interface XFDActionPage : XFDInspectorPage
@property (nonatomic, strong) IBOutlet NSView *actionRowsHost;
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *rows;
@end

@interface XFDItemPage : XFDInspectorPage
@property (nonatomic, strong) IBOutlet XFDRichTextField *itemLabelField;
@property (nonatomic, strong) IBOutlet NSTextField *itemValueField;
@end

@interface XFDItemsetPage : XFDInspectorPage
@property (nonatomic, strong) IBOutlet XFDXPathField *itemsetNodesetField;
@property (nonatomic, strong) IBOutlet XFDIDRefField *itemsetBindField;
@property (nonatomic, strong) IBOutlet XFDXPathField *itemsetLabelRefField;
@property (nonatomic, strong) IBOutlet XFDXPathField *itemsetValueRefField;
@end

/// Any other element; instance data offers a control bound to it.
@interface XFDElementPage : XFDInspectorPage
@property (nonatomic, strong) IBOutlet NSButton *hostNewControlButton;
/// A menu of control kinds; the one chosen made, bound to the selection.
- (IBAction)elementCreateBoundControl:(nullable id)sender;
/// A control of `kind` bound to the selected instance data.
- (void)createBoundControlOfKind:(NSString *)kind;
@end

NS_ASSUME_NONNULL_END
