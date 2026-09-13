/* XFSVGView.m — the NSView that hosts an XFSVGDocument.
   The renderer itself is platform-independent and lives in
   Sources/XFormsKit/SVG/XFSVGDocument.m; this file is only the AppKit
   widget around it, and is excluded from the iOS build.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#import "XFAppKitPriv.h"

#pragma mark - The widget

@implementation XFSVGView {
    XFHostNode *_hostNode;
    __weak XFProcessor *_processor;
    XFXMLNode *_contextNode;
    XFSVGDocument *_svgDocument;
}

- (instancetype)initWithHostNode:(XFHostNode *)hostNode
                       processor:(XFProcessor *)processor
                     contextNode:(XFXMLNode *)contextNode
{
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _hostNode = hostNode;
        _processor = processor;
        _contextNode = contextNode;
        [self rebuild];
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;   // SVG's y axis grows downward
}

- (XFSVGDocument *)svgDocument
{
    return _svgDocument;
}

- (void)rebuild
{
    XFProcessor *processor = _processor;
    if (processor == nil) {
        return;
    }
    _svgDocument = [XFSVGDocument documentWithHostNode:_hostNode
                                             processor:processor
                                           contextNode:_contextNode];
    [self setFrameSize:_svgDocument.size];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(CGRect)dirty
{
    (void)dirty;
    // -CGContext is declared by NSGraphicsContext on Apple and by GNUstep's
    // too, where the Opal backend provides it. A backend that cannot answer
    // one draws nothing rather than crashing.
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    if (ctx == NULL) {
        return;
    }
    [_svgDocument drawInContext:ctx rect:[self bounds]];
}

- (XFXMLElement *)hostElementAtPoint:(CGPoint)point
{
    // the view draws the document across its whole (flipped) bounds, so
    // view coordinates ARE document coordinates
    return [[_svgDocument nodeAtPoint:point] element];
}

- (CGRect)frameOfHostElement:(XFXMLElement *)element
{
    return [_svgDocument frameOfElement:element];
}

@end
