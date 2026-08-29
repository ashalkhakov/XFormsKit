#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>

@interface XFHelloFormTests : XCTestCase
@end

@implementation XFHelloFormTests

- (NSString *)fixtureXML
{
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [bundle pathForResource:@"hello" ofType:@"xhtml"];
    if (path) {
        return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    }
    // Fallback when the fixture has not been copied into the test bundle
    // (running the file as a loose compile).
    NSString *here = [@__FILE__ stringByDeletingLastPathComponent];
    path = [[here stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"Fixtures/hello.xhtml"];
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
}

- (void)testHelloSlice
{
    NSError *error = nil;
    XFProcessor *processor = [XFProcessor processorWithXMLString:[self fixtureXML] error:&error];
    XCTAssertNotNil(processor, @"%@", error);
    XCTAssertEqual(processor.inputControls.count, (NSUInteger)1);
    XCTAssertEqual(processor.outputControls.count, (NSUInteger)1);

    XFInputControl *input = processor.inputControls.firstObject;
    XFOutputControl *output = processor.outputControls.firstObject;
    XCTAssertEqualObjects(input.label, @"Name");
    XCTAssertEqualObjects(output.label, @"Greeting");
    XCTAssertEqualObjects(input.stringValue, @"World");
    XCTAssertEqualObjects(output.stringValue, @"Hello World");

    BOOL ok = [processor setValue:@"Ada" ofControl:input error:&error];
    XCTAssertTrue(ok, @"%@", error);
    XCTAssertEqualObjects(input.stringValue, @"Ada");
    XCTAssertEqualObjects(output.stringValue, @"Hello Ada");
}

@end
