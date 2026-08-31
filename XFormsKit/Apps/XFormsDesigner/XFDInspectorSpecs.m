/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDInspectorSpecs.h"

/// The Action page's row specs, per action local name (XForms 1.1 §10
/// plus the XSLTForms show/hide pair). Row keys: label, attr, kind
/// (xpath | idref | field | popup | content), idkind for idref rows,
/// options for popup rows (first item = attribute removed). Every action
/// additionally gets the Event (ev:event) row, prepended at build time.
NSDictionary *XFDActionSpecs(void)
{
    static NSDictionary *specs;
    if (specs == nil) {
        NSArray *modelRow = @[ @{ @"label": @"Model", @"attr": @"model",
                                  @"kind": @"idref", @"idkind": @"model" } ];
        specs = @{
            @"action": @[],
            @"setvalue": @[
                @{ @"label": @"Node", @"attr": @"ref", @"kind": @"xpath", @"expect": @"node", @"tip": @"The node whose value is set (§10.2)." },
                @{ @"label": @"Bind", @"attr": @"bind", @"kind": @"idref", @"idkind": @"bind", @"tip": @"Bind selecting the target nodes, by id (overrides the in-place expression)." },
                @{ @"label": @"Value", @"attr": @"value", @"kind": @"xpath", @"expect": @"value", @"tip": @"Expression computing the new value; alternatively use inline Text (§10.2)." },
                @{ @"label": @"Text", @"kind": @"content", @"tip": @"Inline content: the literal value (setvalue) or the message body (§10.2, §10.12)." },
            ],
            @"insert": @[
                @{ @"label": @"Nodeset", @"attr": @"nodeset", @"kind": @"xpath", @"expect": @"nodeset", @"tip": @"The homogeneous collection inserted into / deleted from (§10.3, §10.4)." },
                @{ @"label": @"Bind", @"attr": @"bind", @"kind": @"idref", @"idkind": @"bind", @"tip": @"Bind selecting the target nodes, by id (overrides the in-place expression)." },
                @{ @"label": @"At", @"attr": @"at", @"kind": @"xpath", @"expect": @"value", @"tip": @"1-based position within the nodeset the action applies at (§10.3, §10.4)." },
                @{ @"label": @"Position", @"attr": @"position", @"kind": @"popup", @"tip": @"Insert before or after the at-node (§10.3).",
                   @"options": @[ @"(default)", @"before", @"after" ] },
                @{ @"label": @"Origin", @"attr": @"origin", @"kind": @"xpath", @"expect": @"nodeset", @"tip": @"Nodes to copy in; defaults to the last node of the target set (§10.3)." },
                @{ @"label": @"Context", @"attr": @"context", @"kind": @"xpath", @"expect": @"node", @"tip": @"Overrides the in-scope evaluation context node (§10.3, §10.4)." },
            ],
            @"delete": @[
                @{ @"label": @"Nodeset", @"attr": @"nodeset", @"kind": @"xpath", @"expect": @"nodeset", @"tip": @"The homogeneous collection inserted into / deleted from (§10.3, §10.4)." },
                @{ @"label": @"Bind", @"attr": @"bind", @"kind": @"idref", @"idkind": @"bind", @"tip": @"Bind selecting the target nodes, by id (overrides the in-place expression)." },
                @{ @"label": @"At", @"attr": @"at", @"kind": @"xpath", @"expect": @"value", @"tip": @"1-based position within the nodeset the action applies at (§10.3, §10.4)." },
                @{ @"label": @"Context", @"attr": @"context", @"kind": @"xpath", @"expect": @"node", @"tip": @"Overrides the in-scope evaluation context node (§10.3, §10.4)." },
            ],
            @"toggle": @[
                @{ @"label": @"Case", @"attr": @"case", @"kind": @"idref", @"idkind": @"case", @"tip": @"Id of the xf:case to switch to (§10.10)." },
            ],
            @"setindex": @[
                @{ @"label": @"Repeat", @"attr": @"repeat", @"kind": @"idref", @"idkind": @"repeat", @"tip": @"Id of the repeat whose index moves (§10.5)." },
                @{ @"label": @"Index", @"attr": @"index", @"kind": @"xpath", @"expect": @"value", @"tip": @"1-based new index, computed (§10.5)." },
            ],
            @"setfocus": @[
                @{ @"label": @"Control", @"attr": @"control", @"kind": @"idref", @"idkind": @"#control", @"tip": @"Id of the form control to focus (§10.7)." },
            ],
            @"send": @[
                @{ @"label": @"Submission", @"attr": @"submission", @"kind": @"idref", @"idkind": @"submission", @"tip": @"Id of the xf:submission to run (§10.11)." },
            ],
            @"dispatch": @[
                @{ @"label": @"Name", @"attr": @"name", @"kind": @"idref", @"idkind": @"#event", @"tip": @"Event to dispatch — standard or your own custom name (§10.9)." },
                @{ @"label": @"Target", @"attr": @"targetid", @"kind": @"idref", @"idkind": @"*", @"tip": @"Id of the element the event is dispatched to (§10.9)." },
                @{ @"label": @"Delay", @"attr": @"delay", @"kind": @"field", @"tip": @"Milliseconds to wait before dispatching (§10.9)." },
                @{ @"label": @"Bubbles", @"attr": @"bubbles", @"kind": @"popup", @"tip": @"Custom events only: whether the dispatched event bubbles (§10.9). Predefined events keep their spec behavior — XSLTForms-family runtimes read the registry, not this attribute.",
                   @"options": @[ @"(default)", @"true", @"false" ] },
                @{ @"label": @"Cancelable", @"attr": @"cancelable", @"kind": @"popup", @"tip": @"Custom events only: whether the dispatched event can be canceled (§10.9). Predefined events keep their spec behavior — XSLTForms-family runtimes read the registry, not this attribute.",
                   @"options": @[ @"(default)", @"true", @"false" ] },
            ],
            @"load": @[
                @{ @"label": @"Resource", @"attr": @"resource", @"kind": @"field", @"tip": @"URI to open (§10.8)." },
                @{ @"label": @"Show", @"attr": @"show", @"kind": @"popup", @"tip": @"Open in place (replace) or in a new window (§10.8).",
                   @"options": @[ @"(default)", @"replace", @"new" ] },
            ],
            @"message": @[
                @{ @"label": @"Level", @"attr": @"level", @"kind": @"popup", @"tip": @"How the message shows: ephemeral (tooltip-like), modeless, or modal (§10.12).",
                   @"options": @[ @"(default)", @"ephemeral", @"modeless", @"modal" ] },
                @{ @"label": @"Text", @"kind": @"content", @"tip": @"Inline content: the literal value (setvalue) or the message body (§10.2, §10.12)." },
            ],
            @"reset": modelRow,
            @"rebuild": modelRow,
            @"recalculate": modelRow,
            @"revalidate": modelRow,
            @"refresh": modelRow,
            @"show": @[
                @{ @"label": @"Dialog", @"attr": @"dialog", @"kind": @"idref", @"idkind": @"dialog" },
            ],
            @"hide": @[
                @{ @"label": @"Dialog", @"attr": @"dialog", @"kind": @"idref", @"idkind": @"dialog" },
            ],
        };
    }
    return specs;
}

