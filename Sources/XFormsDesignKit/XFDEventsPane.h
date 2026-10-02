/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/// XForms actions are supplementary: a handler observes the ELEMENT IT
/// SITS IN (XML Events attribute module — the observer defaults to the
/// parent of the element bearing ev:event). The Events group makes that
/// visible: a table of the selection's direct child actions, with + / −
/// and double-click to jump into a handler's own inspector.
#pragma once
#import <AppKit/AppKit.h>

@class XFDWindowController;

@interface XFDEventsPane : NSObject <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, weak, readonly) XFDWindowController *controller;
/// The selection's listening handlers, as shown (document order).
@property (nonatomic, copy, readonly) NSArray *handlerElements;
@property (nonatomic, strong, readonly) NSTableView *table;

/// Builds the whole group (note, handler table, + / â) inside `host`.
- (instancetype)initWithController:(XFDWindowController *)controller host:(NSView *)host;
/// Refill for the controller's current selection.
- (void)reload;

@end

void XFDEventsPaneFilePresent(void);
