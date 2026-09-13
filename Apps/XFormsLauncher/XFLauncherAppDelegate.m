//
// XFLauncherAppDelegate.m
//

#import "XFLauncherAppDelegate.h"

@interface XFLauncherAppDelegate ()
@property (nonatomic, strong) NSWindow *window;
@end

@implementation XFLauncherAppDelegate

/// Executable name, button title, one line of explanation.
- (NSArray<NSArray<NSString *> *> *)apps
{
    return @[
        @[ @"XFormsViewer",   @"Form Viewer",
           @"Open an XHTML+XForms document and fill it in." ],
        @[ @"XFormsDesigner", @"Form Designer",
           @"Build and edit forms: outline, palette, inspectors." ],
    ];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    (void)note;
    [self installMenus];

    NSArray<NSArray<NSString *> *> *apps = [self apps];
    CGFloat width = 380, rowHeight = 64, pad = 16;
    NSRect frame = NSMakeRect(0, 0, width,
                              pad * 2 + rowHeight * (CGFloat)apps.count);
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:NSTitledWindowMask | NSClosableWindowMask
                            | NSMiniaturizableWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:@"XFormsKit"];
    NSView *content = [window contentView];

    CGFloat y = NSMaxY(frame) - pad - rowHeight;
    for (NSUInteger i = 0; i < apps.count; i++) {
        NSButton *button = [[NSButton alloc]
            initWithFrame:NSMakeRect(pad, y + 26, width - pad * 2, 32)];
        [button setTitle:apps[i][1]];
        [button setBezelStyle:NSRoundedBezelStyle];
        [button setTag:(NSInteger)i];
        [button setTarget:self];
        [button setAction:@selector(launch:)];
        [content addSubview:button];

        NSTextField *note = [[NSTextField alloc]
            initWithFrame:NSMakeRect(pad, y + 4, width - pad * 2, 18)];
        [note setStringValue:apps[i][2]];
        [note setBezeled:NO];
        [note setDrawsBackground:NO];
        [note setEditable:NO];
        [note setSelectable:NO];
        [note setFont:[NSFont systemFontOfSize:10]];
        [note setTextColor:[NSColor darkGrayColor]];
        [content addSubview:note];

        y -= rowHeight;
    }

    [window center];
    [window makeKeyAndOrderFront:nil];
    self.window = window;
}

- (void)installMenus
{
    NSMenu *menubar = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"XFormsKit"
                                                     action:NULL
                                              keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"XFormsKit"];
    [appMenu addItemWithTitle:@"About XFormsKit"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];
    [menubar addItem:appItem];
    [NSApp setMainMenu:menubar];
}

/// The chosen app's executable, looked for beside this one.
///
/// Inside the image both live in the same Applications directory, which is
/// where a GNUstep application bundle's parent is; GNUSTEP_LOCAL_APPS covers
/// an installed tree where they do not sit together.
- (nullable NSString *)executablePathForApp:(NSString *)app
{
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *siblings = [[[NSBundle mainBundle] bundlePath]
                             stringByDeletingLastPathComponent];
    NSMutableArray<NSString *> *roots = [NSMutableArray arrayWithObject:siblings];
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    for (NSString *key in @[ @"GNUSTEP_LOCAL_APPS", @"GNUSTEP_SYSTEM_APPS" ]) {
        NSString *root = environment[key];
        if (root.length) {
            [roots addObject:root];
        }
    }
    for (NSString *root in roots) {
        NSString *path = [root stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"%@.app/%@", app, app]];
        if ([files isExecutableFileAtPath:path]) {
            return path;
        }
    }
    return nil;
}

- (void)launch:(NSButton *)sender
{
    NSArray<NSArray<NSString *> *> *apps = [self apps];
    if (sender.tag < 0 || (NSUInteger)sender.tag >= apps.count) {
        return;
    }
    NSString *app = apps[(NSUInteger)sender.tag][0];
    NSString *executable = [self executablePathForApp:app];
    if (executable == nil) {
        [self report:@"Application not found"
              detail:[NSString stringWithFormat:
                         @"Could not find %@ beside this launcher.", app]];
        return;
    }

    // Fire and forget: the launcher is not the app's parent in any meaningful
    // sense, and closing it must not take the app with it.
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:executable];
    @try {
        [task launch];
    } @catch (NSException *problem) {
        [self report:@"Could not start the application"
              detail:[NSString stringWithFormat:@"%@: %@", app, [problem reason]]];
    }
}

- (void)report:(NSString *)message detail:(NSString *)detail
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:message];
    [alert setInformativeText:detail];
    [alert runModal];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

@end
