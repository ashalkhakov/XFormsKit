#import <XCTest/XCTest.h>
#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFFormRows.h>
#import <XFormsKit/XFFormViewController.h>
#import <XFormsKit/XFSelectControl.h>
#import <XFormsKit/XFUploadControl.h>
#import <XFormsKit/XFGroup.h>
#import <XFormsKit/XFRichText.h>
#import <XFormsKit/XFXML.h>

/// What the controller does for itself rather than for a caller. These
/// are the seams the keyboard bar, accesskey and the repeat gestures are
/// driven through; a test exercises them the way UIKit would, since the
/// events that normally reach them (a first responder change, a hardware
/// key, a swipe) need a host app and a window.
@interface XFFormViewController (XFFormViewControllerTesting)
- (UIToolbar *)keyboardAccessoryViewForRichText:(BOOL)rich;
- (void)richEditorDidBeginEditing:(UITextView *)textView;
- (void)toggleRichMarker:(NSString *)marker;
- (void)rowUpdatesFrom:(NSArray<XFFormSection *> *)before
                    to:(NSArray<XFFormSection *> *)after
               deletes:(NSArray<NSIndexPath *> **)deletes
               inserts:(NSArray<NSIndexPath *> **)inserts;
- (NSArray<XFFormSection *> *)sectionsFromProcessor;
@property (nonatomic, strong) NSArray<XFFormSection *> *sections;
- (void)rebuildSections;
- (UIToolbar *)keyboardAccessoryView;
- (void)fieldDidBeginEditing:(XFControl *)control;
- (NSArray<NSIndexPath *> *)editableFieldPaths;
- (void)performAccessKey:(UIKeyCommand *)command;
@end

/// The iOS form, driven the way a table view drives it. iOS only: there is
/// no UIKit to answer on macOS or GNUstep, where XFFormView is the widget
/// layer and XFUIControlTests covers it.
@interface XFFormViewControllerTests : XCTestCase
@property (nonatomic, strong) XFProcessor *processor;
@property (nonatomic, strong) XFFormViewController *controller;
/// Cells the test asked the data source for.
///
/// A table retains the cells it is displaying; a test that calls
/// -tableView:cellForRowAtIndexPath: directly is the only owner of what
/// comes back. Let one go and its controls lose their target -- UIControl
/// holds targets weakly, so the action silently stops firing and
/// `allTargets` reports NSNull where the cell used to be.
@property (nonatomic, strong) NSMutableArray *liveCells;
@end

@implementation XFFormViewControllerTests

- (void)setUp
{
    [super setUp];
    self.liveCells = [NSMutableArray array];
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <head><xf:model><xf:instance><data xmlns=\"\">"
        @"    <name>Ada</name><agree>false</agree><note>n</note>"
        @"  </data></xf:instance></xf:model></head>"
        @"  <body>"
        @"    <p>Intro prose.</p>"
        @"    <xf:group><xf:label>Details</xf:label>"
        @"      <xf:input ref=\"name\"><xf:label>Name</xf:label></xf:input>"
        @"      <xf:input ref=\"agree\"><xf:label>Agree</xf:label></xf:input>"
        @"      <xf:output ref=\"name\"><xf:label>Echo</xf:label></xf:output>"
        @"    </xf:group>"
        @"  </body></html>";
    NSError *error = nil;
    self.processor = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(self.processor, @"%@", error);
    self.controller = [[XFFormViewController alloc] initWithProcessor:self.processor];
    [self.controller loadViewIfNeeded];
}

/// A form with `body` and an instance carrying a colour, wrapped in a
/// loaded controller.
- (XFFormViewController *)controllerForBody:(NSString *)body
{
    NSString *xml = [NSString stringWithFormat:
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <head><xf:model><xf:instance><data xmlns=\"\">"
        @"    <colour>red</colour><many/>"
        @"    <when>2001-02-03</when><amount>0</amount><file/>"
        @"    <pic>iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==</pic>"
        @"  </data></xf:instance></xf:model></head>"
        @"  <body>%@</body></html>", body];
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFFormViewController *vc = [[XFFormViewController alloc] initWithProcessor:p];
    [vc loadViewIfNeeded];
    return vc;
}

- (NSString *)valueOfRef:(NSString *)ref in:(XFFormViewController *)vc
{
    XFXMLDocument *doc = [[vc.processor defaultInstance] document];
    for (XFXMLNode *child in [[doc rootElement] children]) {
        if ([[child name] isEqualToString:ref]) {
            return [XFXML stringValueOfNode:child];
        }
    }
    return nil;
}

