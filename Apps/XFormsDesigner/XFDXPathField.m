#import "XFDXPathField.h"
#import <XFormsKit/XFXMLTypes.h>

#pragma mark - Location-path step model

/// Known axes, in the steps-table popup order.
static NSArray *XFDKnownAxes(void)
{
    return @[ @"child", @"attribute", @"parent", @"self",
              @"descendant", @"descendant-or-self",
              @"ancestor", @"ancestor-or-self",
              @"following-sibling", @"preceding-sibling",
              @"following", @"preceding" ];
}

#pragma mark - Syntax highlighting

/// Semantic color, cross-SDK: try the named system color (keeps contrast
/// in dark themes where it exists), fall back to a fixed calibrated one.
static NSColor *XFDSystemColor(NSString *selectorName, CGFloat r, CGFloat g, CGFloat b)
{
    SEL sel = NSSelectorFromString(selectorName);
    if ([NSColor respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSColor *color = [NSColor performSelector:sel];
#pragma clang diagnostic pop
        if (color != nil) {
            return color;
        }
    }
    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1];
}

static NSColor *XFDTokenColor(NSString *kind)
{
    if ([kind isEqualToString:@"string"]) {
        return XFDSystemColor(@"systemRedColor", 0.77, 0.10, 0.09);
    }
    if ([kind isEqualToString:@"number"]) {
        return XFDSystemColor(@"systemBlueColor", 0.11, 0.00, 0.81);
    }
    if ([kind isEqualToString:@"function"]) {
        return XFDSystemColor(@"systemPurpleColor", 0.42, 0.13, 0.66);
    }
    if ([kind isEqualToString:@"axis"]) {
        return XFDSystemColor(@"systemBrownColor", 0.42, 0.30, 0.16);
    }
    if ([kind isEqualToString:@"variable"]) {
        return XFDSystemColor(@"systemTealColor", 0.00, 0.46, 0.54);
    }
    if ([kind isEqualToString:@"operator"]) {
        return XFDSystemColor(@"systemOrangeColor", 0.64, 0.35, 0.00);
    }
    if ([kind isEqualToString:@"punct"]) {
        return [NSColor disabledControlTextColor];
    }
    return [NSColor controlTextColor];   // name
}

/// The expression, colored by the ENGINE's lexer (token spans from
/// +highlightTokensForString: — no second tokenizer). `invalid` paints
/// everything red instead, keeping the existing does-not-compile signal.
static NSAttributedString *XFDHighlightedXPath(NSString *expression,
                                               NSFont *font, BOOL invalid)
{
    NSString *text = expression ?: @"";
    NSMutableDictionary *base = [NSMutableDictionary dictionary];
    if (font != nil) {
        base[NSFontAttributeName] = font;
    }
    base[NSForegroundColorAttributeName] =
        invalid ? [NSColor redColor] : [NSColor controlTextColor];
    NSMutableAttributedString *out =
        [[NSMutableAttributedString alloc] initWithString:text attributes:base];
    if (!invalid) {
        for (NSDictionary *token in [XFXPath highlightTokensForString:text]) {
            NSRange range = [token[@"range"] rangeValue];
            if (NSMaxRange(range) <= text.length) {
                [out addAttribute:NSForegroundColorAttributeName
                            value:XFDTokenColor(token[@"kind"])
                            range:range];
            }
        }
    }
    return out;
}

/// Restyle a text field in place: while it is being edited, recolor the
/// FIELD EDITOR's storage (attributes only — content and selection stay,
/// and attribute edits post no textDidChange); otherwise set the
/// attributed value.
static void XFDApplyXPathHighlight(NSTextField *field, BOOL invalid)
{
    NSAttributedString *styled = XFDHighlightedXPath([field stringValue],
                                                     [field font], invalid);
    NSTextView *editor = (NSTextView *)[field currentEditor];
    if ([editor isKindOfClass:[NSTextView class]]
        && [[[editor textStorage] string] isEqualToString:[styled string]]) {
        NSTextStorage *storage = [editor textStorage];
        [storage beginEditing];
        NSUInteger i = 0;
        while (i < styled.length) {
            NSRange run;
            NSDictionary *attrs = [styled attributesAtIndex:i effectiveRange:&run];
            [storage setAttributes:attrs range:run];
            i = NSMaxRange(run);
        }
        [storage endEditing];
    } else {
        [field setAttributedStringValue:styled];
    }
}

