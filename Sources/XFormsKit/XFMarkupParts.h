/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFBinding, XFExprContext;

NS_ASSUME_NONNULL_BEGIN

/// One `xf:output` met inside host markup, kept unevaluated so the text it
/// contributes is recomputed on every refresh like any other bound value.
@interface XFMarkupOutput : NSObject
@property (nonatomic, strong) XFBinding *binding;
/// `mediatype="application/xhtml+xml"`: the value IS markup and is spliced
/// verbatim. Otherwise it is text and is escaped on the way in, so a value
/// holding "<" cannot turn into a tag.
@property (nonatomic, assign) BOOL rawMarkup;
@end

/// The XHTML inside an `xf:label` / `hint` / `help` / `alert` / `message`,
/// as a part list: `NSString` literals of markup and `XFMarkupOutput` holes.
///
/// XForms 1.1 gives all five the same content model — text, inline host
/// markup, AND `xf:output` (9.3.1) — so the markup a host displays cannot
/// be snapshotted at load: `<xf:hint>Must exceed <b><xf:output
/// ref="min"/></b></xf:hint>` has to re-render whenever `min` changes. This
/// is the label's own literal/binding split (`-collectLabelPartsOf:into:`)
/// carried over to markup, and it is deliberately the same two-step shape:
/// split once at load, join per refresh.
///
/// Elements are re-serialized rather than copied through `-XMLString` so
/// the outputs can be cut out of the middle of a subtree. Only the LOCAL
/// name is written: a fragment naming `html:b` would not parse on its own
/// without the prefix binding, and every consumer (XFRichText) matches on
/// local names anyway.
@interface XFMarkupParts : NSObject

/// The parts of `element`, or nil when it holds no formatting markup —
/// plain text, or text and outputs only, which the plain-text path that
/// every caller already has covers exactly.
+ (nullable NSArray *)partsOfElement:(nullable XFXMLElement *)element;

/// The same split for PLAIN text: literals are the text as written
/// (unescaped, tags dropped) and the holes are the same outputs. Always
/// non-nil for a non-nil element, because every support child has text —
/// `xf:hint`, `xf:alert` and friends take xf:output whether or not they
/// also carry formatting, and flattening the element with
/// `-stringValueOfNode:` would silently drop those values.
+ (nullable NSArray *)textPartsOfElement:(nullable XFXMLElement *)element;

/// Does joining these need a context (is any part an output)?
+ (BOOL)partsAreDynamic:(nullable NSArray *)parts;

/// The markup, with each output evaluated in `context` (a nil context
/// yields empty outputs — the pre-refresh state).
+ (nullable NSString *)markupFromParts:(nullable NSArray *)parts
                               context:(nullable XFExprContext *)context;

/// The joined plain text of `textPartsOfElement:` parts.
+ (nullable NSString *)textFromParts:(nullable NSArray *)parts
                             context:(nullable XFExprContext *)context;

@end

NS_ASSUME_NONNULL_END
