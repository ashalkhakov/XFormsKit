/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* Rich text in xf:hint / xf:alert / xf:help / xf:message.
   XForms 1.1 gives all of them the label's content model — text, inline
   host markup, and xf:output (9.3.1) — so these assert both halves: the
   markup survives to the host, and an output inside it re-renders when
   the value it reads changes. The presentation layers (AppKit's badge
   text view, the iOS note cell) consume exactly these strings. */
#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFInputControl.h>
#import <XFormsKit/XFMessageAction.h>
#import <XFormsKit/XFXML.h>
#import <XFormsKit/XFMarkupParts.h>

@interface XFRichSupportTests : XCTestCase
@end

@implementation XFRichSupportTests

- (XFProcessor *)form:(NSString *)modelBody extra:(NSString *)extra error:(NSError **)error
{
    NSString *xml =
        [NSString stringWithFormat:
         @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
         @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
         @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
         @"  <xf:model id=\"m\">%@</xf:model>%@"
         @"</html>", modelBody, extra ?: @""];
    return [XFProcessor processorWithXMLString:xml error:error];
}

- (id)firstControlOfClass:(Class)cls in:(XFProcessor *)p
{
    for (XFControl *c in p.controls) {
        if ([c isKindOfClass:cls]) { return c; }
    }
    return nil;
}

#pragma mark markup reaches the host

- (void)testHintAndAlertKeepTheirMarkup
{
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
        extra:
        @"<xf:input ref=\"n\"><xf:label>Name</xf:label>"
        @"  <xf:hint>Enter your <b>full</b> name</xf:hint>"
        @"  <xf:alert>Must be <em>at least</em> 3 characters</xf:alert>"
        @"</xf:input>" error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFControl *c = [self firstControlOfClass:[XFInputControl class] in:p];
    // the plain text stays exactly what it was: no host loses anything
    XCTAssertEqualObjects(c.hint, @"Enter your full name");
    XCTAssertEqualObjects(c.alert, @"Must be at least 3 characters");
    XCTAssertEqualObjects(c.hintMarkup, @"Enter your <b>full</b> name");
    XCTAssertEqualObjects(c.alertMarkup, @"Must be <em>at least</em> 3 characters");
}

- (void)testPlainHintHasNoMarkup
{
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
        extra:
        @"<xf:input ref=\"n\"><xf:label>Name</xf:label>"
        @"  <xf:hint>Just text</xf:hint></xf:input>" error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFControl *c = [self firstControlOfClass:[XFInputControl class] in:p];
    XCTAssertEqualObjects(c.hint, @"Just text");
    // nil, not "Just text": a host must be able to tell "no markup" from
    // markup and take its plain path without parsing anything
    XCTAssertNil(c.hintMarkup);
}

- (void)testBoundHintHasNoMarkup
{
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\"><n>Ada</n><h>from the instance</h></data></xf:instance>"
        extra:
        @"<xf:input ref=\"n\"><xf:label>Name</xf:label>"
        @"  <xf:hint ref=\"../h\"/></xf:input>" error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFControl *c = [self firstControlOfClass:[XFInputControl class] in:p];
    XCTAssertEqualObjects(c.hint, @"from the instance");
    XCTAssertNil(c.hintMarkup);   // a bound hint is its node's value: text
}

#pragma mark xf:output inside the markup (9.3.1)

- (void)testOutputInsideHintMarkupTracksTheInstance
{
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\"><n>Ada</n><min>3</min></data></xf:instance>"
        extra:
        @"<xf:input ref=\"n\"><xf:label>Name</xf:label>"
        @"  <xf:hint>At least <b><xf:output ref=\"../min\"/></b> characters</xf:hint>"
        @"</xf:input>"
        @"<xf:input ref=\"min\"><xf:label>Min</xf:label></xf:input>" error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFControl *c = [self firstControlOfClass:[XFInputControl class] in:p];
    XCTAssertEqualObjects(c.hintMarkup, @"At least <b>3</b> characters");
    XCTAssertEqualObjects(c.hint, @"At least 3 characters");

    XFControl *minField = p.controls[1];
    XCTAssertTrue([p setValue:@"8" ofControl:minField error:&error], @"%@", error);
    // the whole point of parts over a load-time snapshot
    XCTAssertEqualObjects(c.hintMarkup, @"At least <b>8</b> characters");
}