/// Unwraps a structure node for "instance('id')" — the quoted single
/// string argument — or nil.
static NSString *XFDInstanceIDOfFunctionNode(NSDictionary *node)
{
    if (![node[@"kind"] isEqualToString:@"function"]
        || ![node[@"name"] isEqualToString:@"instance"]) {
        return nil;
    }
    NSArray *args = node[@"children"];
    if ([args count] != 1 || ![args[0][@"kind"] isEqualToString:@"string"]) {
        return nil;
    }
    NSString *source = args[0][@"source"];   // quoted literal
    if ([source length] < 2) {
        return nil;
    }
    return [source substringWithRange:NSMakeRange(1, [source length] - 2)];
}

static NSArray *XFDStepsFromLocationNode(NSDictionary *location)
{
    NSMutableArray *steps = [NSMutableArray array];
    for (NSDictionary *step in location[@"children"]) {
        NSMutableString *predicates = [NSMutableString string];
        for (NSDictionary *predicate in step[@"children"]) {
            [predicates appendFormat:@"[%@]", predicate[@"source"]];
        }
        [steps addObject:@{ @"axis": step[@"axis"] ?: @"child",
                            @"test": step[@"test"] ?: @"*",
                            @"predicates": predicates }];
    }
    return steps;
}

NSDictionary *XFDSplitLocationPath(NSString *expression)
{
    // built on the ENGINE's parser — the designer re-lexes nothing. The
    // compiled AST's structure decomposes location paths (any axis, any
    // predicate, // included); computed expressions return nil and take
    // the picker's tree view instead.
    NSString *expr = [expression stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (expr.length == 0) {
        return nil;
    }
    XFXPath *compiled = [XFXPath xpathWithString:expr error:NULL];
    if (compiled == nil) {
        return nil;
    }
    NSDictionary *s = [compiled structure];
    NSString *kind = s[@"kind"];
    NSString *start = @"context";
    NSString *instanceID = nil;
    NSDictionary *location = nil;
    if ([kind isEqualToString:@"location"]) {
        location = s;
        start = [s[@"absolute"] boolValue] ? @"root" : @"context";
    } else if ([kind isEqualToString:@"path"]) {
        NSArray *children = s[@"children"];
        instanceID = XFDInstanceIDOfFunctionNode([children firstObject]);
        if (instanceID == nil || [children count] != 2
            || ![children[1][@"kind"] isEqualToString:@"location"]) {
            return nil;
        }
        start = @"instance";
        location = children[1];
    } else {
        instanceID = XFDInstanceIDOfFunctionNode(s);
        if (instanceID == nil) {
            return nil;
        }
        start = @"instance";
    }
    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithDictionary:
        @{ @"start": start,
           @"steps": location ? XFDStepsFromLocationNode(location) : @[] }];
    if (instanceID) {
        out[@"instance"] = instanceID;
    }
    return out;
}

NSString *XFDJoinLocationPath(NSDictionary *path)
{
    NSString *start = path[@"start"] ?: @"context";
    NSMutableArray *rendered = [NSMutableArray array];
    for (NSDictionary *step in path[@"steps"] ?: @[]) {
        NSString *axis = step[@"axis"] ?: @"child";
        NSString *test = step[@"test"] ?: @"*";
        NSString *predicates = step[@"predicates"] ?: @"";
        NSString *head;
        if ([axis isEqualToString:@"parent"] && [test isEqualToString:@"node()"]) {
            head = @"..";
        } else if ([axis isEqualToString:@"self"] && [test isEqualToString:@"node()"]) {
            head = @".";
        } else if ([axis isEqualToString:@"attribute"]) {
            head = [@"@" stringByAppendingString:test];
        } else if ([axis isEqualToString:@"child"]) {
            head = test;
        } else {
            head = [NSString stringWithFormat:@"%@::%@", axis, test];
        }
        [rendered addObject:[head stringByAppendingString:predicates]];
    }
    NSString *tail = [rendered componentsJoinedByString:@"/"];
    if ([start isEqualToString:@"root"]) {
        return [@"/" stringByAppendingString:tail];
    }
    if ([start isEqualToString:@"instance"]) {
        NSString *head = [NSString stringWithFormat:@"instance('%@')",
                          path[@"instance"] ?: @""];
        return tail.length ? [NSString stringWithFormat:@"%@/%@", head, tail] : head;
    }
    return tail.length ? tail : @".";
}

