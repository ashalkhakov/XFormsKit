/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* The iOS host app's own logic: turning a picked file into a form.
   The app is mostly UIKit chrome, but this part is not — a document is
   read, given a base URL so its relative resources resolve, and either
   becomes a processor or reports why it could not. Those two sources are
   compiled into this bundle rather than tested through a separate app
   test target; XFMobileForm is Foundation-only, and the browser needs
   UIKit, so it is excluded on macOS.

   The picker itself, and the push it leads to, are UIKit's to get right;
   what is asserted here is everything either side of them. */
#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import "XFMobileForm.h"
#if __has_include(<UIKit/UIKit.h>)
#import <XFormsKit/XFFormViewController.h>
#import "XFFormBrowserViewController.h"
#endif

@interface XFMobileAppTests : XCTestCase
@property (nonatomic, copy) NSURL *directory;
@end

@implementation XFMobileAppTests

- (void)setUp
{
    [super setUp];
    self.directory = [[NSFileManager defaultManager].temporaryDirectory
        URLByAppendingPathComponent:[[NSUUID UUID] UUIDString] isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.directory
                             withIntermediateDirectories:YES
                                              attributes:nil error:NULL];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtURL:self.directory error:NULL];
    [super tearDown];
}

- (NSURL *)writeForm:(NSString *)xml named:(NSString *)name
{
    NSURL *url = [self.directory URLByAppendingPathComponent:name];
    NSError *error = nil;
    XCTAssertTrue([xml writeToURL:url atomically:YES
                         encoding:NSUTF8StringEncoding error:&error], @"%@", error);
    return url;
}

- (NSURL *)writeSimpleForm
{
    return [self writeForm:
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <head><xf:model><xf:instance><data xmlns=\"\">"
        @"    <name>Ada</name>"
        @"  </data></xf:instance></xf:model></head>"
        @"  <body><xf:input ref=\"name\"><xf:label>Name</xf:label></xf:input></body>"
        @"</html>" named:@"contact-details.xhtml"];
}

- (void)testOpeningAFormBuildsItsProcessor
{
    NSError *error = nil;
    XFMobileForm *form = [XFMobileForm formWithContentsOfURL:[self writeSimpleForm]
                                                       error:&error];
    XCTAssertNotNil(form, @"%@", error);
    XCTAssertEqual(form.processor.controls.count, (NSUInteger)1);
    XCTAssertEqualObjects(form.processor.controls.firstObject.stringValue, @"Ada");
    // the file name, without extension, is what the navigation bar shows
    XCTAssertEqualObjects(form.title, @"contact-details");
}

- (void)testTheDocumentsOwnDirectoryIsTheBaseURL
{
    // a relative instance/@src resolves DURING construction, so a form
    // that loads at all proves the base URL rode in with the source
    NSURL *data = [self.directory URLByAppendingPathComponent:@"people.xml"];
    XCTAssertTrue([@"<people><person>Grace</person></people>"
        writeToURL:data atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    NSURL *url = [self writeForm:
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\">"
        @"  <head><xf:model>"
        @"    <xf:instance src=\"people.xml\"/>"
        @"  </xf:model></head>"
        @"  <body><xf:output ref=\"person\"><xf:label>Who</xf:label></xf:output></body>"
        @"</html>" named:@"sourced.xhtml"];
    NSError *error = nil;
    XFMobileForm *form = [XFMobileForm formWithContentsOfURL:url error:&error];
    XCTAssertNotNil(form, @"%@", error);
    XCTAssertEqualObjects(form.processor.controls.firstObject.stringValue, @"Grace");
}

- (void)testARealSampleFormOpens
{
    // The samples the app bundles are the repo's, found here from this
    // file's own path: the test bundle is not the app bundle, so
    // +bundledSamples (which reads the main bundle) would look in the
    // test host. What matters is that a real sample — not only the
    // synthetic ones above — survives the loader.
    NSString *here = [NSString stringWithUTF8String:__FILE__];
    NSString *root = [[[here stringByDeletingLastPathComponent]
        stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    NSURL *sample = [NSURL fileURLWithPath:
        [root stringByAppendingPathComponent:@"Samples/address.xhtml"]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:[sample path]]) {
        return;   // a checkout without Samples/; the app shows its empty state
    }
    NSError *error = nil;
    XFMobileForm *form = [XFMobileForm formWithContentsOfURL:sample error:&error];
    XCTAssertNotNil(form, @"%@", error);
    XCTAssertTrue(form.processor.controls.count > 0);
    XCTAssertEqualObjects(form.title, @"address");
}

- (void)testAFileThatIsNotThereReportsAnError
{
    NSError *error = nil;
    NSURL *missing = [self.directory URLByAppendingPathComponent:@"nope.xhtml"];
    XCTAssertNil([XFMobileForm formWithContentsOfURL:missing error:&error]);
    XCTAssertNotNil(error, @"the app shows this reason to the user");
}

- (void)testAFormTheEngineRejectsReportsTheEnginesReason
{
    NSURL *url = [self writeForm:@"<html><body>not a form at all</body>" named:@"bad.xhtml"];
    NSError *error = nil;
    XCTAssertNil([XFMobileForm formWithContentsOfURL:url error:&error]);
    XCTAssertNotNil(error);
    XCTAssertTrue(error.localizedDescription.length > 0);
}

#if __has_include(<UIKit/UIKit.h>)

- (void)testOpeningAFormPushesItAsAForm
{
    XFFormBrowserViewController *browser = [[XFFormBrowserViewController alloc] init];
    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:browser];
    [browser loadViewIfNeeded];

    XCTAssertTrue([browser openFormAtURL:[self writeSimpleForm]]);
    XCTAssertEqual(nav.viewControllers.count, (NSUInteger)2);
    XFFormViewController *form = nav.viewControllers.lastObject;
    XCTAssertTrue([form isKindOfClass:[XFFormViewController class]]);
    XCTAssertEqualObjects(form.title, @"contact-details");
    // and it really is the form: the row layer saw the control
    XCTAssertEqual(form.processor.controls.count, (NSUInteger)1);
}

- (void)testAFormThatWillNotOpenLeavesTheBrowserWhereItIs
{
    XFFormBrowserViewController *browser = [[XFFormBrowserViewController alloc] init];
    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:browser];
    [browser loadViewIfNeeded];

    NSURL *url = [self writeForm:@"<html><body>nope" named:@"bad.xhtml"];
    XCTAssertFalse([browser openFormAtURL:url]);
    XCTAssertEqual(nav.viewControllers.count, (NSUInteger)1);
}

#endif

@end
