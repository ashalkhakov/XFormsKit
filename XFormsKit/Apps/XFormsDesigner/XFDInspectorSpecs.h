/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* Shared designer catalogs: the Action page's per-action row specs, the
   element-kind sets the inspector routes on, the palette catalog, and the
   drawn badge icons — data used by the window controller, its panes, and
   the palette panel alike. */
#pragma once
#import <AppKit/AppKit.h>

/// The Action page's row specs, per action local name (XForms 1.1 Â§10
/// plus the XSLTForms show/hide pair); see the .m for the row keys.
NSDictionary *XFDActionSpecs(void);
/// Widget-bearing element kinds â the Control inspector page.
NSSet *XFDControlKinds(void);
/// Value-carrying kinds that need a binding to keep what the user types.
NSSet *XFDValueControlKinds(void);
/// A value control (or repeat) with no ref / nodeset / bind â the
/// preview will not keep what is typed into it.
BOOL XFDElementIsUnbound(NSXMLElement *element);
NSColor *XFDWarningColor(void);
/// The palette: every insertable tag with a one-line description.
NSArray *XFDPaletteCatalog(void);
/// Round badge for a tab bar / outline / palette row (the ModelBuilder
/// pattern â drawn, no image resources).
NSImage *XFDBadge(NSString *letters, CGFloat r, CGFloat g, CGFloat b);

void XFDInspectorSpecsFilePresent(void);
