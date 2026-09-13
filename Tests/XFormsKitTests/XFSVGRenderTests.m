/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* What the SVG renderer actually PAINTS, by rendering into a bitmap and
   looking at where the ink landed.

   The other SVG tests (XFUIControlTests) assert the render tree and hit
   testing — structure, not pixels — and are excluded on iOS. These run on
   every platform, because the renderer is portable and the iOS form is
   now one of its callers; both bugs below reached a user through it. */
#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFSVG.h>
#import <XFormsKit/XFHostNode.h>
#import <XFormsKit/XFFormRows.h>
#import <CoreGraphics/CoreGraphics.h>
#if __has_include(<AppKit/AppKit.h>)
#import <AppKit/AppKit.h>
#endif

/// The bounding box of everything painted, in the drawn rect's own
/// coordinates (y down from the top, like SVG); an empty box when
/// nothing was painted at all.
typedef struct { NSInteger minX, minY, maxX, maxY; NSUInteger count; } XFInkBounds;

@interface XFSVGRenderTests : XCTestCase
@end

@implementation XFSVGRenderTests

- (void)setUp
{
    [super setUp];
#if __has_include(<AppKit/AppKit.h>)
    // Painting <text> rasterizes glyphs through the platform font
    // machinery, and GNUstep's font enumerator asserts unless the
    // shared NSApplication exists; on Apple it is harmless.
    [NSApplication sharedApplication];
#endif
}

- (void)collectSVG:(NSArray<XFHostNode *> *)nodes into:(NSMutableArray *)out
{
    for (XFHostNode *node in nodes) {
        if (node.element && [[node.element localName] isEqualToString:@"svg"]) {
            [out addObject:node];
        }
        [self collectSVG:node.children into:out];
    }
}

/// `svg` is the whole <svg> element, as a form would carry it.
- (XFSVGDocument *)documentForSVG:(NSString *)svg
{
    NSString *xml = [NSString stringWithFormat:
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <head><xf:model><xf:instance><data xmlns=\"\"><v>1</v></data>"
        @"  </xf:instance></xf:model></head><body>%@</body></html>", svg];
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    NSMutableArray *found = [NSMutableArray array];
    [self collectSVG:p.hostNodes into:found];
    XCTAssertEqual(found.count, (NSUInteger)1);
    return [XFSVGDocument documentWithHostNode:found.firstObject processor:p contextNode:nil];
}

/// Draws into a `width` x `height` bitmap the way a view does — y down —
/// and reports where the ink is.
- (XFInkBounds)inkOf:(XFSVGDocument *)document width:(size_t)width height:(size_t)height
{
    XFInkBounds ink = { NSIntegerMax, NSIntegerMax, NSIntegerMin, NSIntegerMin, 0 };
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, 0, space,
                                             kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    XCTAssertTrue(ctx != NULL);
    if (ctx == NULL) {
        return ink;
    }
    // a bitmap context is y-up; SVG is y-down, as every host view arranges
    CGContextTranslateCTM(ctx, 0, height);
    CGContextScaleCTM(ctx, 1, -1);
    [document drawInContext:ctx rect:CGRectMake(0, 0, width, height)];
    uint8_t *data = CGBitmapContextGetData(ctx);
    size_t stride = CGBitmapContextGetBytesPerRow(ctx);
    for (size_t row = 0; row < height; row++) {
        for (size_t col = 0; col < width; col++) {
            if (data[row * stride + col * 4 + 3] == 0) {
                continue;
            }
            // the context was flipped above, so a bitmap row IS the SVG y
            NSInteger y = (NSInteger)row;
            ink.count++;
            ink.minX = MIN(ink.minX, (NSInteger)col);
            ink.maxX = MAX(ink.maxX, (NSInteger)col);
            ink.minY = MIN(ink.minY, y);
            ink.maxY = MAX(ink.maxY, y);
        }
    }
    CGContextRelease(ctx);
    return ink;
}

/// The colour at the middle of the drawing, as 0xRRGGBB (-1 if nothing
/// was painted there).
- (NSInteger)centreColourOf:(XFSVGDocument *)document
                      width:(size_t)width height:(size_t)height
{
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, 0, space,
                                             kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (ctx == NULL) {
        return -1;
    }
    CGContextTranslateCTM(ctx, 0, height);
    CGContextScaleCTM(ctx, 1, -1);
    [document drawInContext:ctx rect:CGRectMake(0, 0, width, height)];
    uint8_t *data = CGBitmapContextGetData(ctx);
    size_t stride = CGBitmapContextGetBytesPerRow(ctx);
    uint8_t *px = data + (height / 2) * stride + (width / 2) * 4;
    NSInteger colour = px[3] == 0 ? -1 : (px[0] << 16) | (px[1] << 8) | px[2];
    CGContextRelease(ctx);
    return colour;
}

