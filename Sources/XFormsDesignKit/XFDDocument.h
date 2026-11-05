/* XFormsDesigner document: an XHTML+XForms file, read into a form
   editor (XFDFormEditor: the host document, its processor and the
   commands that change it, with this document's undo) and written back
   from it. Its window is XFDWindowController's. The live instance data
   is a COPY of the host's inline instances, so previewing a form never
   dirties the saved XML.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>
#import "XFDFormEditor.h"

@interface XFDDocument : NSDocument

/// The Form menu -- Insert Element, Delete Element, Reset Instance Data --
/// for an app that hosts the designer to put in its main menu: its items
/// go to the key window's designer through the responder chain.
+ (NSMenuItem *)formMenuItem;

/// The form, once read.
@property (nonatomic, strong, readonly) XFDFormEditor *formEditor;
/// Its processor and commands (the form editor's).
@property (nonatomic, strong, readonly) XFProcessor *processor;
@property (nonatomic, strong, readonly) XFHostEdit *hostEdit;

/// The document serialized for saving / the source tab (whitespace
/// markers stripped).
- (NSString *)hostXMLString;

/// Source tab commit: reparse and swap the projection. The undo stack is
/// cleared — a text edit has no in-place inverse.
- (BOOL)applySourceXML:(NSString *)xml error:(NSError **)error;

/// Rebuild the projection from the current host XML: fresh instance data.
/// Reparsing replaces every element object, so this too clears the undo
/// stack (undo invocations hold the old document's elements).
- (BOOL)resetPreview:(NSError **)error;

@end
