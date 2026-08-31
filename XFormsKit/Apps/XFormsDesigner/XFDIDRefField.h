/* XFDIDRefField — the designer's entry component for IDREF attributes: a
   combo box whose dropdown lists the LIVE ids of one kind of element,
   while the field still takes a quickly typed id. XForms 1.1 references
   elements by id all over: @bind and @model on binding elements (§3.2.3),
   @instance on submission for replace="instance" (§11.2), @submission on
   xf:submit / xf:send, and — for the action inspectors to come —
   toggle/@case, setindex/@repeat, setfocus/@control. One widget serves
   them all, parameterized by the referenced element's local name.

   Validation mirrors XFDXPathField: a value naming no live id turns red
   with a tooltip but is still accepted — the author may be about to
   create the target. The dropdown repopulates from the processor's host
   document every time it opens, so it is always current.

   The xib instantiates this as a customView with this customClass; the
   controller assigns each row's `kind`.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>

@class XFDIDRefField;

@protocol XFDIDRefFieldProvider <NSObject>
/// The processor whose host document supplies the live ids.
- (XFProcessor *)processorForIDRefField:(XFDIDRefField *)field;
@end

@interface XFDIDRefField : NSView

@property (nonatomic, weak) id<XFDIDRefFieldProvider> provider;
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;

/// Local name of the referenced element kind ("bind", "model",
/// "instance", "submission", "case", "repeat"), or a pseudo-kind:
/// "#control" = focusable form controls (setfocus), "*" = any element
/// with an id (dispatch targets), "#event" = common event names offered
/// as suggestions with validation off (custom events are legitimate).
/// Set once at wiring time.
@property (nonatomic, copy) NSString *kind;

/// The id text. Setting repopulates the dropdown and revalidates.
@property (nonatomic, copy) NSString *stringValue;
/// NO when the current text names no live id of `kind`.
@property (nonatomic, readonly, getter=isValid) BOOL valid;

- (void)setEnabled:(BOOL)enabled;
- (void)validate;

/// Every non-empty @id on a `kind` element in the host document, in
/// document order (also the existence check the binding status line uses).
+ (NSArray<NSString *> *)identifiersOfKind:(NSString *)kind
                               inProcessor:(XFProcessor *)processor;

@end