/// Widget-bearing element kinds — the Control inspector page.
NSSet *XFDControlKinds(void)
{
    static NSSet *set;
    if (set == nil) {
        set = [NSSet setWithArray:@[ @"input", @"output", @"secret", @"textarea",
            @"select", @"select1", @"range", @"trigger", @"submit", @"upload",
            @"group", @"repeat", @"switch", @"case", @"dialog" ]];
    }
    return set;
}

/// Value-carrying kinds that need a binding to keep what the user types.
NSSet *XFDValueControlKinds(void)
{
    static NSSet *set;
    if (set == nil) {
        set = [NSSet setWithArray:@[ @"input", @"output", @"secret", @"textarea",
            @"select", @"select1", @"range", @"upload" ]];
    }
    return set;
}

/// The odd state the user called out: a value control (or repeat) with no
/// ref / nodeset / bind — the preview will not keep what is typed into it.
BOOL XFDElementIsUnbound(NSXMLElement *element)
{
    NSString *local = [element localName];
    BOOL needs = [XFDValueControlKinds() containsObject:local]
        || [local isEqualToString:@"repeat"];
    if (!needs) {
        return NO;
    }
    if ([local isEqualToString:@"output"]
        && [[element attributeForName:@"value"] stringValue].length) {
        return NO;   // a computed output IS bound — to an expression
    }
    return [[element attributeForName:@"ref"] stringValue].length == 0
        && [[element attributeForName:@"nodeset"] stringValue].length == 0
        && [[element attributeForName:@"bind"] stringValue].length == 0;
}

NSColor *XFDWarningColor(void)
{
    if ([[NSColor class] respondsToSelector:@selector(systemOrangeColor)]) {
        return [[NSColor class] performSelector:@selector(systemOrangeColor)];
    }
    return [NSColor colorWithCalibratedRed:0.80 green:0.50 blue:0.10 alpha:1.0];
}

