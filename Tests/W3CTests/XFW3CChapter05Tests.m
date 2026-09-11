/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* W3C XForms 1.1 test suite, chapter 5 (Datatypes) — 15 cases. The 5.1
   forms bind one input per datatype and flip them all valid/invalid
   through their own triggers; the tests assert each input control's
   validity state directly (the form's event-relay outputs are the
   human-visible version of the same MIP state). SPEC-TRUE. */
#import "XFW3CTestCase.h"

@interface XFW3CChapter05Tests : XFW3CTestCase
@end

@implementation XFW3CChapter05Tests

/// ref-or-bind attribute → the input control, for the my_* forms.
- (NSDictionary<NSString *, XFControl *> *)typedInputs
{
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (XFControl *c in [self allControls]) {
        if (![c isKindOfClass:[XFInputControl class]]) {
            continue;
        }
        NSString *key = [[c.element attributeForName:@"ref"] stringValue]
            ?: [[c.element attributeForName:@"bind"] stringValue];
        if (key.length) {
            out[key] = c;
        }
    }
    return out;
}

- (void)assertAllTypedInputsValid:(NSString *)context
{
    [[self typedInputs] enumerateKeysAndObjectsUsingBlock:
        ^(NSString *ref, XFControl *c, BOOL *stop) {
        (void)stop;
        if ([ref hasPrefix:@"my_"]) {
            XCTAssertTrue(c.valid, @"%@: %@ must be valid", context, ref);
        }
    }];
}

- (void)assertTypedInputsInvalidExcept:(NSArray<NSString *> *)stillValid
{
    [[self typedInputs] enumerateKeysAndObjectsUsingBlock:
        ^(NSString *ref, XFControl *c, BOOL *stop) {
        (void)stop;
        if (![ref hasPrefix:@"my_"]) {
            return;
        }
        if ([stillValid containsObject:ref]) {
            XCTAssertTrue(c.valid, @"%@ must stay valid", ref);
        } else {
            XCTAssertFalse(c.valid, @"%@ must be invalid after bogus data", ref);
        }
    }];
}

- (void)test_5_1_a_BuiltInPrimitiveTypes
{
    [self loadRequired:@"Chapt05/5.1/5.1.a.xhtml"];
    [self activateTriggerLabeled:@"Valid Values"];
    [self assertAllTypedInputsValid:@"after Valid Values"];
    [self activateTriggerLabeled:@"Invalid Values"];
    // "…XFORMS-INVALID for all the data types except string"
    [self assertTypedInputsInvalidExcept:@[ @"my_string" ]];
}

- (void)test_5_1_b_BuiltInDerivedTypes
{
    [self loadRequired:@"Chapt05/5.1/5.1.b.xhtml"];
    [self activateTriggerLabeled:@"Valid Values"];
    [self assertAllTypedInputsValid:@"after Valid Values"];
    [self activateTriggerLabeled:@"Invalid Values"];
    // "…except normalizedString and token"
    [self assertTypedInputsInvalidExcept:@[ @"my_normalizedString", @"my_token" ]];
}

- (void)test_5_1_c_BasicProfilePrimitiveTypes
{
    [self loadRequired:@"Chapt05/5.1/5.1.c.xhtml"];
    [self activateTriggerLabeled:@"Valid Values"];
    [self assertAllTypedInputsValid:@"after Valid Values"];
    [self activateTriggerLabeled:@"Invalid Values"];
    [self assertTypedInputsInvalidExcept:@[ @"my_string" ]];
}

- (void)test_5_1_d_BasicProfileDerivedTypes
{
    [self loadRequired:@"Chapt05/5.1/5.1.d.xhtml"];
    [self activateTriggerLabeled:@"Valid Values"];
    [self assertAllTypedInputsValid:@"after Valid Values"];
    [self activateTriggerLabeled:@"Invalid Values"];
    [self assertTypedInputsInvalidExcept:@[ @"my_normalizedString", @"my_token" ]];
}

- (void)test_5_1_e_XsiTypePrimitive
{
    [self loadRequired:@"Chapt05/5.1/5.1.e.xhtml"];
    XFControl *date = [self typedInputs][@"my_date"];
    XCTAssertNotNil(date);
    [self activateTriggerLabeled:@"Valid Value"];
    XCTAssertTrue(date.valid, @"1999-05-31 is a valid xsd:date (via xsi:type)");
    [self activateTriggerLabeled:@"Invalid Value"];
    XCTAssertFalse(date.valid, @"'Bogus Data' is not a valid xsd:date");
}

- (void)runEmptyContentCase:(NSString *)relPath
{
    // "non-empty-content" garbage start → the Run Test trigger empties
    // every node → every XForms-namespace type must accept empty.
    [self loadRequired:relPath];
    XFControl *dateTime = [self typedInputs][@"my_dateTime"] ?: [self typedInputs][@"my_normalizedString"];
    XCTAssertNotNil(dateTime);
    [self activateTriggerLabeled:@"Run Test"];
    [self assertAllTypedInputsValid:@"after Run Test (empty content)"];
}

