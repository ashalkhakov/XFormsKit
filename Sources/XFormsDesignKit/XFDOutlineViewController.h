/* The form's outline (XFDOutlineViewController.xib): the host document's
   elements as a tree, its row the form editor's selection, and the + and
   − under it (+ asks the palette what to insert where the selection is;
   − deletes the selection). A double click on instance data edits it as
   XML.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import "XFDPartViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface XFDOutlineViewController : XFDPartViewController <NSOutlineViewDataSource, NSOutlineViewDelegate>

@property (nonatomic, strong) IBOutlet NSOutlineView *outline;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *plusMinusControl;

/// A row's text: the element's name, its label, ref or id, and whether it
/// is unbound.
- (NSString *)titleOfElement:(XFXMLElement *)element;

- (IBAction)plusMinusClicked:(nullable id)sender;
/// The palette, then what was chosen inserted.
- (IBAction)insertElement:(nullable id)sender;
- (IBAction)deleteElement:(nullable id)sender;
/// The selection's instance data edited as XML.
- (IBAction)editInstanceXML:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
