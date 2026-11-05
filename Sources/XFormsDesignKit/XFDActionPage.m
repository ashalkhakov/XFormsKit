/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDActionPage.h"
#import "XFDPartViewController.h"
#import "XFDEditors.h"

@implementation XFDActionRowTemplate
@end

static XFDXPathExpectation XFDExpectationNamed(NSString *name)
{
    if ([name isEqualToString:@"nodeset"]) {
        return XFDXPathExpectNodeSet;
    }
    if ([name isEqualToString:@"node"]) {
        return XFDXPathExpectNode;
    }
    return [name isEqualToString:@"value"] ? XFDXPathExpectValue : XFDXPathExpectAny;
}

@implementation XFDActionPage {
    XFXMLElement *_element;
}

@synthesize rows = _rows;

/// Held by the perform request until the run loop turns; see below.
- (void)releaseRetiredRows:(NSArray *)retired
{
    (void)retired;
}

- (void)editorDidChange
{
    XFDActionEditor *editor = [self.editor isKindOfClass:[XFDActionEditor class]]
        ? (XFDActionEditor *)self.editor : nil;
    if (_element == editor.element && _rows != nil) {
        return;
    }
    // The old rows leave the page now but stay alive until the event is
    // over: a rebuild can run from inside a row's own action, and AppKit
    // goes on using the sender after the action returns (a button's
    // -[NSControl mouseDown:] still has its cell to finish with; GNUstep's
    // -[NSTextField textDidEndEditing:] asks its window for the first
    // responder). The form view retires its widgets the same way.
    NSView *host = self.actionRowsHost;
    NSArray *retired = [[host subviews] copy];
    for (NSView *sub in retired) {
        for (NSView *field in [sub subviews]) {
            [field unbind:NSValueBinding];
            [field unbind:NSSelectedValueBinding];
        }
        [sub removeFromSuperview];
    }
    if (retired.count) {
        [self performSelector:@selector(releaseRetiredRows:) withObject:retired afterDelay:0];
    }
    _element = editor.element;
    _rows = editor ? [self makeRowsFor:editor] : @[];
}

/// A row of `kind` from the XIB, its label and field.
- (NSView *)rowOfKind:(NSString *)kind label:(NSTextField **)label field:(NSView **)field
{
    XFDActionRowTemplate *row = [[XFDActionRowTemplate alloc] init];
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"XFDActionRow"
                                          bundle:[XFDPartViewController designKitBundle]];
    NSArray *objects = nil;
    if (![nib instantiateWithOwner:row topLevelObjects:&objects]) {
        NSLog(@"XFormsDesignKit: XFDActionRow did not load");
        return nil;
    }
    NSString *name = [@[ @"xpath", @"idref", @"content", @"popup" ] containsObject:kind] ? kind : @"field";
    *label = [row valueForKey:[name stringByAppendingString:@"Label"]];
    *field = [row valueForKey:[name stringByAppendingString:@"Field"]];
    return [row valueForKey:[name stringByAppendingString:@"Row"]];
}

/// The rows laid out from the top, each bound to its key.
- (NSArray *)makeRowsFor:(XFDActionEditor *)editor
{
    NSMutableArray *rows = [NSMutableArray array];
    NSView *host = self.actionRowsHost;
    CGFloat top = NSHeight([host bounds]);
    NSDictionary *validated = @{ NSValidatesImmediatelyBindingOption: @YES };
    for (NSDictionary *spec in editor.rows) {
        NSString *kind = spec[@"kind"];
        NSTextField *label = nil;
        NSView *field = nil;
        NSView *row = [self rowOfKind:kind label:&label field:&field];
        if (row == nil) {
            continue;
        }
        [label setStringValue:spec[@"label"] ?: @""];
        if (spec[@"tip"] != nil) {
            [field setToolTip:spec[@"tip"]];
        }
        NSString *keyPath = [@"content.attributes." stringByAppendingString:spec[@"attr"] ?: @""];
        if ([kind isEqualToString:@"xpath"]) {
            ((XFDXPathField *)field).expectation = XFDExpectationNamed(spec[@"expect"]);
            ((XFDXPathField *)field).provider = self;
        } else if ([kind isEqualToString:@"idref"]) {
            ((XFDIDRefField *)field).kind = spec[@"idkind"];
            ((XFDIDRefField *)field).provider = self;
        } else if ([kind isEqualToString:@"content"]) {
            ((XFDRichTextField *)field).provider = self;
            keyPath = @"content.inlineContent";
        }
        if ([kind isEqualToString:@"popup"]) {
            [(NSPopUpButton *)field removeAllItems];
            [(NSPopUpButton *)field addItemsWithTitles:spec[@"options"]];
            [field bind:NSSelectedValueBinding toObject:self.editorController withKeyPath:keyPath options:nil];
        } else {
            [field bind:NSValueBinding toObject:self.editorController withKeyPath:keyPath options:validated];
        }
        NSRect frame = [row frame];
        frame.origin = NSMakePoint(0, top - NSHeight(frame));
        frame.size.width = NSWidth([host bounds]);
        [row setFrame:frame];
        [host addSubview:row];
        top -= NSHeight(frame);
        [rows addObject:@{ @"attr": spec[@"attr"] ?: @"", @"kind": kind, @"view": field }];
    }
    return rows;
}

@end
