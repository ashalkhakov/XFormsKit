/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDSubmissionTester.h"
#import <XFormsKit/XFXMLTypes.h>
#import "XFDXPathField.h"   // XFDBeep
#import <XFormsKit/XFSubmission.h>
#import <XFormsKit/XFSubmissionTransport.h>
#import <XFormsKit/XFXMLEvents.h>

#pragma mark - Transports

@implementation XFDEchoTransport

- (XFSubmissionResponse *)performRequest:(XFSubmissionRequest *)request error:(NSError **)error
{
    (void)error;
    XFSubmissionResponse *r = [[XFSubmissionResponse alloc] init];
    r.statusCode = 200;
    r.body = request.body ?: @"";
    r.mediaType = request.mediaType ?: @"application/xml";
    r.headers = @{ @"Content-Type": r.mediaType };
    return r;
}

@end

/// Records the submission-level exchange around any inner transport.
@interface XFDCaptureTransport : NSObject <XFSubmissionTransport>
@property (nonatomic, strong) id<XFSubmissionTransport> inner;
@property (nonatomic, strong) XFSubmissionRequest *lastRequest;
@property (nonatomic, strong) XFSubmissionResponse *lastResponse;
@property (nonatomic, strong) NSError *lastError;
@end

@implementation XFDCaptureTransport

- (XFSubmissionResponse *)performRequest:(XFSubmissionRequest *)request error:(NSError **)error
{
    self.lastRequest = request;
    NSError *inner = nil;
    XFSubmissionResponse *resp = [self.inner performRequest:request error:&inner];
    self.lastResponse = resp;
    self.lastError = inner;
    if (inner && error) {
        *error = inner;
    }
    return resp;
}

@end

#pragma mark - One run, headless

NSDictionary *XFDPerformSubmission(XFSubmission *submission,
                                   id<XFSubmissionTransport> transport,
                                   NSDictionary *extraHeaders)
{
    // the capture sits INSIDE the injector, so the recorded request is
    // the one that reaches the wire — injected session headers included
    XFDCaptureTransport *capture = [[XFDCaptureTransport alloc] init];
    capture.inner = transport;
    id<XFSubmissionTransport> entry = capture;
    if (extraHeaders.count) {
        XFHeaderInjectingTransport *inject = [[XFHeaderInjectingTransport alloc] init];
        inject.inner = capture;
        inject.extraHeaders = extraHeaders;
        entry = inject;
    }
    id<XFSubmissionTransport> saved = submission.transport;
    submission.transport = entry;
    submission.lastEventContext = nil;
    [XFXMLEvents dispatch:submission name:@"xforms-submit"];
    if (submission.asynchronous) {
        [submission waitUntilFinished:15.0];
    }
    submission.transport = saved;
    NSDictionary *ctx = submission.lastEventContext ?: @{};
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if (capture.lastRequest) {
        out[@"request"] = capture.lastRequest;
    }
    if (capture.lastResponse) {
        out[@"response"] = capture.lastResponse;
    }
    NSString *errorType = ctx[@"error-type"];
    out[@"outcome"] = errorType.length ? @"error" : @"done";
    if (errorType.length) {
        out[@"error-type"] = errorType;
    }
    out[@"status"] = @(capture.lastResponse ? capture.lastResponse.statusCode
                                            : (capture.lastError ? 0 : -1));
    if (capture.lastError) {
        out[@"error"] = [capture.lastError localizedDescription] ?: @"network error";
    }
    return out;
}

#pragma mark - Panel

static NSString *XFDPrettyXML(NSString *text)
{
    if (text.length == 0) {
        return text ?: @"";
    }
    XFXMLDocument *doc = [[XFXMLDocument alloc] initWithXMLString:text options:0 error:NULL];
    if (doc == nil) {
        return text;
    }
    return [doc XMLStringWithOptions:XFXMLNodePrettyPrint] ?: text;
}

