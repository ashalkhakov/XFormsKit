/* XFDExpressionField — a one-line XPath entry that is ALWAYS syntax
   highlighted, the way a code editor's is.

   An NSTextField cannot be: the text it shows is drawn by its cell, and
   while it is being edited the text lives in the window's shared field
   editor. Highlighting it meant colouring the value for the idle case and
   the field editor's storage for the editing case — two paths, one of
   which AppKit could overwrite at will. The colours came and went.

   So this is an NSTextView backed by XFDXPathTextStorage, which recolours
   itself on every change, wrapped to look and behave like the small field
   it replaces: `fieldEditor = YES` gives Return and Tab their field
   meanings, and the control re-posts NSControl's editing notifications so
   existing -controlTextDidChange: / -controlTextDidEndEditing: delegates
   keep working unchanged.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface XFDExpressionField : NSView

/// The expression. Setting it recolours.
@property (nonatomic, copy) NSString *stringValue;
/// Does not compile: drawn red, no token colours. The designer's signal.
@property (nonatomic, assign) BOOL invalid;
/// Shown, dimmed, while the expression is empty.
@property (nonatomic, copy, nullable) NSString *placeholderString;
/// Sent -controlTextDidChange: and -controlTextDidEndEditing: with this
/// control as the notification object, like an NSTextField would.
@property (nonatomic, weak, nullable) id delegate;
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, assign, nullable) SEL action;

- (void)setEnabled:(BOOL)enabled;
- (void)setFont:(nullable NSFont *)font;

@end

NS_ASSUME_NONNULL_END
