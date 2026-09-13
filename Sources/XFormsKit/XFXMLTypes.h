#import <Foundation/Foundation.h>

/// The XML types the engine is written against.
///
/// Every engine source speaks one XML API, spelled XFXML*, and XFDOM —
/// the portable tree in Sources/XFormsKit/DOM — is what stands behind it
/// everywhere: macOS, GNUstep and iOS alike.
///
/// It used to be a build switch, defaulting to NSXML and selecting XFDOM
/// with XF_PORTABLE_DOM (mandatory on iOS, which has no NSXMLDocument).
/// Now that XFDOM passes every suite on all three platforms there is no
/// reason to keep a second tree alive: one implementation means one set
/// of behaviours to know, and it retires a gnustep-base NSXML bug the
/// engine used to have to work around.
///
/// These are @compatibility_alias declarations, not typedefs or macros:
/// the alias is a true class name, usable as a message receiver, in
/// [XFXMLElement class], and as a type, with no conversion at the seam.
///
/// The DOM's own sources and XFDOMTests never import this header — they
/// name XFDOM* directly. XFDOMTests still compares against the platform's
/// NSXML where there is one, as a reference for what a mature DOM does.

#import <XFormsKit/XFDOM.h>

@compatibility_alias XFXMLNode XFDOMNode;
@compatibility_alias XFXMLElement XFDOMElement;
@compatibility_alias XFXMLDocument XFDOMDocument;

typedef XFDOMNodeKind XFXMLNodeKind;
typedef XFDOMNodeOptions XFXMLNodeOptions;

#define XFXMLInvalidKind XFDOMInvalidKind
#define XFXMLDocumentKind XFDOMDocumentKind
#define XFXMLElementKind XFDOMElementKind
#define XFXMLAttributeKind XFDOMAttributeKind
#define XFXMLNamespaceKind XFDOMNamespaceKind
#define XFXMLProcessingInstructionKind XFDOMProcessingInstructionKind
#define XFXMLCommentKind XFDOMCommentKind
#define XFXMLTextKind XFDOMTextKind
#define XFXMLNodePreserveWhitespace XFDOMNodePreserveWhitespace
#define XFXMLNodeIsCDATA XFDOMNodeIsCDATA
#define XFXMLNodePrettyPrint XFDOMNodePrettyPrint