/// Header names whose values never reach the history (the security rule
/// in docs/submission-auth.md: no logging of credentials).
static BOOL XFDHeaderIsSecret(NSString *name)
{
    return [name caseInsensitiveCompare:@"Authorization"] == NSOrderedSame
        || [name caseInsensitiveCompare:@"Proxy-Authorization"] == NSOrderedSame
        || [name caseInsensitiveCompare:@"Cookie"] == NSOrderedSame
        || [name caseInsensitiveCompare:@"Set-Cookie"] == NSOrderedSame;
}

@implementation XFDSubmissionTester {
    NSPanel *_panel;
    XFProcessor *_processor;
    NSPopUpButton *_submissionPopup;
    NSPopUpButton *_transportPopup;
    NSPopUpButton *_historyPopup;
    NSTextField *_requestLine;
    NSTableView *_headersTable;
    NSArray *_headerRows;          /* dicts: name / value / source */
    NSTextView *_bodyView;
    NSTextField *_extraHeadersField;
    NSTextField *_statusLine;
    NSTableView *_responseHeadersTable;
    NSArray *_responseHeaderRows;
    NSTextView *_responseView;
    NSMutableArray *_history;      /* summary dicts, newest first */
}

- (NSArray<XFSubmission *> *)submissions
{
    NSMutableArray *out = [NSMutableArray array];
    for (XFModel *model in _processor.models) {
        [out addObjectsFromArray:model.submissions];
    }
    return out;
}

- (XFSubmission *)chosenSubmission
{
    NSInteger i = [_submissionPopup indexOfSelectedItem];
    NSArray *all = [self submissions];
    return i >= 0 && (NSUInteger)i < all.count ? all[(NSUInteger)i] : all.firstObject;
}

- (NSDictionary *)extraHeaders
{
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *line in [[_extraHeadersField stringValue]
            componentsSeparatedByString:@";"]) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) {
            continue;
        }
        NSString *name = [[line substringToIndex:colon.location]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *value = [[line substringFromIndex:colon.location + 1]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (name.length) {
            out[name] = value;
        }
    }
    return out;
}

- (id<XFSubmissionTransport>)chosenTransport
{
    switch ([_transportPopup indexOfSelectedItem]) {
        case 1:
            return [[XFDEchoTransport alloc] init];
        case 2:
            return nil;   // offline: no transport = fail fast below
        default:
            return _processor.defaultTransport;
    }
}

#pragma mark preview

/// Recompute the request side from the engine's own previewRequest.
- (void)refreshPreview
{
    XFSubmission *sub = [self chosenSubmission];
    if (sub == nil) {
        [_requestLine setStringValue:@"No submissions in this document."];
        _headerRows = @[];
        [_headersTable reloadData];
        [_bodyView setString:@""];
        return;
    }
    XFSubmissionRequest *req = [sub previewRequest];
    [_requestLine setStringValue:[NSString stringWithFormat:@"%@  %@",
        [req.method uppercaseString], req.URLString ?: @""]];
    NSMutableArray *rows = [NSMutableArray array];
    if (req.mediaType.length) {
        [rows addObject:@{ @"name": @"Content-Type", @"value": req.mediaType,
                           @"source": @"serializer" }];
    }
    for (NSString *name in req.headers) {
        [rows addObject:@{ @"name": name, @"value": req.headers[name] ?: @"",
                           @"source": @"xf:header" }];
    }
    NSDictionary *extra = [self extraHeaders];
    for (NSString *name in extra) {
        [rows addObject:@{ @"name": name, @"value": extra[name],
                           @"source": @"injected" }];
    }
    _headerRows = rows;
    [_headersTable reloadData];
    NSString *lower = [req.method lowercaseString];
    if ([lower isEqualToString:@"get"] || [lower isEqualToString:@"delete"]) {
        [_bodyView setString:@"(no body — the serialization rides the URL's query)"];
    } else if (req.body.length) {
        [_bodyView setString:XFDPrettyXML(req.body)];
    } else {
        [_bodyView setString:@"(empty body)"];
    }
    NSString *replace = sub.replace ?: @"none";
    NSString *target = @"";
    if ([replace isEqualToString:@"instance"]) {
        target = [NSString stringWithFormat:@" → instance('%@')",
                  sub.instanceID ?: @"(default)"];
    }
    [_statusLine setStringValue:[NSString stringWithFormat:
        @"replace=%@%@ · serialization=%@%@ — Send runs the real xforms-submit "
        @"against the live preview data.",
        replace, target, sub.serialization ?: @"application/xml",
        sub.asynchronous ? @" · asynchronous" : @""]];
    [_statusLine setTextColor:[NSColor disabledControlTextColor]];
}

