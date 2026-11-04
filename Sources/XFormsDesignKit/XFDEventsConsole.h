/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* Port of the XSLTForms events console (F1 / debugMode: the
   xsltforms_console div fed by XsltForms_browser.debugConsole.write).
   The engine emits the same stream through XFXMLEvents' trace sink —
   "Dispatching event …", "Captured event …", Setvalue/insert/setIndex/
   Submit/Load/Calculate lines, errors — and this panel renders it live:
   delta-ms timestamps like the original, filtering by kind and text,
   pause, clear, and Save Log… in XSLTForms' tracelog XML format (the
   document the special `xsltforms-tracelog` resource serves). Opening
   the console also runs the original's duplicate-id scan and logs a
   WARNING line per duplicated id. Non-modal: it stays open while the
   form runs in the preview, and survives preview rebuilds (the sink is
   engine-global, so a replaced processor keeps tracing). */
#pragma once
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>
#import <XFormsKit/XFXMLEvents.h>

NS_ASSUME_NONNULL_BEGIN

/// One console line.
@interface XFDEventsLogEntry : NSObject
@property (nonatomic, assign) XFTraceKind kind;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy, nullable) NSString *eventName;
@property (nonatomic, copy, nullable) NSString *elementDescription;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, assign) NSTimeInterval deltaMs; ///< since the previous line (debugConsole's "Δms ->" prefix)
@end

/// The testable core (the selftest drives it headless — the panel needs
/// a window): records the engine trace stream, filters it, and exports
/// the tracelog XML. Install/uninstall mirror debugConsole isOpen()
/// gating — while uninstalled the engine's trace calls are no-ops.
@interface XFDEventsLog : NSObject <XFEventTraceSink>
@property (nonatomic, strong, readonly) NSArray<XFDEventsLogEntry *> *entries;
@property (nonatomic, assign) BOOL paused;          ///< drop incoming lines while set
@property (nonatomic, copy, nullable) void (^onAppend)(XFDEventsLogEntry *entry);
@property (nonatomic, assign) NSUInteger capacity;  ///< oldest lines drop beyond this (default 5000)
- (void)install;    ///< become the engine's trace sink
- (void)uninstall;  ///< stop tracing (only if still the installed sink)
- (void)clear;
/// kindFilter -1 = all kinds; substring nil/empty = no text filter
- (NSArray<XFDEventsLogEntry *> *)entriesMatchingKind:(NSInteger)kindFilter
                                            substring:(nullable NSString *)substring;
/// XSLTForms' tracelog document: <tracelog><event>timestamp -> text</event>…
- (NSString *)tracelogXMLString;
@end

/// The duplicate-id scan XSLTForms runs when the console opens
/// ("WARNING: Duplicate ids: …"): every id value used more than once.
NSArray<NSString *> *XFDDuplicateIDsInDocument(XFXMLDocument *_Nullable document);

/// The console's view (XFDEventsConsole.xib): its log's lines, filtered by
/// kind and text, Pause, Clear, Save Log…, and the count. Started, it is
/// the engine's trace sink (only one log is at a time); stopped, the
/// engine's trace calls are no-ops again. The app shows it in a floating
/// panel (XFDEventsConsole); an IDE in a pane of its own.
@interface XFDEventsConsoleViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)init;
@property (nonatomic, strong) IBOutlet NSPopUpButton *kindPopup;
@property (nonatomic, strong) IBOutlet NSTextField *filterField;
@property (nonatomic, strong) IBOutlet NSButton *pauseButton;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSTextField *countField;
@property (nonatomic, strong, readonly) XFDEventsLog *log;
@property (nonatomic, assign, readonly, getter=isRunning) BOOL running;
/// The log installed as the trace sink, and the duplicate-id scan run
/// over `hostDocument` (nil skips it).
- (void)startWithHostDocument:(nullable XFXMLDocument *)hostDocument;
- (void)stop;
- (IBAction)filterChanged:(nullable id)sender;
- (IBAction)pauseClicked:(nullable id)sender;
- (IBAction)clearClicked:(nullable id)sender;
- (IBAction)saveClicked:(nullable id)sender;
@end

/// The app's events console: the console's view in a floating panel
/// (XFDEventsConsolePanel.xib), one for the app.
@interface XFDEventsConsole : NSObject <NSWindowDelegate>
+ (XFDEventsConsole *)sharedConsole;
@property (nonatomic, strong, nullable) IBOutlet NSPanel *panel;
@property (nonatomic, strong, readonly) XFDEventsConsoleViewController *viewController;
@property (nonatomic, assign, readonly, getter=isVisible) BOOL visible;
/// Show (installing the log as trace sink) and run the duplicate-id scan
/// over `hostDocument`; nil skips the scan.
- (void)showWithHostDocument:(nullable XFXMLDocument *)hostDocument;
- (void)close;
- (void)toggleWithHostDocument:(nullable XFXMLDocument *)hostDocument;
@end

NS_ASSUME_NONNULL_END
