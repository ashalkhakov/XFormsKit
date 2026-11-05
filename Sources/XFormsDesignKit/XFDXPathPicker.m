/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDXPathPicker.h"
#import "XFDXPathPaths.h"
#import "XFDPredicateEditor.h"
#import "XFDXPathTextStorage.h"
#import "XFDExpressionField.h"
#import <XFormsKit/XFXMLTypes.h>

// Its outlets (its XIB's connections), on the ivars above.
@interface XFDXPathPicker ()
@property (nonatomic, strong) IBOutlet NSPanel *panel;
@property (nonatomic, strong) IBOutlet NSTextField *contextField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *instancePopup;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *styleControl;
@property (nonatomic, strong) IBOutlet NSOutlineView *tree;
@property (nonatomic, strong) IBOutlet NSTableView *stepsTable;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *stepsControl;
@property (nonatomic, strong) IBOutlet NSTextField *stepsStatusField;
@property (nonatomic, strong) IBOutlet XFDExpressionField *pathField;
@property (nonatomic, strong) IBOutlet NSTextField *statusField;
@property (nonatomic, strong) IBOutlet NSTableView *resultTable;
@property (nonatomic, strong) IBOutlet NSButton *okButton;
@property (nonatomic, strong) IBOutlet NSButton *editPathButton;
@property (nonatomic, strong) IBOutlet NSButton *predicateButton;
@property (nonatomic, strong) IBOutlet NSPopUpButton *suggestPopup;
@property (nonatomic, strong) IBOutlet NSTextField *functionInfoField;
@end

/// Flatten a structure tree for the table: location paths and path
/// expressions stay LEAVES (they are the editable unit — the sub-picker
/// decomposes them into steps itself).
static void XFDFlattenStructure(NSDictionary *node, NSArray *path,
                                NSUInteger depth, NSMutableArray *rows)
{
    NSString *kind = node[@"kind"];
    NSString *label = kind;
    if (node[@"op"] != nil) {
        label = [NSString stringWithFormat:@"%@  %@", kind, node[@"op"]];
    } else if (node[@"name"] != nil) {
        label = [NSString stringWithFormat:@"%@  %@()", kind, node[@"name"]];
    }
    BOOL leafPath = [kind isEqualToString:@"location"] || [kind isEqualToString:@"path"];
    [rows addObject:@{ @"label": label,
                       @"source": node[@"source"] ?: @"",
                       @"path": path,
                       @"depth": @(depth),
                       @"editable": @(leafPath) }];
    if (leafPath) {
        return;
    }
    NSArray *children = node[@"children"] ?: @[];
    for (NSUInteger i = 0; i < children.count; i++) {
        XFDFlattenStructure(children[i],
                            [path arrayByAddingObject:@(i)],
                            depth + 1, rows);
    }
}

@implementation XFDXPathPicker

- (NSArray<XFInstance *> *)instances
{
    NSMutableArray *out = [NSMutableArray array];
    for (XFModel *model in _processor.models) {
        [out addObjectsFromArray:model.instances];
    }
    return out;
}

- (XFInstance *)chosenInstance
{
    NSInteger i = [_instancePopup indexOfSelectedItem];
    NSArray *all = [self instances];
    return (i >= 0 && (NSUInteger)i < all.count) ? all[(NSUInteger)i] : nil;
}

- (XFInstance *)instanceContainingNode:(XFXMLNode *)node
{
    XFXMLDocument *doc = [node rootDocument];
    for (XFInstance *instance in [self instances]) {
        if (instance.document == doc) {
            return instance;
        }
    }
    return nil;
}

static NSString *XFDExpectationLabel(XFDXPathExpectation e)
{
    switch (e) {
        case XFDXPathExpectNodeSet: return @"a node-set";
        case XFDXPathExpectNode:    return @"a single node";
        case XFDXPathExpectValue:   return @"a value";
        default:                    return nil;
    }
}

#pragma mark panel construction