#pragma mark send

- (void)sendClicked:(id)sender
{
    (void)sender;
    XFSubmission *sub = [self chosenSubmission];
    if (sub == nil) {
        XFDBeep();
        return;
    }
    id<XFSubmissionTransport> transport = [self chosenTransport];
    NSDictionary *summary;
    if (transport == nil) {
        // offline mode: a transport that always fails, exercising the
        // xforms-submit-error path
        XFMapSubmissionTransport *dead = [[XFMapSubmissionTransport alloc] init];
        summary = XFDPerformSubmission(sub, dead, [self extraHeaders]);
    } else {
        summary = XFDPerformSubmission(sub, transport, [self extraHeaders]);
    }
    [self showRunSummary:summary];

    // history keeps the run with its credentials REDACTED (the
    // no-logging rule): good enough to recall what happened, never a
    // token store
    XFSubmissionRequest *req = summary[@"request"];
    NSMutableDictionary *redacted = [NSMutableDictionary dictionary];
    for (NSString *name in req.headers) {
        redacted[name] = XFDHeaderIsSecret(name) ? @"•••" : req.headers[name];
    }
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"HH:mm:ss"];
    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:@{
        @"time": [df stringFromDate:[NSDate date]],
        @"line": [NSString stringWithFormat:@"%@ %@",
                  [req.method uppercaseString] ?: @"?", req.URLString ?: @"?"],
        @"status": summary[@"status"] ?: @0,
        @"outcome": summary[@"outcome"] ?: @"?",
        @"requestHeaders": redacted,
        @"requestBody": req.body ?: @"",
    }];
    XFSubmissionResponse *resp = summary[@"response"];
    if (resp != nil) {
        entry[@"responseBody"] = resp.body ?: @"";
    }
    [_history insertObject:entry atIndex:0];
    while (_history.count > 20) {
        [_history removeLastObject];
    }
    [self reloadHistoryPopup];
    [self refreshPreview];   // replace="instance" may have changed the data
}

- (void)showRunSummary:(NSDictionary *)summary
{
    XFSubmissionResponse *resp = summary[@"response"];
    BOOL ok = [summary[@"outcome"] isEqualToString:@"done"];
    NSString *line;
    if (ok) {
        line = [NSString stringWithFormat:@"✓ %@ — xforms-submit-done",
                summary[@"status"]];
    } else {
        line = [NSString stringWithFormat:@"✗ %@ — xforms-submit-error (%@)%@",
                summary[@"status"], summary[@"error-type"] ?: @"?",
                summary[@"error"] ? [@" — " stringByAppendingString:summary[@"error"]] : @""];
    }
    [_statusLine setStringValue:line];
    [_statusLine setTextColor:ok ? [NSColor disabledControlTextColor] : [NSColor redColor]];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *name in resp.headers) {
        [rows addObject:@{ @"name": name, @"value": resp.headers[name] ?: @"",
                           @"source": @"" }];
    }
    _responseHeaderRows = rows;
    [_responseHeadersTable reloadData];
    [_responseView setString:resp.body.length ? XFDPrettyXML(resp.body) : @"(empty)"];
}

#pragma mark history

- (void)reloadHistoryPopup
{
    [_historyPopup removeAllItems];
    [_historyPopup addItemWithTitle:[NSString stringWithFormat:@"History (%lu)",
                                     (unsigned long)_history.count]];
    for (NSDictionary *entry in _history) {
        [_historyPopup addItemWithTitle:[NSString stringWithFormat:@"%@ · %@ · %@",
            entry[@"time"], entry[@"status"], entry[@"line"]]];
    }
}

