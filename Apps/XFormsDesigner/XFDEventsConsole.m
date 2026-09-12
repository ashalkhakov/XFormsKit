/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDEventsConsole.h"
#import <XFormsKit/XFXMLTypes.h>

void XFDEventsConsoleFilePresent(void) {}

@implementation XFDEventsLogEntry
@end

#pragma mark - XFDEventsLog

@interface XFDEventsLog ()
@property (nonatomic, strong) NSMutableArray<XFDEventsLogEntry *> *store;
@property (nonatomic, strong, nullable) NSDate *lastDate;
@end

@implementation XFDEventsLog

- (instancetype)init
{
    if ((self = [super init])) {
        _store = [NSMutableArray array];
        _capacity = 5000;
    }
    return self;
}

- (NSArray<XFDEventsLogEntry *> *)entries
{
    return self.store;
}

- (void)install
{
    [XFXMLEvents setTraceSink:self];
}

- (void)uninstall
{
    // debugConsole isOpen() gating: only step down if we are the sink —
    // a second console (or a test sink) may have replaced us.
    if ([XFXMLEvents traceSink] == (id)self) {
        [XFXMLEvents setTraceSink:nil];
    }
}

- (void)clear
{
    [self.store removeAllObjects];
    self.lastDate = nil; // debugConsole.clear resets time_
}

- (void)traceEventOfKind:(XFTraceKind)kind
                 message:(NSString *)message
               eventName:(NSString *)eventName
                 element:(XFXMLElement *)element
{
    if (self.paused) {
        return;
    }
    XFDEventsLogEntry *entry = [[XFDEventsLogEntry alloc] init];
    entry.kind = kind;
    entry.message = message ?: @"";
    entry.eventName = eventName;
    entry.elementDescription = element ? XFTraceDescribeElement(element) : nil;
    entry.date = [NSDate date];
    // debugConsole.write: "time - time_ + ' -> ' + text" — a delta from
    // the PREVIOUS line, not from the console's opening.
    entry.deltaMs = self.lastDate
        ? [entry.date timeIntervalSinceDate:self.lastDate] * 1000.0 : 0.0;
    self.lastDate = entry.date;
    [self.store addObject:entry];
    if (self.store.count > self.capacity) {
        [self.store removeObjectsInRange:NSMakeRange(0, self.store.count - self.capacity)];
    }
    if (self.onAppend) {
        self.onAppend(entry);
    }
}

- (NSArray<XFDEventsLogEntry *> *)entriesMatchingKind:(NSInteger)kindFilter
                                            substring:(NSString *)substring
{
    NSMutableArray *result = [NSMutableArray array];
    for (XFDEventsLogEntry *e in self.store) {
        if (kindFilter >= 0 && e.kind != (XFTraceKind)kindFilter) {
            continue;
        }
        if (substring.length &&
            [e.message rangeOfString:substring options:NSCaseInsensitiveSearch].location == NSNotFound &&
            (e.eventName == nil ||
             [e.eventName rangeOfString:substring options:NSCaseInsensitiveSearch].location == NSNotFound)) {
            continue;
        }
        [result addObject:e];
    }
    return result;
}

- (NSString *)tracelogXMLString
{
    // XSLTForms debugMode tracelog: createXMLDocument('<tracelog xmlns=""/>'),
    // one <event> per line, "yyyy-MM-ddThh:mm:ssz -> text".
    XFXMLElement *root = [[XFXMLElement alloc] initWithName:@"tracelog"];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
    for (XFDEventsLogEntry *e in self.store) {
        XFXMLElement *ev = [[XFXMLElement alloc] initWithName:@"event"];
        [ev setStringValue:[NSString stringWithFormat:@"%@ -> %@",
                            [fmt stringFromDate:e.date], e.message]];
        [root addChild:ev];
    }
    XFXMLDocument *doc = [[XFXMLDocument alloc] initWithRootElement:root];
    [doc setVersion:@"1.0"];
    [doc setCharacterEncoding:@"UTF-8"];
    return [doc XMLStringWithOptions:XFXMLNodePrettyPrint];
}

