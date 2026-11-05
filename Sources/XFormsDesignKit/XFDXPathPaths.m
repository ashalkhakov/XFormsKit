/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDXPathPaths.h"
#import <XFormsKit/XFXMLTypes.h>

#pragma mark - Location-path step model

/// Known axes, in the steps-table popup order.
NSArray *XFDKnownAxes(void)
{
    return @[ @"child", @"attribute", @"parent", @"self",
              @"descendant", @"descendant-or-self",
              @"ancestor", @"ancestor-or-self",
              @"following-sibling", @"preceding-sibling",
              @"following", @"preceding" ];
}

#pragma mark - Syntax highlighting
//
// Lives in XFDExpressionField: an NSTextView backed by
// XFDXPathTextStorage, which recolours itself on every change. One path,
// always on, like a code editor. What used to be here -- an attributed
// value for an idle field and a pass over the window's shared field
// editor for an edited one -- AppKit could overwrite at any moment, and
// did, which is why expressions stopped looking highlighted.

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


#pragma mark - A node's path, as the picker and predicate editor show it

NSString *XFDDisplayPathOfNode(XFXMLNode *node)
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