/// The panel from its XIB (XFDXPathPicker.xib), and what is the form's:
/// the context it says, the instances, the axes a step may take, the
/// suggestions.
- (BOOL)loadPanelWithTitle:(NSString *)title
{
    NSArray *objects = nil;
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"XFDXPathPicker"
                                          bundle:[NSBundle bundleForClass:[XFDXPathPicker class]]];
    if (![nib instantiateWithOwner:self topLevelObjects:&objects] || _panel == nil) {
        NSLog(@"XFormsDesignKit: XFDXPathPicker did not load");
        return NO;
    }
    _topLevelObjects = objects;
    [_panel setTitle:title];

    // context awareness: where relative expressions start, and what the
    // attribute wants back
    XFInstance *ctxInstance = [self instanceContainingNode:_contextNode];
    NSString *ctxText;
    if (_contextNode != nil) {
        ctxText = [NSString stringWithFormat:@"Context: %@%@",
            XFDDisplayPathOfNode(_contextNode),
            ctxInstance.identifier.length
                ? [NSString stringWithFormat:@"  (instance ‘%@’)", ctxInstance.identifier]
                : @""];
    } else {
        ctxText = @"Context: default instance root";
    }
    NSString *expectLabel = XFDExpectationLabel(_expectation);
    if (expectLabel != nil) {
        ctxText = [ctxText stringByAppendingFormat:@"  —  expects %@", expectLabel];
    }
    [_contextField setStringValue:ctxText];

    [_instancePopup removeAllItems];
    NSUInteger n = 0;
    for (XFModel *model in _processor.models) {
        for (XFInstance *instance in model.instances) {
            NSString *name = instance.identifier.length ? instance.identifier
                : [NSString stringWithFormat:@"instance %lu", (unsigned long)++n];
            NSString *owner = model.identifier.length ? model.identifier : @"model";
            [_instancePopup addItemWithTitle:[NSString stringWithFormat:@"%@  (%@)", name, owner]];
        }
    }
    [_styleControl setSelectedSegment:_contextNode != nil ? 0 : 2];
    [self populateSuggestions];

    // a step's axis is chosen from the axes XPath has
    NSPopUpButtonCell *axisCell = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
    [axisCell setBordered:NO];
    [axisCell setControlSize:NSSmallControlSize];
    [axisCell setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [axisCell addItemsWithTitles:XFDKnownAxes()];
    [[_stepsTable tableColumnWithIdentifier:@"axis"] setDataCell:axisCell];
    [[[_stepsTable tableColumnWithIdentifier:@"predicates"] dataCell] setFont:[NSFont userFixedPitchFontOfSize:11]];

    [_pathField setFont:[NSFont userFixedPitchFontOfSize:11]];
    [_pathField setTarget:self];
    [_pathField setAction:@selector(expressionEdited:)];
    [_pathField setDelegate:(id)self];
    [_functionInfoField setTextColor:[NSColor disabledControlTextColor]];
    return YES;
}

#pragma mark suggestions & function info

/// The Suggest menu: schema-implied refs relative to the context, the
/// event() properties the host's ev:event carries, and the model's
/// itext keys — spec knowledge in a menu instead of a spec reread.
- (void)populateSuggestions
{
    [_suggestPopup removeAllItems];
    [_suggestPopup addItemWithTitle:@"Suggest"];   // pull-down title slot
    NSMenu *menu = [_suggestPopup menu];
    void (^add)(NSString *) = ^(NSString *expression) {
        NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:expression
                                           action:@selector(suggestPicked:)
                                    keyEquivalent:@""];
        [item setTarget:self];
        [item setRepresentedObject:expression];
    };
    XFXMLNode *context = _contextNode
        ?: [[_processor defaultInstance] documentElement];
    NSArray *paths = XFDSchemaPathsFromNode(context, 80);
    for (NSString *path in paths) {
        add(path);
    }
    NSString *eventName = _hostElement
        ? [XFXML attributeValue:@"event"
                   namespaceURI:XFXMLEventsNamespaceURI
                      onElement:_hostElement]
        : nil;
    NSArray *props = XFDEventContextProperties(eventName);
    if (props.count) {
        [menu addItem:[NSMenuItem separatorItem]];
        for (NSString *prop in props) {
            add([NSString stringWithFormat:@"event('%@')", prop]);
        }
    }
    NSDictionary *translations = _processor.model.translations;
    if (translations.count) {
        NSString *lang = _processor.model.defaultLanguage
            ?: [[translations allKeys] firstObject];
        NSArray *keys = [[translations[lang] allKeys]
            sortedArrayUsingSelector:@selector(compare:)];
        if (keys.count) {
            [menu addItem:[NSMenuItem separatorItem]];
            NSUInteger cap = MIN(keys.count, (NSUInteger)30);
            for (NSUInteger i = 0; i < cap; i++) {
                add([NSString stringWithFormat:@"itext('%@')", keys[i]]);
            }
        }
    }
    [_suggestPopup setEnabled:[menu numberOfItems] > 1];
}