@end

#pragma mark - duplicate-id scan

NSArray<NSString *> *XFDDuplicateIDsInDocument(XFXMLDocument *document)
{
    // XSLTForms debugging(): walk every element, count id attribute
    // values, warn on the ones seen more than once.
    if (document == nil) {
        return @[];
    }
    NSCountedSet *seen = [[NSCountedSet alloc] init];
    NSMutableArray *order = [NSMutableArray array];
    NSMutableArray *queue = [NSMutableArray arrayWithObject:document];
    while (queue.count) {
        XFXMLNode *node = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([node kind] == XFXMLElementKind) {
            NSString *ident = [[(XFXMLElement *)node attributeForName:@"id"] stringValue];
            if (ident.length) {
                if ([seen countForObject:ident] == 0) {
                    [order addObject:ident];
                }
                [seen addObject:ident];
            }
        }
        for (XFXMLNode *child in [node children]) {
            [queue addObject:child];
        }
    }
    NSMutableArray *dupes = [NSMutableArray array];
    for (NSString *ident in order) {
        if ([seen countForObject:ident] > 1) {
            [dupes addObject:ident];
        }
    }
    return dupes;
}

#pragma mark - XFDEventsConsole (the panel)

static NSString *XFDTraceKindName(XFTraceKind kind)
{
    switch (kind) {
        case XFTraceKindEvent:   return @"event";
        case XFTraceKindHandler: return @"handler";
        case XFTraceKindAction:  return @"action";
        case XFTraceKindModel:   return @"model";
        case XFTraceKindError:   return @"error";
        case XFTraceKindWarning: return @"warning";
    }
    return @"?";
}

@interface XFDEventsConsole ()
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) XFDEventsLog *log;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSPopUpButton *kindPopup;
@property (nonatomic, strong) NSTextField *filterField;
@property (nonatomic, strong) NSButton *pauseButton;
@property (nonatomic, strong) NSTextField *countField;
@property (nonatomic, strong) NSArray<XFDEventsLogEntry *> *shown;
@property (nonatomic, assign, readwrite, getter=isVisible) BOOL visible;
@end

@implementation XFDEventsConsole

+ (XFDEventsConsole *)sharedConsole
{
    static XFDEventsConsole *shared = nil;
    if (shared == nil) {
        shared = [[XFDEventsConsole alloc] init];
    }
    return shared;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _log = [[XFDEventsLog alloc] init];
        _shown = @[];
    }
    return self;
}

