/* Editing view-models for the designer inspector — one per selection
   kind (the ModelBuilder pattern). Each wraps (host XFXMLElement +
   XFDFormEditor) and exposes KVC/KVO-compliant properties whose setters
   write host XML through XFHostEdit: every set is undoable and notifies
   the processor in place. The inspectors bind their fields to them
   (through an NSObjectController in each XIB); nothing here touches a
   view.

   They are the model layer's gate: what a field gives is validated
   here, by key-value validation (-validateValue:forKey:error:, which a
   binding with NSValidatesImmediately calls): an XPath must compile, an
   id must be an unused NCName, rich content must parse. A setter given
   an unvalidated value still writes it.

   The element can change under an editor (an undo, the source applied,
   another inspector's edit): -reload tells its observers that every
   property may have changed.

   The selection IS the host element, never a runtime XFControl — repeat
   templates vs item clones would fight an inspector bound to a control.
   Elements are mutated in place, so holding the element keeps an editor
   valid across renames and undo round trips.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>

/* XFormsDesignKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef XFORMSDESIGNKIT_EXPORT
#define XFORMSDESIGNKIT_EXPORT FOUNDATION_EXPORT
#endif

@class XFDFormEditor, NSColor;

/// The domain of the editors' validation errors.
XFORMSDESIGNKIT_EXPORT NSString *const XFDEditorErrorDomain;

@interface XFDElementEditor : NSObject

/// The editor for `element`'s kind: XFDControlEditor for a control,
/// XFDBindEditor for a bind, and so on; XFDElementEditor for any other.
+ (instancetype)editorForElement:(XFXMLElement *)element formEditor:(XFDFormEditor *)formEditor;

@property (nonatomic, strong, readonly) XFXMLElement *element;
@property (nonatomic, strong, readonly) XFDFormEditor *formEditor;

/// Every property's observers told it may have changed: the element was
/// changed by something else than this editor.
- (void)reload;

/// Whether it is instance data a control can be bound to (the
/// selection's, as XFDFormEditor -createControlOfKind:... takes it).
@property (nonatomic, readonly) BOOL takesBoundControl;

/// "xf:input — input-3" (the inspector's title line).
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy) NSString *identifier;          /* @id: an unused NCName */

/* Support children. The *Content properties are the child's inner XML,
   plain text escaped (what a rich text field shows and gives); empty
   when the child is absent, and set empty removes it. The *Text
   properties are the flattened strings (empty removes the child); the
   *XML ones the inner XML, nil when the child is absent. */
@property (nonatomic, copy) NSString *labelContent;
@property (nonatomic, copy) NSString *hintContent;
@property (nonatomic, copy) NSString *helpContent;
@property (nonatomic, copy) NSString *alertContent;
@property (nonatomic, copy) NSString *labelText;
@property (nonatomic, copy) NSString *hintText;
@property (nonatomic, copy) NSString *helpText;
@property (nonatomic, copy) NSString *alertText;
@property (nonatomic, copy) NSString *labelXML;
@property (nonatomic, copy) NSString *hintXML;
@property (nonatomic, copy) NSString *helpXML;
@property (nonatomic, copy) NSString *alertXML;

/* Generic attribute / support-child access for subclasses. */
- (NSString *)attribute:(NSString *)name;
- (void)setAttribute:(NSString *)name value:(NSString *)value;
- (NSString *)supportText:(NSString *)name;
- (void)setSupportText:(NSString *)name to:(NSString *)text;
- (NSString *)supportContent:(NSString *)name;
- (void)setSupportContent:(NSString *)name to:(NSString *)content;

/// The keys whose values are XPath expressions, validated by compiling
/// them against the element.
+ (NSSet<NSString *> *)expressionKeys;
/// `expression` compiled against the element; NO and why when it does not.
- (BOOL)validateExpression:(NSString *)expression error:(NSError **)error;
/// `content` parsed as a support child's or element's content.
- (BOOL)validateContent:(NSString *)content error:(NSError **)error;