- (void)suggestPicked:(NSMenuItem *)item
{
    _syncing = YES;
    [_pathField setStringValue:[item representedObject] ?: @""];
    _syncing = NO;
    [self expressionChanged];
}

/// What the functions in the expression will give, resolved statically:
/// instance('id') → that instance's root; event('prop') → checked against
/// the host's ev:event; itext('key') → the translation. Spec facts,
/// surfaced where the expression is written.
- (void)refreshFunctionInfoFor:(XFXPath *)compiled
{
    NSMutableArray *notes = [NSMutableArray array];
    if (compiled != nil) {
        [self collectFunctionNotes:[compiled structure] into:notes];
    }
    NSMutableArray *unique = [NSMutableArray array];
    for (NSString *note in notes) {
        if (![unique containsObject:note]) {
            [unique addObject:note];
        }
    }
    [_functionInfoField setStringValue:[unique componentsJoinedByString:@"   ·   "]];
}

- (void)collectFunctionNotes:(NSDictionary *)node into:(NSMutableArray *)notes
{
    if ([node[@"kind"] isEqualToString:@"function"]) {
        NSString *name = node[@"name"];
        NSArray *args = node[@"children"];
        NSString *literal = nil;
        if (args.count == 1 && [args[0][@"kind"] isEqualToString:@"string"]) {
            NSString *src = args[0][@"source"];
            literal = [src length] >= 2
                ? [src substringWithRange:NSMakeRange(1, [src length] - 2)] : nil;
        }
        if ([name isEqualToString:@"instance"] && literal != nil) {
            XFInstance *found = nil;
            XFModel *owner = nil;
            for (XFModel *model in _processor.models) {
                for (XFInstance *instance in model.instances) {
                    if ([instance.identifier isEqualToString:literal]) {
                        found = instance;
                        owner = model;
                    }
                }
            }
            if (found != nil) {
                [notes addObject:[NSString stringWithFormat:
                    @"instance('%@') → <%@> (model %@)", literal,
                    [[found documentElement] name] ?: @"?",
                    owner.identifier.length ? owner.identifier : @"1"]];
            } else {
                [notes addObject:[NSString stringWithFormat:
                    @"⚠ no instance with id '%@'", literal]];
            }
        } else if ([name isEqualToString:@"event"]) {
            NSString *eventName = _hostElement
                ? [XFXML attributeValue:@"event"
                           namespaceURI:XFXMLEventsNamespaceURI
                              onElement:_hostElement]
                : nil;
            NSArray *props = XFDEventContextProperties(eventName);
            if (eventName.length == 0) {
                [notes addObject:@"event(): the host element declares no ev:event"];
            } else if (props == nil) {
                [notes addObject:[NSString stringWithFormat:
                    @"event() on '%@' — context properties unknown here", eventName]];
            } else if (literal != nil) {
                if ([props containsObject:literal]) {
                    [notes addObject:[NSString stringWithFormat:
                        @"event('%@') ✓ defined for %@", literal, eventName]];
                } else {
                    [notes addObject:[NSString stringWithFormat:
                        @"⚠ event('%@') not defined for %@%@", literal, eventName,
                        props.count ? [@" — has: " stringByAppendingString:
                            [props componentsJoinedByString:@", "]] : @""]];
                }
            } else if (props.count) {
                [notes addObject:[NSString stringWithFormat:
                    @"event() on '%@' → %@", eventName,
                    [props componentsJoinedByString:@", "]]];
            } else {
                [notes addObject:[NSString stringWithFormat:
                    @"event() on '%@' — no context properties", eventName]];
            }
        } else if ([name isEqualToString:@"itext"] && literal != nil) {
            XFModel *model = _processor.model;
            NSString *text = [model itextForIdentifier:literal language:nil];
            if (text != nil) {
                if (text.length > 40) {
                    text = [[text substringToIndex:39] stringByAppendingString:@"…"];
                }
                [notes addObject:[NSString stringWithFormat:
                    @"itext('%@') → ‘%@’ (%@)", literal, text,
                    [[model.translations.allKeys
                        sortedArrayUsingSelector:@selector(compare:)]
                        componentsJoinedByString:@", "]]];
            } else {
                [notes addObject:[NSString stringWithFormat:
                    @"⚠ no itext '%@' in the model", literal]];
            }
        }
    }
    for (NSDictionary *child in node[@"children"] ?: @[]) {
        [self collectFunctionNotes:child into:notes];
    }
}

