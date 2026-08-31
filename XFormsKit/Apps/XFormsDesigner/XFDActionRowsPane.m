/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDActionRowsPane.h"
#import "XFDWindowControllerPriv.h"
#import "XFDInspectorSpecs.h"
#import "XFDDocument.h"
#import "XFDEditors.h"
#import "XFDXPathField.h"
#import "XFDRichTextField.h"
#import "XFDIDRefField.h"

@implementation XFDActionRowsPane {
    NSView *_host;
    NSXMLElement *_element;
}

- (instancetype)initWithController:(XFDWindowController *)controller host:(NSView *)host
{
    self = [super init];
    if (self) {
        _controller = controller;
        _host = host;
    }
    return self;
}

/// (Re)build the Action page's rows for the selected action element —
/// only when the element actually changed: rebuilding under a component
/// that is mid-action-send would free it.
- (void)buildRowsIfNeededForElement:(NSXMLElement *)element
{
    if (_element == element && _rows != nil) {
        return;
    }
    for (NSView *sub in [[_host subviews] copy]) {
        [sub removeFromSuperview];
    }
    NSMutableArray *rows = [NSMutableArray array];
    NSArray *specs = XFDActionSpecs()[[element localName]] ?: @[];
    // every handler starts with its trigger, the XML Events attribute
    // module's observer/target redirections, and the XForms 1.1 §10.1.1
    // conditionals: if (condition), while (iteration) — plus iterate,
    // the XSLTForms / 2.0 extension the engine also compiles
    NSMutableArray *all = [NSMutableArray arrayWithArray:@[
        @{ @"label": @"Event", @"attr": @"ev:event", @"kind": @"idref", @"idkind": @"#event",
           @"tip": @"The event this handler listens for — on its parent element, or on the Observer when set (XML Events)." },
        @{ @"label": @"Observer", @"attr": @"ev:observer", @"kind": @"idref", @"idkind": @"*",
           @"tip": @"Listen on this element instead of the parent — id of the observer (XML Events attribute module)." },
        @{ @"label": @"Target filter", @"attr": @"ev:target", @"kind": @"idref", @"idkind": @"*",
           @"tip": @"Only fire when the event's original target is this element — id filter for bubbled events (XML Events attribute module)." },
        @{ @"label": @"If", @"attr": @"if", @"kind": @"xpath", @"expect": @"value",
           @"tip": @"Condition: the action runs only when this is true (§10.1.1)." },
        @{ @"label": @"While", @"attr": @"while", @"kind": @"xpath", @"expect": @"value",
           @"tip": @"Loop: the action repeats while this stays true (§10.1.1)." },
        @{ @"label": @"Iterate", @"attr": @"iterate", @"kind": @"xpath", @"expect": @"nodeset",
           @"tip": @"Run once per node in this set, each as context (XSLTForms / XForms 2.0)." },
    ]];
    [all addObjectsFromArray:specs];

    NSRect bounds = [_host bounds];
    CGFloat y = NSHeight(bounds) - 30;
    for (NSDictionary *spec in all) {
        NSString *kind = spec[@"kind"];
        NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, y, 92, 14)];
        [label setEditable:NO];
        [label setBordered:NO];
        [label setDrawsBackground:NO];
        [label setAlignment:NSRightTextAlignment];
        [label setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [label setStringValue:spec[@"label"] ?: @""];
        [label setAutoresizingMask:NSViewMinYMargin];
        [_host addSubview:label];

        NSRect frame = NSMakeRect(98, y - 4, NSWidth(bounds) - 106, 21);
        NSView *view = nil;
        if ([kind isEqualToString:@"xpath"]) {
            XFDXPathField *field = [[XFDXPathField alloc] initWithFrame:frame];
            field.provider = (id)self.controller;
            field.target = self.controller;
            field.action = @selector(inspectorChanged:);
            NSString *expect = spec[@"expect"];
            field.expectation = [expect isEqualToString:@"nodeset"] ? XFDXPathExpectNodeSet
                : ([expect isEqualToString:@"node"] ? XFDXPathExpectNode
                : ([expect isEqualToString:@"value"] ? XFDXPathExpectValue : XFDXPathExpectAny));
            view = field;
        } else if ([kind isEqualToString:@"idref"]) {
            XFDIDRefField *field = [[XFDIDRefField alloc]
                initWithFrame:NSMakeRect(98, y - 5, NSWidth(bounds) - 106, 23)];
            field.kind = spec[@"idkind"];
            field.provider = (id)self.controller;
            field.target = self.controller;
            field.action = @selector(inspectorChanged:);
            view = field;
        } else if ([kind isEqualToString:@"content"]) {
            XFDRichTextField *field = [[XFDRichTextField alloc] initWithFrame:frame];
            field.provider = (id)self.controller;
            field.target = self.controller;
            field.action = @selector(inspectorChanged:);
            view = field;
        } else if ([kind isEqualToString:@"popup"]) {
            NSPopUpButton *popup = [[NSPopUpButton alloc]
                initWithFrame:NSMakeRect(98, y - 5, NSWidth(bounds) - 106, 22) pullsDown:NO];
            [[popup cell] setControlSize:NSSmallControlSize];
            [popup setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
            [popup addItemsWithTitles:spec[@"options"]];
            [popup setTarget:self.controller];
            [popup setAction:@selector(inspectorChanged:)];
            view = popup;
        } else {   // field
            NSTextField *field = [[NSTextField alloc] initWithFrame:
                NSMakeRect(98, y - 3, NSWidth(bounds) - 106, 19)];
            [[field cell] setControlSize:NSSmallControlSize];
            [field setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
            [[field cell] setScrollable:YES];
            [[field cell] setSendsActionOnEndEditing:YES];
            [field setTarget:self.controller];
            [field setAction:@selector(inspectorChanged:)];
            view = field;
        }
        [view setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        if (spec[@"tip"] != nil) {
            [view setToolTip:spec[@"tip"]];
        }
        [_host addSubview:view];
        [rows addObject:@{ @"attr": spec[@"attr"] ?: @"", @"kind": kind, @"view": view }];
        y -= 26;
    }
    _rows = rows;
    _element = element;
}

- (void)fillForElement:(NSXMLElement *)element
{
    [self buildRowsIfNeededForElement:element];
    XFDElementEditor *e = [XFDElementEditor editorForElement:element
                                                    document:[self.controller formDocument]];
    for (NSDictionary *row in _rows) {
        NSString *kind = row[@"kind"];
        id view = row[@"view"];
        if ([kind isEqualToString:@"content"]) {
            XFHostEdit *edit = [[self.controller formDocument] hostEdit];
            NSString *xml = [edit inlineContentXMLOfElement:element];
            [(XFDRichTextField *)view setPlainText:[XFXML stringValueOfNode:element] ?: @""
                                               xml:xml.length ? xml : nil];
        } else if ([kind isEqualToString:@"popup"]) {
            NSString *value = [e attribute:row[@"attr"]];
            NSInteger idx = value.length ? [(NSPopUpButton *)view indexOfItemWithTitle:value] : 0;
            [(NSPopUpButton *)view selectItemAtIndex:idx >= 0 ? idx : 0];
        } else {
            [(id)view setStringValue:[e attribute:row[@"attr"]]];
        }
    }
}

- (void)applyToElement:(NSXMLElement *)element
{
    if (_element != element || _rows == nil) {
        return;
    }
    XFDElementEditor *e = [XFDElementEditor editorForElement:element
                                                    document:[self.controller formDocument]];
    for (NSDictionary *row in _rows) {
        NSString *kind = row[@"kind"];
        id view = row[@"view"];
        if ([kind isEqualToString:@"content"]) {
            XFHostEdit *edit = [[self.controller formDocument] hostEdit];
            XFDRichTextField *field = view;
            NSString *xml = [field isRich] ? [field xmlValue]
                                           : XFDEscapeXML([field stringValue]);
            [edit setInlineContentXML:xml onElement:element error:NULL];
        } else if ([kind isEqualToString:@"popup"]) {
            NSInteger idx = [(NSPopUpButton *)view indexOfSelectedItem];
            [e setAttribute:row[@"attr"]
                      value:idx <= 0 ? @"" : [(NSPopUpButton *)view titleOfSelectedItem]];
        } else {
            [e setAttribute:row[@"attr"] value:[(id)view stringValue]];
        }
    }
}

@end

void XFDActionRowsPaneFilePresent(void) {}
