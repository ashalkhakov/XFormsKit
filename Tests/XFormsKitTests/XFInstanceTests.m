#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>

@interface XFInstanceTests : XCTestCase
@end

@implementation XFInstanceTests

- (void)testLoadInlineInstance
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
         " xmlns:xf=\"http://www.w3.org/2002/xforms\">"
         "<head><xf:model><xf:instance id=\"data\">"
         "<person xmlns=\"\"><n>Ada</n></person>"
         "</xf:instance></xf:model></head><body/></html>";
    NSError *error = nil;
    XFProcessor *processor = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(processor, @"%@", error);
    XCTAssertEqual(processor.model.instances.count, (NSUInteger)1);
    XCTAssertEqualObjects(processor.defaultInstance.identifier, @"data");
    XCTAssertEqualObjects([[processor.defaultInstance documentElement] localName], @"person");
    XCTAssertEqualObjects([XFXML stringValueOfNode:
                           [XFXML firstElementWithLocalName:@"n" namespaceURI:@""
                                                     inNode:[processor.defaultInstance documentElement]]],
                          @"Ada");
}

@end