- (void)test_5_2_1_a_EmptyContentPrimitives
{
    [self runEmptyContentCase:@"Chapt05/5.2/5.2.1/5.2.1.a.xhtml"];
}

- (void)test_5_2_1_b_EmptyContentDerived
{
    [self runEmptyContentCase:@"Chapt05/5.2/5.2.1/5.2.1.b.xhtml"];
}

- (void)test_5_2_1_c_EmptyContentBasicProfile
{
    [self runEmptyContentCase:@"Chapt05/5.2/5.2.1/5.2.1.c.xhtml"];
}

- (void)test_5_2_2_a_ListItem
{
    // ready-time setvalue "RedBlueGreen" — one listItem, valid
    [self loadRequired:@"Chapt05/5.2/5.2.2/5.2.2.a.xhtml"];
    XFControl *input = [self controlOfClass:[XFInputControl class] index:0];
    XCTAssertEqualObjects([self stringForXPath:@"/car/availableColors"], @"RedBlueGreen");
    XCTAssertTrue(input.valid, @"'RedBlueGreen' is a valid xforms:listItem");
}

- (void)test_5_2_3_a_ListItems
{
    [self loadRequired:@"Chapt05/5.2/5.2.3/5.2.3.a.xhtml"];
    XFControl *input = [self controlOfClass:[XFInputControl class] index:0];
    XCTAssertEqualObjects([self stringForXPath:@"/car/availableColors"], @"Red Blue Green");
    XCTAssertTrue(input.valid, @"'Red Blue Green' is a valid xforms:listItems");
}

- (void)test_5_2_4_a_DayTimeDuration
{
    [self loadRequired:@"Chapt05/5.2/5.2.4/5.2.4.a.xhtml"];
    XFControl *input = [self controlOfClass:[XFInputControl class] index:0];
    XCTAssertTrue(input.valid, @"P5DT3H4M2S is a valid xforms:dayTimeDuration");
}

- (void)test_5_2_5_a_YearMonthDuration
{
    [self loadRequired:@"Chapt05/5.2/5.2.5/5.2.5.a.xhtml"];
    XFControl *input = [self controlOfClass:[XFInputControl class] index:0];
    XCTAssertTrue(input.valid, @"P100Y1M is a valid xforms:yearMonthDuration");
}

- (void)test_5_2_6_a_Email
{
    [self loadRequired:@"Chapt05/5.2/5.2.6/5.2.6.a.xhtml"];
    XFControl *input = [self controlOfClass:[XFInputControl class] index:0];
    [self activateTriggerLabeled:@"Valid Email Test 1"];
    XCTAssertTrue(input.valid, @"valid email 1: '%@'", input.stringValue);
    [self activateTriggerLabeled:@"Invalid Email Test 1"];
    XCTAssertFalse(input.valid, @"invalid email 1: '%@'", input.stringValue);
    [self activateTriggerLabeled:@"Valid Email Test 2"];
    XCTAssertTrue(input.valid, @"valid email 2: '%@'", input.stringValue);
    [self activateTriggerLabeled:@"Invalid Email Test 2"];
    XCTAssertFalse(input.valid, @"invalid email 2: '%@'", input.stringValue);
}

- (void)test_5_2_7_a_CardNumber
{
    [self loadRequired:@"Chapt05/5.2/5.2.7/5.2.7.a.xhtml"];
    XFControl *input = [self controlOfClass:[XFInputControl class] index:0];
    [self activateTriggerLabeled:@"Valid card-number Test 1"];
    XCTAssertTrue(input.valid, @"valid card-number 1: '%@'", input.stringValue);
    [self activateTriggerLabeled:@"Invalid card-number Test 1"];
    XCTAssertFalse(input.valid, @"invalid card-number 1: '%@'", input.stringValue);
    [self activateTriggerLabeled:@"Valid card-number Test 2"];
    XCTAssertTrue(input.valid, @"valid card-number 2: '%@'", input.stringValue);
    [self activateTriggerLabeled:@"Invalid card-number Test 2"];
    XCTAssertFalse(input.valid, @"invalid card-number 2: '%@'", input.stringValue);
}

- (void)test_5_2_7_b_CardNumberCreditCardExample
{
    [self loadRequired:@"Chapt05/5.2/5.2.7/5.2.7.b.xhtml"];
    XFControl *input = [self controlOfClass:[XFInputControl class] index:0];
    [self activateTriggerLabeled:@"Valid card-number Test"];
    XCTAssertTrue(input.valid, @"valid card-number: '%@'", input.stringValue);
}

@end
