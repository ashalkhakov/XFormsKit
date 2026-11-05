/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDPredicateEditor.h"
#import "XFDXPathPaths.h"
#import "XFDExpressionField.h"
#import <XFormsKit/XFXMLTypes.h>

#pragma mark - Predicate sub-editing

NSDictionary *XFDPredicatePreview(NSString *baseExpression,
                                  NSString *predicates,
                                  XFXMLElement *hostElement,
                                  XFXMLNode *contextNode,
                                  XFModel *model)
{
    NSString *trimmed = [predicates ?: @"" stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *normalized = @"";
    if (trimmed.length) {
        // typing convenience: a bare expression IS one predicate
        normalized = [trimmed hasPrefix:@"["]
            ? trimmed : [NSString stringWithFormat:@"[%@]", trimmed];
    }
    if (normalized.length) {
        // the list must parse AS predicates (brackets, order, nesting)
        NSError *parse = nil;
        if ([XFXPath xpathWithString:[@"self::node()" stringByAppendingString:normalized]
                             element:hostElement error:&parse] == nil) {
            return @{ @"ok": @NO,
                      @"normalized": normalized,
                      @"error": [parse localizedDescription] ?: @"does not parse" };
        }
    }
    XFExprContext * (^makeContext)(void) = ^XFExprContext * {
        XFExprContext *ctx = [[XFExprContext alloc] initWithNode:contextNode];
        ctx.model = model;
        return ctx;
    };
    XFXPath *base = [XFXPath xpathWithString:baseExpression element:hostElement error:NULL];
    XFXPathValue *baseValue = [base evaluateInContext:makeContext() error:NULL];
    if (baseValue == nil || baseValue.type != XFXPathValueTypeNodeSet) {
        return @{ @"ok": @NO,
                  @"normalized": normalized,
                  @"error": @"the step selects no node-set here" };
    }
    NSArray *candidates = baseValue.nodes;
    NSArray *kept = candidates;
    if (normalized.length) {
        XFXPath *filtered = [XFXPath xpathWithString:
            [baseExpression stringByAppendingString:normalized]
                                             element:hostElement error:NULL];
        XFXPathValue *filteredValue = [filtered evaluateInContext:makeContext() error:NULL];
        kept = filteredValue.type == XFXPathValueTypeNodeSet ? filteredValue.nodes : @[];
    }
    NSMutableArray *rows = [NSMutableArray array];
    NSUInteger cap = MIN(candidates.count, (NSUInteger)200);
    for (NSUInteger i = 0; i < cap; i++) {
        XFXMLNode *node = candidates[i];
        NSString *text = [node stringValue] ?: @"";
        if (text.length > 80) {
            text = [[text substringToIndex:79] stringByAppendingString:@"\u2026"];
        }
        [rows addObject:@{ @"index": @(i + 1),
                           @"node": XFDDisplayPathOfNode(node),
                           @"value": text,
                           @"match": @([kept indexOfObjectIdenticalTo:node] != NSNotFound) }];
    }
    return @{ @"ok": @YES,
              @"normalized": normalized,
              @"total": @(candidates.count),
              @"matching": @(kept.count),
              @"rows": rows };
}

// Its outlets (its XIB's connections), on the ivars above.
@interface XFDPredicateEditor ()
@property (nonatomic, strong) IBOutlet NSPanel *panel;
@property (nonatomic, strong) IBOutlet NSTextField *introField;
@property (nonatomic, strong) IBOutlet XFDExpressionField *field;
@property (nonatomic, strong) IBOutlet NSTextField *statusField;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSButton *okButton;
@end

@implementation XFDPredicateEditor

/// The panel from its XIB (XFDPredicateEditor.xib), told what it filters.
- (BOOL)loadPanel
{
    NSArray *objects = nil;
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"XFDPredicateEditor"
                                          bundle:[NSBundle bundleForClass:[XFDPredicateEditor class]]];
    if (![nib instantiateWithOwner:self topLevelObjects:&objects] || _panel == nil) {
        NSLog(@"XFormsDesignKit: XFDPredicateEditor did not load");
        return NO;
    }
    _topLevelObjects = objects;
    [_introField setStringValue:[NSString stringWithFormat:
        @"Filters the nodes  %@  selects \u2014 the predicates run per node; "
        @"position() and last() see the candidate set below.", _baseExpression]];
    [_field setFont:[NSFont userFixedPitchFontOfSize:11]];
    [_field setPlaceholderString:@"[price > 10]  \u2014 or a bare expression"];
    [_field setDelegate:self];
    return YES;
}

