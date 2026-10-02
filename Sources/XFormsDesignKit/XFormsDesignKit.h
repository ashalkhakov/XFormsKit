/* XFormsDesignKit -- the XForms designer's editor as a framework, for
   XFormsDesigner.app and for any app that edits forms of its own.

   The editor is a document: XFDDocument, an NSDocument whose window
   (XFDWindowController, from XFDDocumentWindow.xib in this framework)
   edits the XHTML+XForms text in place, with undo, a live preview and
   the inspectors. A host declares it as the class of its XForms document
   type (NSDocumentClass XFDDocument, extension xhtml), opens forms through
   its NSDocumentController as it opens its own documents, and adds
   +[XFDDocument formMenuItem] to its main menu.

   Like XFormsKit, the framework carries no headers: include them from
   Sources/XFormsDesignKit.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>
#import "XFDDocument.h"
#import "XFDWindowController.h"
