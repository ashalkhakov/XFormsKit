/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* The Action inspector page: rows generated from XFDActionSpecs() for the
   selected action element â built only when the element changes (a rebuild
   under a field currently sending its action would free it), filled from
   and applied to the element's attributes / inline content. */
#pragma once
#import <AppKit/AppKit.h>

@class XFDWindowController;

@interface XFDActionRowsPane : NSObject

@property (nonatomic, weak, readonly) XFDWindowController *controller;
/// The built rows: dicts { attr, kind, view }.
@property (nonatomic, copy, readonly) NSArray *rows;

- (instancetype)initWithController:(XFDWindowController *)controller host:(NSView *)host;
- (void)fillForElement:(NSXMLElement *)element;
- (void)applyToElement:(NSXMLElement *)element;

@end

void XFDActionRowsPaneFilePresent(void);
