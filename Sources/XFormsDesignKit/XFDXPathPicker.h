/* The node picker: an expression built from its context, steps and the
   instances, evaluated live (XFDXPathPicker.xib).
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>
#import "XFDXPathField.h"

@class XFDExpressionField;

/// Modal expression builder: shows the evaluation CONTEXT and what the
/// attribute EXPECTS, lets the start be overridden (relative / absolute /
/// instance('id')), offers the instance tree for a quick base path,
/// decomposes simple location paths into an EDITABLE STEPS table (axis /
/// node test / predicates, + / −), keeps the raw expression editable
/// throughout (a non-simple expression — functions, unions, // — simply
/// disables the steps table), and EVALUATES LIVE into a result table
/// with cardinality warnings. OK requires only that the expression
/// compiles.
@interface XFDXPathPicker : NSObject <NSTableViewDataSource, NSTableViewDelegate>
{
    IBOutlet NSPanel *_panel;
    IBOutlet NSTextField *_contextField;
    IBOutlet NSPopUpButton *_instancePopup;
    IBOutlet NSSegmentedControl *_styleControl;
    IBOutlet NSOutlineView *_tree;
    IBOutlet NSTableView *_stepsTable;
    IBOutlet NSSegmentedControl *_stepsControl;
    IBOutlet NSTextField *_stepsStatusField;
    IBOutlet XFDExpressionField *_pathField;
    IBOutlet NSTextField *_statusField;
    IBOutlet NSTableView *_resultTable;
    IBOutlet NSButton *_okButton;
    NSArray *_topLevelObjects;
    XFProcessor *_processor;
    XFXMLNode *_contextNode;
    XFXMLElement *_hostElement;
    XFDXPathExpectation _expectation;
    NSString *_result;
    NSMutableArray *_steps;         /* step dicts; nil = not a simple path */
    NSString *_startKind;           /* context | root | instance */
    NSString *_startInstance;
    NSArray *_resultRows;           /* dicts: index / node / value */
    NSArray *_treeRows;             /* computed-expression mode: dicts
                                       label / source / path / depth /
                                       editable */
    IBOutlet NSButton *_editPathButton;
    IBOutlet NSButton *_predicateButton;
    IBOutlet NSPopUpButton *_suggestPopup;
    IBOutlet NSTextField *_functionInfoField;
    BOOL _syncing;
}
+ (NSString *)runForProcessor:(XFProcessor *)processor
                  contextNode:(XFXMLNode *)contextNode
                  hostElement:(XFXMLElement *)hostElement
                        title:(NSString *)title
                      initial:(NSString *)initial
                  expectation:(XFDXPathExpectation)expectation;
@end
