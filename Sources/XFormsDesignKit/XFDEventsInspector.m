/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDEventsInspector.h"
#import <XFormsKit/XFXMLTypes.h>
#import "XFDInspectorSpecs.h"
#import "XFDXPathField.h"

static BOOL XFDElementIsActionHandler(XFXMLElement *e)
{
    return XFDActionSpecs()[[e localName]] != nil
        && [XFXML element:e hasLocalName:[e localName] namespaceURI:XFXFormsNamespaceURI];
}

/// The handler's effective observer id (ev:observer, engine-style "#id"
/// tolerated) — empty when it observes its parent, the default.
static NSString *XFDHandlerObserverID(XFXMLElement *e)
{
    NSString *observer = [XFXML attributeValue:@"observer"
                                  namespaceURI:XFXMLEventsNamespaceURI
                                     onElement:e];
    if ([observer hasPrefix:@"#"]) {
        observer = [observer substringFromIndex:1];
    }
    return observer ?: @"";
}

static void XFDCollectHandlersObserving(NSString *observerID, XFXMLElement *scope,
                                        XFXMLElement *skipParent, NSMutableArray *out)
{
    for (XFXMLNode *c in [scope children]) {
        if ([c kind] != XFXMLElementKind) {
            continue;
        }
        XFXMLElement *e = (XFXMLElement *)c;
        if ([e parent] != skipParent && XFDElementIsActionHandler(e)
            && [XFDHandlerObserverID(e) isEqualToString:observerID]) {
            [out addObject:e];
        }
        XFDCollectHandlersObserving(observerID, e, skipParent, out);
    }
}

@implementation XFDEventsInspector

@synthesize handlerElements = _handlerElements;

- (instancetype)initWithFormEditor:(XFDFormEditor *)formEditor nibName:(NSString *)nibName
{
    if ((self = [super initWithFormEditor:formEditor nibName:nibName])) {
        self.title = @"Events";
        _handlerElements = @[];
    }
    return self;
}

- (void)viewDidLoadFromNib
{
    [self reload];
}

- (NSArray *)handlerElementsOf:(XFXMLElement *)element
{
    // The table shows what LISTENS ON this element. XML Events defaults
    // the observer to the handler's parent, but ev:observer redirects it:
    // a child observing elsewhere drops out, and any handler in the
    // document naming this element's id comes in (its Detail column shows
    // the ev:observer that brought it here).
    NSString *elementID = [[element attributeForName:@"id"] stringValue];
    NSMutableArray *out = [NSMutableArray array];
    for (XFXMLNode *c in [element children]) {
        if ([c kind] != XFXMLElementKind) {
            continue;
        }
        XFXMLElement *e = (XFXMLElement *)c;
        if (!XFDElementIsActionHandler(e)) {
            continue;
        }
        NSString *observer = XFDHandlerObserverID(e);
        if (observer.length && ![observer isEqualToString:elementID]) {
            continue;   // redirected away — it does not listen here
        }
        [out addObject:e];
    }
    XFXMLElement *root = [self.formEditor rootElement];
    if (elementID.length && root != nil) {
        XFDCollectHandlersObserving(elementID, root, element, out);
    }
    return out;
}

/// The action names the + menu offers for the selection.
- (NSArray *)addableHandlerNames
{
    NSMutableArray *names = [NSMutableArray array];
    XFXMLElement *selected = self.formEditor.selection;
    if (selected != nil) {
        for (NSString *name in [XFHostEdit insertableNamesUnderParent:selected]) {
            if (XFDActionSpecs()[name] != nil) {
                [names addObject:name];
            }
        }
    }
    return names;
}

- (void)reload
{
    XFXMLElement *selected = self.formEditor.selection;
    _handlerElements = selected ? [self handlerElementsOf:selected] : @[];
    if (![self isViewLoaded]) {
        return;
    }
    BOOL canAdd = [self addableHandlerNames].count > 0;
    [self.plusMinusControl setEnabled:canAdd forSegment:0];
    [self.plusMinusControl setEnabled:[self.table selectedRow] >= 0 forSegment:1];
    [self.noteField setStringValue:selected == nil
        ? @"No selection."
        : (canAdd || _handlerElements.count
            ? @"Handlers below listen on this element's events."
            : @"This element does not take event handlers.")];
    [self.table reloadData];
}

#pragma mark The form editor's news

- (void)formEditorSelectionDidChange:(XFDFormEditor *)editor
{
    (void)editor;
    [self reload];
}

- (void)formEditor:(XFDFormEditor *)editor hostDidChange:(XFXMLElement *)element
{
    (void)editor;
    (void)element;
    [self reload];
}

- (void)formEditorProcessorWasReplaced:(XFDFormEditor *)editor
{
    (void)editor;
    [self reload];
}

#pragma mark + and −

- (IBAction)plusMinusClicked:(id)sender
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
                                                             action:@selector(addHandler:)
                                                      keyEquivalent:@""];
            [item setTarget:self];
            [item setRepresentedObject:name];
        }
        // [NSApp currentEvent] is the mouse-UP by action time and menus
        // cannot track from it: a mouse-down over the control instead
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
        NSInteger row = [self.table selectedRow];
        if (row < 0 || (NSUInteger)row >= _handlerElements.count) {
            XFDBeep();
            return;
        }
        [self.formEditor.hostEdit deleteElement:_handlerElements[(NSUInteger)row]];
    }
}

- (void)addHandler:(NSMenuItem *)item
{
    NSError *error = nil;
    XFXMLElement *selected = self.formEditor.selection;
    XFXMLElement *element = [self.formEditor.hostEdit insertElementNamed:[item representedObject]
                                                             underParent:selected
                                                                 atIndex:-1
                                                                   error:&error];
    if (element == nil) {
        [self presentError:error];
        return;
    }
    // stay on the parent: the table is the point here; a double click on
    // the new row edits the handler in depth
    NSUInteger row = [_handlerElements indexOfObjectIdenticalTo:element];
    if (row != NSNotFound) {
        [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    }
}

- (IBAction)rowDoubleClicked:(id)sender
{
    (void)sender;
    NSInteger row = [self.table clickedRow];
    if (row < 0) {
        row = [self.table selectedRow];
    }
    if (row < 0 || (NSUInteger)row >= _handlerElements.count) {
        return;
    }
    // the handler's own page, in the Attributes inspector
    XFXMLElement *handler = _handlerElements[(NSUInteger)row];
    [self.formEditor showAttributes];
    self.formEditor.selection = handler;
}

#pragma mark The table

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
    (void)note;
    [self.plusMinusControl setEnabled:[self.table selectedRow] >= 0 forSegment:1];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
    (void)table;
    return (NSInteger)_handlerElements.count;
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)table;
    if ((NSUInteger)row >= _handlerElements.count) {
        return nil;
    }
    XFXMLElement *e = _handlerElements[(NSUInteger)row];
    NSString *ident = [column identifier];
    if ([ident isEqualToString:@"event"]) {
        return [XFXML attributeValue:@"event" namespaceURI:XFXMLEventsNamespaceURI onElement:e] ?: @"";
    }
    if ([ident isEqualToString:@"action"]) {
        return [e localName] ?: @"";
    }
    // detail: the interesting attributes, else the text content
    NSMutableArray *parts = [NSMutableArray array];
    for (XFXMLNode *attr in [e attributes]) {
        NSString *name = [attr name] ?: @"";
        if ([name isEqualToString:@"id"] || [name hasSuffix:@":event"] || [name isEqualToString:@"event"]) {
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
