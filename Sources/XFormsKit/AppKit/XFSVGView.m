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
#if defined(GNUSTEP)
    // GNUstep cannot be handed the window's context: -[NSGraphicsContext
    // CGContext] there answers -graphicsPort, which under the cairo backend
    // (the one this project builds) is a cairo_t and not a CGContextRef at
    // all. Drawing a document through it painted nothing -- every <svg> in a
    // form, piechart.xhtml included, came up blank.
    //
    // So the drawing goes into an Opal bitmap context, which Opal owns end to
    // end, and the pixels are blitted with AppKit. This is the same context
    // setup XFSVGRenderTests uses, and it passes there, so what a form shows
    // is what the suite measures.
    CGRect bounds = [self bounds];
    size_t width = (size_t)ceil(CGRectGetWidth(bounds));
    size_t height = (size_t)ceil(CGRectGetHeight(bounds));
    if (width == 0 || height == 0) {
        return;
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, 0, space,
                                             (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (ctx == NULL) {
        return;
    }
    // a bitmap context is y-up; this view is flipped, and so is SVG
    CGContextTranslateCTM(ctx, 0, (CGFloat)height);
    CGContextScaleCTM(ctx, 1, -1);
    [_svgDocument drawInContext:ctx rect:CGRectMake(0, 0, (CGFloat)width, (CGFloat)height)];

    unsigned char *pixels = CGBitmapContextGetData(ctx);
    size_t stride = CGBitmapContextGetBytesPerRow(ctx);
    if (pixels != NULL) {
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:&pixels
                          pixelsWide:(NSInteger)width
                          pixelsHigh:(NSInteger)height
                       bitsPerSample:8
                     samplesPerPixel:4
                            hasAlpha:YES
                            isPlanar:NO
                      colorSpaceName:NSDeviceRGBColorSpace
                         bytesPerRow:(NSInteger)stride
                        bitsPerPixel:32];
        // the rep is y-down like the bitmap, and so is this view
        // the source rect is spelled out rather than left empty: "all of it"
        // is a convention, and one backend need not read it like another
        [rep drawInRect:NSMakeRect(0, 0, (CGFloat)width, (CGFloat)height)
               fromRect:NSMakeRect(0, 0, (CGFloat)width, (CGFloat)height)
              operation:NSCompositeSourceOver
               fraction:1.0
         respectFlipped:YES
                  hints:nil];
    }
    CGContextRelease(ctx);
#else
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    if (ctx == NULL) {
        return;
    }
    [_svgDocument drawInContext:ctx rect:[self bounds]];
#endif
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
