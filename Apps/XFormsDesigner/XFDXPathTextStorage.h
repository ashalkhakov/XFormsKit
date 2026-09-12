/* XFDXPathTextStorage — text being edited as an XPath expression, which
   recolours itself as it is typed.

   Colouring belongs in the STORAGE rather than in a -textDidChange: or a
   pass over the field editor afterwards, because the storage is told
   about every change to the text — including the ones no delegate hears
   about, such as a paste from another pasteboard owner, an undo, or
   AppKit re-applying a control's own attributes. The previous approach
   set colours after the fact and lost them again whenever the field
   editor reset its typing attributes, which is why the expression stopped
   looking highlighted while it was being edited.

   Ported from RDLDesigner's RDLExpressionTextStorage; the tokens come
   from the engine's own lexer (+[XFXPath highlightTokensForString:]) so
   there is no second tokenizer to keep in step.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The colour one token kind is drawn in — the kinds
/// +[XFXPath highlightTokensForString:] reports.
FOUNDATION_EXPORT NSColor *XFDXPathTokenColor(NSString *kind);

/// The expression coloured, as a plain attributed string, for somewhere
/// that only DISPLAYS it — a table cell. Anywhere it can be EDITED uses
/// XFDExpressionField, whose storage recolours as the text changes.
FOUNDATION_EXPORT NSAttributedString *XFDXPathAttributedString(NSString *expression,
                                                               NSFont *_Nullable font);

@interface XFDXPathTextStorage : NSTextStorage

/// What the whole text starts from before token colours are laid over it.
@property (nonatomic, copy) NSDictionary<NSString *, id> *baseAttributes;
/// The expression does not compile: everything is drawn red and no token
/// colours are applied, which is the designer's existing signal.
@property (nonatomic, assign) BOOL invalid;

/// Takes over `view`'s layout manager and answers the storage now behind
/// it, or nil if the view would not give it up. Anything already in the
/// view is carried across.
+ (nullable instancetype)installedInTextView:(NSTextView *)view;

@end

NS_ASSUME_NONNULL_END