- (void)testOutputValueIsEscapedIntoTheMarkup
{
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\"><n>Ada</n><t>a &lt;b&gt; &amp; c</t></data></xf:instance>"
        extra:
        @"<xf:input ref=\"n\"><xf:label>Name</xf:label>"
        @"  <xf:hint>Say <i><xf:output ref=\"../t\"/></i></xf:hint></xf:input>" error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFControl *c = [self firstControlOfClass:[XFInputControl class] in:p];
    // an instance value holding "<b>" is TEXT and must not become a tag
    XCTAssertEqualObjects(c.hintMarkup, @"Say <i>a &lt;b&gt; &amp; c</i>");
}

- (void)testTextAndOutputOnlyHintStaysPlain
{
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\"><n>Ada</n><min>3</min></data></xf:instance>"
        extra:
        @"<xf:input ref=\"n\"><xf:label>Name</xf:label>"
        @"  <xf:hint>At least <xf:output ref=\"../min\"/></xf:hint></xf:input>" error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFControl *c = [self firstControlOfClass:[XFInputControl class] in:p];
    XCTAssertEqualObjects(c.hint, @"At least 3");
    // no formatting to carry: the plain path already renders this exactly
    XCTAssertNil(c.hintMarkup);
}

#pragma mark xf:message

- (void)testRichMessageReachesTheRichHandler
{
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
        extra:
        @"<xf:trigger id=\"go\"><xf:label>Go</xf:label>"
        @"  <xf:message ev:event=\"DOMActivate\" level=\"modal\">Hello <b><xf:output ref=\"n\"/></b>!</xf:message>"
        @"</xf:trigger>" error:&error];
    XCTAssertNotNil(p, @"%@", error);
    __block NSString *gotMarkup = nil, *gotText = nil, *gotLevel = nil;
    __block NSUInteger plainCalls = 0;
    p.richMessageHandler = ^(NSString *markup, NSString *text, NSString *level) {
        gotMarkup = markup; gotText = text; gotLevel = level;
    };
    p.messageHandler = ^(NSString *text, NSString *level) { plainCalls++; };
    [p activateControl:p.controls.firstObject];
    XCTAssertEqualObjects(gotMarkup, @"Hello <b>Ada</b>!");
    XCTAssertEqualObjects(gotText, @"Hello Ada!");
    XCTAssertEqualObjects(gotLevel, @"modal");
    XCTAssertEqual(plainCalls, (NSUInteger)0, @"a rich message goes to one handler, not both");
}

- (void)testPlainMessageStillUsesThePlainHandler
{
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
        extra:
        @"<xf:trigger id=\"go\"><xf:label>Go</xf:label>"
        @"  <xf:message ev:event=\"DOMActivate\">Hello <xf:output ref=\"n\"/></xf:message>"
        @"</xf:trigger>" error:&error];
    XCTAssertNotNil(p, @"%@", error);
    __block NSString *plain = nil;
    __block NSUInteger richCalls = 0;
    p.richMessageHandler = ^(NSString *m, NSString *t, NSString *l) { richCalls++; };
    p.messageHandler = ^(NSString *text, NSString *level) { plain = text; };
    [p activateControl:p.controls.firstObject];
    XCTAssertEqualObjects(plain, @"Hello Ada");
    XCTAssertEqual(richCalls, (NSUInteger)0);
}

