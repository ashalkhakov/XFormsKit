/* The Attributes inspector's page for an action (XForms 1.1 §10). Its
   rows are the action's (XFDActionEditor -rows): each a row of its kind
   from XFDActionRow.xib (an XPath, an IDREF, a pop-up, a plain field, or
   inline content), its label, tip and pop-up items the row's, its field
   bound to the editor controller's `content.attributes.<attr>` (content:
   `content.inlineContent`). They are made again only when the action
   changes.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import "XFDInspectorPages.h"

NS_ASSUME_NONNULL_BEGIN

/// One row of XFDActionRow.xib's, of each kind: the nib's owner while it
/// loads.
@interface XFDActionRowTemplate : NSObject
@property (nonatomic, strong) IBOutlet NSView *xpathRow;
@property (nonatomic, strong) IBOutlet NSTextField *xpathLabel;
@property (nonatomic, strong) IBOutlet XFDXPathField *xpathField;
@property (nonatomic, strong) IBOutlet NSView *idrefRow;
@property (nonatomic, strong) IBOutlet NSTextField *idrefLabel;
@property (nonatomic, strong) IBOutlet XFDIDRefField *idrefField;
@property (nonatomic, strong) IBOutlet NSView *contentRow;
@property (nonatomic, strong) IBOutlet NSTextField *contentLabel;
@property (nonatomic, strong) IBOutlet XFDRichTextField *contentField;
@property (nonatomic, strong) IBOutlet NSView *popupRow;
@property (nonatomic, strong) IBOutlet NSTextField *popupLabel;
@property (nonatomic, strong) IBOutlet NSPopUpButton *popupField;
@property (nonatomic, strong) IBOutlet NSView *fieldRow;
@property (nonatomic, strong) IBOutlet NSTextField *fieldLabel;
@property (nonatomic, strong) IBOutlet NSTextField *fieldField;
@end

@interface XFDActionPage : XFDInspectorPage
@property (nonatomic, strong) IBOutlet NSView *actionRowsHost;
/// What is shown: each row's {attr, kind, view (its field)}.
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *rows;
@end

NS_ASSUME_NONNULL_END