#pragma mark - Predicate sub-editing

static NSString *XFDDisplayPathOfNode(XFXMLNode *node);

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

/// Modal predicate editor for ONE step of the picker's Steps table: the
/// field takes a predicate list ([a][b]) or a bare expression (one
/// predicate, brackets added), validated live; the table shows every
/// node the step selects WITHOUT its predicates and which of them the
/// current predicates keep \u2014 position() and last() run against that
/// candidate set, exactly as they will at refresh time.
@interface XFDPredicateEditor : NSObject <NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate>
{
    NSPanel *_panel;
    NSTextField *_field;
    NSTextField *_statusField;
    NSTableView *_table;
    NSButton *_okButton;
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

@implementation XFDPredicateEditor

- (void)buildPanel
{
    const CGFloat W = 500, H = 420;
    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, W, H)
                                        styleMask:NSTitledWindowMask | NSClosableWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    [_panel setTitle:@"Edit Predicates"];
    NSView *content = [_panel contentView];

    NSTextField * (^label)(NSString *, NSRect) = ^NSTextField *(NSString *text, NSRect frame) {
        NSTextField *l = [[NSTextField alloc] initWithFrame:frame];
        [l setEditable:NO];
        [l setBordered:NO];
        [l setDrawsBackground:NO];
        [l setFont:[NSFont systemFontOfSize:11]];
        [[l cell] setWraps:YES];
        [l setStringValue:text];
        [content addSubview:l];
        return l;
    };
    label([NSString stringWithFormat:
        @"Filters the nodes  %@  selects \u2014 the predicates run per node; "
        @"position() and last() see the candidate set below.", _baseExpression],
        NSMakeRect(12, H - 48, W - 24, 32));

    label(@"Predicates:", NSMakeRect(12, H - 74, 80, 17));
    _field = [[NSTextField alloc] initWithFrame:NSMakeRect(96, H - 78, W - 108, 22)];
    [_field setFont:[NSFont userFixedPitchFontOfSize:11]];
    [[_field cell] setPlaceholderString:@"[price > 10]  \u2014 or a bare expression"];
    [_field setDelegate:self];
    [content addSubview:_field];

    _statusField = label(@"", NSMakeRect(12, H - 100, W - 24, 17));

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:
        NSMakeRect(12, 44, W - 24, H - 152)];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];
    _table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, W - 24, H - 152)];
    struct { NSString *ident; NSString *title; CGFloat width; } cols[] = {
        { @"match", @"\u2713", 28 },
        { @"index", @"#", 36 },
        { @"node", @"Node", 210 },
        { @"value", @"Value", 170 },
    };
    for (NSUInteger i = 0; i < 4; i++) {
        NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:cols[i].ident];
        [[c headerCell] setStringValue:cols[i].title];
        [c setWidth:cols[i].width];
        [[c dataCell] setEditable:NO];
        [[c dataCell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [_table addTableColumn:c];
    }
    [_table setDataSource:self];
    [_table setDelegate:self];
    [scroll setDocumentView:_table];
    [content addSubview:scroll];

    NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(W - 190, 8, 84, 28)];
    [cancel setTitle:@"Cancel"];
    [cancel setBezelStyle:NSRoundedBezelStyle];
    [cancel setKeyEquivalent:@"\033"];
    [cancel setTarget:self];
    [cancel setAction:@selector(cancelClicked:)];
    [content addSubview:cancel];
    _okButton = [[NSButton alloc] initWithFrame:NSMakeRect(W - 100, 8, 84, 28)];
    [_okButton setTitle:@"OK"];
    [_okButton setBezelStyle:NSRoundedBezelStyle];
    [_okButton setKeyEquivalent:@"\r"];
    [_okButton setTarget:self];
    [_okButton setAction:@selector(okClicked:)];
    [content addSubview:_okButton];
    [_panel setDelegate:(id)self];
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
    XFDApplyXPathHighlight(_field, !_valid);
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

- (void)okClicked:(id)sender
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