- (void)testNoteCellDrawsHintMarkupBold
{
    XFFormViewController *vc = [self controllerForBody:
        @"<xf:input ref=\"colour\"><xf:label>Colour</xf:label>"
        @"  <xf:hint>Enter your <b>full</b> name</xf:hint></xf:input>"];
    // row 0 is the field, row 1 its note
    UITableViewCell *cell = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    [self.liveCells addObject:cell];
    UILabel *label = nil;
    for (UIView *v in cell.contentView.subviews) {
        if ([v isKindOfClass:[UILabel class]]) { label = (UILabel *)v; break; }
    }
    XCTAssertNotNil(label);
    NSAttributedString *text = label.attributedText;
    XCTAssertEqualObjects(text.string, @"Enter your full name");
    // "full" is bold and the rest is not: the markup became presentation,
    // rather than being flattened or shown as tags
    NSRange bold = [text.string rangeOfString:@"full"];
    UIFont *boldFont = [text attribute:NSFontAttributeName atIndex:bold.location
                        effectiveRange:NULL];
    UIFont *plainFont = [text attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    XCTAssertTrue((boldFont.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0,
                  @"the <b> run should be bold");
    XCTAssertFalse((plainFont.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0,
                   @"the surrounding text should not be");
}

- (void)testPlainNoteCellStillShowsItsText
{
    XFFormViewController *vc = [self controllerForBody:
        @"<xf:input ref=\"colour\"><xf:label>Colour</xf:label>"
        @"  <xf:hint>Plain hint</xf:hint></xf:input>"];
    UITableViewCell *cell = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    [self.liveCells addObject:cell];
    UILabel *label = nil;
    for (UIView *v in cell.contentView.subviews) {
        if ([v isKindOfClass:[UILabel class]]) { label = (UILabel *)v; break; }
    }
    XCTAssertEqualObjects(label.attributedText.string, @"Plain hint");
}

- (void)testGridShowsColumnTitlesWhenTheTableHasNoHeaderCells
{
    // no <th> anywhere: the names live on the controls' own labels, which
    // is where balance-table puts them
    XFFormViewController *vc = [self controllerForBody:
        @"<table><tr>"
        @"<td><xf:input ref=\"colour\"><xf:label>Colour</xf:label></xf:input></td>"
        @"<td><xf:input ref=\"when\"><xf:label>When</xf:label></xf:input></td>"
        @"</tr></table>"];
    UITableViewCell *cell = [self onlyCellOf:vc];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (UILabel *label in [self viewsUnder:cell.contentView ofClass:[UILabel class]]) {
        if (label.text.length) { [texts addObject:label.text]; }
    }
    XCTAssertTrue([texts containsObject:@"Colour"], @"headings missing: %@", texts);
    XCTAssertTrue([texts containsObject:@"When"], @"headings missing: %@", texts);
}

- (void)testGridLeavesANonRelevantCellEmpty
{
    XFFormViewController *vc = [self controllerForBody:
        @"<table><tr>"
        @"<td><xf:input ref=\"colour\"><xf:label>Colour</xf:label></xf:input></td>"
        @"<td><xf:group ref=\"missing\">"
        @"  <xf:input ref=\"nope\"><xf:label>Hidden</xf:label></xf:input></xf:group></td>"
        @"</tr></table>"];
    UITableViewCell *cell = [self onlyCellOf:vc];
    NSArray<UIView *> *fields = [self viewsUnder:cell.contentView
                                         ofClass:[UITextField class]];
    // only the relevant one: a field that cannot take a value must not
    // look as though it can
    XCTAssertEqual(fields.count, (NSUInteger)1);
}

- (void)testAPendingFocusIsAdoptedWhenTheViewAppears
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"  <head><xf:model><xf:instance><data xmlns=\"\"><a/><b/></data></xf:instance>"
        @"  <xf:action ev:event=\"xforms-ready\">"
        @"    <xf:setfocus control=\"second\"/></xf:action></xf:model></head>"
        @"  <body>"
        @"    <xf:input ref=\"a\" id=\"first\"><xf:label>A</xf:label></xf:input>"
        @"    <xf:input ref=\"b\" id=\"second\"><xf:label>B</xf:label></xf:input>"
        @"  </body></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    // the engine recorded it during construction, when no host existed
    XCTAssertEqualObjects(p.focusedControl.identifier, @"second");

    XFFormViewController *vc = [[XFFormViewController alloc] initWithProcessor:p];
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 800)];
    window.rootViewController = vc;
    [window makeKeyAndVisible];
    [vc.tableView layoutIfNeeded];
    [vc viewDidAppear:NO];

    // the LIVE cell, not a freshly dequeued one: the focus went to the
    // view the table is actually showing
    UITableViewCell *live = [vc.tableView
        cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    XCTAssertNotNil(live, @"row 1 should be on screen");
    UITextField *second = (UITextField *)
        [self viewsUnder:live.contentView ofClass:[UITextField class]].firstObject;
    XCTAssertNotNil(second);
    // the form asked for the cursor to start there, and it does
    XCTAssertTrue(second.isFirstResponder,
                  @"the xforms-ready setfocus should have been applied");
}

#pragma mark - prose with controls in it

- (XFFormViewController *)sentenceController
{
    return [self controllerForBody:
        @"<p>Pick <xf:output ref=\"colour\"/> or "
        @"<xf:trigger><xf:label>Change</xf:label></xf:trigger> now</p>"];
}

- (void)testASentenceIsOneRowWithItsWordsAndWidgetsOnALine
{
    XFFormViewController *vc = [self sentenceController];
    XCTAssertEqual([vc tableView:vc.tableView numberOfRowsInSection:0], (NSInteger)1,
                   @"one line, not a row per control");
    UITableViewCell *cell = [self onlyCellOf:vc];
    NSArray<UIView *> *labels = [self viewsUnder:cell.contentView ofClass:[UILabel class]];
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (UILabel *label in labels) {
        if (label.text.length) { [words addObject:label.text]; }
    }
    for (NSString *want in @[ @"Pick", @"red", @"or", @"now" ]) {
        XCTAssertTrue([words containsObject:want], @"missing %@ in %@", want, words);
    }
    NSArray<UIView *> *buttons = [self viewsUnder:cell.contentView ofClass:[UIButton class]];
    XCTAssertEqual(buttons.count, (NSUInteger)1, @"the trigger is a button on the line");

    // everything on one line: same y, increasing x
    UIView *first = nil, *last = nil;
    for (UIView *view in [labels arrayByAddingObjectsFromArray:buttons]) {
        if (CGRectIsEmpty(view.frame)) { continue; }
        if (first == nil || view.frame.origin.x < first.frame.origin.x) { first = view; }
        if (last == nil || view.frame.origin.x > last.frame.origin.x) { last = view; }
    }
    XCTAssertNotNil(first);
    XCTAssertTrue(last.frame.origin.x > first.frame.origin.x, @"laid out across");
    XCTAssertEqualWithAccuracy(first.frame.origin.y, last.frame.origin.y, 12.0,
                               @"and on the same line");
}

- (void)testATriggerInASentenceActivates
{
    XFFormViewController *vc = [self controllerForBody:
        @"<p>Press <xf:trigger><xf:label>Go</xf:label>"
        @"  <xf:setvalue ev:event=\"DOMActivate\" ref=\"colour\" value=\"'blue'\"/>"
        @"</xf:trigger> to change <xf:output ref=\"colour\"/></p>"];
    UITableViewCell *cell = [self onlyCellOf:vc];
    UIButton *go = (UIButton *)
        [self viewsUnder:cell.contentView ofClass:[UIButton class]].firstObject;
    XCTAssertNotNil(go);
    [self fireActionsOn:go forEvent:UIControlEventTouchUpInside];
    XCTAssertEqualObjects([self valueOfRef:@"colour" in:vc], @"blue");
}

- (void)testALongSentenceWrapsOntoMoreLines
{
    NSMutableString *body = [NSMutableString stringWithString:@"<p>"];
    for (int i = 0; i < 40; i++) {
        [body appendString:@"word "];
    }
    [body appendString:@"<xf:output ref=\"colour\"/></p>"];
    XFFormViewController *vc = [self controllerForBody:body];
    UITableViewCell *cell = [self onlyCellOf:vc];
    CGSize fits = [cell systemLayoutSizeFittingSize:CGSizeMake(390, 0)
                      withHorizontalFittingPriority:UILayoutPriorityRequired
                            verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    // forty words cannot fit one line of a phone: the row is several
    // lines tall, and the table asks the cell for exactly this
    XCTAssertTrue(fits.height > 80, @"expected a wrapped block, got %g", fits.height);

    NSArray<UIView *> *labels = [self viewsUnder:cell.contentView ofClass:[UILabel class]];
    NSMutableSet<NSNumber *> *lines = [NSMutableSet set];
    for (UIView *label in labels) {
        if (!CGRectIsEmpty(label.frame)) { [lines addObject:@(label.frame.origin.y)]; }
    }
    XCTAssertTrue(lines.count > 1, @"words should sit on several lines");
}

#pragma mark - typing is not interrupted

/// A field bound to a constrained node, so validity flips as you type.
- (XFFormViewController *)emailController
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <head><xf:model><xf:instance><data xmlns=\"\"><mail>a</mail></data>"
        @"  </xf:instance>"
        @"  <xf:bind nodeset=\"mail\" constraint=\"contains(., '@')\"/></xf:model></head>"
        @"  <body><xf:input ref=\"mail\" incremental=\"true\">"
        @"    <xf:label>Email</xf:label><xf:alert>Needs an @</xf:alert>"
        @"  </xf:input></body></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFFormViewController *vc = [[XFFormViewController alloc] initWithProcessor:p];
    [vc loadViewIfNeeded];
    return vc;
}

/// Typing the "@" of an email address drops the alert row, and that used
/// to be a full reload — which rebuilt the cell holding the keyboard, so
/// the field stopped accepting input. The change must arrive as a row
/// deletion, leaving every other cell (the editor included) alone.
- (void)testValidityFlipWhileTypingIsARowDeletionNotAReload
{
    XFFormViewController *vc = [self emailController];
    XFControl *control = vc.processor.controls.firstObject;
    // invalid to begin with: field + alert note
    XCTAssertEqual([vc tableView:vc.tableView numberOfRowsInSection:0], (NSInteger)2);

    [vc fieldDidBeginEditing:control];
    NSArray<XFFormSection *> *before = vc.sections;
    NSError *error = nil;
    XCTAssertTrue([vc.processor setValue:@"a@b" ofControl:control error:&error], @"%@", error);
    NSArray<XFFormSection *> *after = [vc sectionsFromProcessor];

    NSArray<NSIndexPath *> *deletes = nil;
    NSArray<NSIndexPath *> *inserts = nil;
    [vc rowUpdatesFrom:before to:after deletes:&deletes inserts:&inserts];
    XCTAssertEqual(deletes.count, (NSUInteger)1, @"just the alert row goes");
    XCTAssertEqual(deletes.firstObject.row, (NSInteger)1);
    XCTAssertEqual(inserts.count, (NSUInteger)0);
}

- (void)testGoingInvalidWhileTypingIsARowInsertion
{
    XFFormViewController *vc = [self emailController];
    XFControl *control = vc.processor.controls.firstObject;
    NSError *error = nil;
    [vc.processor setValue:@"a@b" ofControl:control error:&error];   // valid
    [vc reloadFromProcessor];
    [vc fieldDidBeginEditing:control];
    NSArray<XFFormSection *> *before = vc.sections;
    [vc.processor setValue:@"ab" ofControl:control error:&error];    // invalid again
    NSArray<XFFormSection *> *after = [vc sectionsFromProcessor];

    NSArray<NSIndexPath *> *deletes = nil;
    NSArray<NSIndexPath *> *inserts = nil;
    [vc rowUpdatesFrom:before to:after deletes:&deletes inserts:&inserts];
    XCTAssertEqual(inserts.count, (NSUInteger)1, @"the alert row arrives");
    XCTAssertEqual(inserts.firstObject.row, (NSInteger)1);
    XCTAssertEqual(deletes.count, (NSUInteger)0);
}

- (void)testAnUnchangedFormNeedsNoRowUpdates
{
    XFFormViewController *vc = [self emailController];
    NSArray<XFFormSection *> *before = vc.sections;
    NSArray<XFFormSection *> *after = [vc sectionsFromProcessor];
    NSArray<NSIndexPath *> *deletes = nil;
    NSArray<NSIndexPath *> *inserts = nil;
    [vc rowUpdatesFrom:before to:after deletes:&deletes inserts:&inserts];
    XCTAssertEqual(deletes.count, (NSUInteger)0);
    XCTAssertEqual(inserts.count, (NSUInteger)0);
}

/// The whole point, end to end: keystroke after keystroke, the value
/// reaches the instance and the field is never rebuilt.
- (void)testTypingAnEmailAddressRunsToTheEnd
{
    XFFormViewController *vc = [self emailController];
    // the table must have counted its rows, as it has in a real window,
    // or a batch update has nothing to diff against
    vc.view.frame = CGRectMake(0, 0, 390, 800);
    [vc.tableView layoutIfNeeded];
    UITextField *field = [self textFieldInRow:0 of:vc];
    XCTAssertNotNil(field);
    [field.delegate textFieldDidBeginEditing:field];
    UITextField *sameField = field;
    for (NSString *typed in @[ @"a", @"ad", @"ada", @"ada@", @"ada@b", @"ada@b.c" ]) {
        sameField.text = typed;
        [self fireActionsOn:sameField forEvent:UIControlEventEditingChanged];
        XCTAssertEqualObjects([self valueOfRef:@"mail" in:vc], typed,
                              @"every keystroke reaches the instance");
        // and the field the user is typing into is still the same object,
        // holding the text they typed
        XCTAssertEqualObjects(sameField.text, typed);
    }
}

#pragma mark - xf:textarea, plain and rich

- (XFFormViewController *)textareaControllerRich:(BOOL)rich
{
    NSString *xml = [NSString stringWithFormat:
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <head><xf:model><xf:instance><data xmlns=\"\">"
        @"    <rich>&lt;p&gt;Paragraph &lt;i&gt;number one&lt;/i&gt;&lt;/p&gt;</rich>"
        @"  </data></xf:instance></xf:model></head>"
        @"  <body>"
        @"    <xf:textarea ref=\"rich\"%@><xf:label>Body</xf:label></xf:textarea>"
        @"    <xf:output value=\"rich\"><xf:label>Raw</xf:label></xf:output>"
        @"    <xf:output value=\"rich\" mediatype=\"application/xhtml+xml\">"
        @"      <xf:label>HTML</xf:label></xf:output>"
        @"  </body></html>",
        rich ? @" mediatype=\"application/xhtml+xml\"" : @""];
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFFormViewController *vc = [[XFFormViewController alloc] initWithProcessor:p];
    [vc loadViewIfNeeded];
    return vc;
}

- (UITextView *)textViewInRow:(NSInteger)row of:(XFFormViewController *)vc
{
    UITableViewCell *cell = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
    [self.liveCells addObject:cell];
    for (UIView *view in cell.contentView.subviews) {
        for (UIView *inner in view.subviews) {
            if ([inner isKindOfClass:[UITextView class]]) { return (UITextView *)inner; }
        }
    }
    return nil;
}

- (void)testTextareaGetsAMultiLineFieldNotAOneLineOne
{
    XFFormViewController *vc = [self textareaControllerRich:NO];
    UITableViewCell *cell = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    [self.liveCells addObject:cell];
    BOOL hasTextField = NO;
    for (UIView *view in cell.contentView.subviews) {
        if ([view isKindOfClass:[UITextField class]]) { hasTextField = YES; }
    }
    XCTAssertFalse(hasTextField, @"a textarea is not a one-line field");
    XCTAssertNotNil([self textViewInRow:0 of:vc]);
}

- (void)testRichTextareaShowsFormattedTextRatherThanTags
{
    XFFormViewController *vc = [self textareaControllerRich:YES];
    UITextView *editor = [self textViewInRow:0 of:vc];
    XCTAssertNotNil(editor);
    NSAttributedString *shown = editor.attributedText;
    // the user sees the words, never the markup
    XCTAssertEqualObjects(shown.string, @"Paragraph number one");
    NSRange italic = [shown.string rangeOfString:@"number one"];
    UIFont *italicFont = [shown attribute:NSFontAttributeName atIndex:italic.location
                           effectiveRange:NULL];
    UIFont *plainFont = [shown attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    XCTAssertTrue((italicFont.fontDescriptor.symbolicTraits & UIFontDescriptorTraitItalic) != 0,
                  @"the <i> run should be italic");
    XCTAssertFalse((plainFont.fontDescriptor.symbolicTraits & UIFontDescriptorTraitItalic) != 0);
}

- (void)testPlainTextareaStillShowsItsValueVerbatim
{
    XFFormViewController *vc = [self textareaControllerRich:NO];
    UITextView *editor = [self textViewInRow:0 of:vc];
    // no mediatype: the value is text, markup and all
    XCTAssertEqualObjects(editor.text, @"<p>Paragraph <i>number one</i></p>");
}

- (void)testEditingTheRichTextareaWritesMarkupBack
{
    XFFormViewController *vc = [self textareaControllerRich:YES];
    UITextView *editor = [self textViewInRow:0 of:vc];
    NSMutableAttributedString *edited = [editor.attributedText mutableCopy];
    [edited.mutableString setString:@"Hello world"];
    editor.attributedText = edited;
    [editor.delegate textViewDidEndEditing:editor];
    // what lands in the instance is markup, not the plain string
    NSString *stored = [self valueOfRef:@"rich" in:vc];
    XCTAssertTrue([stored containsString:@"Hello world"], @"%@", stored);
    XCTAssertTrue([stored hasPrefix:@"<p>"], @"a paragraph survives the round trip: %@", stored);
}

- (void)testFormattingBarMarksTheSelection
{
    XFFormViewController *vc = [self textareaControllerRich:YES];
    UITextView *editor = [self textViewInRow:0 of:vc];
    [vc richEditorDidBeginEditing:editor];
    editor.selectedRange = [editor.attributedText.string rangeOfString:@"Paragraph"];
    [vc toggleRichMarker:XFRichBoldAttributeName];

    UIFont *font = [editor.attributedText attribute:NSFontAttributeName atIndex:0
                                     effectiveRange:NULL];
    XCTAssertTrue((font.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0,
                  @"the selection should have gone bold");
    [editor.delegate textViewDidEndEditing:editor];
    XCTAssertTrue([[self valueOfRef:@"rich" in:vc] containsString:@"<strong>"],
                  @"%@", [self valueOfRef:@"rich" in:vc]);
}

- (void)testRichBarCarriesFormattingAndThePlainOneDoesNot
{
    XFFormViewController *vc = [self textareaControllerRich:YES];
    XCTAssertEqual([vc keyboardAccessoryViewForRichText:NO].items.count, (NSUInteger)4);
    // prev, next, gap, B, I, U, gap, Done
    XCTAssertEqual([vc keyboardAccessoryViewForRichText:YES].items.count, (NSUInteger)8);
    // and the two bars must not share their navigation items: a
    // UIBarButtonItem belongs to one toolbar
    XCTAssertNotEqual([vc keyboardAccessoryViewForRichText:NO].items.firstObject,
                      [vc keyboardAccessoryViewForRichText:YES].items.firstObject);
}

- (void)testHTMLOutputRendersWhilePlainOutputShowsTheMarkup
{
    XFFormViewController *vc = [self textareaControllerRich:YES];
    UITableViewCell *raw = [vc tableView:vc.tableView
                   cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    UITableViewCell *html = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
    [self.liveCells addObjectsFromArray:@[ raw, html ]];
    XCTAssertEqualObjects(raw.detailTextLabel.text, @"<p>Paragraph <i>number one</i></p>");
    XCTAssertEqualObjects(html.detailTextLabel.attributedText.string, @"Paragraph number one");
}

#pragma mark - keyboard accessory navigation

/// A form of three text fields, the middle one readonly.
- (XFFormViewController *)threeFieldController
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <head><xf:model><xf:instance><data xmlns=\"\">"
        @"    <a>1</a><b>2</b><c>3</c>"
        @"  </data></xf:instance>"
        @"  <xf:bind ref=\"b\" readonly=\"true()\"/></xf:model></head>"
        @"  <body>"
        @"    <xf:input ref=\"a\"><xf:label>A</xf:label></xf:input>"
        @"    <xf:input ref=\"b\"><xf:label>B</xf:label></xf:input>"
        @"    <xf:input ref=\"c\"><xf:label>C</xf:label></xf:input>"
        @"  </body></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFFormViewController *vc = [[XFFormViewController alloc] initWithProcessor:p];
    [vc loadViewIfNeeded];
    return vc;
}

- (void)testKeyboardAccessoryIsSharedAndComplete
{
    XFFormViewController *vc = [self threeFieldController];
    UIToolbar *bar = [vc keyboardAccessoryView];
    XCTAssertNotNil(bar);
    XCTAssertEqual(bar.items.count, (NSUInteger)4);   // prev, next, gap, Done
    // one bar for the whole form: only one field can be first responder
    XCTAssertEqual(bar, [vc keyboardAccessoryView]);
    UITextField *field = [self textFieldInRow:0 of:vc];
    XCTAssertEqual(field.inputAccessoryView, bar);
}

- (void)testPreviousAndNextEnableAtTheEndsOfTheForm
{
    XFFormViewController *vc = [self threeFieldController];
    UIToolbar *bar = [vc keyboardAccessoryView];
    UIBarButtonItem *previous = bar.items[0];
    UIBarButtonItem *next = bar.items[1];

    NSArray<XFControl *> *controls = vc.processor.controls;
    [vc fieldDidBeginEditing:controls[0]];
    XCTAssertFalse(previous.enabled, @"nothing before the first field");
    XCTAssertTrue(next.enabled);

    // controls[1] is readonly, so the last editable field is controls[2]
    [vc fieldDidBeginEditing:controls[2]];
    XCTAssertTrue(previous.enabled);
    XCTAssertFalse(next.enabled, @"nothing after the last field");
}

- (void)testReadonlyFieldIsSkippedByNavigation
{
    XFFormViewController *vc = [self threeFieldController];
    NSArray<NSIndexPath *> *paths = [vc editableFieldPaths];
    // A and C only: a readonly field takes no keyboard, so stopping on it
    // would be a dead end
    XCTAssertEqual(paths.count, (NSUInteger)2);
    XCTAssertEqual(paths[0].row, (NSInteger)0);
    XCTAssertEqual(paths[1].row, (NSInteger)2);
}

#pragma mark - accesskey

- (XFFormViewController *)accessKeyController
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:ev=\"http://www.w3.org/2001/xml-events\">"
        @"  <head><xf:model><xf:instance><data xmlns=\"\">"
        @"    <name>Ada</name>"
        @"  </data></xf:instance></xf:model></head>"
        @"  <body>"
        @"    <xf:input ref=\"name\" accesskey=\"n\"><xf:label>Name</xf:label></xf:input>"
        @"    <xf:trigger accesskey=\"g\"><xf:label>Go</xf:label>"
        @"      <xf:setvalue ev:event=\"DOMActivate\" ref=\"name\" value=\"'pressed'\"/>"
        @"    </xf:trigger>"
        @"  </body></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFFormViewController *vc = [[XFFormViewController alloc] initWithProcessor:p];
    [vc loadViewIfNeeded];
    return vc;
}

- (void)testAccessKeysBecomeKeyCommands
{
    XFFormViewController *vc = [self accessKeyController];
    NSArray<UIKeyCommand *> *commands = vc.keyCommands;
    XCTAssertEqual(commands.count, (NSUInteger)2);
    NSMutableSet<NSString *> *inputs = [NSMutableSet set];
    for (UIKeyCommand *command in commands) {
        [inputs addObject:command.input];
        XCTAssertEqual(command.modifierFlags, UIKeyModifierCommand);
    }
    XCTAssertEqualObjects(inputs, ([NSSet setWithArray:@[ @"n", @"g" ]]));
    // the label is what the shortcut overlay shows
    XCTAssertTrue([commands.firstObject.discoverabilityTitle length] > 0);
}

- (void)testAccessKeyActivatesATrigger
{
    XFFormViewController *vc = [self accessKeyController];
    UIKeyCommand *command = [UIKeyCommand keyCommandWithInput:@"g"
                                                modifierFlags:UIKeyModifierCommand
                                                       action:@selector(performAccessKey:)];
    [vc performAccessKey:command];
    XCTAssertEqualObjects([self valueOfRef:@"name" in:vc], @"pressed");
}

- (void)testAccessKeyOnAFieldFocusesRatherThanActivating
{
    XFFormViewController *vc = [self accessKeyController];
    UIKeyCommand *command = [UIKeyCommand keyCommandWithInput:@"n"
                                                modifierFlags:UIKeyModifierCommand
                                                       action:@selector(performAccessKey:)];
    [vc performAccessKey:command];
    XCTAssertEqualObjects([self valueOfRef:@"name" in:vc], @"Ada", @"focus must not edit");
    XCTAssertEqual(vc.processor.focusedControl, vc.processor.controls.firstObject);
}

#pragma mark - repeat add / remove

- (XFFormViewController *)repeatController
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <head><xf:model><xf:instance><data xmlns=\"\">"
        @"    <item><name>one</name></item>"
        @"    <item><name>two</name></item>"
        @"  </data></xf:instance></xf:model></head>"
        @"  <body>"
        @"    <xf:repeat nodeset=\"item\"><xf:label>Items</xf:label>"
        @"      <xf:input ref=\"name\"><xf:label>Name</xf:label></xf:input>"
        @"    </xf:repeat>"
        @"  </body></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFFormViewController *vc = [[XFFormViewController alloc] initWithProcessor:p];
    [vc loadViewIfNeeded];
    return vc;
}

- (NSUInteger)itemCountIn:(XFFormViewController *)vc
{
    XFXMLDocument *doc = [[vc.processor defaultInstance] document];
    NSUInteger count = 0;
    for (XFXMLNode *child in [[doc rootElement] children]) {
        if ([[child name] isEqualToString:@"item"]) { count++; }
    }
    return count;
}

- (void)testOnlyRepeatItemRowsCanBeSwipedAway
{
    XFFormViewController *vc = [self repeatController];
    NSIndexPath *item = [NSIndexPath indexPathForRow:0 inSection:0];
    XCTAssertTrue([vc tableView:vc.tableView canEditRowAtIndexPath:item]);
    XCTAssertEqual([vc tableView:vc.tableView editingStyleForRowAtIndexPath:item],
                   UITableViewCellEditingStyleDelete);
    // the last row of the section is the add row, which is not swipeable
    NSInteger last = [vc tableView:vc.tableView numberOfRowsInSection:0] - 1;
    NSIndexPath *add = [NSIndexPath indexPathForRow:last inSection:0];
    XCTAssertFalse([vc tableView:vc.tableView canEditRowAtIndexPath:add]);
}

- (void)testSwipingARowDeletesThatRepeatItem
{
    XFFormViewController *vc = [self repeatController];
    XCTAssertEqual([self itemCountIn:vc], (NSUInteger)2);
    [vc tableView:vc.tableView
        commitEditingStyle:UITableViewCellEditingStyleDelete
         forRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    XCTAssertEqual([self itemCountIn:vc], (NSUInteger)1);
    // and the remaining item is the SECOND one, not the first
    XFXMLDocument *doc = [[vc.processor defaultInstance] document];
    XFXMLElement *item = (XFXMLElement *)[[doc rootElement] elementsForName:@"item"].firstObject;
    XCTAssertEqualObjects([XFXML stringValueOfNode:
        [item elementsForName:@"name"].firstObject], @"two");
}

- (void)testTappingTheAddRowAppendsAnItem
{
    XFFormViewController *vc = [self repeatController];
    NSInteger last = [vc tableView:vc.tableView numberOfRowsInSection:0] - 1;
    [vc tableView:vc.tableView
        didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:last inSection:0]];
    XCTAssertEqual([self itemCountIn:vc], (NSUInteger)3);
    // the table grew by the new item's row, and the add row is still last
    NSInteger grown = [vc tableView:vc.tableView numberOfRowsInSection:0];
    XCTAssertEqual(grown, last + 2);
}

#pragma mark - xf:dialog

- (void)testDialogContentControllerLeavesTheFormsHostHooksAlone
{
    XFFormViewController *vc = [self controllerForBody:
        @"<xf:group><xf:label>Inner</xf:label>"
        @"  <xf:input ref=\"colour\"><xf:label>Colour</xf:label></xf:input>"
        @"</xf:group>"];
    __block BOOL parentSawMessage = NO;
    vc.processor.messageHandler = ^(NSString *text, NSString *level) {
        parentSawMessage = YES;
    };
    // the controller a presented xf:dialog uses: same processor, one group
    XFGroup *group = nil;
    for (XFControl *control in vc.processor.controls) {
        if ([control isKindOfClass:[XFGroup class]]) { group = (XFGroup *)control; break; }
    }
    XCTAssertNotNil(group);
    XFFormViewController *content =
        [[XFFormViewController alloc] initWithProcessor:vc.processor];
    content.rootGroup = group;
    [content loadViewIfNeeded];
    vc.processor.messageHandler(@"hi", @"modal");
    XCTAssertTrue(parentSawMessage,
                  @"a nested form view must not take over the processor's hooks");
}

/// Invokes a control's registered target/action pairs directly.
///
/// -sendActionsForControlEvents: routes through UIApplication, and an iOS
/// unit-test bundle with no host app has none -- the action silently never
/// fires, which reads exactly like a wiring bug. Walking allTargets tests
/// the same two things that matter: that the target/action really is
/// registered, and that the handler does the right thing.
- (UITextField *)textFieldInRow:(NSInteger)row of:(XFFormViewController *)vc
{
    UITableViewCell *cell = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
    [self.liveCells addObject:cell];
    for (UIView *view in cell.contentView.subviews) {
        if ([view isKindOfClass:[UITextField class]]) {
            return (UITextField *)view;
        }
    }
    return nil;
}

- (void)fireActionsOn:(UIControl *)control
{
    [self fireActionsOn:control forEvent:UIControlEventValueChanged];
}

- (void)fireActionsOn:(UIControl *)control forEvent:(UIControlEvents)event
{
    for (id target in control.allTargets) {
        for (NSString *action in [control actionsForTarget:target
                                           forControlEvent:event]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [target performSelector:NSSelectorFromString(action) withObject:control];
#pragma clang diagnostic pop
        }
    }
}

- (void)testTableMirrorsTheForm
{
    UITableView *table = self.controller.tableView;
    XCTAssertEqual([table numberOfSections], 2, @"loose prose, then the group");
    XCTAssertEqual([table numberOfRowsInSection:0], 1);
    XCTAssertEqual([table numberOfRowsInSection:1], 3);
    XCTAssertEqualObjects([self.controller tableView:table titleForHeaderInSection:1], @"Details");
}

- (void)testCellsShowTheirControls
{
    UITableView *table = self.controller.tableView;
    UITableViewCell *name = [self.controller tableView:table
                                 cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    XCTAssertEqualObjects(name.textLabel.text, @"Name");
    UITextField *field = nil;
    for (UIView *v in name.contentView.subviews) {
        if ([v isKindOfClass:[UITextField class]]) { field = (UITextField *)v; }
    }
    XCTAssertNotNil(field, @"an xf:input row carries a UITextField");
    XCTAssertEqualObjects(field.text, @"Ada");

    UITableViewCell *agree = [self.controller tableView:table
                                  cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:1]];
    XCTAssertTrue([agree.accessoryView isKindOfClass:[UISwitch class]],
                  @"a boolean input puts a UISwitch in the accessory, as iOS forms do");
    XCTAssertFalse([(UISwitch *)agree.accessoryView isOn]);

    UITableViewCell *echo = [self.controller tableView:table
                                 cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:1]];
    XCTAssertEqualObjects(echo.detailTextLabel.text, @"Ada", @"xf:output shows its value");
}

