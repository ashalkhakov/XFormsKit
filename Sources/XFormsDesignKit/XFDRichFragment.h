/* Rich content fragments, shared by the rich text field and its panel:
   parsed with the label vocabulary, told whether the rich view can show
   them, and their outputs turned into tokens and back (XFDRichTextField.h
   declares those, the kit's API).
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import "XFDRichTextField.h"

/// An output token's brackets: ⟦expr⟧.
extern NSString * const XFDTokenOpen;
extern NSString * const XFDTokenClose;
/// `fragment` parsed with XHTML as the default namespace and xf: for
/// XForms; nil when it does not parse.
XFXMLElement *XFDParseFragment(NSString *fragment, NSError **error);
/// Whether the rich view can show all of `fragment`.
BOOL XFDFragmentIsRichEditable(NSString *fragment);
/// A lone <p>…</p> unwrapped to its content.
NSString *XFDUnwrapSingleParagraph(NSString *html);
