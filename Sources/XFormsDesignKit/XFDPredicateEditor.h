/* The predicate editor: one step's predicates, edited against the nodes
   the step selects (XFDPredicateEditor.xib).
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>

@class XFDExpressionField;

/// Modal predicate editor for ONE step of the picker's Steps table: the
/// field takes a predicate list ([a][b]) or a bare expression (one
/// predicate, brackets added), validated live; the table shows every
/// node the step selects WITHOUT its predicates and which of them the
/// current predicates keep \u2014 position() and last() run against that
/// candidate set, exactly as they will at refresh time.
@interface XFDPredicateEditor : NSObject <NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate>
{
    IBOutlet NSPanel *_panel;
    IBOutlet NSTextField *_introField;
    IBOutlet XFDExpressionField *_field;
    IBOutlet NSTextField *_statusField;
    IBOutlet NSTableView *_table;
    IBOutlet NSButton *_okButton;
    NSArray *_topLevelObjects;
    NSString *_baseExpression;
    XFXMLElement *_hostElement;
    XFXMLNode *_contextNode;
    XFModel *_model;
    NSArray *_rows;
    NSString *_normalized;
    BOOL _valid;
    NSString *_result;
}
+ (NSString *)runWithBaseExpression:(NSString *)base
                         predicates:(NSString *)predicates
                        hostElement:(XFXMLElement *)hostElement
                        contextNode:(XFXMLNode *)contextNode
                              model:(XFModel *)model;
@end
