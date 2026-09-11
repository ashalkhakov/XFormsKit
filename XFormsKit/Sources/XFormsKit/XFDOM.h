#import <Foundation/Foundation.h>

/// XFDOM — the portable XML tree XFormsKit runs on.
///
/// A clean-room implementation of the slice of the NSXML API the engine
/// actually uses, so that the same engine sources build against Apple
/// Foundation, GNUstep base, and iOS — where NSXMLDocument / NSXMLElement
/// / NSXMLNode do not exist at all (iOS Foundation ships NSXMLParser and
/// nothing else). See docs/ios-port-plan.md.
///
/// The API deliberately mirrors NSXML's spelling and semantics: the
/// engine's ~1,200 call sites are meant to move over by renaming the
/// class, not by rewriting the call. Where NSXML's behaviour is
/// under-specified (whitespace, escaping, empty-element form) the
/// reference is Apple's and GNUstep's observable behaviour, pinned by the
/// differential tests in Tests/XFormsKitTests/XFDOMTests.m.
///
/// Nodes are real Objective-C objects with stable identity: the engine
/// hangs per-node MIP state off them with objc_setAssociatedObject
/// (XFNodeState) and compares them with indexOfObjectIdenticalTo:, so a
/// node must never be re-wrapped or recreated behind the caller's back.

/// Mirrors NSXMLNodeKind, including its numeric values.
typedef NS_ENUM(NSUInteger, XFDOMNodeKind) {
    XFDOMInvalidKind = 0,
    XFDOMDocumentKind = 1,
    XFDOMElementKind = 2,
    XFDOMAttributeKind = 3,
    XFDOMNamespaceKind = 4,
    XFDOMProcessingInstructionKind = 5,
    XFDOMCommentKind = 6,
    XFDOMTextKind = 7,
};

/// The subset of NSXMLNodeOptions the engine passes.
typedef NS_OPTIONS(NSUInteger, XFDOMNodeOptions) {
    XFDOMNodeOptionsNone = 0,
    /// Keep whitespace-only text nodes that the default parse drops.
    XFDOMNodePreserveWhitespace = 1 << 0,
    /// Serialise this text node as a CDATA section.
    XFDOMNodeIsCDATA = 1 << 1,
};

FOUNDATION_EXPORT NSString *const XFDOMErrorDomain;

#import <XFormsKit/XFDOMNode.h>
#import <XFormsKit/XFDOMElement.h>
#import <XFormsKit/XFDOMDocument.h>