- (void)cancelClicked:(id)sender
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
    [editor buildPanel];
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

#pragma mark - Schema suggestions & function knowledge

static void XFDCollectSchemaPaths(XFXMLElement *element, NSString *prefix,
                                  NSUInteger depth, NSMutableArray *out,
                                  NSUInteger cap)
{
    if (out.count >= cap || depth > 5) {
        return;
    }
    // schema UNION: one entry per child NAME, however many clones exist
    NSMutableArray *names = [NSMutableArray array];
    for (XFXMLNode *attribute in [element attributes]) {
        NSString *path = [NSString stringWithFormat:@"%@@%@", prefix, [attribute name]];
        if (out.count < cap && ![out containsObject:path]) {
            [out addObject:path];
        }
    }
    for (XFXMLNode *child in [element children]) {
        if ([child kind] != XFXMLElementKind) {
            continue;
        }
        NSString *name = [child name] ?: @"*";
        if ([names containsObject:name]) {
            continue;
        }
        [names addObject:name];
        NSString *path = [prefix stringByAppendingString:name];
        if (out.count < cap && ![out containsObject:path]) {
            [out addObject:path];
        }
        XFDCollectSchemaPaths((XFXMLElement *)child,
                              [path stringByAppendingString:@"/"],
                              depth + 1, out, cap);
    }
}

/// Refs suggested from the data's implied schema, relative to `context`:
/// descendant name-paths (positional clones collapsed — the schema XForms
/// infers implicitly) plus the parent level as ../name.
NSArray *XFDSchemaPathsFromNode(XFXMLNode *context, NSUInteger cap)
{
    NSMutableArray *out = [NSMutableArray array];
    if ([context kind] != XFXMLElementKind) {
        return out;
    }
    XFDCollectSchemaPaths((XFXMLElement *)context, @"", 0, out, cap);
    XFXMLNode *parent = [context parent];
    if ([parent kind] == XFXMLElementKind && out.count < cap) {
        [out addObject:@".."];
        NSMutableArray *names = [NSMutableArray array];
        for (XFXMLNode *sibling in [parent children]) {
            if ([sibling kind] != XFXMLElementKind || sibling == context) {
                continue;
            }
            NSString *name = [sibling name] ?: @"*";
            if (![names containsObject:name] && out.count < cap) {
                [names addObject:name];
                [out addObject:[@"../" stringByAppendingString:name]];
            }
        }
    }
    return out;
}

/// The context properties event() exposes per event, XForms 1.1 §4 — the
/// spec knowledge users should not need to re-read daily. nil = event
/// unknown here; empty = known to carry none.
NSArray *XFDEventContextProperties(NSString *eventName)
{
    static NSDictionary *map;
    if (map == nil) {
        map = @{
            @"xforms-submit-done": @[ @"resource-uri", @"response-status-code",
                @"response-headers", @"response-reason-phrase" ],
            @"xforms-submit-error": @[ @"error-type", @"resource-uri",
                @"response-status-code", @"response-headers",
                @"response-reason-phrase", @"response-body" ],
            @"xforms-insert": @[ @"inserted-nodes", @"origin-nodes",
                @"insert-location-node", @"position" ],
            @"xforms-delete": @[ @"deleted-nodes", @"delete-location" ],
            @"xforms-link-exception": @[ @"resource-uri" ],
            @"xforms-link-error": @[ @"resource-uri" ],
            @"xforms-compute-exception": @[ @"error-message" ],
            @"xforms-version-exception": @[ @"error-information" ],
            @"xforms-binding-exception": @[],
            @"xforms-ready": @[],
            @"DOMActivate": @[],
            @"xforms-value-changed": @[],
            @"xforms-select": @[],
            @"xforms-deselect": @[],
        };
    }
    return map[eventName ?: @""];
}

