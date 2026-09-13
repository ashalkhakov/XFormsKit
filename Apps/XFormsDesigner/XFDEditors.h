/* Editing view-models for the designer inspector — one per selection
   kind (the ModelBuilder pattern). Each wraps (host XFXMLElement +
   XFDDocument) and exposes plain KVC properties whose setters write host
   XML through XFHostEdit: every set is undoable and notifies the
   processor in place. The window controller copies control values in and
   out; nothing here touches a view.

   The selection IS the host element, never a runtime XFControl — repeat
   templates vs item clones would fight an inspector bound to a control.
   Elements are mutated in place, so holding the element keeps an editor
   valid across renames and undo round trips.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFDDocument;

@interface XFDElementEditor : NSObject

+ (instancetype)editorForElement:(XFXMLElement *)element document:(XFDDocument *)document;

@property (nonatomic, strong, readonly) XFXMLElement *element;
@property (nonatomic, strong, readonly) XFDDocument *document;

/// "xf:input — input-3" (the inspector's title line).
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy) NSString *identifier;          /* @id */

/* Support children (empty removes the child). The *Text properties are
   the flattened strings; the *XML properties carry the child's inner XML
   for rich XForms 1.1 content (inline markup + xf:output) — nil when the
   child is absent, and a set that does not parse is dropped silently
   (the rich field component validates before applying). */
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

@end

/* ---------------------------------------------------------------- */

@interface XFDControlEditor : XFDElementEditor
@property (nonatomic, copy) NSString *ref;
@property (nonatomic, copy) NSString *valueExpression;     /* @value (xf:output only) */
@property (nonatomic, copy) NSString *bind;                /* IDREF → xf:bind */
@property (nonatomic, copy) NSString *model;               /* IDREF → xf:model */
@property (nonatomic, copy) NSString *submission;          /* IDREF → xf:submission (xf:submit) */
@property (nonatomic, copy) NSString *appearance;          /* empty = default */
@property (nonatomic, assign, getter=isIncremental) BOOL incremental;
@property (nonatomic, copy) NSString *mediatype;
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