@end

/* ---------------------------------------------------------------- */

@interface XFDControlEditor : XFDElementEditor
@property (nonatomic, copy) NSString *ref;
@property (nonatomic, copy) NSString *valueExpression;     /* @value (xf:output only; empty elsewhere) */
@property (nonatomic, copy) NSString *bind;                /* IDREF → xf:bind */
@property (nonatomic, copy) NSString *model;               /* IDREF → xf:model */
@property (nonatomic, copy) NSString *submission;          /* IDREF → xf:submission (xf:submit only; empty elsewhere) */
@property (nonatomic, copy) NSString *appearance;          /* empty = default */
/// The appearance as its pop-up's item: "(default)" for none.
@property (nonatomic, copy) NSString *appearanceTitle;
@property (nonatomic, assign, getter=isIncremental) BOOL incremental;
@property (nonatomic, copy) NSString *mediatype;

/// What the control takes: @value (an output), @submission (a submit),
/// and whether its ref selects a node-set (a repeat) or one node.
@property (nonatomic, readonly) BOOL takesValueExpression;
@property (nonatomic, readonly) BOOL takesSubmission;
@property (nonatomic, readonly) BOOL refSelectsNodeSet;
/// How the control is bound, in a line, and that line's colour (a
/// missing bind or an unbound value control is a warning).
@property (nonatomic, copy, readonly) NSString *bindingStatus;
@property (nonatomic, strong, readonly) NSColor *bindingStatusColor;
/// Whether its ref can become a named bind (Create Bind).
@property (nonatomic, readonly) BOOL canCreateBind;
@end

@interface XFDBindEditor : XFDElementEditor
@property (nonatomic, copy) NSString *nodeset;             /* @nodeset, falling back to @ref */
@property (nonatomic, copy) NSString *typeName;            /* @type */
@property (nonatomic, copy) NSString *calculate;
@property (nonatomic, copy) NSString *constraint;
@property (nonatomic, copy) NSString *required;
@property (nonatomic, copy) NSString *relevant;
@property (nonatomic, copy) NSString *readonly;
@end

@interface XFDSubmissionEditor : XFDElementEditor
@property (nonatomic, copy) NSString *resource;            /* @resource, falling back to @action */
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *replace;             /* empty = none */
/// The replacement as its pop-up's item: "none" for none.
@property (nonatomic, copy) NSString *replaceTitle;
@property (nonatomic, copy) NSString *instance;            /* IDREF → xf:instance (replace="instance") */
@property (nonatomic, copy) NSString *ref;
@property (nonatomic, copy) NSString *bind;                /* IDREF → xf:bind */
@end

@interface XFDInstanceEditor : XFDElementEditor
@property (nonatomic, copy) NSString *src;
@end

@interface XFDItemEditor : XFDElementEditor
@property (nonatomic, copy) NSString *valueText;           /* xf:value child text */
@end

@interface XFDItemsetEditor : XFDElementEditor
@property (nonatomic, copy) NSString *nodeset;             /* @nodeset, falling back to @ref */
@property (nonatomic, copy) NSString *bind;                /* IDREF → xf:bind */
@property (nonatomic, copy) NSString *labelRef;            /* xf:label/@ref */
@property (nonatomic, copy) NSString *valueRef;            /* xf:value/@ref */
@end

/// An action (XForms 1.1 §10): its rows are XFDActionCommonSpecs()' and
/// its kind's XFDActionSpecs(), and `attributes` is each row's value by
/// its attribute name — `attributes.ev:event`, `attributes.if` — read,
/// set and validated by the row's kind (an XPath compiles; a pop-up's
/// first option is the attribute removed). A content row's value is
/// `inlineContent`.
@interface XFDActionEditor : XFDElementEditor
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *rows;
@property (nonatomic, strong, readonly) id attributes;
@property (nonatomic, copy) NSString *inlineContent;
@end