#pragma mark - Node picker panel (v2)

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
    NSPanel *_panel;
    NSTextField *_contextField;
    NSPopUpButton *_instancePopup;
    NSSegmentedControl *_styleControl;
    NSOutlineView *_tree;
    NSTableView *_stepsTable;
    NSSegmentedControl *_stepsControl;
    NSTextField *_stepsStatusField;
    NSTextField *_pathField;
    NSTextField *_statusField;
    NSTableView *_resultTable;
    NSButton *_okButton;
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
    NSButton *_editPathButton;
    NSButton *_predicateButton;
    NSPopUpButton *_suggestPopup;
    NSTextField *_functionInfoField;
    BOOL _syncing;
}
+ (NSString *)runForProcessor:(XFProcessor *)processor
                  contextNode:(XFXMLNode *)contextNode
                  hostElement:(XFXMLElement *)hostElement
                        title:(NSString *)title
                      initial:(NSString *)initial
                  expectation:(XFDXPathExpectation)expectation;
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

static NSString *XFDDisplayPathOfNode(XFXMLNode *node)
{
    if (node == nil) {
        return @"?";
    }
    NSString *tail = [XFHostEdit stepsBelowRootToNode:node];
    XFXMLNode *walk = node;
    while ([walk parent] != nil && [[walk parent] kind] != XFXMLDocumentKind) {
        walk = [walk parent];
    }
    NSString *rootName = [walk name] ?: @"*";
    if (tail == nil) {
        return [node name] ?: @"?";
    }
    return tail.length ? [NSString stringWithFormat:@"/%@/%@", rootName, tail]
                       : [@"/" stringByAppendingString:rootName];
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

- (NSTextField *)makeLabel:(NSString *)text frame:(NSRect)frame in:(NSView *)parent
{
    NSTextField *l = [[NSTextField alloc] initWithFrame:frame];
    [l setEditable:NO];
    [l setBordered:NO];
    [l setDrawsBackground:NO];
    [l setStringValue:text];
    [l setFont:[NSFont systemFontOfSize:11]];
    [parent addSubview:l];
    return l;
}

- (void)buildPanelWithTitle:(NSString *)title
{
    const CGFloat W = 560, H = 700;
    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, W, H)
                                        styleMask:NSTitledWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    [_panel setTitle:title];
    NSView *content = [_panel contentView];

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
    NSTextField *ctx = [self makeLabel:ctxText frame:NSMakeRect(12, H - 30, W - 24, 17) in:content];
    [[ctx cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    _contextField = ctx;

    [self makeLabel:@"Instance:" frame:NSMakeRect(12, H - 56, 70, 17) in:content];
    _instancePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(86, H - 60, 250, 24) pullsDown:NO];
    NSUInteger n = 0;
    for (XFModel *model in _processor.models) {
        for (XFInstance *instance in model.instances) {
            NSString *name = instance.identifier.length ? instance.identifier
                : [NSString stringWithFormat:@"instance %lu", (unsigned long)++n];
            NSString *owner = model.identifier.length ? model.identifier : @"model";
            [_instancePopup addItemWithTitle:[NSString stringWithFormat:@"%@  (%@)", name, owner]];
        }
    }
    [_instancePopup setTarget:self];
    [_instancePopup setAction:@selector(instanceChanged:)];
    [content addSubview:_instancePopup];

    [self makeLabel:@"Start:" frame:NSMakeRect(12, H - 84, 50, 17) in:content];
    _styleControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(86, H - 88, 280, 24)];
    [_styleControl setSegmentCount:3];
    [_styleControl setLabel:@"Relative" forSegment:0];
    [_styleControl setLabel:@"/" forSegment:1];
    [_styleControl setLabel:@"instance()" forSegment:2];
    [_styleControl setSelectedSegment:_contextNode != nil ? 0 : 2];
    [_styleControl setTarget:self];
    [_styleControl setAction:@selector(styleChanged:)];
    [content addSubview:_styleControl];

    _suggestPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(W - 172, H - 88, 160, 24)
                                               pullsDown:YES];
    [[_suggestPopup cell] setControlSize:NSSmallControlSize];
    [_suggestPopup setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [self populateSuggestions];
    [content addSubview:_suggestPopup];

    // the data tree: click a node for a base path in the current style
    NSScrollView *treeScroll = [[NSScrollView alloc] initWithFrame:
        NSMakeRect(12, H - 240, W - 24, 144)];
    [treeScroll setHasVerticalScroller:YES];
    [treeScroll setBorderType:NSBezelBorder];
    _tree = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, W - 24, 144)];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"node"];
    [col setWidth:W - 60];
    [[col dataCell] setEditable:NO];
    [_tree addTableColumn:col];
    [_tree setOutlineTableColumn:col];
    [_tree setHeaderView:nil];
    [_tree setDataSource:(id)self];
    [_tree setDelegate:(id)self];
    [treeScroll setDocumentView:_tree];
    [content addSubview:treeScroll];

    // editable steps
    [self makeLabel:@"Steps:" frame:NSMakeRect(12, H - 264, 50, 17) in:content];
    _stepsStatusField = [self makeLabel:@"" frame:NSMakeRect(64, H - 264, W - 286, 17) in:content];
    _stepsControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(W - 82, H - 268, 70, 24)];
    [_stepsControl setSegmentCount:2];
    [_stepsControl setLabel:@"+" forSegment:0];
    [_stepsControl setLabel:@"−" forSegment:1];
    [(NSSegmentedCell *)[_stepsControl cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
    [_stepsControl setTarget:self];
    [_stepsControl setAction:@selector(stepsPlusMinusClicked:)];
    [content addSubview:_stepsControl];

    _predicateButton = [[NSButton alloc] initWithFrame:NSMakeRect(W - 198, H - 268, 110, 24)];
    [_predicateButton setTitle:@"Predicate\u2026"];
    [_predicateButton setBezelStyle:NSRoundedBezelStyle];
    [[_predicateButton cell] setControlSize:NSSmallControlSize];
    [_predicateButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [_predicateButton setToolTip:@"Edit the selected step's predicates with live per-node match preview."];
    [_predicateButton setTarget:self];
    [_predicateButton setAction:@selector(predicateClicked:)];
    [_predicateButton setEnabled:NO];
    [content addSubview:_predicateButton];

    _editPathButton = [[NSButton alloc] initWithFrame:NSMakeRect(W - 122, H - 268, 110, 24)];
    [_editPathButton setTitle:@"Edit Path…"];
    [_editPathButton setBezelStyle:NSRoundedBezelStyle];
    [[_editPathButton cell] setControlSize:NSSmallControlSize];
    [_editPathButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [_editPathButton setTarget:self];
    [_editPathButton setAction:@selector(editPathClicked:)];
    [_editPathButton setHidden:YES];
    [content addSubview:_editPathButton];

    NSScrollView *stepsScroll = [[NSScrollView alloc] initWithFrame:
        NSMakeRect(12, H - 388, W - 24, 116)];
    [stepsScroll setHasVerticalScroller:YES];
    [stepsScroll setBorderType:NSBezelBorder];
    _stepsTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, W - 24, 116)];
    NSTableColumn *axisCol = [[NSTableColumn alloc] initWithIdentifier:@"axis"];
    [[axisCol headerCell] setStringValue:@"Axis"];
    [axisCol setWidth:140];
    NSPopUpButtonCell *axisCell = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
    [axisCell setBordered:NO];
    [axisCell setControlSize:NSSmallControlSize];
    [axisCell setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [axisCell addItemsWithTitles:XFDKnownAxes()];
    [axisCol setDataCell:axisCell];
    [_stepsTable addTableColumn:axisCol];
    NSTableColumn *testCol = [[NSTableColumn alloc] initWithIdentifier:@"test"];
    [[testCol headerCell] setStringValue:@"Node"];
    [testCol setWidth:150];
    [[testCol dataCell] setEditable:YES];
    [[testCol dataCell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [_stepsTable addTableColumn:testCol];
    NSTableColumn *predCol = [[NSTableColumn alloc] initWithIdentifier:@"predicates"];
    [[predCol headerCell] setStringValue:@"Predicates"];
    [predCol setWidth:200];
    [[predCol dataCell] setEditable:YES];
    [[predCol dataCell] setFont:[NSFont userFixedPitchFontOfSize:11]];
    [_stepsTable addTableColumn:predCol];
    [_stepsTable setDataSource:self];
    [_stepsTable setDelegate:self];
    [_stepsTable setAllowsMultipleSelection:NO];
    [stepsScroll setDocumentView:_stepsTable];
    [content addSubview:stepsScroll];

    // the expression itself — always editable
    [self makeLabel:@"Expression:" frame:NSMakeRect(12, H - 412, 90, 17) in:content];
    _pathField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, H - 436, W - 24, 22)];
    [_pathField setFont:[NSFont userFixedPitchFontOfSize:11]];
    [[_pathField cell] setSendsActionOnEndEditing:YES];
    [_pathField setTarget:self];
    [_pathField setAction:@selector(expressionEdited:)];
    [_pathField setDelegate:(id)self];
    [content addSubview:_pathField];

    _statusField = [self makeLabel:@"" frame:NSMakeRect(12, H - 458, W - 24, 17) in:content];
    _functionInfoField = [self makeLabel:@"" frame:NSMakeRect(12, H - 488, W - 24, 28) in:content];
    [[_functionInfoField cell] setWraps:YES];
    [_functionInfoField setTextColor:[NSColor disabledControlTextColor]];

    // live result
    NSScrollView *resultScroll = [[NSScrollView alloc] initWithFrame:
        NSMakeRect(12, 44, W - 24, H - 540)];
    [resultScroll setHasVerticalScroller:YES];
    [resultScroll setBorderType:NSBezelBorder];
    _resultTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, W - 24, H - 540)];
    struct { NSString *ident; NSString *title; CGFloat width; } cols[] = {
        { @"index", @"#", 36 },
        { @"node", @"Node", 220 },
        { @"value", @"Value", 230 },
    };
    for (NSUInteger i = 0; i < 3; i++) {
        NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:cols[i].ident];
        [[c headerCell] setStringValue:cols[i].title];
        [c setWidth:cols[i].width];
        [[c dataCell] setEditable:NO];
        [[c dataCell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [_resultTable addTableColumn:c];
    }
    [_resultTable setDataSource:self];
    [_resultTable setDelegate:self];
    [resultScroll setDocumentView:_resultTable];
    [content addSubview:resultScroll];

    NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(W - 190, 8, 84, 28)];
    [cancel setTitle:@"Cancel"];
    [cancel setBezelStyle:NSRoundedBezelStyle];
    [cancel setTarget:self];
    [cancel setAction:@selector(cancelClicked:)];
    [content addSubview:cancel];
    _okButton = [[NSButton alloc] initWithFrame:NSMakeRect(W - 100, 8, 84, 28)];
    [_okButton setTitle:@"OK"];
    [_okButton setBezelStyle:NSRoundedBezelStyle];
    [_okButton setKeyEquivalent:@"\r"];
    [_okButton setTarget:self];
    [_okButton setAction:@selector(okClicked:)];
    [_okButton setEnabled:NO];
    [content addSubview:_okButton];
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
    XFDApplyXPathHighlight(_pathField,
        expr.length != 0
        && [XFXPath xpathWithString:expr element:_hostElement error:NULL] == nil);
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

- (void)expressionEdited:(id)sender
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

- (void)styleChanged:(id)sender
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

- (void)instanceChanged:(id)sender
{
    (void)sender;
    [_tree reloadData];
    [_tree expandItem:[[self chosenInstance] documentElement] expandChildren:YES];
    if ([_startKind isEqualToString:@"instance"]) {
        [self styleChanged:nil];
    }
}

- (void)stepsPlusMinusClicked:(NSSegmentedControl *)sender
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

- (void)okClicked:(id)sender
{
    (void)sender;
    _result = [self expression];
    [NSApp stopModal];
    [_panel orderOut:nil];
}

- (void)cancelClicked:(id)sender
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
            return XFDHighlightedXPath(node[@"source"],
                [NSFont systemFontOfSize:[NSFont smallSystemFontSize]], NO);
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
- (void)predicateClicked:(id)sender
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
- (void)editPathClicked:(id)sender
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
    [picker buildPanelWithTitle:title];
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

#pragma mark - The field component

@interface XFDXPathField () <NSTextFieldDelegate>
@property (nonatomic, strong) NSTextField *field;
@property (nonatomic, strong) NSButton *pickButton;
@property (nonatomic, assign, readwrite, getter=isValid) BOOL valid;
@end

@implementation XFDXPathField

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self buildSubviews];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self buildSubviews];
    }
    return self;
}

