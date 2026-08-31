/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDEventsPane.h"
#import "XFDWindowControllerPriv.h"
#import "XFDInspectorSpecs.h"
#import "XFDDocument.h"

@implementation XFDEventsPane {
    NSSegmentedControl *_eventsControl;
    NSTextField *_eventsNote;
}

@synthesize handlerElements = _handlerElements;
@synthesize table = _eventsTable;

- (instancetype)initWithController:(XFDWindowController *)controller host:(NSView *)host
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    _controller = controller;
    NSRect bounds = [host bounds];
    CGFloat W = NSWidth(bounds), H = NSHeight(bounds);

    _eventsNote = [[NSTextField alloc] initWithFrame:NSMakeRect(8, H - 34, W - 16, 28)];
    [_eventsNote setEditable:NO];
    [_eventsNote setBordered:NO];
    [_eventsNote setDrawsBackground:NO];
    [_eventsNote setFont:[NSFont systemFontOfSize:11]];
    [[_eventsNote cell] setWraps:YES];
    [_eventsNote setStringValue:@"Handlers below listen on this element's events."];
    [_eventsNote setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [host addSubview:_eventsNote];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:
        NSMakeRect(8, 40, W - 16, H - 80)];
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];
    _eventsTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, W - 16, H - 80)];
    struct { NSString *ident; NSString *title; CGFloat width; } cols[] = {
        { @"event", @"Event", 96 },
        { @"action", @"Action", 64 },
        { @"detail", @"Detail", 90 },
    };
    for (NSUInteger i = 0; i < 3; i++) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:cols[i].ident];
        [[col headerCell] setStringValue:cols[i].title];
        [col setWidth:cols[i].width];
        [[col dataCell] setEditable:NO];
        [[col dataCell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [_eventsTable addTableColumn:col];
    }
    [_eventsTable setDataSource:self];
    [_eventsTable setDelegate:self];
    [_eventsTable setTarget:self];
    [_eventsTable setDoubleAction:@selector(eventsRowDoubleClicked:)];
    [_eventsTable setAllowsMultipleSelection:NO];
    [scroll setDocumentView:_eventsTable];
    [host addSubview:scroll];

    _eventsControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(8, 8, 68, 24)];
    [_eventsControl setSegmentCount:2];
    [_eventsControl setLabel:@"+" forSegment:0];
    [_eventsControl setLabel:@"−" forSegment:1];
    [_eventsControl setAutoresizingMask:NSViewMaxYMargin];
    [(NSSegmentedCell *)[_eventsControl cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
    [_eventsControl setTarget:self];
    [_eventsControl setAction:@selector(eventsPlusMinusClicked:)];
    [host addSubview:_eventsControl];
    return self;
}

static BOOL XFDElementIsActionHandler(NSXMLElement *e)
{
    return XFDActionSpecs()[[e localName]] != nil
        && [XFXML element:e hasLocalName:[e localName]
             namespaceURI:XFXFormsNamespaceURI];
}

/// The handler's effective observer id (ev:observer, engine-style "#id"
/// tolerated) — empty when it observes its parent, the default.
static NSString *XFDHandlerObserverID(NSXMLElement *e)
{
    NSString *observer = [XFXML attributeValue:@"observer"
                                  namespaceURI:XFXMLEventsNamespaceURI
                                     onElement:e];
    if ([observer hasPrefix:@"#"]) {
        observer = [observer substringFromIndex:1];
    }
    return observer ?: @"";
}

static void XFDCollectHandlersObserving(NSString *observerID, NSXMLElement *scope,
                                        NSXMLElement *skipParent, NSMutableArray *out)
{
    for (NSXMLNode *c in [scope children]) {
        if ([c kind] != NSXMLElementKind) {
            continue;
        }
        NSXMLElement *e = (NSXMLElement *)c;
        if ([e parent] != skipParent && XFDElementIsActionHandler(e)
            && [XFDHandlerObserverID(e) isEqualToString:observerID]) {
            [out addObject:e];
        }
        XFDCollectHandlersObserving(observerID, e, skipParent, out);
    }
}

- (NSArray *)handlerElementsOf:(NSXMLElement *)element
{
    // The table shows what LISTENS ON this element. XML Events defaults
    // the observer to the handler's parent, but ev:observer redirects it:
    // a child observing elsewhere drops out, and any handler in the
    // document naming this element's id comes in (its Detail column shows
    // the ev:observer that brought it here).
    NSString *elementID = [[element attributeForName:@"id"] stringValue];
    NSMutableArray *out = [NSMutableArray array];
    for (NSXMLNode *c in [element children]) {
        if ([c kind] != NSXMLElementKind) {
            continue;
        }
        NSXMLElement *e = (NSXMLElement *)c;
        if (!XFDElementIsActionHandler(e)) {
            continue;
        }
        NSString *observer = XFDHandlerObserverID(e);
        if (observer.length && ![observer isEqualToString:elementID]) {
            continue;   // redirected away — it does not listen here
        }
        [out addObject:e];
    }
    if (elementID.length && [self.controller rootElement] != nil) {
        XFDCollectHandlersObserving(elementID, [self.controller rootElement], element, out);
    }
    return out;
}

/// The action names the + menu offers for the selection.
- (NSArray *)addableHandlerNames
{
    NSMutableArray *names = [NSMutableArray array];
    if (self.controller.selected != nil) {
        for (NSString *name in [XFHostEdit insertableNamesUnderParent:self.controller.selected]) {
            if (XFDActionSpecs()[name] != nil) {
                [names addObject:name];
            }
        }
    }
    return names;
}

- (void)reload
{
    _handlerElements = self.controller.selected ? [self handlerElementsOf:self.controller.selected] : @[];
    BOOL canAdd = [self addableHandlerNames].count > 0;
    [_eventsControl setEnabled:canAdd forSegment:0];
    [_eventsControl setEnabled:[_eventsTable selectedRow] >= 0
                    forSegment:1];
    [_eventsNote setStringValue:self.controller.selected == nil
        ? @"No selection."
        : (canAdd || _handlerElements.count
            ? @"Handlers below listen on this element's events."
            : @"This element does not take event handlers.")];
    [_eventsTable reloadData];
}

- (void)eventsPlusMinusClicked:(NSSegmentedControl *)sender
{
    if ([sender selectedSegment] == 0) {
        NSArray *names = [self addableHandlerNames];
        if (names.count == 0) {
            XFDBeep();
            return;
        }
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Add Handler"];
        for (NSString *name in names) {
            NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:name
                                               action:@selector(eventsAddHandler:)
                                        keyEquivalent:@""];
            [item setTarget:self];
            [item setRepresentedObject:name];
        }
        // [NSApp currentEvent] is the mouse-UP by action time and menus
        // cannot track from it — synthesize a mouse-down over the control
        NSPoint where = [[sender superview] convertPoint:[sender frame].origin toView:nil];
        NSEvent *down = [NSEvent mouseEventWithType:NSLeftMouseDown
                                           location:where
                                      modifierFlags:0
                                          timestamp:0
                                       windowNumber:[[sender window] windowNumber]
                                            context:nil
                                        eventNumber:0
                                         clickCount:1
                                           pressure:1];
        [NSMenu popUpContextMenu:menu withEvent:down forView:sender];
    } else {
        NSInteger row = [_eventsTable selectedRow];
        if (row < 0 || (NSUInteger)row >= _handlerElements.count) {
            XFDBeep();
            return;
        }
        [[self.controller formDocument].hostEdit deleteElement:_handlerElements[(NSUInteger)row]];
    }
}