/// The point of the design: cells are views OF controls, so a cell can be
/// recycled and rebound without the control losing anything.
- (void)testRebindingACellFollowsTheInstance
{
    UITableView *table = self.controller.tableView;
    NSIndexPath *path = [NSIndexPath indexPathForRow:0 inSection:1];
    UITableViewCell *first = [self.controller tableView:table cellForRowAtIndexPath:path];

    XFControl *name = nil;
    for (XFFormSection *section in [XFFormRows sectionsForProcessor:self.processor]) {
        for (XFFormRow *row in section.rows) {
            if ([row.label isEqualToString:@"Name"]) { name = row.control; }
        }
    }
    XCTAssertNotNil(name);

    NSError *error = nil;
    XCTAssertTrue([self.processor setValue:@"Grace" ofControl:name error:&error], @"%@", error);
    [self.controller reloadFromProcessor];

    UITableViewCell *again = [self.controller tableView:table cellForRowAtIndexPath:path];
    UITextField *field = nil;
    for (UIView *v in again.contentView.subviews) {
        if ([v isKindOfClass:[UITextField class]]) { field = (UITextField *)v; }
    }
    XCTAssertEqualObjects(field.text, @"Grace");
    (void)first;
}

/// appearance="full" with few items: every option on the form at once, in
/// a segmented control, and picking one reaches the instance.
- (void)testFullAppearanceShowsSegmentsInline
{
    XFFormViewController *vc = [self controllerForBody:
        @"<xf:select1 ref=\"colour\" appearance=\"full\"><xf:label>Colour</xf:label>"
        @"<xf:item><xf:label>Red</xf:label><xf:value>red</xf:value></xf:item>"
        @"<xf:item><xf:label>Blue</xf:label><xf:value>blue</xf:value></xf:item>"
        @"</xf:select1>"];
    UITableViewCell *cell = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    UISegmentedControl *segments = nil;
    for (UIView *v in cell.contentView.subviews) {
        if ([v isKindOfClass:[UISegmentedControl class]]) { segments = (UISegmentedControl *)v; }
    }
    XCTAssertNotNil(segments);
    XCTAssertEqual(segments.numberOfSegments, 2);
    XCTAssertEqual(segments.selectedSegmentIndex, 0, @"red is the instance value");

    segments.selectedSegmentIndex = 1;
    [self fireActionsOn:segments];
    XCTAssertEqualObjects([self valueOfRef:@"colour" in:vc], @"blue",
                          @"picking a segment writes through to the instance");
}

