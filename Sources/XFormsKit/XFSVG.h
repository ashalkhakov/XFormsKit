#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>
#import <CoreGraphics/CoreGraphics.h>
#if __has_include(<AppKit/AppKit.h>)
#import <AppKit/AppKit.h>
#endif

@class XFHostNode;
@class XFProcessor;

NS_ASSUME_NONNULL_BEGIN

/// SVG Tiny rendering over the host DOM — G-20 phase 3. XSLTForms keeps
/// SVG elements in the live document and lets the browser draw them,
/// with AVTs ({expr} attributes) and nested xf:repeat / xf:output
/// providing the dynamic parts (piechart, gantt, flags samples). The
/// XFormsKit port keeps the same source of truth — the NSXML host DOM,
/// reached through the XFHostNode tree so per-repeat-item instantiation
/// comes for free — and renders with NSBezierPath / NSAffineTransform,
/// which GNUstep libs-gui implements Apple-compatibly. The path-data
/// scanner and arc-to-bezier conversion follow the SVG 1.1 grammar
/// (spec appendix F.6), with NanoSVG (zlib license) consulted as the
/// reference implementation shape.
///
/// Supported subset (the Tiny profile the samples exercise): svg (width /
/// height with px|mm|cm|in|pt|pc units, viewBox), g, path, rect, circle,
/// ellipse, line, polyline, polygon, text (font-size, font-weight,
/// text-anchor; content gathered from the host tree, xf:output values
/// included), defs / use (href / xlink:href, x / y, cycle-guarded) and
/// the paint servers: linearGradient / radialGradient (stops with
/// offset / stop-color / stop-opacity, gradientUnits objectBoundingBox
/// or userSpaceOnUse, gradientTransform; drawn with NSGradient inside
/// the shape's clip) and pattern (its content tiled over the shape;
/// patternUnits both ways). Presentation attributes and the style=""
/// attribute (style wins): fill, stroke, stroke-width, stroke-linecap,
/// stroke-linejoin, fill-rule, opacity, fill-opacity, stroke-opacity;
/// colors as #rgb / #rrggbb / rgb(…) / common names / none; a url(#…)
/// that resolves to nothing degrades to a neutral gray; a gradient
/// stroke uses its first stop's color. title / desc / metadata /
/// clipPath / mask / marker subtrees are skipped. Every attribute goes
/// through XFAVT first, evaluated in the element's in-scope context
/// (repeat items give their node and position(); bound groups their
/// bound node).

/// One resolved element of the render tree: attributes have their AVTs
/// evaluated, `text` elements carry their gathered content.
@interface XFSVGNode : NSObject
@property (nonatomic, copy) NSString *tag;
@property (nonatomic, strong, nullable) XFXMLElement *element;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *attributes;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy) NSArray<XFSVGNode *> *children;
@end

/// The render tree for one <svg> host node, plus the drawing.
@interface XFSVGDocument : NSObject

/// Builds the tree: walks `hostNode` (kind SVG), resolving AVTs against
/// `contextNode` (nil = the default instance root), descending into
/// xf:repeat items / bound groups / selected switch cases, gathering
/// text content (output values included) for <text>.
+ (instancetype)documentWithHostNode:(XFHostNode *)hostNode
                           processor:(XFProcessor *)processor
                         contextNode:(nullable XFXMLNode *)contextNode;

@property (nonatomic, strong, readonly) XFSVGNode *root;
/// The viewport in points: width/height attributes (units converted),
/// else the viewBox size, else the SVG default 300×150.
@property (nonatomic, assign, readonly) CGSize size;

/// Draws into `ctx`, which must use SVG's own orientation: y growing
/// downwards, as a flipped NSView or a UIView gives. `rect`'s size scales
/// the viewport; content outside is clipped.
- (void)drawInContext:(CGContextRef)ctx rect:(CGRect)rect;

/// The node registered under this id (defs content, paint servers, any
/// element with an id) — what url(#…) and use href resolve to.
- (nullable XFSVGNode *)nodeForIdentifier:(NSString *)identifier;

/// The topmost painted shape or text at `point` (document coordinates —
/// the box `size` spans). Content reached through <use> reports the use
/// node. nil over empty space.
- (nullable XFSVGNode *)nodeAtPoint:(CGPoint)point;

/// The union of the painted rectangles of every render node whose host
/// element is `element` (a repeat template element matches once per
/// item), in document coordinates. CGRectZero when it paints nothing.
- (CGRect)frameOfElement:(XFXMLElement *)element;

/* Parsing utilities (exposed for tests).

   The two that answer CoreFoundation objects return them OWNED: the
   caller releases. CFAutorelease would be simpler, but CoreFoundation is
   optional where GNUstep draws through Opal. */
+ (nullable CGPathRef)createPathWithSVGPathData:(NSString *)d CF_RETURNS_RETAINED;
+ (CGAffineTransform)transformWithSVGString:(nullable NSString *)s;
+ (nullable CGColorRef)createColorWithSVGString:(nullable NSString *)s CF_RETURNS_RETAINED;
+ (NSDictionary<NSString *, NSString *> *)declarationsWithSVGStyle:(nullable NSString *)css;
+ (CGFloat)lengthWithSVGString:(nullable NSString *)s fallback:(CGFloat)fallback;

@end

#if __has_include(<AppKit/AppKit.h>)

/// The widget XFFormView places for a XFHostNodeKindSVG node. `rebuild`
/// re-resolves the render tree (fresh AVT and output values) and resizes
/// to the document; the form view calls it from its refresh paths.
@interface XFSVGView : NSView

- (instancetype)initWithHostNode:(XFHostNode *)hostNode
                       processor:(XFProcessor *)processor
                     contextNode:(nullable XFXMLNode *)contextNode;

@property (nonatomic, strong, readonly) XFSVGDocument *svgDocument;

- (void)rebuild;

/* Design-support hit testing (the designer's overlay): both take and
   return the view's own coordinates. */
- (nullable XFXMLElement *)hostElementAtPoint:(CGPoint)point;
- (CGRect)frameOfHostElement:(XFXMLElement *)element;

@end

#endif

NS_ASSUME_NONNULL_END