- (void)historyPicked:(id)sender
{
    (void)sender;
    NSInteger i = [_historyPopup indexOfSelectedItem] - 1;
    if (i < 0 || (NSUInteger)i >= _history.count) {
        return;
    }
    NSDictionary *entry = _history[(NSUInteger)i];
    [_responseView setString:[(NSString *)entry[@"responseBody"] length]
        ? XFDPrettyXML(entry[@"responseBody"]) : @"(empty)"];
    [_statusLine setStringValue:[NSString stringWithFormat:@"%@ · %@ · %@ (%@)",
        entry[@"time"], entry[@"status"], entry[@"line"], entry[@"outcome"]]];
}

#pragma mark tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
    if (table == _headersTable) {
        return (NSInteger)_headerRows.count;
    }
    return (NSInteger)_responseHeaderRows.count;
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
    NSArray *rows = table == _headersTable ? _headerRows : _responseHeaderRows;
    if ((NSUInteger)row >= rows.count) {
        return nil;
    }
    return rows[(NSUInteger)row][[column identifier]];
}

- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    (void)table; (void)column; (void)row;
    return NO;
}

#pragma mark build

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame in:(NSView *)content
{
    NSTextField *l = [[NSTextField alloc] initWithFrame:frame];
    [l setEditable:NO];
    [l setBordered:NO];
    [l setDrawsBackground:NO];
    [l setFont:[NSFont systemFontOfSize:11]];
    [l setStringValue:text];
    [content addSubview:l];
    return l;
}

- (NSTableView *)headerTableIn:(NSView *)content frame:(NSRect)frame withSource:(BOOL)withSource
{
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];
    NSTableView *table = [[NSTableView alloc] initWithFrame:
        NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame))];
    struct { NSString *ident; NSString *title; CGFloat width; } cols[] = {
        { @"name", @"Header", 150 },
        { @"value", @"Value", withSource ? 330 : 420 },
        { @"source", @"Source", 70 },
    };
    for (NSUInteger i = 0; i < (withSource ? 3u : 2u); i++) {
        NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:cols[i].ident];
        [[c headerCell] setStringValue:cols[i].title];
        [c setWidth:cols[i].width];
        [[c dataCell] setEditable:NO];
        [[c dataCell] setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [table addTableColumn:c];
    }
    [table setDataSource:self];
    [table setDelegate:self];
    [scroll setDocumentView:table];
    [content addSubview:scroll];
    return table;
}

- (NSTextView *)textViewIn:(NSView *)content frame:(NSRect)frame
{
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];
    NSTextView *tv = [[NSTextView alloc] initWithFrame:
        NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame))];
    [tv setFont:[NSFont userFixedPitchFontOfSize:11]];
    [tv setEditable:NO];
    [tv setVerticallyResizable:YES];
    [tv setAutoresizingMask:NSViewWidthSizable];
    [[tv textContainer] setWidthTracksTextView:YES];
    [scroll setDocumentView:tv];
    [content addSubview:scroll];
    return tv;
}

