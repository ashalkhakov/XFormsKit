/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/// Modal XML editor for instance data: paste or type the document, pull
/// an existing file in (Load File…), or Blankify it — clear every leaf
/// value and attribute so imported real data becomes the form's initial
/// data. OK requires well-formed XML with a single root.
#pragma once
#import <AppKit/AppKit.h>
#import "XFDFormEditor.h"

@interface XFDInstanceXMLEditor : NSObject
+ (NSString *)runWithXML:(NSString *)xml title:(NSString *)title;
/// The data of the xf:instance `element` is in (or is) edited, and that
/// instance selected; NO when there is none, the editor was cancelled,
/// or (with why) the XML could not be set.
+ (BOOL)editInstanceOfElement:(XFXMLElement *)element
                 inFormEditor:(XFDFormEditor *)formEditor
                        error:(NSError **)error;
@end