- (void)eventsAddHandler:(NSMenuItem *)item
{
    NSString *name = [item representedObject];
    NSError *error = nil;
    NSXMLElement *element = [[self.controller formDocument].hostEdit
        insertElementNamed:name underParent:self.controller.selected atIndex:-1 error:&error];
    if (element == nil) {
        [self.controller presentError:error];
        return;
    }
    // stay on the parent — the table is the point here; double-click the
    // new row to edit the handler in depth
    NSUInteger row = [[self handlerElementsOf:self.controller.selected] indexOfObject:element];
    if (row != NSNotFound) {
        [_eventsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                  byExtendingSelection:NO];
    }
}

- (void)eventsRowDoubleClicked:(id)sender
{
    (void)sender;
    NSInteger row = [_eventsTable clickedRow];
    if (row < 0) {
        row = [_eventsTable selectedRow];
    }
    if (row < 0 || (NSUInteger)row >= _handlerElements.count) {
        return;
    }
    // jump into the handler's own inspector (the Attributes group's
    // Action page)
    [self.controller showAttributesGroup];
    [self.controller selectElement:_handlerElements[(NSUInteger)row]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
    if ([note object] == _eventsTable) {
        [_eventsControl setEnabled:[_eventsTable selectedRow] >= 0 forSegment:1];
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
    return table == _eventsTable ? (NSInteger)_handlerElements.count : 0;
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
    if (table != _eventsTable || (NSUInteger)row >= _handlerElements.count) {
        return nil;
    }
    NSXMLElement *e = _handlerElements[(NSUInteger)row];
    NSString *ident = [column identifier];
    if ([ident isEqualToString:@"event"]) {
        return [XFXML attributeValue:@"event"
                        namespaceURI:XFXMLEventsNamespaceURI
                           onElement:e] ?: @"";
    }
    if ([ident isEqualToString:@"action"]) {
        return [e localName] ?: @"";
    }
    // detail: the interesting attributes, else the text content
    NSMutableArray *parts = [NSMutableArray array];
    for (NSXMLNode *attr in [e attributes]) {
        NSString *name = [attr name] ?: @"";
        if ([name isEqualToString:@"id"] || [name hasSuffix:@":event"]
            || [name isEqualToString:@"event"]) {
            continue;
        }
        [parts addObject:[NSString stringWithFormat:@"%@=%@", name, [attr stringValue] ?: @""]];
    }
    if (parts.count == 0) {
        NSString *text = [[XFXML stringValueOfNode:e] stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return text ?: @"";
    }
    return [parts componentsJoinedByString:@"  "];
}

@end

void XFDEventsPaneFilePresent(void) {}
