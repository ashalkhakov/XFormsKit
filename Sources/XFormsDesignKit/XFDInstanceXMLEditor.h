/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/// Modal XML editor for instance data: paste or type the document, pull
/// an existing file in (Load File…), or Blankify it — clear every leaf
/// value and attribute so imported real data becomes the form's initial
/// data. OK requires well-formed XML with a single root.
#pragma once
#import <AppKit/AppKit.h>

@interface XFDInstanceXMLEditor : NSObject
+ (NSString *)runWithXML:(NSString *)xml title:(NSString *)title;
@end

void XFDInstanceXMLEditorFilePresent(void);
