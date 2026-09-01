/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* W3C XForms 1.1 test suite, appendix B (Common Insert and Delete
   Recipes) as XCTest assertions — see XFW3CTestCase.h for the approach
   and the spec-true policy. Every case runs its recipe at xforms-ready;
   the tests assert the resulting instance state through XPath. */
#import "XFW3CTestCase.h"

@interface XFW3CAppendixBTests : XFW3CTestCase
@end

@implementation XFW3CAppendixBTests

- (void)test_b_1_a_PrependElementCopy
{
    // insert context="people" origin="…/person", no nodeset: the clone
    // becomes the FIRST child of the context node
    [self loadRequired:@"Appendix/B/B.1/b.1.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"count(people/person)"], @"2");
    XCTAssertEqualObjects([self stringForXPath:@"people/person[1]/name"], @"",
                          @"the empty prototype is prepended");
    XCTAssertEqualObjects([self stringForXPath:@"people/person[2]/name"], @"Jane Doe");
}

- (void)test_b_2_a_AppendElementCopy
{
    [self loadRequired:@"Appendix/B/B.2/b.2.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"count(people/person)"], @"2");
    XCTAssertEqualObjects([self stringForXPath:@"people/person[1]/name"], @"Jane Doe");
    XCTAssertEqualObjects([self stringForXPath:@"people/person[2]/name"], @"",
                          @"the empty prototype is appended");
}

- (void)test_b_3_a_DuplicateElement
{
    // insert nodeset="paragraph[2]": clone it, insert after it
    [self loadRequired:@"Appendix/B/B.3/b.3.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"count(paragraph)"], @"3");
    XCTAssertEqualObjects([self stringForXPath:@"paragraph[3]"],
                          @"Primis abhorreant delicatissimi",
                          @"the third paragraph duplicates the second");
}

- (void)test_b_4_a_SetAttribute
{
    // an attribute origin attaches to the context node, replacing a
    // same-named attribute
    [self loadRequired:@"Appendix/B/B.4/b.4.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"item[1]/@rating"], @"classified");
    XCTAssertEqualObjects([self stringForXPath:@"item[2]/@rating"], @"classified",
                          @"the attribute is copied onto item 2");
    XCTAssertEqualObjects([self stringForXPath:@"item[3]/@rating"], @"classified",
                          @"item 3's 'unknown' is replaced");
}

- (void)test_b_5_a_RemoveElement
{
    [self loadRequired:@"Appendix/B/B.5/b.5.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"count(item)"], @"1");
    XCTAssertEqualObjects([self stringForXPath:@"item[1]/product"], @"SKU-0815");
}

- (void)test_b_6_a_RemoveAttribute
{
    [self loadRequired:@"Appendix/B/B.6/b.6.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"count(item/@rating)"], @"0",
                          @"the rating attribute is deleted");
    XCTAssertEqualObjects([self stringForXPath:@"item/@key"], @"23");
}

- (void)test_b_7_a_RemoveNodeset
{
    [self loadRequired:@"Appendix/B/B.7/b.7.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"count(track)"], @"0",
                          @"all tracks are deleted");
    XCTAssertEqualObjects([self stringForXPath:@"name"], @"Music for Airports");
}

- (void)test_b_8_a_CopyNodeset
{
    // a multi-node origin: ALL origin nodes are cloned, in order
    [self loadRequired:@"Appendix/B/B.8/b.8.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"count(people/person)"], @"3");
    XCTAssertEqualObjects([self stringForXPath:@"people/person[1]/name"], @"Jane Doe");
    XCTAssertEqualObjects([self stringForXPath:@"people/person[2]/name"], @"John Doe");
    XCTAssertEqualObjects([self stringForXPath:@"people/person[3]/name"], @"Joe Sixpack");
}

- (void)test_b_9_a_CopyAttributeList
{
    // origin="../item[1]/@*": every attribute is copied onto the context
    [self loadRequired:@"Appendix/B/B.9/b.9.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"item[2]/@key"], @"0");
    XCTAssertEqualObjects([self stringForXPath:@"item[2]/@rating"], @"classified");
}

- (void)test_b_10_a_ReplaceElement
{
    // insert the prototype after person[1], then delete person[1]
    [self loadRequired:@"Appendix/B/B.10/b.10.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"count(person)"], @"1");
    XCTAssertEqualObjects([self stringForXPath:@"person[1]/name"], @"",
                          @"the named person is replaced by the empty prototype");
}

- (void)test_b_11_a_ReplaceAttribute
{
    // setvalue on the attribute node
    [self loadRequired:@"Appendix/B/B.11/b.11.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"item[1]/@key"], @"0");
    XCTAssertEqualObjects([self stringForXPath:@"item[2]/@key"], @"0",
                          @"item 2's key is overwritten with item 1's");
}

- (void)test_b_12_a_ReplaceInstanceWithInsert
{
    // insert nodeset="." at the root: the document element is replaced
    // by the empty prototype cart
    [self loadRequired:@"Appendix/B/B.12/b.12.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"count(item)"], @"0",
                          @"the empty cart replaced the full one");
}

- (void)test_b_13_a_MoveElement
{
    // clone playlist1's track 461 into playlist2, delete the original
    [self loadRequired:@"Appendix/B/B.13/b.13.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"count(playlist[2]/track)"], @"3");
    XCTAssertEqualObjects([self stringForXPath:@"playlist[2]/track[3]/@id"], @"461");
    XCTAssertEqualObjects([self stringForXPath:@"count(playlist[1]/track)"], @"2",
                          @"the original 461 is deleted");
    XCTAssertEqualObjects([self stringForXPath:@"playlist[1]/track[2]/@id"], @"629");
}

- (void)test_b_14_a_MoveAttribute
{
    [self loadRequired:@"Appendix/B/B.14/b.14.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"item[2]/@rating"], @"classified",
                          @"the attribute moved to item 2");
    XCTAssertEqualObjects([self stringForXPath:@"count(item[1]/@rating)"], @"0",
                          @"…and is gone from item 1");
}

- (void)test_b_15_a_InsertIntoHeterogeneousNodeset
{
    // chapter/* across both chapters = 7 nodes; at=7 position=before →
    // the empty paragraph lands in chapter 2, before "Exemplum 3"
    [self loadRequired:@"Appendix/B/B.15/b.15.a.xhtml"];
    XCTAssertEqualObjects([self stringForXPath:@"count(chapter[2]/paragraph)"], @"1");
    XCTAssertEqualObjects([self stringForXPath:@"chapter[2]/paragraph[1]"], @"");
    XCTAssertEqualObjects([self stringForXPath:@"count(chapter[1]/*)"], @"5",
                          @"chapter 1 is untouched");
}

@end
