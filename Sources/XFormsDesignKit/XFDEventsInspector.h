/* The Events inspector (XFDEventsInspector.xib). XForms actions are
   supplementary: a handler observes the ELEMENT IT SITS IN (the XML
   Events attribute module: the observer defaults to the parent of the
   element bearing ev:event), or the one its ev:observer names. This
   makes that visible: a table of the handlers listening on the
   selection, + to add one of the actions it takes, − to delete the one
   chosen, and a double click to go to a handler's own page in the
   Attributes inspector.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import "XFDPartViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface XFDEventsInspector : XFDPartViewController <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *plusMinusControl;
@property (nonatomic, strong) IBOutlet NSTextField *noteField;

/// The selection's listening handlers, as shown (document order).
@property (nonatomic, copy, readonly) NSArray<XFXMLElement *> *handlerElements;

- (IBAction)plusMinusClicked:(nullable id)sender;
- (IBAction)rowDoubleClicked:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