#pragma mark expression ↔ steps sync

- (NSString *)expression
{
    return [_pathField stringValue];
}

/// Re-derive steps/start from the raw expression, refresh dependent UI,
/// evaluate. The single funnel every edit goes through.
- (void)expressionChanged
{
    NSString *expr = [self expression];
    NSDictionary *split = XFDSplitLocationPath(expr);
    if (split != nil) {
        _steps = [split[@"steps"] mutableCopy];
        _startKind = split[@"start"];
        _startInstance = split[@"instance"];
        [_stepsStatusField setStringValue:@""];
        [_stepsControl setEnabled:YES forSegment:0];
        [_stepsControl setEnabled:[_stepsTable selectedRow] >= 0 forSegment:1];
        _syncing = YES;
        NSInteger style = [_startKind isEqualToString:@"root"] ? 1
            : ([_startKind isEqualToString:@"instance"] ? 2 : 0);
        [_styleControl setSelectedSegment:style];
        if (_startInstance.length) {
            NSArray *all = [self instances];
            for (NSUInteger i = 0; i < all.count; i++) {
                if ([[all[i] identifier] isEqualToString:_startInstance]) {
                    [_instancePopup selectItemAtIndex:(NSInteger)i];
                    [_tree reloadData];
                    [_tree expandItem:[[self chosenInstance] documentElement] expandChildren:YES];
                    break;
                }
            }
        }
        _syncing = NO;
    } else {
        _steps = nil;
        [_stepsControl setEnabled:NO forSegment:0];
        [_stepsControl setEnabled:NO forSegment:1];
        // a COMPUTED expression (../in - ../out): show its structure tree
        // and let the embedded paths be edited with the sub-picker
        XFXPath *compiled = expr.length
            ? [XFXPath xpathWithString:expr element:_hostElement error:NULL] : nil;
        if (compiled != nil) {
            NSMutableArray *rows = [NSMutableArray array];
            XFDFlattenStructure([compiled structure], @[], 0, rows);
            _treeRows = rows;
            [_stepsStatusField setStringValue:
                @"Computed expression — select a path below to edit it."];
        } else {
            _treeRows = nil;
            [_stepsStatusField setStringValue:
                expr.length ? @"Does not parse — edit the expression directly." : @""];
        }
    }
    if (_steps != nil) {
        _treeRows = nil;
    }
    [self refreshStepsTableMode];
    [_stepsTable reloadData];
    [self evaluate];
}

/// Steps mode ↔ tree mode: swap headers, editability and the buttons.
- (void)refreshStepsTableMode
{
    BOOL tree = (_treeRows != nil);
    NSArray *columns = [_stepsTable tableColumns];
    [[[columns objectAtIndex:0] headerCell]
        setStringValue:tree ? @"Kind" : @"Axis"];
    [[[columns objectAtIndex:1] headerCell]
        setStringValue:tree ? @"Source" : @"Node"];
    [[[columns objectAtIndex:2] headerCell]
        setStringValue:tree ? @"" : @"Predicates"];
    // tree sources run long (sum(/balance/transaction[…]/amount)) — give
    // the Source column nearly the whole table there
    [[columns objectAtIndex:0] setWidth:tree ? 160 : 140];
    [[columns objectAtIndex:1] setWidth:tree ? 350 : 150];
    [[columns objectAtIndex:2] setWidth:tree ? 10 : 200];
    [[_stepsTable headerView] setNeedsDisplay:YES];
    [_stepsControl setHidden:tree];
    [_editPathButton setHidden:!tree];
    [_editPathButton setEnabled:NO];
    [_predicateButton setHidden:tree];
    [_predicateButton setEnabled:NO];
}

/// Steps were edited: render them back into the expression, evaluate.
- (void)stepsChanged
{
    if (_steps == nil) {
        return;
    }
    NSMutableDictionary *path = [NSMutableDictionary dictionaryWithDictionary:
        @{ @"start": _startKind ?: @"context", @"steps": _steps }];
    if (_startInstance) {
        path[@"instance"] = _startInstance;
    }
    _syncing = YES;
    [_pathField setStringValue:XFDJoinLocationPath(path)];
    _syncing = NO;
    [self evaluate];
}

#pragma mark evaluation

- (XFExprContext *)pickerContext
{
    XFXMLNode *node = _contextNode
        ?: [[_processor defaultInstance] documentElement];
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:node];
    ctx.model = _processor.model;
    return ctx;
}