/// An SVG inside an xf:repeat paints THIS item's values.
///
/// Its AVTs evaluate against the in-scope context node, which the row
/// model carries from the repeat item the markup came from. Passing no
/// context (which the iOS form used to do) resolved `fill="{@code}"` on
/// the wrong node, so every flag in the flags sample came out the same
/// fallback grey while AppKit, which threads the same context through its
/// layout, drew them correctly.
- (void)testSVGInARepeatTakesItsColourFromItsOwnItem
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <head><xf:model><xf:instance><colors xmlns=\"\">"
        @"    <color name=\"Red\" code=\"#FF0000\"/>"
        @"    <color name=\"Blue\" code=\"#0000FF\"/>"
        @"  </colors></xf:instance></xf:model></head>"
        @"  <body><xf:repeat nodeset=\"color\">"
        @"    <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\">"
        @"      <rect x=\"0\" y=\"0\" width=\"20\" height=\"20\" style=\"fill:{@code}\"/>"
        @"    </svg>"
        @"  </xf:repeat></body></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);

    NSMutableArray<NSNumber *> *colours = [NSMutableArray array];
    for (XFFormSection *section in [XFFormRows sectionsForProcessor:p]) {
        for (XFFormRow *row in section.rows) {
            if (row.kind != XFFormRowKindMarkup) {
                continue;
            }
            NSMutableArray *svgs = [NSMutableArray array];
            [self collectSVG:row.hostNodes into:svgs];
            for (XFHostNode *node in svgs) {
                XFSVGDocument *document =
                    [XFSVGDocument documentWithHostNode:node processor:p
                                            contextNode:row.contextNode];
                [colours addObject:@([self centreColourOf:document width:20 height:20])];
            }
        }
    }
    XCTAssertEqual(colours.count, (NSUInteger)2, @"one flag per repeat item");
    XCTAssertEqual(colours[0].integerValue, 0xFF0000L, @"the first item is red");
    XCTAssertEqual(colours[1].integerValue, 0x0000FFL, @"the second item is blue");
}

#pragma mark - text placement

/// A <text> is painted at its own baseline.
///
/// The text matrix that flips a glyph run (SVG's y grows downward, a
/// glyph's does not) applies to the POSITIONS as well as to the outlines,
/// so an un-negated baseline of 80 drew at -80 — off the top of the
/// viewport, invisible. Text inside a translate() landed mirrored about
/// that origin instead of vanishing, which is how a pie chart could show
/// its slice labels (inside a translate) while losing its legend
/// (not inside one) entirely.
- (void)testTextIsPaintedAtItsBaseline
{
    XFSVGDocument *document = [self documentForSVG:
        @"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"100\">"
        @"  <text x=\"10\" y=\"80\" font-size=\"20\">Hello</text>"
        @"</svg>"];
    XFInkBounds ink = [self inkOf:document width:200 height:100];
    XCTAssertTrue(ink.count > 0, @"the text was not painted at all");
    // glyphs sit ON the baseline: above it, and near it
    XCTAssertTrue(ink.maxY <= 85, @"ink below the baseline (maxY %ld)", (long)ink.maxY);
    XCTAssertTrue(ink.minY >= 55, @"ink far above the baseline (minY %ld)", (long)ink.minY);
    XCTAssertTrue(ink.minX >= 9, @"ink left of x (minX %ld)", (long)ink.minX);
}

- (void)testTextInsideATranslateIsNotMirrored
{
    XFSVGDocument *document = [self documentForSVG:
        @"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"200\">"
        @"  <g transform=\"translate(0,150)\">"
        @"    <text x=\"10\" y=\"20\" font-size=\"20\">Hello</text>"
        @"  </g></svg>"];
    XFInkBounds ink = [self inkOf:document width:200 height:200];
    XCTAssertTrue(ink.count > 0, @"the text was not painted at all");
    // baseline 150 + 20 = 170, NOT 150 - 20 = 130
    XCTAssertTrue(ink.maxY > 150 && ink.maxY <= 175,
                  @"text mirrored about the group origin (ink y %ld..%ld)",
                  (long)ink.minY, (long)ink.maxY);
}

#pragma mark - preserveAspectRatio

/// A drawing keeps its proportions in a rect that does not share them.
/// The default is "xMidYMid meet": uniform scale, centred. AppKit never
/// showed this because its view frame IS the document size; the iOS form,
/// whose rows are as wide as the table, drew every chart squashed.
- (void)testDrawingIsScaledUniformlyByDefault
{
    XFSVGDocument *document = [self documentForSVG:
        @"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\">"
        @"  <rect x=\"0\" y=\"0\" width=\"100\" height=\"100\" fill=\"black\"/>"
        @"</svg>"];
    // twice as wide as it is tall: the square must stay square
    XFInkBounds ink = [self inkOf:document width:200 height:100];
    XCTAssertTrue(ink.count > 0);
    NSInteger width = ink.maxX - ink.minX;
    NSInteger height = ink.maxY - ink.minY;
    XCTAssertTrue(labs(width - height) <= 2,
                  @"stretched: %ld x %ld", (long)width, (long)height);
    // and centred in the spare width
    XCTAssertTrue(labs(ink.minX - 50) <= 2, @"not centred (minX %ld)", (long)ink.minX);
}

- (void)testPreserveAspectRatioNoneStillStretches
{
    XFSVGDocument *document = [self documentForSVG:
        @"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\""
        @"     preserveAspectRatio=\"none\">"
        @"  <rect x=\"0\" y=\"0\" width=\"100\" height=\"100\" fill=\"black\"/>"
        @"</svg>"];
    XFInkBounds ink = [self inkOf:document width:200 height:100];
    XCTAssertTrue(ink.count > 0);
    XCTAssertTrue(ink.maxX - ink.minX > 190, @"none must fill the width");
}

- (void)testViewBoxStillMapsIntoTheRect
{
    XFSVGDocument *document = [self documentForSVG:
        @"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\""
        @"     viewBox=\"0 0 50 50\">"
        @"  <rect x=\"0\" y=\"0\" width=\"25\" height=\"25\" fill=\"black\"/>"
        @"</svg>"];
    // the viewBox doubles everything: a 25-unit square covers half of 100
    XFInkBounds ink = [self inkOf:document width:100 height:100];
    XCTAssertTrue(ink.count > 0);
    XCTAssertTrue(labs((ink.maxX - ink.minX) - 50) <= 2,
                  @"viewBox scale lost (%ld wide)", (long)(ink.maxX - ink.minX));
}

@end
