/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDInstanceXMLEditor.h"
#import <XFormsKit/XFXMLTypes.h>
#import "XFDXPathField.h"

#pragma mark - Instance XML editor panel

@interface XFDInstanceXMLEditor ()
@property (nonatomic, strong) IBOutlet NSPanel *panel;
@property (nonatomic, strong) IBOutlet NSTextView *text;
@property (nonatomic, strong) IBOutlet NSTextField *statusField;
@property (nonatomic, strong) IBOutlet NSButton *okButton;
@end

@implementation XFDInstanceXMLEditor {
    NSArray *_topLevelObjects;
    NSString *_result;
}

/// The panel from its XIB (XFDInstanceXMLEditor.xib).
- (BOOL)loadPanelWithTitle:(NSString *)title
{
    NSArray *objects = nil;
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"XFDInstanceXMLEditor"
                                          bundle:[NSBundle bundleForClass:[XFDInstanceXMLEditor class]]];
    if (![nib instantiateWithOwner:self topLevelObjects:&objects] || _panel == nil) {
        NSLog(@"XFormsDesignKit: XFDInstanceXMLEditor did not load");
        return NO;
    }
    _topLevelObjects = objects;
    [_panel setTitle:title];
    [_text setFont:[NSFont userFixedPitchFontOfSize:11]];
    [[_text textContainer] setWidthTracksTextView:YES];
    return YES;
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

- (IBAction)blankifyClicked:(id)sender
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

- (IBAction)loadClicked:(id)sender
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

- (IBAction)okClicked:(id)sender
{
    (void)sender;
    _result = [_text string];
    [NSApp stopModal];
    [_panel orderOut:nil];
}

- (IBAction)cancelClicked:(id)sender
{
    (void)sender;
    _result = nil;
    [NSApp abortModal];
    [_panel orderOut:nil];
}

+ (NSString *)runWithXML:(NSString *)xml title:(NSString *)title
{
    XFDInstanceXMLEditor *editor = [[XFDInstanceXMLEditor alloc] init];
    if (![editor loadPanelWithTitle:title]) {
        return nil;
    }
    [editor->_text setString:xml.length ? xml : @"<data xmlns=\"\">\n</data>"];
    [editor validateNow];
    [editor->_panel center];
    [NSApp runModalForWindow:editor->_panel];
    return editor->_result;
}

+ (BOOL)editInstanceOfElement:(XFXMLElement *)element
                 inFormEditor:(XFDFormEditor *)formEditor
                        error:(NSError **)error
{
    XFXMLElement *instance = [formEditor instanceElementOf:element];
    if (instance == nil) {
        XFDBeep();
        return NO;
    }
    XFHostEdit *edit = formEditor.hostEdit;
    NSString *xml = [self runWithXML:[edit contentXMLOfElement:instance]
                               title:[NSString stringWithFormat:@"Instance data — %@",
                                      [[instance attributeForName:@"id"] stringValue] ?: @"instance"]];
    if (xml == nil) {
        return NO;
    }
    if (![edit setContentXML:xml onElement:instance error:error]) {
        return NO;
    }
    formEditor.selection = instance;
    return YES;
}

@end