- (void)buildSubviews
{
    if (self.field != nil) {
        return;
    }
    _valid = YES;
    NSRect bounds = [self bounds];
    CGFloat buttonWidth = 22;
    self.field = [[NSTextField alloc] initWithFrame:
        NSMakeRect(0, 0, NSWidth(bounds) - buttonWidth - 4, NSHeight(bounds))];
    [self.field setAutoresizingMask:NSViewWidthSizable];
    [[self.field cell] setControlSize:NSSmallControlSize];
    [self.field setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [[self.field cell] setScrollable:YES];
    [[self.field cell] setSendsActionOnEndEditing:YES];
    [self.field setTarget:self];
    [self.field setAction:@selector(fieldEdited:)];
    [self.field setDelegate:self];   // live re-validate + highlight
    [self addSubview:self.field];

    self.pickButton = [[NSButton alloc] initWithFrame:
        NSMakeRect(NSWidth(bounds) - buttonWidth, 0, buttonWidth, NSHeight(bounds))];
    [self.pickButton setAutoresizingMask:NSViewMinXMargin];
    [self.pickButton setTitle:@"…"];
    [self.pickButton setBezelStyle:NSRoundedBezelStyle];
    [[self.pickButton cell] setControlSize:NSSmallControlSize];
    [self.pickButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [self.pickButton setTarget:self];
    [self.pickButton setAction:@selector(pickClicked:)];
    [self addSubview:self.pickButton];
}

#pragma mark value / validation

- (NSString *)stringValue
{
    return [self.field stringValue];
}

- (void)setStringValue:(NSString *)value
{
    [self.field setStringValue:value ?: @""];
    [self validate];
}

- (void)setEnabled:(BOOL)enabled
{
    [self.field setEnabled:enabled];
    [self.pickButton setEnabled:enabled];
}

- (void)validate
{
    NSString *expression = [self.field stringValue];
    XFXMLElement *host = [self.provider hostElementForXPathField:self];
    if (expression.length == 0 || host == nil) {
        self.valid = YES;
        [self.field setToolTip:nil];
        XFDApplyXPathHighlight(self.field, NO);
        return;
    }
    NSError *error = nil;
    XFXPath *compiled = [XFXPath xpathWithString:expression element:host error:&error];
    self.valid = (compiled != nil);
    if (compiled == nil) {
        [self.field setToolTip:[error localizedDescription] ?: @"Invalid XPath"];
    } else {
        [self.field setToolTip:nil];
    }
    XFDApplyXPathHighlight(self.field, compiled == nil);
}

- (void)controlTextDidChange:(NSNotification *)note
{
    if ([note object] == self.field) {
        [self validate];
    }
}

- (void)sendAction
{
    if (self.target != nil && self.action != NULL) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.target performSelector:self.action withObject:self];
#pragma clang diagnostic pop
    }
}

