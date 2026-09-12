/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* The designer's XPath syntax highlighting.
   
   The engine's lexer was already covered (XFUIControlTests), but nothing
   asserted that the colours reach the text — which is how the highlight
   quietly stopped appearing while an expression was being edited. These
   drive XFDXPathTextStorage the way typing does, so the recolour-on-every-
   change property is pinned rather than assumed.

   macOS only: the storage is AppKit, and the designer is a macOS app. */
#import <XCTest/XCTest.h>
#if __has_include(<AppKit/AppKit.h>)
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFXPath.h>
#import "XFDXPathTextStorage.h"

@interface XFDXPathHighlightTests : XCTestCase
@end

@implementation XFDXPathHighlightTests

/// AppKit headless bring-up, as every AppKit-touching test here does.
///
/// The storage asks for a font in its initialiser, and GNUstep's font
/// enumerator asserts unless the shared NSApplication exists — the same
/// assertion the accesskey tests hit. On Apple it is harmless.
- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
}

- (XFDXPathTextStorage *)storageWith:(NSString *)expression
{
    XFDXPathTextStorage *storage = [[XFDXPathTextStorage alloc] init];
    [storage replaceCharactersInRange:NSMakeRange(0, 0) withString:expression];
    return storage;
}

- (NSColor *)colourIn:(NSTextStorage *)storage at:(NSUInteger)index
{
    NSColor *c = [storage attribute:NSForegroundColorAttributeName
                            atIndex:index effectiveRange:NULL];
    return [c colorUsingColorSpaceName:NSCalibratedRGBColorSpace] ?: c;
}

- (void)testTokensAreColouredDifferently
{
    XFDXPathTextStorage *storage = [self storageWith:@"concat('a', 12)"];
    NSString *text = storage.string;
    NSColor *fn = [self colourIn:storage at:[text rangeOfString:@"concat"].location];
    NSColor *str = [self colourIn:storage at:[text rangeOfString:@"'a'"].location];
    NSColor *num = [self colourIn:storage at:[text rangeOfString:@"12"].location];
    XCTAssertNotNil(fn);
    // the point is that they DIFFER: a function is not a string is not a
    // number. The exact palette is XFDXPathTokenColor's business.
    XCTAssertNotEqualObjects(fn, str);
    XCTAssertNotEqualObjects(str, num);
    XCTAssertNotEqualObjects(fn, num);
}

/// The regression that prompted this: the colours must survive editing.
/// Setting attributes after the fact did not — a storage recolours itself
/// because it is told about every change.
- (void)testColoursSurviveEveryEdit
{
    XFDXPathTextStorage *storage = [self storageWith:@"count("];
    // typed one character at a time, as a person would
    for (NSString *typed in @[ @"i", @"t", @"e", @"m", @")" ]) {
        [storage replaceCharactersInRange:NSMakeRange(storage.length, 0) withString:typed];
    }
    XCTAssertEqualObjects(storage.string, @"count(item)");
    NSString *text = storage.string;
    NSColor *fn = [self colourIn:storage at:[text rangeOfString:@"count"].location];
    NSColor *name = [self colourIn:storage at:[text rangeOfString:@"item"].location];
    XCTAssertNotNil(fn);
    XCTAssertNotEqualObjects(fn, name, @"the function must still be coloured after typing");
}

/// Re-lexing the WHOLE text matters: a quote or bracket typed in the
/// middle changes what everything after it is.
- (void)testAnOpenedQuoteRecoloursWhatFollows
{
    XFDXPathTextStorage *storage = [self storageWith:@"a, b"];
    NSString *before = storage.string;
    NSColor *bPlain = [self colourIn:storage at:[before rangeOfString:@"b"].location];
    // now open a string before it: "b" becomes part of a string literal
    [storage replaceCharactersInRange:NSMakeRange(0, 0) withString:@"'"];
    NSString *after = storage.string;
    XCTAssertEqualObjects(after, @"'a, b");
    NSColor *bInString = [self colourIn:storage at:[after rangeOfString:@"b"].location];
    XCTAssertNotEqualObjects(bPlain, bInString,
                             @"text after a new quote must be re-lexed");
}

- (void)testInvalidPaintsEverythingRed
{
    XFDXPathTextStorage *storage = [self storageWith:@"concat('a', 12)"];
    storage.invalid = YES;
    NSString *text = storage.string;
    NSColor *red = [[NSColor redColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    for (NSUInteger i = 0; i < text.length; i++) {
        XCTAssertEqualObjects([self colourIn:storage at:i], red,
                              @"character %lu should be red", (unsigned long)i);
    }
    // and clearing it brings the token colours back
    storage.invalid = NO;
    NSColor *fn = [self colourIn:storage at:[text rangeOfString:@"concat"].location];
    XCTAssertNotEqualObjects(fn, red);
}

- (void)testBaseAttributesCarryTheFont
{
    XFDXPathTextStorage *storage = [self storageWith:@"item"];
    NSFont *mono = [NSFont userFixedPitchFontOfSize:11];
    storage.baseAttributes = @{ NSFontAttributeName: mono };
    XCTAssertEqualObjects([storage attribute:NSFontAttributeName atIndex:0
                              effectiveRange:NULL], mono);
}

/// A plain location path is all `name` and `punct`, and those two kinds
/// are the default text colour and a dimmed grey — so `A/fio` looks
/// unhighlighted even though it was lexed and coloured correctly. This
/// pins that, because it is exactly what makes the feature look broken:
/// nearly every ref/nodeset in a form is this shape.
- (void)testALocationPathUsesTheNameAndPunctColours
{
    XFDXPathTextStorage *storage = [self storageWith:@"A/fio"];
    NSColor *name = [self colourIn:storage at:0];
    NSColor *slash = [self colourIn:storage at:1];
    XCTAssertEqualObjects(name, [self colourIn:storage at:2], @"both names alike");
    XCTAssertNotEqualObjects(name, slash, @"the separator is dimmed");
    // both sides resolved: the table returns catalog colours, the storage
    // stores what they resolve to
    NSColor *(^rgb)(NSColor *) = ^NSColor *(NSColor *c) {
        return [c colorUsingColorSpaceName:NSCalibratedRGBColorSpace] ?: c;
    };
    XCTAssertEqualObjects(name, rgb(XFDXPathTokenColor(@"name")));
    XCTAssertEqualObjects(slash, rgb(XFDXPathTokenColor(@"punct")));
}

@end
#endif
