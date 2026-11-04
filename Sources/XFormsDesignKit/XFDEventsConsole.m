/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDEventsConsole.h"
#import <XFormsKit/XFXMLTypes.h>


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

#pragma mark - XFDEventsConsoleViewController (the console's view)

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

@interface XFDEventsConsoleViewController ()
@property (nonatomic, strong) NSArray<XFDEventsLogEntry *> *shown;
@property (nonatomic, assign, readwrite, getter=isRunning) BOOL running;
@end

@implementation XFDEventsConsoleViewController

- (instancetype)init
{
    if ((self = [super initWithNibName:@"XFDEventsConsole"
                                bundle:[NSBundle bundleForClass:[XFDEventsConsoleViewController class]]])) {
        _log = [[XFDEventsLog alloc] init];
        _shown = @[];
        self.title = @"Events Console";
        __weak XFDEventsConsoleViewController *weakSelf = self;
        _log.onAppend = ^(XFDEventsLogEntry *entry) {
            (void)entry;
            [weakSelf refreshKeepingScroll:NO];
        };
    }
    return self;
}

- (void)loadView
{
    [super loadView];
    [self refreshKeepingScroll:YES];
}

- (void)startWithHostDocument:(XFXMLDocument *)hostDocument
{
    [self.log install];
    self.running = YES;
    // XSLTForms debugging(): the duplicate-id scan when the console opens
    NSArray<NSString *> *dupes = XFDDuplicateIDsInDocument(hostDocument);
    if (dupes.count) {
        XFTraceWrite(XFTraceKindWarning, nil, nil, @"WARNING: Duplicate ids: %@",
                     [dupes componentsJoinedByString:@" "]);
    }
    [self refreshKeepingScroll:YES];
}

- (void)stop
{
    [self.log uninstall];
    self.running = NO;
}

#pragma mark actions

- (NSInteger)kindFilter
{
    NSInteger sel = [self.kindPopup indexOfSelectedItem];
    return sel <= 0 ? -1 : sel - 1; // rows follow the XFTraceKind order
}

- (IBAction)filterChanged:(id)sender
{
    (void)sender;
    [self refreshKeepingScroll:YES];
}

- (IBAction)pauseClicked:(id)sender
{
    (void)sender;
    self.log.paused = ([self.pauseButton state] == NSOnState);
    [self refreshKeepingScroll:YES];
}

- (IBAction)clearClicked:(id)sender
{
    (void)sender;
    [self.log clear];
    [self refreshKeepingScroll:NO];
}

- (IBAction)saveClicked:(id)sender
{
    (void)sender;
    NSSavePanel *save = [NSSavePanel savePanel];
    [save setNameFieldStringValue:@"tracelog.xml"];
    if ([save runModal] == NSFileHandlingPanelOKButton && [save URL]) {
        [[self.log tracelogXMLString] writeToURL:[save URL] atomically:YES
                                        encoding:NSUTF8StringEncoding error:NULL];
    }
}

- (void)refreshKeepingScroll:(BOOL)keep
{
    if (![self isViewLoaded]) {
        return;
    }
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

#pragma mark - XFDEventsConsole (the app's panel)

@interface XFDEventsConsole ()
@property (nonatomic, assign, readwrite, getter=isVisible) BOOL visible;
@end

@implementation XFDEventsConsole {
    NSArray *_topLevelObjects;
}

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
        _viewController = [[XFDEventsConsoleViewController alloc] init];
    }
    return self;
}

/// The panel from its XIB, the console's view in it.
- (BOOL)loadPanelIfNeeded
{
    if (self.panel != nil) {
        return YES;
    }
    NSArray *objects = nil;
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"XFDEventsConsolePanel"
                                          bundle:[NSBundle bundleForClass:[XFDEventsConsole class]]];
    if (![nib instantiateWithOwner:self topLevelObjects:&objects] || self.panel == nil) {
        NSLog(@"XFormsDesignKit: XFDEventsConsolePanel did not load");
        return NO;
    }
    _topLevelObjects = objects;
    NSView *content = [self.panel contentView];
    NSView *view = [self.viewController view];
    [view setFrame:[content bounds]];
    [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [content addSubview:view];
    return YES;
}

- (void)showWithHostDocument:(XFXMLDocument *)hostDocument
{
    if (![self loadPanelIfNeeded]) {
        return;
    }
    [self.viewController startWithHostDocument:hostDocument];
    self.visible = YES;
    [self.panel makeKeyAndOrderFront:nil];
}

- (void)close
{
    [self.viewController stop];
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
    // the close box: tracing stops, as toggling off does
    [self.viewController stop];
    self.visible = NO;
}

@end
