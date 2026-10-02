/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDInstanceXMLEditor.h"
#import <XFormsKit/XFXMLTypes.h>
#import "XFDXPathField.h"

#pragma mark - Instance XML editor panel

@implementation XFDInstanceXMLEditor {
    NSPanel *_panel;
    NSTextView *_text;
    NSTextField *_statusField;
    NSButton *_okButton;
    NSString *_result;
}

- (void)buildPanelWithTitle:(NSString *)title
{
    const CGFloat W = 560, H = 500;
    _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, W, H)
                                        styleMask:NSTitledWindowMask
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    [_panel setTitle:title];
    NSView *content = [_panel contentView];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 72, W - 24, H - 84)];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];
    _text = [[NSTextView alloc] initWithFrame:
        NSMakeRect(0, 0, [scroll contentSize].width, [scroll contentSize].height)];
    [_text setFont:[NSFont userFixedPitchFontOfSize:11]];
    [_text setRichText:NO];
    [_text setAllowsUndo:YES];
    [_text setVerticallyResizable:YES];
    [_text setHorizontallyResizable:NO];
    [_text setAutoresizingMask:NSViewWidthSizable];
    [[_text textContainer] setWidthTracksTextView:YES];
    [_text setDelegate:(id)self];
    [scroll setDocumentView:_text];
    [content addSubview:scroll];

    _statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 46, W - 24, 17)];
    [_statusField setEditable:NO];
    [_statusField setBordered:NO];
    [_statusField setDrawsBackground:NO];
    [_statusField setFont:[NSFont systemFontOfSize:11]];
    [content addSubview:_statusField];

    NSButton *load = [[NSButton alloc] initWithFrame:NSMakeRect(12, 8, 110, 28)];
    [load setTitle:@"Load File…"];
    [load setBezelStyle:NSRoundedBezelStyle];
    [load setTarget:self];
    [load setAction:@selector(loadClicked:)];
    [content addSubview:load];
    NSButton *blank = [[NSButton alloc] initWithFrame:NSMakeRect(126, 8, 100, 28)];
    [blank setTitle:@"Blankify"];
    [blank setBezelStyle:NSRoundedBezelStyle];
    [blank setToolTip:@"Clear every leaf value and attribute — real data becomes initial data"];
    [blank setTarget:self];
    [blank setAction:@selector(blankifyClicked:)];
    [content addSubview:blank];

    NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(W - 190, 8, 84, 28)];
    [cancel setTitle:@"Cancel"];
    [cancel setBezelStyle:NSRoundedBezelStyle];
    [cancel setTarget:self];
    [cancel setAction:@selector(cancelClicked:)];
    [content addSubview:cancel];
    _okButton = [[NSButton alloc] initWithFrame:NSMakeRect(W - 100, 8, 84, 28)];
    [_okButton setTitle:@"OK"];
    [_okButton setBezelStyle:NSRoundedBezelStyle];
    [_okButton setKeyEquivalent:@"\r"];
    [_okButton setTarget:self];
    [_okButton setAction:@selector(okClicked:)];
    [content addSubview:_okButton];
}

- (XFXMLDocument *)parsedDocument:(NSError **)error
{
    return [[XFXMLDocument alloc] initWithXMLString:[_text string] options:0 error:error];
}

- (void)validateNow
{
    NSError *error = nil;
    XFXMLDocument *doc = [self parsedDocument:&error];
    if (doc != nil) {
        [_statusField setStringValue:@"✓ well-formed"];
        [_statusField setTextColor:[NSColor disabledControlTextColor]];
        [_okButton setEnabled:YES];
    } else {
        [_statusField setStringValue:[@"✗ " stringByAppendingString:
            [error localizedDescription] ?: @"not well-formed XML"]];
        [_statusField setTextColor:[NSColor redColor]];
        [_okButton setEnabled:NO];
    }
}

- (void)textDidChange:(NSNotification *)note
{
    (void)note;
    [self validateNow];
}

/// Clear every leaf element's text and every attribute value, keeping the
/// structure — imported real data becomes the form's default data.
static void XFDBlankify(XFXMLElement *element)
{
    for (XFXMLNode *attribute in [element attributes]) {
        [attribute setStringValue:@""];
    }
    BOOL hasElementChildren = NO;
    for (XFXMLNode *child in [element children]) {
        if ([child kind] == XFXMLElementKind) {
            hasElementChildren = YES;
            XFDBlankify((XFXMLElement *)child);
        }
    }
    if (!hasElementChildren) {
        [element setStringValue:@""];
    }
}

- (void)blankifyClicked:(id)sender
{
    (void)sender;
    NSError *error = nil;
    XFXMLDocument *doc = [self parsedDocument:&error];
    if (doc == nil) {
        XFDBeep();
        return;
    }
    XFDBlankify([doc rootElement]);
    [_text setString:[[doc rootElement] XMLStringWithOptions:XFXMLNodePrettyPrint] ?: @""];
    [self validateNow];
}

- (void)loadClicked:(id)sender
{
    (void)sender;
    NSOpenPanel *open = [NSOpenPanel openPanel];
    if ([open runModal] != NSOKButton) {
        return;
    }
    NSURL *url = [[open URLs] firstObject] ?: [open URL];
    NSString *xml = [NSString stringWithContentsOfURL:url
                                             encoding:NSUTF8StringEncoding
                                                error:NULL]
        ?: [NSString stringWithContentsOfURL:url encoding:NSISOLatin1StringEncoding error:NULL];
    if (xml == nil) {
        XFDBeep();
        return;
    }
    [_text setString:xml];
    [self validateNow];
}

- (void)okClicked:(id)sender
{
    (void)sender;
    _result = [_text string];
    [NSApp stopModal];
    [_panel orderOut:nil];
}

- (void)cancelClicked:(id)sender
{
    (void)sender;
    _result = nil;
    [NSApp abortModal];
    [_panel orderOut:nil];
}

+ (NSString *)runWithXML:(NSString *)xml title:(NSString *)title
{
    XFDInstanceXMLEditor *editor = [[XFDInstanceXMLEditor alloc] init];
    [editor buildPanelWithTitle:title];
    [editor->_text setString:xml.length ? xml : @"<data xmlns=\"\">\n</data>"];
    [editor validateNow];
    [editor->_panel center];
    [NSApp runModalForWindow:editor->_panel];
    return editor->_result;
}

@end

void XFDInstanceXMLEditorFilePresent(void) {}