/// appearance="full" with many items: a row each, checkmarked, and tapping
/// one picks it.
- (void)testFullAppearanceWithManyItemsShowsCheckRows
{
    NSMutableString *items = [NSMutableString string];
    for (NSUInteger i = 0; i < 6; i++) {
        [items appendFormat:@"<xf:item><xf:label>Item %lu</xf:label>"
                             "<xf:value>v%lu</xf:value></xf:item>",
                            (unsigned long)i, (unsigned long)i];
    }
    XFFormViewController *vc = [self controllerForBody:[NSString stringWithFormat:
        @"<xf:select1 ref=\"colour\" appearance=\"full\"><xf:label>Colour</xf:label>%@"
        @"</xf:select1>", items]];
    XCTAssertEqual([vc.tableView numberOfRowsInSection:0], 6);
    UITableViewCell *third = [vc tableView:vc.tableView
                     cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
    XCTAssertEqualObjects(third.textLabel.text, @"Item 2");
    XCTAssertEqual(third.accessoryType, UITableViewCellAccessoryNone);

    [vc tableView:vc.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
    XCTAssertEqualObjects([self valueOfRef:@"colour" in:vc], @"v2");
    UITableViewCell *again = [vc tableView:vc.tableView
                     cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
    XCTAssertEqual(again.accessoryType, UITableViewCellAccessoryCheckmark);
}

/// appearance="minimal": the options are NOT on the form. Tapping the row
/// opens a screen of them, and picking there writes through and leaves.
- (void)testMinimalAppearanceOpensAScreenOfOptions
{
    XFFormViewController *vc = [self controllerForBody:
        @"<xf:select1 ref=\"colour\" appearance=\"minimal\"><xf:label>Colour</xf:label>"
        @"<xf:item><xf:label>Red</xf:label><xf:value>red</xf:value></xf:item>"
        @"<xf:item><xf:label>Blue</xf:label><xf:value>blue</xf:value></xf:item>"
        @"</xf:select1>"];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [nav loadViewIfNeeded];

    UITableViewCell *cell = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    XCTAssertEqualObjects(cell.textLabel.text, @"Colour");
    XCTAssertEqualObjects(cell.detailTextLabel.text, @"Red", @"the row shows the choice");
    XCTAssertEqual(cell.accessoryType, UITableViewCellAccessoryDisclosureIndicator);
    XCTAssertEqual([vc.tableView numberOfRowsInSection:0], 1, @"the options are not on the form");

    [vc tableView:vc.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    UITableViewController *options = (UITableViewController *)nav.topViewController;
    XCTAssertNotEqualObjects(options, (UITableViewController *)vc, @"tapping pushed a screen");
    XCTAssertEqualObjects(options.title, @"Colour");
    [options loadViewIfNeeded];
    XCTAssertEqual([options tableView:options.tableView numberOfRowsInSection:0], 2);

    [options tableView:options.tableView
    didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    XCTAssertEqualObjects([self valueOfRef:@"colour" in:vc], @"blue");
}

/// A date input shows its value and carries a UIDatePicker as the cell's
/// inputView, so the wheels rise where the keyboard would.
- (void)testDateRowCarriesAPickerAsItsInputView
{
    XFFormViewController *vc = [self controllerForBody:
        @"<xf:input ref=\"when\"><xf:label>When</xf:label></xf:input>"];
    UITableViewCell *cell = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    XCTAssertEqualObjects(cell.textLabel.text, @"When");
    // localized, not the instance's lexical value — the picker beside it
    // writes dates the same way
    XCTAssertNotEqualObjects(cell.detailTextLabel.text, @"2001-02-03");
    XCTAssertTrue([cell.detailTextLabel.text containsString:@"2001"],
                  @"%@", cell.detailTextLabel.text);
    UIDatePicker *picker = (UIDatePicker *)cell.inputView;
    XCTAssertTrue([picker isKindOfClass:[UIDatePicker class]],
                  @"the picker is the cell's inputView, not a row of its own");
    XCTAssertEqual(picker.datePickerMode, UIDatePickerModeDate);

    // moving the wheels writes a formatted date through to the instance
    picker.date = [picker.date dateByAddingTimeInterval:24 * 60 * 60];
    [self fireActionsOn:picker];
    XCTAssertEqualObjects([self valueOfRef:@"when" in:vc], @"2001-02-04");
}

/// xf:range: the slider spans start..end and quantises to @step.
- (void)testSliderQuantisesToStepAndWritesOnRelease
{
    XFFormViewController *vc = [self controllerForBody:
        @"<xf:range ref=\"amount\" start=\"0\" end=\"10\" step=\"5\">"
        @"<xf:label>Amount</xf:label></xf:range>"];
    UITableViewCell *cell = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    UISlider *slider = nil;
    for (UIView *v in cell.contentView.subviews) {
        if ([v isKindOfClass:[UISlider class]]) { slider = (UISlider *)v; }
    }
    XCTAssertNotNil(slider);
    XCTAssertEqual(slider.minimumValue, 0.0f);
    XCTAssertEqual(slider.maximumValue, 10.0f);

    // 6.2 is nearer 5 than 10, and @step says those are the only stops
    slider.value = 6.2f;
    [self fireActionsOn:slider];
    XCTAssertEqualObjects([self valueOfRef:@"amount" in:vc], @"0",
                          @"a non-incremental range writes when the finger lifts");
    [cell performSelector:@selector(finished:) withObject:slider];
    XCTAssertEqualObjects([self valueOfRef:@"amount" in:vc], @"5");
}

/// xf:upload. AppKit ran NSOpenPanel modally and had the URL on the next
/// line; here the picker is presented and answers through a delegate, so
/// the test drives that callback the way the picker would.
- (void)testUploadRowNamesTheFileAndCommitsAPickedOne
{
    XFFormViewController *vc = [self controllerForBody:
        @"<xf:upload ref=\"file\" mediatype=\"text/plain\">"
        @"<xf:label>Attachment</xf:label></xf:upload>"];
    UITableViewCell *cell = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    XCTAssertEqualObjects(cell.textLabel.text, @"Attachment");
    XCTAssertEqualObjects(cell.detailTextLabel.text, @"Choose…", @"nothing chosen yet");
    XCTAssertEqual(cell.accessoryType, UITableViewCellAccessoryDisclosureIndicator);

    NSURL *file = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:@"xfupload.txt"];
    XCTAssertTrue([@"hello" writeToURL:file atomically:YES
                             encoding:NSUTF8StringEncoding error:NULL]);
    XFUploadControl *upload = nil;
    for (XFFormSection *section in [XFFormRows sectionsForProcessor:vc.processor]) {
        for (XFFormRow *row in section.rows) {
            if ([row.control isKindOfClass:[XFUploadControl class]]) {
                upload = (XFUploadControl *)row.control;
            }
        }
    }
    XCTAssertNotNil(upload);
    XCTAssertTrue([vc commitPickedFileAtURL:file forUpload:upload]);

    UITableViewCell *again = [vc tableView:vc.tableView
                     cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    XCTAssertEqualObjects(again.detailTextLabel.text, @"xfupload.txt",
                          @"the row names what was picked");
    XCTAssertEqualObjects([self valueOfRef:@"file" in:vc],
                          [[@"hello" dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0],
                          @"and the instance holds its base64");
    [[NSFileManager defaultManager] removeItemAtURL:file error:NULL];
}

/// Host markup: prose with inline emphasis becomes one attributed string,
/// headings take a heading style, and an <svg> gets a view that draws
/// through the portable renderer.
- (void)testMarkupCellRendersProseHeadingsAndSVG
{
    XFFormViewController *vc = [self controllerForBody:
        @"<h2>A heading</h2>"
        @"<p>Plain and <b>bold</b> and <i>italic</i>.</p>"
        @"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"40\" height=\"20\">"
        @"<rect x=\"0\" y=\"0\" width=\"40\" height=\"20\" fill=\"red\"/></svg>"
        @"<xf:input ref=\"colour\"><xf:label>After</xf:label></xf:input>"];
    UITableViewCell *cell = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];

    UILabel *body = nil;
    UIView *svg = nil;
    NSMutableArray<UIView *> *queue = [@[ cell.contentView ] mutableCopy];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([view isKindOfClass:[UILabel class]] && ((UILabel *)view).attributedText.length) {
            body = (UILabel *)view;
        }
        if ([NSStringFromClass([view class]) containsString:@"SVG"]) {
            svg = view;
        }
        [queue addObjectsFromArray:view.subviews];
    }

    XCTAssertNotNil(body, @"prose renders as attributed text");
    NSString *text = body.attributedText.string;
    XCTAssertTrue([text containsString:@"A heading"]);
    XCTAssertTrue([text containsString:@"bold"]);

    // the heading and the body are not set in the same font
    UIFont *headingFont = [body.attributedText attribute:NSFontAttributeName
                                                 atIndex:0 effectiveRange:NULL];
    NSUInteger plain = [text rangeOfString:@"Plain"].location;
    UIFont *bodyFont = [body.attributedText attribute:NSFontAttributeName
                                              atIndex:plain effectiveRange:NULL];
    XCTAssertGreaterThan(headingFont.pointSize, bodyFont.pointSize,
                         @"<h2> is bigger than the prose under it");

    // and bold really is bold
    NSUInteger bold = [text rangeOfString:@"bold"].location;
    UIFont *boldFont = [body.attributedText attribute:NSFontAttributeName
                                              atIndex:bold effectiveRange:NULL];
    XCTAssertTrue((boldFont.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold) != 0,
                  @"<b> is bold: %@", boldFont.fontName);

    XCTAssertNotNil(svg, @"an <svg> node gets a view of its own");
    XCTAssertEqual(svg.intrinsicContentSize.width, 40.0);
    XCTAssertEqual(svg.intrinsicContentSize.height, 20.0);
}

/// An image output draws the picture. Shown as a value row it printed the
/// base64 of the picture instead.
- (void)testImageOutputDrawsThePicture
{
    XFFormViewController *vc = [self controllerForBody:
        @"<xf:output ref=\"pic\" mediatype=\"image/png\">"
        @"<xf:label>Picture</xf:label></xf:output>"];
    UITableViewCell *cell = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    UIImageView *picture = nil;
    for (UIView *v in cell.contentView.subviews) {
        if ([v isKindOfClass:[UIImageView class]] && ((UIImageView *)v).image != nil) {
            picture = (UIImageView *)v;
        }
    }
    XCTAssertNotNil(picture, @"the row draws the image");
    XCTAssertEqual(picture.image.size.width, 1.0, @"the 1x1 test pixel");
    XCTAssertNil(cell.detailTextLabel.text, @"and never its base64");
}

/// A host <table> is transposed into "Header value" lines rather than
/// drawn as a grid: columns on a phone are the sideways-scrolling problem
/// this layer exists to avoid.
/// Every view under `root`, at any depth — the grid nests its cells
/// inside a scroll view, so a one-level sweep of contentView would miss
/// them.
- (NSArray<UIView *> *)viewsUnder:(UIView *)root ofClass:(Class)cls
{
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    for (UIView *view in root.subviews) {
        if ([view isKindOfClass:cls]) {
            [found addObject:view];
        }
        [found addObjectsFromArray:[self viewsUnder:view ofClass:cls]];
    }
    return found;
}

- (UITableViewCell *)onlyCellOf:(XFFormViewController *)vc
{
    UITableViewCell *cell = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    [self.liveCells addObject:cell];
    // the grid lays out by hand, so give it a width to lay out in
    cell.frame = CGRectMake(0, 0, 390, 400);
    [cell layoutIfNeeded];
    return cell;
}

- (void)testControlFreeTableIsDrawnAsAGrid
{
    XFFormViewController *vc = [self controllerForBody:
        @"<table><tr><th>Name</th><th>Qty</th></tr>"
        @"<tr><td>Bolt</td><td>7</td></tr>"
        @"<tr><td>Nut</td><td>9</td></tr></table>"];
    UITableViewCell *cell = [self onlyCellOf:vc];
    NSArray<UIView *> *labels = [self viewsUnder:cell.contentView ofClass:[UILabel class]];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (UILabel *label in labels) {
        if (label.text.length) { [texts addObject:label.text]; }
    }
    // one label per cell, not one block of transposed text
    for (NSString *want in @[ @"Name", @"Qty", @"Bolt", @"7", @"Nut", @"9" ]) {
        XCTAssertTrue([texts containsObject:want], @"missing %@ in %@", want, texts);
    }
}

- (void)testGridColumnsLineUpAcrossRows
{
    XFFormViewController *vc = [self controllerForBody:
        @"<table><tr><th>Name</th><th>Qty</th></tr>"
        @"<tr><td>Bolt</td><td>7</td></tr>"
        @"<tr><td>Nut</td><td>9</td></tr></table>"];
    UITableViewCell *cell = [self onlyCellOf:vc];
    NSMutableDictionary<NSString *, NSNumber *> *xByText = [NSMutableDictionary dictionary];
    for (UILabel *label in [self viewsUnder:cell.contentView ofClass:[UILabel class]]) {
        if (label.text.length) {
            xByText[label.text] = @([cell.contentView convertRect:label.bounds
                                                         fromView:label].origin.x);
        }
    }
    // a column is a column: the second column's cells share an x
    XCTAssertEqualWithAccuracy(xByText[@"Qty"].doubleValue,
                               xByText[@"7"].doubleValue, 1.0);
    XCTAssertEqualWithAccuracy(xByText[@"7"].doubleValue,
                               xByText[@"9"].doubleValue, 1.0);
    // and the first column sits left of the second
    XCTAssertTrue(xByText[@"Bolt"].doubleValue < xByText[@"7"].doubleValue);
}

- (void)testTableOfControlsKeepsThemUsableInTheGrid
{
    XFFormViewController *vc = [self controllerForBody:
        @"<table><tr><td>Amount</td>"
        @"<td><xf:input ref=\"amount\"><xf:label>Amount</xf:label></xf:input></td>"
        @"</tr></table>"];
    // one row now: the table is a grid rather than a cell per row
    XCTAssertEqual([vc tableView:vc.tableView numberOfRowsInSection:0], (NSInteger)1);
    UITableViewCell *cell = [self onlyCellOf:vc];
    NSArray<UIView *> *fields = [self viewsUnder:cell.contentView
                                         ofClass:[UITextField class]];
    XCTAssertEqual(fields.count, (NSUInteger)1, @"the input is in the grid");
    UITextField *field = (UITextField *)fields.firstObject;
    XCTAssertTrue(field.enabled, @"and still editable");
    XCTAssertEqualObjects(field.text, @"0");
}

- (void)testGridTriggerActivatesItsControl
{
    XFFormViewController *vc = [self controllerForBody:
        @"<table><tr>"
        @"<td><xf:trigger><xf:label>Seven</xf:label>"
        @"  <xf:setvalue ev:event=\"DOMActivate\" ref=\"colour\" value=\"'7'\"/>"
        @"</xf:trigger></td></tr></table>"];
    UITableViewCell *cell = [self onlyCellOf:vc];
    NSArray<UIView *> *buttons = [self viewsUnder:cell.contentView ofClass:[UIButton class]];
    UIButton *seven = nil;
    for (UIButton *button in buttons) {
        if ([[button titleForState:UIControlStateNormal] isEqualToString:@"Seven"]) {
            seven = button;
        }
    }
    XCTAssertNotNil(seven, @"a trigger in a cell is a button — the calculator keypad");
    [self fireActionsOn:seven forEvent:UIControlEventTouchUpInside];
    XCTAssertEqualObjects([self valueOfRef:@"colour" in:vc], @"7");
}

- (void)testAWideTableScrollsInsideItsOwnRow
{
    NSMutableString *body = [NSMutableString stringWithString:@"<table><tr>"];
    for (int i = 0; i < 12; i++) {
        [body appendFormat:@"<th>Column heading %d</th>", i];
    }
    [body appendString:@"</tr><tr>"];
    for (int i = 0; i < 12; i++) {
        [body appendFormat:@"<td>value %d</td>", i];
    }
    [body appendString:@"</tr></table>"];
    XFFormViewController *vc = [self controllerForBody:body];
    UITableViewCell *cell = [self onlyCellOf:vc];
    NSArray<UIView *> *scrolls = [self viewsUnder:cell.contentView
                                          ofClass:[UIScrollView class]];
    XCTAssertEqual(scrolls.count, (NSUInteger)1);
    UIScrollView *scroll = (UIScrollView *)scrolls.firstObject;
    // the table is wider than the row, so it scrolls sideways in place —
    // the form itself never does
    XCTAssertTrue(scroll.contentSize.width > scroll.bounds.size.width,
                  @"content %g should exceed the row's %g",
                  scroll.contentSize.width, scroll.bounds.size.width);
}

- (void)testANarrowTableDoesNotScroll
{
    XFFormViewController *vc = [self controllerForBody:
        @"<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>"];
    UITableViewCell *cell = [self onlyCellOf:vc];
    UIScrollView *scroll = (UIScrollView *)
        [self viewsUnder:cell.contentView ofClass:[UIScrollView class]].firstObject;
    XCTAssertNotNil(scroll);
    XCTAssertEqualWithAccuracy(scroll.contentSize.width, scroll.bounds.size.width, 1.0,
                               @"two columns share the row's width instead");
}

/// A cell holding a group shows the group's control, the way the AppKit
/// table does: XFTableModel unwraps a block-level wrapper to the single
/// control inside it, and both renderers are driven by that one model, so
/// they agree about what a cell contains.
- (void)testACellWrappingAControlStillShowsIt
{
    XFFormViewController *vc = [self controllerForBody:
        @"<table><tr><td>"
        @"  <xf:group><xf:label>Inner</xf:label>"
        @"    <xf:input ref=\"colour\"><xf:label>Colour</xf:label></xf:input>"
        @"  </xf:group>"
        @"</td></tr></table>"];
    UITableViewCell *cell = [self onlyCellOf:vc];
    NSArray<UIView *> *fields = [self viewsUnder:cell.contentView
                                         ofClass:[UITextField class]];
    XCTAssertEqual(fields.count, (NSUInteger)1, @"the wrapped input is in the grid");
    XCTAssertEqualObjects(((UITextField *)fields.firstObject).text, @"red");
}

/// xf:hint shows as a footnote under the field: AppKit's hover badge has
/// no gesture on a phone, and explanatory text under the field is what
/// iOS does.
- (void)testHintShowsUnderTheField
{
    XFFormViewController *vc = [self controllerForBody:
        @"<xf:input ref=\"colour\"><xf:label>Colour</xf:label>"
        @"<xf:hint>Any colour you like.</xf:hint></xf:input>"];
    XCTAssertEqual([vc.tableView numberOfRowsInSection:0], 2, @"the field and its hint");
    UITableViewCell *hint = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    UILabel *label = nil;
    for (UIView *v in hint.contentView.subviews) {
        if ([v isKindOfClass:[UILabel class]] && ((UILabel *)v).text.length) {
            label = (UILabel *)v;
        }
    }
    XCTAssertEqualObjects(label.text, @"Any colour you like.");
    XCTAssertEqualObjects(label.textColor, [UIColor secondaryLabelColor],
                          @"guidance is not a problem");
}

/// A minimal hint is the field's placeholder, per XSLTForms, so it is not
/// repeated under the row.
- (void)testMinimalHintStaysAPlaceholder
{
    XFFormViewController *vc = [self controllerForBody:
        @"<xf:input ref=\"colour\"><xf:label>Colour</xf:label>"
        @"<xf:hint appearance=\"minimal\">Type a colour</xf:hint></xf:input>"];
    XCTAssertEqual([vc.tableView numberOfRowsInSection:0], 1, @"no note row");
    UITableViewCell *cell = [vc tableView:vc.tableView
                    cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    UITextField *field = nil;
    for (UIView *v in cell.contentView.subviews) {
        if ([v isKindOfClass:[UITextField class]]) { field = (UITextField *)v; }
    }
    XCTAssertEqualObjects(field.placeholder, @"Type a colour");
}

/// While a control is invalid its xf:alert shows in red, and it goes away
/// when the value is fixed — the constraint is live, so the note follows
/// the MIP rather than a submit.
- (void)testAlertAppearsWhileInvalidAndGoesWhenFixed
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <head><xf:model>"
        @"    <xf:instance><data xmlns=\"\"><age>5</age></data></xf:instance>"
        @"    <xf:bind nodeset=\"age\" constraint=\". &gt;= 18\"/>"
        @"  </xf:model></head>"
        @"  <body><xf:input ref=\"age\"><xf:label>Age</xf:label>"
        @"    <xf:alert>You must be at least 18.</xf:alert></xf:input></body></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    XFFormViewController *vc = [[XFFormViewController alloc] initWithProcessor:p];
    [vc loadViewIfNeeded];

    XCTAssertEqual([vc.tableView numberOfRowsInSection:0], 2, @"the field and its alert");
    UITableViewCell *alert = [vc tableView:vc.tableView
                     cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    UILabel *label = nil;
    for (UIView *v in alert.contentView.subviews) {
        if ([v isKindOfClass:[UILabel class]] && ((UILabel *)v).text.length) {
            label = (UILabel *)v;
        }
    }
    XCTAssertEqualObjects(label.text, @"You must be at least 18.");
    XCTAssertEqualObjects(label.textColor, [UIColor systemRedColor]);
    XCTAssertTrue([alert.accessibilityLabel hasPrefix:@"Error:"],
                  @"and VoiceOver says it is one");

    // fix the value: the alert row goes
    XFControl *age = nil;
    for (XFFormSection *section in [XFFormRows sectionsForProcessor:p]) {
        for (XFFormRow *row in section.rows) {
            if (row.kind != XFFormRowKindNote) { age = row.control; }
        }
    }
    XCTAssertTrue([p setValue:@"21" ofControl:age error:&error], @"%@", error);
    [vc reloadFromProcessor];
    XCTAssertEqual([vc.tableView numberOfRowsInSection:0], 1, @"no alert once valid");
}

/// The engine's host hooks are wired: xf:message reaches a handler, and
/// xf:setfocus reaches the row's field. (The alert itself needs a window,
/// so the test checks the wiring, not the presentation.)
- (void)testHostHandlersAreInstalled
{
    XFFormViewController *vc = [self controllerForBody:
        @"<xf:input ref=\"colour\"><xf:label>Colour</xf:label></xf:input>"];
    XCTAssertNotNil(vc.processor.messageHandler, @"xf:message has somewhere to go");
    XCTAssertNotNil(vc.processor.helpRequestHandler, @"and so does xf:help");
    XCTAssertNotNil(vc.processor.focusRequestHandler, @"xf:setfocus too");

    // driving the focus handler must not throw, with or without a window
    XFControl *colour = nil;
    for (XFFormSection *section in [XFFormRows sectionsForProcessor:vc.processor]) {
        for (XFFormRow *row in section.rows) { colour = row.control; }
    }
    XCTAssertNoThrow(vc.processor.focusRequestHandler(colour));
    XCTAssertNoThrow(vc.processor.messageHandler(@"hello", @"modal"));
}

/// incremental="true" commits on every keystroke; without it the write
/// waits for focus to leave. The AppKit field makes the same distinction,
/// and iOS bound only the focus-loss event until now.
- (void)testIncrementalTextCommitsPerKeystroke
{
    XFFormViewController *plain = [self controllerForBody:
        @"<xf:input ref=\"colour\"><xf:label>Colour</xf:label></xf:input>"];
    UITextField *plainField = [self textFieldInRow:0 of:plain];
    plainField.text = @"green";
    [self fireActionsOn:plainField forEvent:UIControlEventEditingChanged];
    XCTAssertEqualObjects([self valueOfRef:@"colour" in:plain], @"red",
                          @"a plain field waits for focus to leave");
    [self fireActionsOn:plainField forEvent:UIControlEventEditingDidEnd];
    XCTAssertEqualObjects([self valueOfRef:@"colour" in:plain], @"green");

    XFFormViewController *live = [self controllerForBody:
        @"<xf:input ref=\"colour\" incremental=\"true\">"
        @"<xf:label>Colour</xf:label></xf:input>"];
    UITextField *liveField = [self textFieldInRow:0 of:live];
    liveField.text = @"blue";
    [self fireActionsOn:liveField forEvent:UIControlEventEditingChanged];
    XCTAssertEqualObjects([self valueOfRef:@"colour" in:live], @"blue",
                          @"an incremental field writes as it is typed");
}

@end

#endif