/// The palette: every insertable tag with a one-line description. Rows
/// whose tag the current insert target refuses are dimmed (XFHostEdit's
/// insertion zones are the single validity authority).
NSArray *XFDPaletteCatalog(void)
{
    static NSArray *catalog;
    if (catalog == nil) {
        catalog = @[
            @{ @"cat": @"Controls",   @"name": @"input",      @"desc": @"Single-line text entry bound to a node" },
            @{ @"cat": @"Controls",   @"name": @"textarea",   @"desc": @"Multi-line text entry" },
            @{ @"cat": @"Controls",   @"name": @"secret",     @"desc": @"Masked password entry" },
            @{ @"cat": @"Controls",   @"name": @"output",     @"desc": @"Read-only display of a value" },
            @{ @"cat": @"Controls",   @"name": @"select1",    @"desc": @"Choose one item (popup / radio)" },
            @{ @"cat": @"Controls",   @"name": @"select",     @"desc": @"Choose several items (checkboxes)" },
            @{ @"cat": @"Controls",   @"name": @"range",      @"desc": @"Slider over a numeric range" },
            @{ @"cat": @"Controls",   @"name": @"trigger",    @"desc": @"Button that fires actions" },
            @{ @"cat": @"Controls",   @"name": @"submit",     @"desc": @"Button that runs a submission" },
            @{ @"cat": @"Controls",   @"name": @"upload",     @"desc": @"File chooser bound to a node" },
            @{ @"cat": @"Containers", @"name": @"group",      @"desc": @"Box grouping related controls" },
            @{ @"cat": @"Containers", @"name": @"repeat",     @"desc": @"Repeats its content per nodeset node" },
            @{ @"cat": @"Containers", @"name": @"switch",     @"desc": @"Shows exactly one of its cases" },
            @{ @"cat": @"Containers", @"name": @"case",       @"desc": @"One branch of a switch" },
            @{ @"cat": @"Containers", @"name": @"dialog",     @"desc": @"Panel shown by xf:show" },
            @{ @"cat": @"Choices",    @"name": @"item",       @"desc": @"A fixed choice inside select / select1" },
            @{ @"cat": @"Choices",    @"name": @"itemset",    @"desc": @"Choices generated from instance nodes" },
            @{ @"cat": @"Model",      @"name": @"model",      @"desc": @"The data model of the form (in the head)" },
            @{ @"cat": @"Model",      @"name": @"instance",   @"desc": @"XML data document inside a model" },
            @{ @"cat": @"Model",      @"name": @"bind",       @"desc": @"Type / constraint / calculate for nodes" },
            @{ @"cat": @"Model",      @"name": @"submission", @"desc": @"How instance data is sent and received" },
            @{ @"cat": @"Actions",    @"name": @"action",     @"desc": @"Groups several actions under one event" },
            @{ @"cat": @"Actions",    @"name": @"setvalue",   @"desc": @"Sets an instance node to a value" },
            @{ @"cat": @"Actions",    @"name": @"insert",     @"desc": @"Inserts nodes into a nodeset" },
            @{ @"cat": @"Actions",    @"name": @"delete",     @"desc": @"Deletes nodes from a nodeset" },
            @{ @"cat": @"Actions",    @"name": @"toggle",     @"desc": @"Switches a switch to one of its cases" },
            @{ @"cat": @"Actions",    @"name": @"setindex",   @"desc": @"Moves a repeat's current index" },
            @{ @"cat": @"Actions",    @"name": @"setfocus",   @"desc": @"Gives a form control the focus" },
            @{ @"cat": @"Actions",    @"name": @"send",       @"desc": @"Runs a submission" },
            @{ @"cat": @"Actions",    @"name": @"dispatch",   @"desc": @"Fires an event at a target element" },
            @{ @"cat": @"Actions",    @"name": @"load",       @"desc": @"Opens a resource (link traversal)" },
            @{ @"cat": @"Actions",    @"name": @"message",    @"desc": @"Shows a message to the user" },
            @{ @"cat": @"Actions",    @"name": @"reset",      @"desc": @"Resets a model to its initial data" },
            @{ @"cat": @"Actions",    @"name": @"rebuild",    @"desc": @"Rebuilds a model's dependency graph" },
            @{ @"cat": @"Actions",    @"name": @"recalculate",@"desc": @"Recalculates a model's computed values" },
            @{ @"cat": @"Actions",    @"name": @"revalidate", @"desc": @"Revalidates a model's data" },
            @{ @"cat": @"Actions",    @"name": @"refresh",    @"desc": @"Refreshes the user interface" },
            @{ @"cat": @"Actions",    @"name": @"show",       @"desc": @"Opens a dialog (XSLTForms)" },
            @{ @"cat": @"Actions",    @"name": @"hide",       @"desc": @"Closes a dialog (XSLTForms)" },
        ];
    }
    return catalog;
}

/// Round badge for a tab bar / outline item (the ModelBuilder pattern —
/// drawn, no image resources).
NSImage *XFDBadge(NSString *letters, CGFloat r, CGFloat g, CGFloat b)
{
    static NSMutableDictionary *cache;
    if (cache == nil) {
        cache = [NSMutableDictionary dictionary];
    }
    NSString *key = [NSString stringWithFormat:@"%@|%.2f%.2f%.2f", letters, r, g, b];
    NSImage *image = cache[key];
    if (image) {
        return image;
    }
    NSSize size = NSMakeSize(15, 15);
    image = [[NSImage alloc] initWithSize:size];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [image lockFocus];
    [[NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.5, 14, 14)] fill];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:letters.length > 1 ? 7.0 : 9.0],
        NSForegroundColorAttributeName: [NSColor whiteColor],
    };
    NSSize ts = [letters sizeWithAttributes:attrs];
    [letters drawAtPoint:NSMakePoint((size.width - ts.width) / 2, (size.height - ts.height) / 2)
          withAttributes:attrs];
    [image unlockFocus];
#pragma clang diagnostic pop
    cache[key] = image;
    return image;
}

void XFDInspectorSpecsFilePresent(void) {}