- (void)evaluate
{
    NSString *expr = [self expression];
    [_pathField setInvalid:(expr.length != 0
        && [XFXPath xpathWithString:expr element:_hostElement error:NULL] == nil)];
    if (expr.length == 0) {
        _resultRows = @[];
        [_resultTable reloadData];
        [self refreshFunctionInfoFor:nil];
        [_statusField setStringValue:@"Enter or build an expression."];
        [_statusField setTextColor:[NSColor disabledControlTextColor]];
        [_okButton setEnabled:NO];
        return;
    }
    NSError *error = nil;
    XFXPath *compiled = [XFXPath xpathWithString:expr element:_hostElement error:&error];
    [self refreshFunctionInfoFor:compiled];
    if (compiled == nil) {
        _resultRows = @[];
        [_resultTable reloadData];
        [_statusField setStringValue:[@"✗ " stringByAppendingString:
            [error localizedDescription] ?: @"does not compile"]];
        [_statusField setTextColor:[NSColor redColor]];
        [_okButton setEnabled:NO];
        return;
    }
    [_okButton setEnabled:YES];   // compiling is all OK requires
    XFXPathValue *value = [compiled evaluateInContext:[self pickerContext] error:&error];
    if (value == nil) {
        _resultRows = @[];
        [_resultTable reloadData];
        [_statusField setStringValue:[@"✓ compiles — evaluation failed: "
            stringByAppendingString:[error localizedDescription] ?: @"?"]];
        [_statusField setTextColor:[NSColor disabledControlTextColor]];
        return;
    }

    NSMutableArray *rows = [NSMutableArray array];
    NSString *summary;
    if (value.type == XFXPathValueTypeNodeSet) {
        NSArray *nodes = value.nodes;
        summary = [NSString stringWithFormat:@"node-set, %lu node%s",
                   (unsigned long)nodes.count, nodes.count == 1 ? "" : "s"];
        NSUInteger cap = MIN(nodes.count, (NSUInteger)200);
        for (NSUInteger i = 0; i < cap; i++) {
            XFXMLNode *node = nodes[i];
            NSString *text = [node stringValue] ?: @"";
            if (text.length > 80) {
                text = [[text substringToIndex:79] stringByAppendingString:@"…"];
            }
            [rows addObject:@{ @"index": @(i + 1),
                               @"node": XFDDisplayPathOfNode(node),
                               @"value": text }];
        }
    } else {
        NSString *kind = value.type == XFXPathValueTypeString ? @"string"
            : (value.type == XFXPathValueTypeNumber ? @"number" : @"boolean");
        summary = [NSString stringWithFormat:@"%@ ‘%@’", kind, [value stringValue] ?: @""];
        [rows addObject:@{ @"index": @1, @"node": kind,
                           @"value": [value stringValue] ?: @"" }];
    }

    // cardinality against what the attribute wants — advice, never a gate
    NSString *warning = nil;
    if (_expectation == XFDXPathExpectNodeSet && value.type != XFXPathValueTypeNodeSet) {
        warning = @"the attribute expects nodes, this is a computed value";
    } else if (_expectation == XFDXPathExpectNode) {
        if (value.type != XFXPathValueTypeNodeSet) {
            warning = @"the attribute expects a node, this is a computed value";
        } else if (value.nodes.count == 0) {
            warning = @"empty node-set — the control will be unbound";
        } else if (value.nodes.count > 1) {
            warning = [NSString stringWithFormat:
                @"%lu nodes — only the first is used", (unsigned long)value.nodes.count];
        }
    }
    _resultRows = rows;
    [_resultTable reloadData];
    if (warning != nil) {
        [_statusField setStringValue:[NSString stringWithFormat:@"✓ %@ — ⚠ %@", summary, warning]];
        [_statusField setTextColor:[NSColor colorWithCalibratedRed:0.72 green:0.45 blue:0.10 alpha:1]];
    } else {
        [_statusField setStringValue:[@"✓ " stringByAppendingString:summary]];
        [_statusField setTextColor:[NSColor disabledControlTextColor]];
    }
}

#pragma mark actions

- (IBAction)expressionEdited:(id)sender
{
    (void)sender;
    if (!_syncing) {
        [self expressionChanged];
    }
}

- (void)controlTextDidChange:(NSNotification *)note
{
    if ([note object] == _pathField && !_syncing) {
        [self expressionChanged];
    }
}