- (void)fieldEdited:(id)sender
{
    (void)sender;
    [self validate];
    [self sendAction];
}

#pragma mark picker

+ (NSString *)runPickerForProcessor:(XFProcessor *)processor
                        contextNode:(XFXMLNode *)contextNode
                        hostElement:(XFXMLElement *)hostElement
                              title:(NSString *)title
{
    return [XFDXPathPicker runForProcessor:processor
                               contextNode:contextNode
                               hostElement:hostElement
                                     title:title
                                   initial:@""
                               expectation:XFDXPathExpectAny];
}

+ (NSString *)runPickerForProcessor:(XFProcessor *)processor
                        contextNode:(XFXMLNode *)contextNode
                        hostElement:(XFXMLElement *)hostElement
                              title:(NSString *)title
                            initial:(NSString *)initial
                        expectation:(XFDXPathExpectation)expectation
{
    return [XFDXPathPicker runForProcessor:processor
                               contextNode:contextNode
                               hostElement:hostElement
                                     title:title
                                   initial:initial
                               expectation:expectation];
}

- (void)pickClicked:(id)sender
{
    (void)sender;
    XFProcessor *processor = [self.provider processorForXPathField:self];
    XFXMLElement *host = [self.provider hostElementForXPathField:self];
    if (processor == nil || host == nil) {
        XFDBeep();
        return;
    }
    NSString *path = [XFDXPathPicker
        runForProcessor:processor
            contextNode:[self.provider contextNodeForXPathField:self]
            hostElement:host
                  title:[NSString stringWithFormat:@"Path for %@", [host name] ?: @"element"]
                initial:[self.field stringValue]
            expectation:self.expectation];
    if (path == nil) {
        return;
    }
    [self.field setStringValue:path];
    [self validate];
    [self sendAction];
}

@end