- (void)preview
{
    NSDictionary *p = XFDPredicatePreview(_baseExpression, [_field stringValue],
                                          _hostElement, _contextNode, _model);
    _valid = [p[@"ok"] boolValue];
    _normalized = p[@"normalized"] ?: @"";
    _rows = p[@"rows"] ?: @[];
    [_table reloadData];
    [_okButton setEnabled:_valid];
    [_field setInvalid:!_valid];
    if (!_valid) {
        [_statusField setStringValue:[@"\u2717 " stringByAppendingString:p[@"error"] ?: @""]];
        [_statusField setTextColor:[NSColor redColor]];
        return;
    }
    NSUInteger total = [p[@"total"] unsignedIntegerValue];
    NSUInteger matching = [p[@"matching"] unsignedIntegerValue];
    NSString *text = _normalized.length == 0
        ? [NSString stringWithFormat:@"No predicates \u2014 all %lu node%s kept.",
           (unsigned long)total, total == 1 ? "" : "s"]
        : [NSString stringWithFormat:@"\u2713 %lu of %lu node%s match.",
           (unsigned long)matching, (unsigned long)total, total == 1 ? "" : "s"];
    [_statusField setStringValue:text];
    [_statusField setTextColor:matching == 0 && _normalized.length
        ? [NSColor colorWithCalibratedRed:0.72 green:0.45 blue:0.10 alpha:1]
        : [NSColor disabledControlTextColor]];
}

- (void)controlTextDidChange:(NSNotification *)note
{
    (void)note;
    [self preview];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
    (void)table;
    return (NSInteger)_rows.count;
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
    (void)table;
    if ((NSUInteger)row >= _rows.count) {
        return nil;
    }
    NSDictionary *r = _rows[(NSUInteger)row];
    if ([[column identifier] isEqualToString:@"match"]) {
        return [r[@"match"] boolValue] ? @"\u2713" : @"\u2014";
    }
    return r[[column identifier]];
}

- (BOOL)tableView:(NSTableView *)table shouldSelectRow:(NSInteger)row
{
    (void)table; (void)row;
    return NO;
}

- (IBAction)okClicked:(id)sender
{
    (void)sender;
    if (!_valid) {
        XFDBeep();
        return;
    }
    _result = _normalized;
    [NSApp stopModal];
    [_panel orderOut:nil];
}

- (IBAction)cancelClicked:(id)sender
{
    (void)sender;
    _result = nil;
    [NSApp abortModal];
    [_panel orderOut:nil];
}

- (BOOL)windowShouldClose:(id)sender
{
    (void)sender;
    [self cancelClicked:sender];
    return NO;
}

+ (NSString *)runWithBaseExpression:(NSString *)base
                         predicates:(NSString *)predicates
                        hostElement:(XFXMLElement *)hostElement
                        contextNode:(XFXMLNode *)contextNode
                              model:(XFModel *)model
{
    XFDPredicateEditor *editor = [[XFDPredicateEditor alloc] init];
    editor->_baseExpression = base ?: @".";
    editor->_hostElement = hostElement;
    editor->_contextNode = contextNode;
    editor->_model = model;
    if (![editor loadPanel]) {
        return nil;
    }
    // brackets stripped for the common single-predicate case: the field
    // edits the EXPRESSION, the brackets come back on OK
    NSString *initial = predicates ?: @"";
    if ([initial hasPrefix:@"["] && [initial hasSuffix:@"]"]
        && [initial rangeOfString:@"]["].location == NSNotFound) {
        initial = [initial substringWithRange:NSMakeRange(1, initial.length - 2)];
    }
    [editor->_field setStringValue:initial];
    [editor preview];
    [editor->_panel center];
    [editor->_panel makeFirstResponder:editor->_field];
    [NSApp runModalForWindow:editor->_panel];
    return editor->_result;
}

@end