- (IBAction)styleChanged:(id)sender
{
    (void)sender;
    // keep the steps, swap the start — the explicit context override
    NSInteger style = [_styleControl selectedSegment];
    _startKind = style == 1 ? @"root" : (style == 2 ? @"instance" : @"context");
    if (style == 2) {
        _startInstance = [self chosenInstance].identifier;
        if (_startInstance.length == 0) {
            [_statusField setStringValue:@"⚠ the chosen instance has no id — instance() needs one"];
            [_statusField setTextColor:[NSColor redColor]];
        }
    } else {
        _startInstance = nil;
    }
    if (_steps == nil) {
        _steps = [NSMutableArray array];
    }
    [self stepsChanged];
}

- (IBAction)instanceChanged:(id)sender
{
    (void)sender;
    [_tree reloadData];
    [_tree expandItem:[[self chosenInstance] documentElement] expandChildren:YES];
    if ([_startKind isEqualToString:@"instance"]) {
        [self styleChanged:nil];
    }
}

- (IBAction)stepsPlusMinusClicked:(NSSegmentedControl *)sender
{
    if (_steps == nil) {
        return;
    }
    if ([sender selectedSegment] == 0) {
        NSDictionary *step = @{ @"axis": @"child", @"test": @"*", @"predicates": @"" };
        NSInteger row = [_stepsTable selectedRow];
        NSUInteger at = row >= 0 ? (NSUInteger)row + 1 : _steps.count;
        [_steps insertObject:step atIndex:at];
        [self stepsChanged];
        [_stepsTable reloadData];
        [_stepsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:at]
                 byExtendingSelection:NO];
    } else {
        NSInteger row = [_stepsTable selectedRow];
        if (row < 0 || (NSUInteger)row >= _steps.count) {
            return;
        }
        [_steps removeObjectAtIndex:(NSUInteger)row];
        [self stepsChanged];
        [_stepsTable reloadData];
    }
}

