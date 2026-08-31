/* XFormsDesigner document — the host NSXMLDocument is the document; the
   XFProcessor is a rebuildable projection of it. Authoring goes through
   XFHostEdit (insert / delete / attribute / support-child commands with
   undo and in-place processor notification); the full-reload path exists
   only for the source tab and for opening. The live instance data is a
   COPY of the host's inline instances, so previewing a form never dirties
   the saved XML.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>

@interface XFDDocument : NSDocument

/// The projection: rebuilt only by open / applySourceXML / resetPreview.
@property (nonatomic, strong, readonly) XFProcessor *processor;
/// The command layer bound to `processor` and this document's undo manager.
@property (nonatomic, strong, readonly) XFHostEdit *hostEdit;
/// Forwarded from XFHostEdit after every mutation, undo and redo included.
@property (nonatomic, copy) void (^hostChangedHandler)(NSXMLElement *element);
/// Called after the processor was REPLACED (source apply / preview reset):
/// everything referencing the old processor must be rebuilt.
@property (nonatomic, copy) void (^processorReplacedHandler)(void);

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
