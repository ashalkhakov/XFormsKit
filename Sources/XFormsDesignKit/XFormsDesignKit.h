/* XFormsDesignKit -- the XForms designer's editor as a framework, for
   XFormsDesigner.app and for any app that edits forms of its own.

   The editor is a document: XFDDocument, an NSDocument whose window
   (XFDWindowController, from XFDDocumentWindow.xib in this framework)
   edits the XHTML+XForms text in place, with undo, a live preview and
   the inspectors. A host declares it as the class of its XForms document
   type (NSDocumentClass XFDDocument, extension xhtml), opens forms through
   its NSDocumentController as it opens its own documents, and adds
   +[XFDDocument formMenuItem] to its main menu.

   The window is made of parts, each a view controller of its own over a
   form editor (XFDFormEditor: the form, its undo, the selection): the
   outline, the preview, the Identity, Attributes and Events inspectors,
   the library and the events console. A host with panes of its own (an
   IDE) makes a form editor over its text and puts the parts in them.

   Its headers are installed with it, laid out as in
   Sources/XFormsDesignKit (ThirdParty/ too).
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>
#import "XFDFormEditor.h"
#import "XFDDocument.h"
#import "XFDWindowController.h"
#import "XFDOutlineViewController.h"
#import "XFDPreviewViewController.h"
#import "XFDInspectorViewController.h"
#import "XFDIdentityInspector.h"
#import "XFDAttributesInspector.h"
#import "XFDEventsInspector.h"
#import "XFDLibraryViewController.h"
#import "XFDEventsConsole.h"
