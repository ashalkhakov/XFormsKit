/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* Dates as a reader sees them. The instance keeps the lexical
   `2025-01-01`; what a host PRINTS should be in the reader's locale, the
   way the date pickers already write it. Both backends were showing the
   raw value in their read-only paths. */
#import <XCTest/XCTest.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFDateDisplay.h>
#import <XFormsKit/XFInputControl.h>
#import <XFormsKit/XFOutputControl.h>

@interface XFDateDisplayTests : XCTestCase
@end

@implementation XFDateDisplayTests

- (XFProcessor *)dateForm
{
    NSString *xml =
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\""
        @"      xmlns:xf=\"http://www.w3.org/2002/xforms\""
        @"      xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">"
        @"  <head><xf:model><xf:instance><data xmlns=\"\">"
        @"    <when>2025-01-31</when><at>13:45:00</at><text>hello</text>"
        @"  </data></xf:instance>"
        @"  <xf:bind nodeset=\"when\" type=\"xs:date\"/>"
        @"  <xf:bind nodeset=\"at\" type=\"xs:time\"/></xf:model></head>"
        @"  <body>"
        @"    <xf:input ref=\"when\"><xf:label>When</xf:label></xf:input>"
        @"    <xf:output ref=\"when\"><xf:label>Shown</xf:label></xf:output>"
        @"    <xf:output ref=\"at\"><xf:label>At</xf:label></xf:output>"
        @"    <xf:output ref=\"text\"><xf:label>Text</xf:label></xf:output>"
        @"  </body></html>";
    NSError *error = nil;
    XFProcessor *p = [XFProcessor processorWithXMLString:xml error:&error];
    XCTAssertNotNil(p, @"%@", error);
    return p;
}

- (void)testADateTypedValueIsLocalized
{
    NSString *shown = [XFDateDisplay localizedStringForValue:@"2025-01-31"
                                                    typeName:@"date"];
    XCTAssertNotNil(shown);
    // not the lexical form, and it names the right day in some order
    XCTAssertNotEqualObjects(shown, @"2025-01-31");
    XCTAssertTrue([shown containsString:@"2025"], @"%@", shown);
    XCTAssertTrue([shown containsString:@"31"], @"%@", shown);
}

- (void)testTheDayDoesNotShiftAcrossTheTimeZone
{
    // parsed as UTC, so it must print as UTC: otherwise a date west of
    // Greenwich comes out a day early
    NSDateFormatter *reference = [[NSDateFormatter alloc] init];
    reference.dateFormat = @"d";
    reference.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSString *shown = [XFDateDisplay localizedStringForValue:@"2025-01-01"
                                                    typeName:@"date"];
    XCTAssertTrue([shown containsString:@"1"], @"%@", shown);
    XCTAssertFalse([shown containsString:@"31"], @"a day early: %@", shown);
    XCTAssertFalse([shown containsString:@"2024"], @"a year early: %@", shown);
}

- (void)testATimeTypedValueIsLocalized
{
    NSString *shown = [XFDateDisplay localizedStringForValue:@"13:45:00"
                                                    typeName:@"time"];
    XCTAssertNotNil(shown);
    XCTAssertNotEqualObjects(shown, @"13:45:00");
    // 13:45 or 1:45 PM depending on the locale; either names the minute
    XCTAssertTrue([shown containsString:@"45"], @"%@", shown);
}

- (void)testANonDateValueIsLeftAlone
{
    // nil, not a guess: the caller then shows the value as it stands
    XCTAssertNil([XFDateDisplay localizedStringForValue:@"hello" typeName:@"string"]);
    XCTAssertNil([XFDateDisplay localizedStringForValue:@"hello" typeName:nil]);
    XCTAssertNil([XFDateDisplay localizedStringForValue:@"" typeName:@"date"]);
}

- (void)testAHalfTypedDateIsShownAsTyped
{
    // mid-edit values must not become a guessed date
    XCTAssertNil([XFDateDisplay localizedStringForValue:@"2025-01" typeName:@"date"]);
    XCTAssertNil([XFDateDisplay localizedStringForValue:@"not a date" typeName:@"date"]);
}

- (void)testControlsAreReadThroughTheirBoundType
{
    XFProcessor *p = [self dateForm];
    XFControl *input = p.controls[0];
    XFControl *dateOutput = p.controls[1];
    XFControl *timeOutput = p.controls[2];
    XFControl *textOutput = p.controls[3];
    XCTAssertNotNil([XFDateDisplay localizedStringForControl:input]);
    XCTAssertNotNil([XFDateDisplay localizedStringForControl:dateOutput]);
    XCTAssertNotNil([XFDateDisplay localizedStringForControl:timeOutput]);
    // and a plain string output is not a date
    XCTAssertNil([XFDateDisplay localizedStringForControl:textOutput]);
    // the INSTANCE is untouched: the lexical value is the value
    XCTAssertEqualObjects(dateOutput.stringValue, @"2025-01-31");
}

@end