- (void)buildPanel
{
    const CGFloat W = 820, H = 640;
    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, W, H)
                                        styleMask:NSTitledWindowMask | NSClosableWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    [_panel setTitle:@"Submission Tester"];
    NSView *content = [_panel contentView];

    // top bar
    [self label:@"Submission:" frame:NSMakeRect(12, H - 34, 78, 17) in:content];
    _submissionPopup = [[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(92, H - 39, 170, 26) pullsDown:NO];
    for (XFSubmission *sub in [self submissions]) {
        [_submissionPopup addItemWithTitle:sub.identifier.length
            ? sub.identifier : @"(unnamed)"];
    }
    [_submissionPopup setTarget:self];
    [_submissionPopup setAction:@selector(submissionPicked:)];
    [content addSubview:_submissionPopup];

    _transportPopup = [[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(270, H - 39, 130, 26) pullsDown:NO];
    [_transportPopup addItemsWithTitles:@[ @"Live HTTP", @"Echo", @"Offline" ]];
    [_transportPopup setToolTip:
        @"Live HTTP = the document's transport (cookie jar included). "
        @"Echo answers with the request body (offline replace round-trips). "
        @"Offline fails fast — the xforms-submit-error path."];
    [content addSubview:_transportPopup];

    _historyPopup = [[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(408, H - 39, 190, 26) pullsDown:NO];
    [_historyPopup setTarget:self];
    [_historyPopup setAction:@selector(historyPicked:)];
    [content addSubview:_historyPopup];

    NSButton *send = [[NSButton alloc] initWithFrame:NSMakeRect(W - 108, H - 42, 96, 30)];
    [send setTitle:@"Send"];
    [send setBezelStyle:NSRoundedBezelStyle];
    [send setKeyEquivalent:@"\r"];
    [send setTarget:self];
    [send setAction:@selector(sendClicked:)];
    [content addSubview:send];

    // request side
    _requestLine = [self label:@"" frame:NSMakeRect(12, H - 64, W - 24, 18) in:content];
    [_requestLine setFont:[NSFont userFixedPitchFontOfSize:12]];
    _headersTable = [self headerTableIn:content
                                  frame:NSMakeRect(12, H - 188, W - 24, 116)
                             withSource:YES];
    [self label:@"Extra headers (Name: value; Name: value) — injected like a host session:"
          frame:NSMakeRect(12, H - 212, W - 24, 17) in:content];
    _extraHeadersField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, H - 236, W - 24, 22)];
    [_extraHeadersField setFont:[NSFont userFixedPitchFontOfSize:11]];
    [[_extraHeadersField cell] setSendsActionOnEndEditing:YES];
    [_extraHeadersField setTarget:self];
    [_extraHeadersField setAction:@selector(submissionPicked:)];
    [content addSubview:_extraHeadersField];
    [self label:@"Body (as the runtime serializes it):"
          frame:NSMakeRect(12, H - 260, W - 24, 17) in:content];
    _bodyView = [self textViewIn:content frame:NSMakeRect(12, H - 372, W - 24, 108)];

    // response side
    _statusLine = [self label:@"" frame:NSMakeRect(12, H - 398, W - 24, 18) in:content];
    _responseHeadersTable = [self headerTableIn:content
                                          frame:NSMakeRect(12, H - 480, W - 24, 76)
                                     withSource:NO];
    _responseView = [self textViewIn:content frame:NSMakeRect(12, 44, W - 24, H - 532)];

    NSButton *close = [[NSButton alloc] initWithFrame:NSMakeRect(W - 100, 8, 84, 28)];
    [close setTitle:@"Close"];
    [close setBezelStyle:NSRoundedBezelStyle];
    [close setKeyEquivalent:@"\033"];
    [close setTarget:self];
    [close setAction:@selector(closeClicked:)];
    [content addSubview:close];
    [_panel setDelegate:(id)self];
}

- (void)submissionPicked:(id)sender
{
    (void)sender;
    [self refreshPreview];
}

- (void)closeClicked:(id)sender
{
    (void)sender;
    [NSApp stopModal];
    [_panel orderOut:nil];
}

- (BOOL)windowShouldClose:(id)sender
{
    (void)sender;
    [self closeClicked:sender];
    return NO;
}

+ (void)runForProcessor:(XFProcessor *)processor
      initialSubmission:(NSString *)identifier
{
    XFDSubmissionTester *tester = [[XFDSubmissionTester alloc] init];
    tester->_processor = processor;
    tester->_history = [NSMutableArray array];
    [tester buildPanel];
    if ([tester submissions].count == 0) {
        XFDBeep();
        return;
    }
    if (identifier.length) {
        NSArray *all = [tester submissions];
        for (NSUInteger i = 0; i < all.count; i++) {
            if ([[all[i] identifier] isEqualToString:identifier]) {
                [tester->_submissionPopup selectItemAtIndex:(NSInteger)i];
                break;
            }
        }
    }
    [tester reloadHistoryPopup];
    [tester refreshPreview];
    [tester->_panel center];
    [NSApp runModalForWindow:tester->_panel];
}

@end

void XFDSubmissionTesterFilePresent(void) {}
