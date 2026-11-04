/* The form being edited, and the selection in it: what the designer's
   parts share. It holds the host document (the processor built from the
   XHTML+XForms text, and XFHostEdit, the commands that change it with
   undo), knows which element is selected, and tells every part when the
   selection moves, when the host changes and when the processor is
   replaced. It decides where an insert goes and makes it, and it gives
   the inspectors' fields what they evaluate against.

   Its parts are the outline, the preview, the inspectors, the library
   and the events console (XFDOutlineViewController…); XFDDocument has
   one for its file, XFDWindowController puts the parts in its window,
   and a host (an IDE) can put them in panes of its own, keeping the text
   as it likes: -replaceWithXMLString:error: reads it again, and
   -hostXMLString is what to write back.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFXMLTypes.h>

NS_ASSUME_NONNULL_BEGIN

@class XFDFormEditor;

/// What a part hears. Each is optional.
@protocol XFDFormEditorObserver <NSObject>
@optional
/// Another element is selected (or none).
- (void)formEditorSelectionDidChange:(XFDFormEditor *)editor;
/// The host document changed (any XFHostEdit command, undo and redo
/// included), at `element`.
- (void)formEditor:(XFDFormEditor *)editor hostDidChange:(nullable XFXMLElement *)element;
/// The processor was replaced (the text read again, the preview reset):
/// whatever refers to the old one's elements must be rebuilt.
- (void)formEditorProcessorWasReplaced:(XFDFormEditor *)editor;
@end

/// What the parts ask of whoever shows them.
@protocol XFDFormEditorDelegate <NSObject>
@optional
/// The Attributes inspector brought forward (the Events inspector's
/// double click on a handler).
- (void)formEditorShowAttributes:(XFDFormEditor *)editor;
/// The form read again from text the user wrote (the preview's Source
/// tab): a change of the document's, which no undo records.
- (void)formEditorDidApplySource:(XFDFormEditor *)editor;
@end

@interface XFDFormEditor : NSObject

/// The form read from `xml`; nil and why when it is no form. Relative
/// instance/@src, includes and schemas resolve against `baseURL`. Every
/// change is recorded on `undoManager`.
- (nullable instancetype)initWithXMLString:(NSString *)xml
                                   baseURL:(nullable NSURL *)baseURL
                               undoManager:(NSUndoManager *)undoManager
                                     error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, strong, readonly) XFProcessor *processor;
@property (nonatomic, strong, readonly) XFHostEdit *hostEdit;
@property (nonatomic, strong, readonly) NSUndoManager *undoManager;
@property (nonatomic, copy, nullable) NSURL *baseURL;
@property (nonatomic, weak, nullable) id<XFDFormEditorDelegate> delegate;

/// The host document as text (whitespace markers stripped), ending in a
/// newline: what is saved.
- (NSString *)hostXMLString;
/// The text read again: a new processor, the undo stack cleared (its
/// actions hold the old document's elements), the selection kept where
/// an element is at the same place. NO and why when it is no form; the
/// form stays as it was.
- (BOOL)replaceWithXMLString:(NSString *)xml error:(NSError **)error;
/// The preview's instance data fresh: the processor rebuilt from the
/// host as it is.
- (BOOL)resetPreview:(NSError **)error;
/// -replaceWithXMLString:error: for text the user wrote, the delegate
/// told (-formEditorDidApplySource:).
- (BOOL)applySourceXMLString:(NSString *)xml error:(NSError **)error;
/// The delegate asked to bring the Attributes inspector forward.
- (void)showAttributes;

/// Parts, held weakly.
- (void)addObserver:(id<XFDFormEditorObserver>)observer;
- (void)removeObserver:(id<XFDFormEditorObserver>)observer;

#pragma mark The selection

/// The selected host element, never a runtime control. Setting it tells
/// the observers.
@property (nonatomic, strong, nullable) XFXMLElement *selection;
/// The observers told again of the selection, as it is (after a change
/// that moved the element, say).
- (void)selectionMayHaveChanged;
/// Where an element is: the child-element indexes from the root; nil for
/// none. -elementAtPath: finds it in the document as it is now.
- (nullable NSArray<NSNumber *> *)pathOfElement:(nullable XFXMLElement *)element;
- (nullable XFXMLElement *)elementAtPath:(nullable NSArray<NSNumber *> *)path;

#pragma mark The document's structure

- (nullable XFXMLElement *)rootElement;
- (nullable XFXMLElement *)bodyElement;
/// Its element children (an outline row's).
- (NSArray<XFXMLElement *> *)elementChildrenOf:(XFXMLElement *)element;
/// The xf:instance an element lives in (itself, or an ancestor); nil.
- (nullable XFXMLElement *)instanceElementOf:(nullable XFXMLElement *)element;
/// The selection when it is instance data (inside an xf:instance, not the
/// instance itself); nil.
- (nullable XFXMLElement *)selectedInstanceDataNode;
/// The ref that reaches an instance-data node from a control's default
/// context: steps for the default instance, instance('id')/… for a named
/// one; nil when its instance cannot be addressed.
- (nullable NSString *)refForDataNode:(XFXMLElement *)node;

#pragma mark Inserting and deleting

/// Every element name that can go somewhere on the selection's ancestor
/// chain (what the library offers).
- (NSSet<NSString *> *)insertableNamesForSelection;
/// Where the + would insert: the selection when it takes children, else
/// its nearest ancestor that does, after the selection; the body when
/// nothing is selected. -1 appends.
- (nullable XFXMLElement *)insertParentForSelection:(nullable NSInteger *)index;
/// `name` inserted where it can go nearest the selection, and selected;
/// nil and why when it can go nowhere.
- (nullable XFXMLElement *)insertElementNamed:(NSString *)name error:(NSError **)error;
/// Whether the selection may be deleted (not the html, head, body, model).
- (BOOL)canDeleteSelection;
/// The selection deleted, its parent selected.
- (BOOL)deleteSelection;
/// An element moved (a drag in the preview), as one undoable change.
- (BOOL)moveElement:(XFXMLElement *)element underParent:(XFXMLElement *)parent atIndex:(NSInteger)index;
/// A new xf:bind made of the selected control's ref, the control bound
/// to it by id instead (one undoable change).
- (BOOL)createBindFromSelectedRef:(NSError **)error;
/// A control of `kind` at the end of the body, bound to the selected
/// instance-data node and labelled after it.
- (nullable XFXMLElement *)createControlOfKind:(NSString *)kind
                      boundToSelectedDataNode:(NSError **)error;

#pragma mark What the inspectors' fields evaluate against

/// The node an expression of the selection evaluates against: for a
/// bind's model item properties, its first node (its nodeset: the outer
/// bind's); for a control, the nearest bound ancestor's; else the default
/// instance's root.
- (nullable XFXMLNode *)contextNodeForSelectionNodeset:(BOOL)nodeset;
/// The node a control's label, hint, help and alert outputs evaluate
/// against: its own bound node, else its nearest bound ancestor's, else
/// the default instance's root.
- (nullable XFXMLNode *)contextNodeForSelectionContent;

@end

NS_ASSUME_NONNULL_END
