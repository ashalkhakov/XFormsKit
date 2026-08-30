#import <AppKit/AppKit.h>
#import "XFFormDocument.h"

@interface XFViewerApp : NSObject
@end

@implementation XFViewerApp

- (void)applicationWillFinishLaunching:(NSNotification *)note
{
    NSDocumentController *dc = [NSDocumentController sharedDocumentController];
    (void)dc;
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
    [fileMenu addItemWithTitle:@"Close"
                        action:@selector(performClose:)
                 keyEquivalent:@"w"];
    [fileItem setSubmenu:fileMenu];
    [menubar addItem:fileItem];

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
    return @[
        @"hello.xhtml",
        @"address.xhtml",
        @"bind.xhtml",
        @"button.xhtml",
        @"checkbox.xhtml",
        @"date.xhtml",
        @"range.xhtml",
        @"readonly.xhtml",
        @"relevant.xhtml",
        @"repeat.xhtml",
        @"secret.xhtml",
        @"select1.xhtml",
        @"switch.xhtml",
        @"textarea.xhtml"
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

- (void)openSample:(NSMenuItem *)sender
{
    NSString *name = [sender representedObject];
    NSURL *url = [[self samplesDirectory] URLByAppendingPathComponent:name];
    NSError *error = nil;
    id doc = [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url
                                                                                    display:YES
                                                                                      error:&error];
    if (doc == nil) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Could not open sample"];
        [alert setInformativeText:[NSString stringWithFormat:@"%@\n%@",
                                   [url path],
                                   [error localizedDescription] ?: @""]];
        [alert runModal];
    }
}

@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        XFViewerApp *app = [[XFViewerApp alloc] init];
        [NSApp setDelegate:(id)app];
        if ([NSApp respondsToSelector:@selector(setActivationPolicy:)]) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        }
        [NSApp activateIgnoringOtherApps:YES];
        return NSApplicationMain(argc, argv);
    }
}
