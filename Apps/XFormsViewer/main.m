#import <AppKit/AppKit.h>
#import "XFFormDocument.h"
#import "XFDocumentWindowController.h"
#if defined(GNUSTEP)
#import <XFormsKit/XFCrashReporter.h>   // not in the Xcode project: GNUstep-only
#endif

@interface XFViewerApp : NSObject
@end

@implementation XFViewerApp

- (void)applicationWillFinishLaunching:(NSNotification *)note
{
    (void)[XFFormDocument class];
    (void)[XFDocumentWindowController class];
    (void)[NSDocumentController sharedDocumentController];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    [self installMenus];
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    return NO;
}

- (void)installMenus
{
    NSMenu *menubar = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"XFormsViewer" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"XFormsViewer"];
    [appMenu addItemWithTitle:@"About XFormsViewer"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit XFormsViewer"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];
    [menubar addItem:appItem];

    NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"File" action:NULL keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New"
                        action:@selector(newDocument:)
                 keyEquivalent:@"n"];
    [fileMenu addItemWithTitle:@"Open…"
                        action:@selector(openDocument:)
                 keyEquivalent:@"o"];
    NSMenuItem *samplesItem = [[NSMenuItem alloc] initWithTitle:@"Open Sample"
                                                         action:NULL
                                                  keyEquivalent:@""];
    NSMenu *samples = [[NSMenu alloc] initWithTitle:@"Open Sample"];
    for (NSString *name in [self sampleNames]) {
        NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:name
                                                    action:@selector(openSample:)
                                             keyEquivalent:@""];
        [it setRepresentedObject:name];
        [it setTarget:self];
        [samples addItem:it];
    }
    [samplesItem setSubmenu:samples];
    [fileMenu addItem:samplesItem];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Save"
                        action:@selector(saveDocument:)
                 keyEquivalent:@"s"];
    [fileMenu addItemWithTitle:@"Save As…"
                        action:@selector(saveDocumentAs:)
                 keyEquivalent:@"S"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close"
                        action:@selector(performClose:)
                 keyEquivalent:@"w"];
    [fileItem setSubmenu:fileMenu];
    [menubar addItem:fileItem];

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Add Palette Item"
                        action:@selector(addPaletteItem:)
                 keyEquivalent:@""];
    [editMenu addItemWithTitle:@"Duplicate Element"
                        action:@selector(duplicateSelected:)
                 keyEquivalent:@"d"];
    [editMenu addItemWithTitle:@"Delete Element"
                        action:@selector(deleteSelected:)
                 keyEquivalent:@""];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Apply Inspector"
                        action:@selector(applyInspector:)
                 keyEquivalent:@""];
    [editMenu addItemWithTitle:@"Apply Source"
                        action:@selector(applySource:)
                 keyEquivalent:@""];
    [editItem setSubmenu:editMenu];
    [menubar addItem:editItem];

    NSMenuItem *viewItem = [[NSMenuItem alloc] initWithTitle:@"View" action:NULL keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem *reload = [[NSMenuItem alloc] initWithTitle:@"Reload Form"
                                                    action:@selector(refreshForm:)
                                             keyEquivalent:@"r"];
    [viewMenu addItem:reload];
    [viewItem setSubmenu:viewMenu];
    [menubar addItem:viewItem];

    [NSApp setMainMenu:menubar];
}

- (NSArray<NSString *> *)sampleNames
{
    // Everything in Samples/ (XSLTForms testsuite/samples + XFormsKit extras).
    return @[
        @"address.xhtml",
        @"balance-table.xhtml",
        @"balance.xhtml",
        @"bind.xhtml",
        @"bookmarks.xhtml",
        @"books.xhtml",
        @"button.xhtml",
        @"calculator.xhtml",
        @"checkbox.xhtml",
        @"choices.xhtml",
        @"colors.xhtml",
        @"date.xhtml",
        @"deep-copy.xhtml",
        @"dialog.xhtml",
        @"first-field.xhtml",
        @"flags.xhtml",
        @"gantt.xhtml",
        @"hello.xhtml",
        @"incremental-textarea.xhtml",
        @"incremental.xhtml",
        @"input-width.xhtml",
        @"input.xhtml",
        @"output-image.xhtml",
        @"piechart.xhtml",
        @"range.xhtml",
        @"readonly.xhtml",
        @"relevant.xhtml",
        @"repeat.xhtml",
        @"secret.xhtml",
        @"select-from-file.xhtml",
        @"select-model.xhtml",
        @"select-multi-col.xhtml",
        @"select.xhtml",
        @"select1-drop.xhtml",
        @"select1.xhtml",
        @"spreadsheet.xhtml",
        @"switch.xhtml",
        @"textarea-styled.xhtml",
        @"textarea.xhtml",
        @"tinymce.xhtml",
        @"upload.xhtml",
        @"uploads.xhtml",
        @"validation.xhtml",
        @"wikipediasearch.xhtml",
        @"writers.xhtml",
        @"xf.xhtml",
        @"xpath.xhtml"
    ];
}