- (IBAction)okClicked:(id)sender
{
    (void)sender;
    _result = [self expression];
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

#pragma mark data tree (base-path gesture)

- (NSArray *)childrenOfNode:(XFXMLNode *)node
{
    NSMutableArray *out = [NSMutableArray array];
    if ([node kind] == XFXMLElementKind) {
        for (XFXMLNode *attribute in [(XFXMLElement *)node attributes]) {
            [out addObject:attribute];
        }
    }
    for (XFXMLNode *child in [node children]) {
        if ([child kind] == XFXMLElementKind) {
            [out addObject:child];
        }
    }
    return out;
}

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item
{
    (void)ov;
    if (item == nil) {
        return [[self chosenInstance] documentElement] ? 1 : 0;
    }
    return (NSInteger)[self childrenOfNode:item].count;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(id)item
{
    (void)ov;
    if (item == nil) {
        return [[self chosenInstance] documentElement];
    }
    return [self childrenOfNode:item][(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item
{
    (void)ov;
    return [self childrenOfNode:item].count > 0;
}

- (id)outlineView:(NSOutlineView *)ov objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
    (void)ov;
    (void)column;
    XFXMLNode *node = item;
    if ([node kind] == XFXMLAttributeKind) {
        return [NSString stringWithFormat:@"@%@ = ‘%@’", [node name], [node stringValue] ?: @""];
    }
    BOOL leaf = [self childrenOfNode:node].count == 0;
    NSString *value = leaf ? [node stringValue] : nil;
    return value.length ? [NSString stringWithFormat:@"%@  ‘%@’", [node name], value]
                        : ([node name] ?: @"?");
}

- (void)outlineViewSelectionDidChange:(NSNotification *)note
{
    (void)note;
    NSInteger row = [_tree selectedRow];
    XFXMLNode *target = row >= 0 ? [_tree itemAtRow:row] : nil;
    if (target == nil) {
        return;
    }
    NSString *path = nil;
    switch ([_styleControl selectedSegment]) {
        case 0:
            path = [XFHostEdit pathFromNode:_contextNode toNode:target];
            break;
        case 1:
            path = XFDDisplayPathOfNode(target);
            break;
        case 2: {
            NSString *identifier = [self chosenInstance].identifier;
            NSString *tail = [XFHostEdit stepsBelowRootToNode:target];
            if (identifier.length && tail != nil) {
                path = tail.length
                    ? [NSString stringWithFormat:@"instance('%@')/%@", identifier, tail]
                    : [NSString stringWithFormat:@"instance('%@')", identifier];
            }
            break;
        }
    }
    if (path == nil) {
        [_statusField setStringValue:@"No path in this style (missing context or instance id)."];
        [_statusField setTextColor:[NSColor disabledControlTextColor]];
        return;
    }
    _syncing = YES;
    [_pathField setStringValue:path];
    _syncing = NO;
    [self expressionChanged];
}

#pragma mark steps & result tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
    if (table == _stepsTable) {
        return _treeRows != nil ? (NSInteger)_treeRows.count : (NSInteger)_steps.count;
    }
    if (table == _resultTable) {
        return (NSInteger)_resultRows.count;
    }
    return 0;
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
    NSString *ident = [column identifier];
    if (table == _stepsTable && _treeRows != nil) {
        if ((NSUInteger)row >= _treeRows.count) {
            return nil;
        }
        NSDictionary *node = _treeRows[(NSUInteger)row];
        if ([ident isEqualToString:@"axis"]) {
            NSUInteger depth = [node[@"depth"] unsignedIntegerValue];
            return [[@"" stringByPaddingToLength:depth * 3
                                      withString:@"   "
                                 startingAtIndex:0]
                        stringByAppendingString:node[@"label"]];
        }
        if ([ident isEqualToString:@"test"]) {
            return XFDXPathAttributedString(node[@"source"],
                [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]);
        }
        return @"";
    }
    if (table == _stepsTable) {
        if ((NSUInteger)row >= _steps.count) {
            return nil;
        }
        NSDictionary *step = _steps[(NSUInteger)row];
        if ([ident isEqualToString:@"axis"]) {
            NSUInteger index = [XFDKnownAxes() indexOfObject:step[@"axis"] ?: @"child"];
            return @(index == NSNotFound ? 0 : index);
        }
        return step[ident] ?: @"";
    }
    if (table == _resultTable) {
        if ((NSUInteger)row >= _resultRows.count) {
            return nil;
        }
        return _resultRows[(NSUInteger)row][ident];
    }
    return nil;
}

- (NSCell *)tableView:(NSTableView *)table
    dataCellForTableColumn:(NSTableColumn *)column
                       row:(NSInteger)row
{
    (void)row;
    if (table == _stepsTable && _treeRows != nil && column != nil) {
        static NSTextFieldCell *plain;
        if (plain == nil) {
            plain = [[NSTextFieldCell alloc] initTextCell:@""];
            [plain setControlSize:NSSmallControlSize];
            [plain setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
            [plain setEditable:NO];
            [plain setLineBreakMode:NSLineBreakByTruncatingTail];
        }
        return plain;
    }
    return column != nil ? [column dataCell] : nil;
}

- (void)tableView:(NSTableView *)table
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)column
               row:(NSInteger)row
{
    if (table != _stepsTable || _steps == nil || _treeRows != nil
        || (NSUInteger)row >= _steps.count) {
        return;
    }
    NSMutableDictionary *step = [_steps[(NSUInteger)row] mutableCopy];
    NSString *ident = [column identifier];
    if ([ident isEqualToString:@"axis"]) {
        NSInteger index = [value integerValue];
        NSArray *axes = XFDKnownAxes();
        if (index >= 0 && (NSUInteger)index < axes.count) {
            step[@"axis"] = axes[(NSUInteger)index];
            // shorthand spellings need their node() test
            if (([step[@"axis"] isEqualToString:@"parent"]
                 || [step[@"axis"] isEqualToString:@"self"])
                && [step[@"test"] isEqualToString:@"*"]) {
                step[@"test"] = @"node()";
            }
        }
    } else {
        step[ident] = [value description] ?: @"";
    }
    _steps[(NSUInteger)row] = step;
    [self stepsChanged];
}

- (NSString *)tableView:(NSTableView *)table
            toolTipForCell:(NSCell *)cell
                      rect:(NSRectPointer)rect
               tableColumn:(NSTableColumn *)column
                       row:(NSInteger)row
             mouseLocation:(NSPoint)mouseLocation
{
    (void)cell; (void)rect; (void)column; (void)mouseLocation;
    if (table == _stepsTable && _treeRows != nil
        && row >= 0 && (NSUInteger)row < _treeRows.count) {
        return _treeRows[(NSUInteger)row][@"source"];
    }
    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
    if ([note object] == _stepsTable) {
        NSInteger row = [_stepsTable selectedRow];
        if (_treeRows != nil) {
            BOOL editable = row >= 0 && (NSUInteger)row < _treeRows.count
                && [_treeRows[(NSUInteger)row][@"editable"] boolValue];
            [_editPathButton setEnabled:editable];
        } else {
            [_stepsControl setEnabled:_steps != nil && row >= 0 forSegment:1];
            [_predicateButton setEnabled:_steps != nil && row >= 0
                && (NSUInteger)row < _steps.count];
        }
    }
}

/// The predicate sub-editor on the selected step: candidates = the path
/// THROUGH that step with its own predicates stripped (what the
/// predicates will filter), evaluated in the picker's context.
- (IBAction)predicateClicked:(id)sender
{
    (void)sender;
    NSInteger row = [_stepsTable selectedRow];
    if (_steps == nil || row < 0 || (NSUInteger)row >= _steps.count) {
        return;
    }
    NSMutableArray *baseSteps = [NSMutableArray array];
    for (NSInteger i = 0; i <= row; i++) {
        NSMutableDictionary *step = [_steps[(NSUInteger)i] mutableCopy];
        if (i == row) {
            step[@"predicates"] = @"";
        }
        [baseSteps addObject:step];
    }
    NSMutableDictionary *path = [NSMutableDictionary dictionaryWithDictionary:
        @{ @"start": _startKind ?: @"context", @"steps": baseSteps }];
    if (_startInstance) {
        path[@"instance"] = _startInstance;
    }
    NSString *edited = [XFDPredicateEditor
        runWithBaseExpression:XFDJoinLocationPath(path)
                   predicates:_steps[(NSUInteger)row][@"predicates"]
                  hostElement:_hostElement
                  contextNode:_contextNode
                            ?: [[_processor defaultInstance] documentElement]
                        model:_processor.model];
    if (edited == nil) {
        return;
    }
    NSMutableDictionary *step = [_steps[(NSUInteger)row] mutableCopy];
    step[@"predicates"] = edited;
    _steps[(NSUInteger)row] = step;
    [self stepsChanged];
    [_stepsTable reloadData];
    if (row < [_stepsTable numberOfRows]) {
        [_stepsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                 byExtendingSelection:NO];
    }
}

/// Sub-picker on an embedded location path of a computed expression, the
/// result spliced back through the AST (sourceReplacingNodeAtPath:).
- (IBAction)editPathClicked:(id)sender
{
    (void)sender;
    NSInteger row = [_stepsTable selectedRow];
    if (_treeRows == nil || row < 0 || (NSUInteger)row >= _treeRows.count) {
        return;
    }
    NSDictionary *node = _treeRows[(NSUInteger)row];
    if (![node[@"editable"] boolValue]) {
        return;
    }
    NSString *edited = [XFDXPathPicker runForProcessor:_processor
                                           contextNode:_contextNode
                                           hostElement:_hostElement
                                                 title:@"Edit Path"
                                               initial:node[@"source"]
                                           expectation:XFDXPathExpectAny];
    if (edited == nil) {
        return;
    }
    XFXPath *compiled = [XFXPath xpathWithString:[self expression]
                                         element:_hostElement error:NULL];
    NSString *replaced = [compiled sourceReplacingNodeAtPath:node[@"path"]
                                                        with:edited];
    if (replaced == nil) {
        XFDBeep();
        return;
    }
    _syncing = YES;
    [_pathField setStringValue:replaced];
    _syncing = NO;
    [self expressionChanged];
}

#pragma mark run

+ (NSString *)runForProcessor:(XFProcessor *)processor
                  contextNode:(XFXMLNode *)contextNode
                  hostElement:(XFXMLElement *)hostElement
                        title:(NSString *)title
                      initial:(NSString *)initial
                  expectation:(XFDXPathExpectation)expectation
{
    XFDXPathPicker *picker = [[XFDXPathPicker alloc] init];
    picker->_processor = processor;
    picker->_contextNode = contextNode;
    picker->_hostElement = hostElement;
    picker->_expectation = expectation;
    if ([picker instances].count == 0) {
        XFDBeep();
        return nil;
    }
    if (![picker loadPanelWithTitle:title]) {
        return nil;
    }
    [picker->_tree reloadData];
    [picker->_tree expandItem:[[picker chosenInstance] documentElement] expandChildren:YES];
    picker->_syncing = YES;
    [picker->_pathField setStringValue:initial ?: @""];
    picker->_syncing = NO;
    [picker expressionChanged];
    [picker->_panel center];
    [NSApp runModalForWindow:picker->_panel];
    return picker->_result;
}

@end