- (void)testRichMessageFallsBackWhenTheHostIsPlainOnly
{
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\"><n>Ada</n></data></xf:instance>"
        extra:
        @"<xf:trigger id=\"go\"><xf:label>Go</xf:label>"
        @"  <xf:message ev:event=\"DOMActivate\">Do <b>not</b> panic</xf:message>"
        @"</xf:trigger>" error:&error];
    XCTAssertNotNil(p, @"%@", error);
    __block NSString *plain = nil;
    p.messageHandler = ^(NSString *text, NSString *level) { plain = text; };
    [p activateControl:p.controls.firstObject];
    // no richMessageHandler: the host that cannot draw markup still gets
    // the message, exactly as before this feature existed
    XCTAssertEqualObjects(plain, @"Do not panic");
}

#pragma mark the part splitter itself

- (void)testMarkupPartsSerializeNestedElementsAroundOutputs
{
    NSError *error = nil;
    XFProcessor *p = [self form:
        @"<xf:instance><data xmlns=\"\"><n>Ada</n><a>X</a></data></xf:instance>"
        extra:
        @"<xf:input ref=\"n\"><xf:label>Name</xf:label>"
        @"  <xf:hint><p>one <b>two <xf:output ref=\"../a\"/> three</b></p><br/>tail</xf:hint>"
        @"</xf:input>" error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFControl *c = [self firstControlOfClass:[XFInputControl class] in:p];
    XCTAssertEqualObjects(c.hintMarkup, @"<p>one <b>two X three</b></p><br/>tail");
}

@end

#if __has_include(<AppKit/AppKit.h>)
#import <AppKit/AppKit.h>
#import <XFormsKit/XFRichText.h>

/// The AppKit half: the read-only text view the hint popup and the
/// message alert both put their markup in.
@interface XFRichDisplayViewTests : XCTestCase
@end

@implementation XFRichDisplayViewTests

/// AppKit headless bring-up. Every test here asks for a font, and
/// GNUstep's font enumerator asserts unless the shared NSApplication
/// exists; on Apple it is harmless.
- (void)setUp
{
    [super setUp];
    [NSApplication sharedApplication];
}

- (void)testDisplayViewIsReadOnlyAndSizedToItsText
{
    NSTextView *view = [XFRichText displayViewWithMarkup:@"Enter your <b>full</b> name"
                                                    font:[NSFont systemFontOfSize:11]
                                                maxWidth:220
                                               textColor:[NSColor blackColor]];
    XCTAssertNotNil(view);
    XCTAssertFalse([view isEditable], @"a hint box takes no typing");
    XCTAssertFalse([view isSelectable], @"and no clicks");
    XCTAssertEqualObjects([[view textStorage] string], @"Enter your full name");
    XCTAssertTrue(NSWidth([view frame]) > 0 && NSWidth([view frame]) <= 220);
    XCTAssertTrue(NSHeight([view frame]) > 0, @"the frame is the fitting size");
}

- (void)testDisplayViewMakesTheMarkedRunBold
{
    NSTextView *view = [XFRichText displayViewWithMarkup:@"Enter your <b>full</b> name"
                                                    font:[NSFont systemFontOfSize:11]
                                                maxWidth:220
                                               textColor:nil];
    NSAttributedString *text = [view textStorage];
    NSRange bold = [[text string] rangeOfString:@"full"];
    NSFont *boldFont = [text attribute:NSFontAttributeName atIndex:bold.location
                        effectiveRange:NULL];
    NSFont *plainFont = [text attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    NSFontTraitMask boldMask = [[NSFontManager sharedFontManager] traitsOfFont:boldFont];
    NSFontTraitMask plainMask = [[NSFontManager sharedFontManager] traitsOfFont:plainFont];
    XCTAssertTrue((boldMask & NSBoldFontMask) != 0);
    XCTAssertFalse((plainMask & NSBoldFontMask) != 0);
}

- (void)testDisplayViewIsNilForPlainText
{
    // the caller's one test for "take the plain path"
    XCTAssertNil([XFRichText displayViewWithMarkup:nil font:nil maxWidth:220 textColor:nil]);
    XCTAssertNil([XFRichText displayViewWithMarkup:@"" font:nil maxWidth:220 textColor:nil]);
}

@end
#endif
