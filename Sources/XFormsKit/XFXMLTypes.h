#import <Foundation/Foundation.h>

/// The XML types the engine is written against.
///
/// Every engine source speaks one XML API, spelled XFXML*. Which
/// implementation stands behind it is a build switch:
///
///   default           NSXML — Apple Foundation or GNUstep base. The
///                     shipping macOS product and the two apps are
///                     unaffected: XFXMLElement *is* NSXMLElement, so
///                     app code that names NSXML types directly keeps
///                     compiling and behaviour is bit-for-bit unchanged.
///   XF_PORTABLE_DOM   XFDOM, the portable tree in Sources/XFormsKit/DOM.
///                     Mandatory on iOS, where NSXMLDocument /
///                     NSXMLElement / NSXMLNode do not exist.
///
/// These are @compatibility_alias declarations, not typedefs or macros:
/// the alias is a true class name, usable as a message receiver, in
/// [XFXMLElement class], and as a type, with no conversion at the seam.
///
/// The DOM's own sources and XFDOMTests never import this header — they
/// name XFDOM* directly, so the differential tests keep comparing the two
/// implementations in either configuration.

#if XF_PORTABLE_DOM

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

#else

@compatibility_alias XFXMLNode NSXMLNode;
@compatibility_alias XFXMLElement NSXMLElement;
@compatibility_alias XFXMLDocument NSXMLDocument;

typedef NSXMLNodeKind XFXMLNodeKind;
typedef NSUInteger XFXMLNodeOptions;

#define XFXMLInvalidKind NSXMLInvalidKind
#define XFXMLDocumentKind NSXMLDocumentKind
#define XFXMLElementKind NSXMLElementKind
#define XFXMLAttributeKind NSXMLAttributeKind
#define XFXMLNamespaceKind NSXMLNamespaceKind
#define XFXMLProcessingInstructionKind NSXMLProcessingInstructionKind
#define XFXMLCommentKind NSXMLCommentKind
#define XFXMLTextKind NSXMLTextKind
#define XFXMLNodePreserveWhitespace NSXMLNodePreserveWhitespace
#define XFXMLNodeIsCDATA NSXMLNodeIsCDATA

#endif