- (void)buildPanelIfNeeded
{
    if (self.panel) {
        return;
    }
    NSRect frame = NSMakeRect(120, 120, 720, 420);
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:frame
                  styleMask:(NSTitledWindowMask | NSClosableWindowMask
                             | NSResizableWindowMask | NSUtilityWindowMask)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [panel setTitle:@"Events Console"];
    [panel setReleasedWhenClosed:NO];
    [panel setFloatingPanel:NO];
    [panel setDelegate:(id)self];
    [panel setMinSize:NSMakeSize(480, 240)];
    NSView *content = [panel contentView];
    CGFloat width = NSWidth([content bounds]);
    CGFloat height = NSHeight([content bounds]);

    /* Top bar: kind filter, text filter, pause, clear, save. */
    CGFloat barY = height - 32;
    NSPopUpButton *kinds = [[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(8, barY, 110, 24) pullsDown:NO];
    for (NSString *title in @[ @"All kinds", @"Events", @"Handlers",
                               @"Actions", @"Model", @"Errors", @"Warnings" ]) {
        [kinds addItemWithTitle:title];
    }
    [kinds setTarget:self];
    [kinds setAction:@selector(filterChanged:)];
    [kinds setAutoresizingMask:NSViewMinYMargin];
    [content addSubview:kinds];
    self.kindPopup = kinds;

    NSTextField *filter = [[NSTextField alloc]
        initWithFrame:NSMakeRect(126, barY + 2, width - 126 - 250, 21)];
    [[filter cell] setPlaceholderString:@"Filter (message or event name)"];
    [filter setTarget:self];
    [filter setAction:@selector(filterChanged:)];
    [filter setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [content addSubview:filter];
    self.filterField = filter;

    CGFloat x = width - 244;
    NSButton *pause = [[NSButton alloc] initWithFrame:NSMakeRect(x, barY, 70, 24)];
    [pause setButtonType:NSPushOnPushOffButton];
    [pause setTitle:@"Pause"];
    [pause setBezelStyle:NSRoundedBezelStyle];
    [pause setTarget:self];
    [pause setAction:@selector(pauseClicked:)];
    [pause setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [content addSubview:pause];
    self.pauseButton = pause;

    NSButton *clear = [[NSButton alloc] initWithFrame:NSMakeRect(x + 74, barY, 70, 24)];
    [clear setTitle:@"Clear"];
    [clear setBezelStyle:NSRoundedBezelStyle];
    [clear setTarget:self];
    [clear setAction:@selector(clearClicked:)];
    [clear setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [content addSubview:clear];

    NSButton *save = [[NSButton alloc] initWithFrame:NSMakeRect(x + 148, barY, 92, 24)];
    [save setTitle:@"Save Log…"];
    [save setBezelStyle:NSRoundedBezelStyle];
    [save setTarget:self];
    [save setAction:@selector(saveClicked:)];
    [save setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [content addSubview:save];

    /* The log table. */
    NSScrollView *scroll = [[NSScrollView alloc]
        initWithFrame:NSMakeRect(0, 24, width, height - 24 - 36)];
    [scroll setHasVerticalScroller:YES];
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    NSTableView *table = [[NSTableView alloc]
        initWithFrame:[[scroll contentView] bounds]];
    struct { NSString *ident; NSString *title; CGFloat width; } cols[] = {
        { @"delta", @"Δms", 52 },
        { @"kind", @"Kind", 62 },
        { @"event", @"Event", 150 },
        { @"message", @"Message", 420 },
    };
    for (NSUInteger i = 0; i < 4; i++) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:cols[i].ident];
        [[col headerCell] setStringValue:cols[i].title];
        [col setWidth:cols[i].width];
        [col setEditable:NO];
        [table addTableColumn:col];
    }
    [table setUsesAlternatingRowBackgroundColors:YES];
    [table setAllowsMultipleSelection:NO];
    [table setDataSource:(id)self];
    [table setDelegate:(id)self];
    [scroll setDocumentView:table];
    [content addSubview:scroll];
    self.table = table;

    /* Bottom: the count line. */
    NSTextField *count = [[NSTextField alloc]
        initWithFrame:NSMakeRect(8, 3, width - 16, 17)];
    [count setEditable:NO];
    [count setBordered:NO];
    [count setDrawsBackground:NO];
    [count setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [count setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [content addSubview:count];
    self.countField = count;

    self.panel = panel;

    __weak XFDEventsConsole *weakSelf = self;
    self.log.onAppend = ^(XFDEventsLogEntry *entry) {
        (void)entry;
        [weakSelf refreshKeepingScroll:NO];
    };
}

#pragma mark show / close

- (void)showWithHostDocument:(XFXMLDocument *)hostDocument
{
    [self buildPanelIfNeeded];
    [self.log install];
    self.visible = YES;
    // XSLTForms debugging(): duplicate-id scan when the console opens.
    NSArray<NSString *> *dupes = XFDDuplicateIDsInDocument(hostDocument);
    if (dupes.count) {
        XFTraceWrite(XFTraceKindWarning, nil, nil,
                     @"WARNING: Duplicate ids: %@",
                     [dupes componentsJoinedByString:@" "]);
    }
    [self refreshKeepingScroll:YES];
    [self.panel makeKeyAndOrderFront:nil];
}

- (void)close
{
    [self.log uninstall];
    self.visible = NO;
    [self.panel orderOut:nil];
}

- (void)toggleWithHostDocument:(XFXMLDocument *)hostDocument
{
    if (self.visible) {
        [self close];
    } else {
        [self showWithHostDocument:hostDocument];
    }
}

- (void)windowWillClose:(NSNotification *)note
{
    (void)note;
    // The close box: stop tracing, exactly like toggling off.
    [self.log uninstall];
    self.visible = NO;
}

#pragma mark actions

- (NSInteger)kindFilter
{
    NSInteger sel = [self.kindPopup indexOfSelectedItem];
    return sel <= 0 ? -1 : sel - 1; // rows follow the XFTraceKind order
}

- (void)filterChanged:(id)sender
{
    (void)sender;
    [self refreshKeepingScroll:YES];
}

- (void)pauseClicked:(id)sender
{
    (void)sender;
    self.log.paused = ([self.pauseButton state] == NSOnState);
}

- (void)clearClicked:(id)sender
{
    (void)sender;
    [self.log clear];
    [self refreshKeepingScroll:NO];
}

- (void)saveClicked:(id)sender
{
    (void)sender;
    NSSavePanel *save = [NSSavePanel savePanel];
    [save setNameFieldStringValue:@"tracelog.xml"];
    if ([save runModal] == NSFileHandlingPanelOKButton && [save URL]) {
        NSString *xml = [self.log tracelogXMLString];
        [xml writeToURL:[save URL] atomically:YES
               encoding:NSUTF8StringEncoding error:NULL];
    }
}

- (void)refreshKeepingScroll:(BOOL)keep
{
    self.shown = [self.log entriesMatchingKind:[self kindFilter]
                                     substring:[self.filterField stringValue]];
    [self.table reloadData];
    [self.countField setStringValue:
        [NSString stringWithFormat:@"%lu line(s), %lu shown%@",
         (unsigned long)self.log.entries.count,
         (unsigned long)self.shown.count,
         self.log.paused ? @" — paused" : @""]];
    if (!keep && self.shown.count) {
        [self.table scrollRowToVisible:(NSInteger)self.shown.count - 1];
    }
}

#pragma mark table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    (void)tableView;
    return (NSInteger)self.shown.count;
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
    (void)tableView;
    if (row < 0 || (NSUInteger)row >= self.shown.count) {
        return @"";
    }
    XFDEventsLogEntry *e = self.shown[(NSUInteger)row];
    NSString *ident = [column identifier];
    if ([ident isEqualToString:@"delta"]) {
        return [NSString stringWithFormat:@"%.0f", e.deltaMs];
    }
    if ([ident isEqualToString:@"kind"]) {
        return XFDTraceKindName(e.kind);
    }
    if ([ident isEqualToString:@"event"]) {
        return e.eventName ?: @"";
    }
    return e.message;
}

- (void)tableView:(NSTableView *)tableView
  willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn *)column
              row:(NSInteger)row
{
    (void)tableView; (void)column;
    if (row < 0 || (NSUInteger)row >= self.shown.count) {
        return;
    }
    XFDEventsLogEntry *e = self.shown[(NSUInteger)row];
    NSColor *color = [NSColor controlTextColor];
    if (e.kind == XFTraceKindError) {
        color = [NSColor redColor];
    } else if (e.kind == XFTraceKindWarning) {
        color = [NSColor orangeColor];
    } else if (e.kind == XFTraceKindHandler || e.kind == XFTraceKindModel) {
        color = [NSColor disabledControlTextColor];
    }
    if ([cell respondsToSelector:@selector(setTextColor:)]) {
        [cell setTextColor:color];
    }
}

@end
