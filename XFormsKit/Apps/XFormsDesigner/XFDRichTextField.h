/* XFDRichTextField — the designer's entry component for label / hint /
   help / alert content. XForms 1.1 lets those hold more than a string:
   inline host-language markup plus dynamic content (`xf:output`, itext),
   e.g. `<xf:label>Enter your <strong>first</strong> name</xf:label>`.

   Plain text stays a plain text field, editable in place exactly as
   before. Rich content shows its flattened text with in-place editing
   off; the "…" button opens a modal editor with two views of the same
   fragment — Rich (XFRichTextEditor over the XFRichText subset:
   p / h1–h3 / ul / ol / li blocks, strong / em / u / s / br inline) and
   Source (the raw fragment XML, parse-checked before OK enables). A
   fragment using markup outside that subset — xf:output above all — is
   edited as source; the Rich view refuses to open on it rather than
   silently dropping what it cannot show. The host receives the
   target/action send after every committed change.

   The xib instantiates this as a customView with this customClass, like
   XFDXPathField.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>

@class XFDRichTextField;

/// Context for the "Insert Output…" token flow: the same node picker the
/// XPath fields run needs the processor / context node / host element.
/// Without a provider the rich editor still works — it just cannot insert
/// outputs.
@protocol XFDRichTextFieldProvider <NSObject>
- (NSXMLElement *)hostElementForRichTextField:(XFDRichTextField *)field;
- (XFProcessor *)processorForRichTextField:(XFDRichTextField *)field;
- (NSXMLNode *)contextNodeForRichTextField:(XFDRichTextField *)field;
@end

/// Fragment ↔ rich-view transforms (exposed for the selftest): a simple
/// dynamic output — `<xf:output value="…"/>`, that one attribute, no
/// children — appears in the rich editor as an atomic-looking token
/// `⟦expr⟧` (mail-merge style), and the brackets are the truth on the way
/// back. Everything else round-trips through XFRichText untouched.
FOUNDATION_EXPORT NSString *XFDTokenizeFragment(NSString *fragment);
FOUNDATION_EXPORT NSString *XFDEscapeXML(NSString *text);
FOUNDATION_EXPORT NSString *XFDDetokenizeFragment(NSString *fragment);

@interface XFDRichTextField : NSView

@property (nonatomic, weak) id<XFDRichTextFieldProvider> provider;
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;

/// Fill from the host document: `text` is the flattened string (what the
/// plain field shows), `xml` the support child's inner XML — nil or
/// markup-free means plain content and the field edits in place.
- (void)setPlainText:(NSString *)text xml:(NSString *)xml;

/// The current value as fragment XML when rich, nil when plain — the
/// caller applies xmlValue through setSupportChild:contentXML: or
/// stringValue through setSupportChild:text:.
- (NSString *)xmlValue;
@property (nonatomic, readonly, getter=isRich) BOOL rich;

/// Plain-mode accessors (NSTextField-compatible, so scripted callers can
/// treat this like the plain field it replaces).
- (NSString *)stringValue;
- (void)setStringValue:(NSString *)value;

- (void)setEnabled:(BOOL)enabled;

@end