- (NSURL *)samplesDirectory
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSBundle *bundle = [NSBundle mainBundle];
    NSURL *res = [bundle resourceURL];
    if ([fm fileExistsAtPath:[[res URLByAppendingPathComponent:@"hello.xhtml"] path]]) {
        return res;
    }
    NSURL *inBundle = [res URLByAppendingPathComponent:@"Samples"];
    if ([fm fileExistsAtPath:[[inBundle URLByAppendingPathComponent:@"hello.xhtml"] path]]) {
        return inBundle;
    }
    NSString *exe = [bundle bundlePath];
    NSArray *candidates = @[
        [[exe stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Samples"],
        [[exe stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"../Samples"],
        [[exe stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"../../Samples"],
        [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"Samples"]
    ];
    for (NSString *path in candidates) {
        NSString *resolved = [path stringByStandardizingPath];
        if ([fm fileExistsAtPath:[resolved stringByAppendingPathComponent:@"hello.xhtml"]]) {
            return [NSURL fileURLWithPath:resolved];
        }
    }
    return res;
}

- (BOOL)openFormURL:(NSURL *)url error:(NSError **)error
{
    if (url == nil) {
        return NO;
    }
    NSDocumentController *dc = [NSDocumentController sharedDocumentController];
    for (NSDocument *existing in [dc documents]) {
        if ([[existing fileURL] isEqual:url]) {
            [existing showWindows];
            return YES;
        }
    }

    XFFormDocument *doc = [[XFFormDocument alloc] init];
    if (![doc readFromURL:url ofType:@"xhtml" error:error]) {
        return NO;
    }
    [doc setFileURL:url];
    [doc setFileType:@"xhtml"];
    [dc addDocument:doc];
    [doc makeWindowControllers];
    [doc showWindows];
    return YES;
}

- (void)openSample:(NSMenuItem *)sender
{
    NSString *name = [sender representedObject];
    NSURL *url = [[self samplesDirectory] URLByAppendingPathComponent:name];
    NSError *error = nil;
    if (![self openFormURL:url error:&error]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Could not open sample"];
        [alert setInformativeText:[NSString stringWithFormat:@"%@\n%@",
                                   [url path],
                                   [error localizedDescription] ?: @"No window was created"]];
        [alert runModal];
    }
}

@end

/// Host-registered XPath extension functions (XFXPath
/// registerHostFunctionNamed:) — the native stand-ins for the page
/// JavaScript XSLTForms lets samples define. gantt.xhtml's lastday(): the
/// latest of days-from-date(start[i]) + duration[i] over two comma-joined
/// lists.
static NSInteger XFDaysFromCivil(NSInteger y, NSInteger m, NSInteger d)
{
    // Howard Hinnant's days_from_civil — days since 1970-01-01
    y -= m <= 2;
    NSInteger era = (y >= 0 ? y : y - 399) / 400;
    NSInteger yoe = y - era * 400;
    NSInteger doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    NSInteger doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}

static void XFRegisterSampleFunctions(void)
{
    [XFXPath registerHostFunctionNamed:@"lastday"
                             evaluator:^XFXPathValue *(XFExprContext *ctx,
                                                       NSArray *args,
                                                       NSError **err) {
        (void)ctx;
        (void)err;
        NSArray *starts = [[args.firstObject stringValue] componentsSeparatedByString:@","];
        NSArray *durations = args.count > 1
            ? [[args[1] stringValue] componentsSeparatedByString:@","] : @[];
        double last = 0;
        for (NSUInteger i = 0; i < starts.count && i < durations.count; i++) {
            int y = 0, m = 0, d = 0;
            if (sscanf([starts[i] UTF8String], "%d%*[./-]%d%*[./-]%d", &y, &m, &d) != 3) {
                continue;
            }
            double t = (double)XFDaysFromCivil(y, m, d)
                + [durations[i] doubleValue];
            last = MAX(last, t);
        }
        return [XFXPathValue number:last];
    }];
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
#if defined(GNUSTEP)
        // A crash in the AppImage reports its own backtrace on stderr:
        // gdb cannot be started against the image's libraries.
        XFInstallCrashReporter();
#endif
        [NSApplication sharedApplication];
        XFRegisterSampleFunctions();
        XFViewerApp *app = [[XFViewerApp alloc] init];
        [NSApp setDelegate:(id)app];
#if !defined(GNUSTEP)
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
#endif
        [NSApp activateIgnoringOtherApps:YES];
        return NSApplicationMain(argc, argv);
    }
}
