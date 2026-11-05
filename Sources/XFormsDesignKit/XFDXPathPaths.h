/* What the XPath components know about paths, shared between them: the
   location-path step model, the schema's suggestions, events' context
   properties (XFDXPathField.h declares those, the kit's API), and the
   axes and a node's display path, which are the kit's own.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import "XFDXPathField.h"

/// Known axes, in the steps-table popup order.
NSArray *XFDKnownAxes(void);
/// A node as the picker and the predicate editor show it: /root/a[2]/@b.
NSString *XFDDisplayPathOfNode(XFXMLNode *node);
