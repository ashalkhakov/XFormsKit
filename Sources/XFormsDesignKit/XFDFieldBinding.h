/* The value and enabled bindings of the designer's own fields
   (XFDXPathField, XFDIDRefField, XFDRichTextField), which are views, not
   controls, so AppKit binds them only as far as KVC goes. A field binds
   as a control does (Cocoa Bindings Programming Topics, "How Do Bindings
   Work?"): it shows the bound key's value as it changes, and gives its
   edited value to the bound object when its editing ends, validated first
   (-validateValue:forKeyPath:error:) when the binding has
   NSValidatesImmediately. A refused value's error is presented by the
   field, which keeps its text for the author to correct.

   A field holds one XFDFieldBinding per binding, from its
   -bind:toObject:withKeyPath:options: (XIB connections included), and
   answers -infoForBinding: from it. Its -commitEditing (NSEditor) gives
   the bound object what it shows.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// What a bindable field does with a bound value.
@protocol XFDBindableField <NSObject>
/// The bound value shown (NSValueBinding).
- (void)setBoundValue:(nullable id)value;
- (void)setEnabled:(BOOL)enabled;
@end

@interface XFDFieldBinding : NSObject

/// `field`'s `binding` (NSValueBinding or NSEnabledBinding) to `keyPath`
/// of `object`, the field given the value now and on every change.
- (instancetype)initWithField:(NSView<XFDBindableField> *)field
                      binding:(NSString *)binding
                     toObject:(id)object
                  withKeyPath:(NSString *)keyPath
                      options:(nullable NSDictionary *)options;

/// -infoForBinding:'s answer.
@property (nonatomic, readonly) NSDictionary *info;

/// The field's edited value given to the bound object: validated first
/// when the binding asks, a validator's replacement shown. NO when
/// refused, the error presented by the field; YES, and nothing set, when
/// it is the bound value already.
- (BOOL)commitValue:(nullable id)value;

/// Observation stopped (-unbind:, the field's dealloc).
- (void)invalidate;

@end

/// The bindings a field holds, by name: -bind:..., -unbind: and
/// -infoForBinding: for a field that keeps them in `bindings`.
BOOL XFDFieldBind(NSView<XFDBindableField> *field, NSMutableDictionary *bindings,
                  NSString *binding, id object, NSString *keyPath,
                  NSDictionary *_Nullable options);
BOOL XFDFieldUnbind(NSMutableDictionary *bindings, NSString *binding);

NS_ASSUME_NONNULL_END
