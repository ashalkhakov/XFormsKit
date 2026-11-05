/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDOutlineViewController.h"
#import <XFormsKit/XFXMLTypes.h>
#import "XFDInspectorSpecs.h"
#import "XFDPalettePanel.h"
#import "XFDInstanceXMLEditor.h"
#import "XFDXPathField.h"

@implementation XFDOutlineViewController {
    /// The outline being filled: its selection changes are its own.
    BOOL _reloading;
}

- (void)viewDidLoadFromNib
{
    [self.outline setTarget:self];
    [self.outline setDoubleAction:@selector(outlineDoubleClicked:)];
    [self reloadKeepingSelection];
}

#pragma mark The form editor's news

- (void)formEditorSelectionDidChange:(XFDFormEditor *)editor
{
    (void)editor;
    [self reloadKeepingSelection];
}

- (void)formEditor:(XFDFormEditor *)editor hostDidChange:(XFXMLElement *)element
{
    (void)editor;
    (void)element;
    [self reloadKeepingSelection];
}

- (void)formEditorProcessorWasReplaced:(XFDFormEditor *)editor
{
    (void)editor;
    [self reloadKeepingSelection];
}

#pragma mark The tree

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item
{
    (void)ov;
    if (item == nil) {
        return [self.formEditor rootElement] ? 1 : 0;
    }
    return (NSInteger)[self.formEditor elementChildrenOf:item].count;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(id)item
{
    (void)ov;
    if (item == nil) {
        return [self.formEditor rootElement];
    }
    return [self.formEditor elementChildrenOf:item][(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item
{
    (void)ov;
    return [self.formEditor elementChildrenOf:item].count > 0;
}

- (NSString *)titleOfElement:(XFXMLElement *)e
{
    NSString *name = [e name] ?: [e localName] ?: @"?";
    NSString *detail = nil;
    NSString *labelText = [self.formEditor.hostEdit supportChildText:@"label" onElement:e];
    if (labelText.length) {
        detail = [NSString stringWithFormat:@"‘%@’", labelText];
    } else {
        NSString *ref = [[e attributeForName:@"ref"] stringValue]
            ?: [[e attributeForName:@"nodeset"] stringValue];
        if (ref.length) {
            detail = ref;
        } else {
            NSString *identifier = [[e attributeForName:@"id"] stringValue];
            if (identifier.length) {
                detail = [@"#" stringByAppendingString:identifier];
            }
        }
    }
    NSString *title = detail.length ? [NSString stringWithFormat:@"%@  %@", name, detail] : name;
    if (XFDElementIsUnbound(e)) {
        title = [title stringByAppendingString:@"  · unbound"];
    }
    return title;
}

- (id)outlineView:(NSOutlineView *)ov objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
    (void)ov;
    (void)column;
    return [self titleOfElement:item];
}

- (BOOL)outlineView:(NSOutlineView *)ov shouldEditTableColumn:(NSTableColumn *)column item:(id)item
{
    (void)ov;
    (void)column;
    (void)item;
    return NO;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)note
{
    (void)note;
    if (_reloading) {
        return;
    }
    NSInteger row = [self.outline selectedRow];
    self.formEditor.selection = row >= 0 ? [self.outline itemAtRow:row] : nil;
}

/// The tree read again, the levels that are always open opened, and the
/// form editor's selection shown (its ancestors opened).
- (void)reloadKeepingSelection
{
    if (self.outline == nil) {
        return;
    }
    _reloading = YES;
    [self.outline reloadData];
    XFXMLElement *root = [self.formEditor rootElement];
    if (root != nil) {
        [self.outline expandItem:root];
        for (XFXMLElement *top in [self.formEditor elementChildrenOf:root]) {
            [self.outline expandItem:top];
            for (XFXMLElement *second in [self.formEditor elementChildrenOf:top]) {
                if ([[second localName] isEqualToString:@"model"]) {
                    [self.outline expandItem:second];
                }
            }
        }
    }
    XFXMLElement *keep = self.formEditor.selection;
    if (keep != nil) {
        NSMutableArray *chain = [NSMutableArray array];
        for (XFXMLNode *walk = [keep parent]; walk != nil && [walk kind] == XFXMLElementKind;
             walk = [walk parent]) {
            [chain insertObject:walk atIndex:0];
        }
        for (id ancestor in chain) {
            [self.outline expandItem:ancestor];
        }
    }
    NSInteger row = keep != nil ? [self.outline rowForItem:keep] : -1;
    if (row >= 0) {
        [self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                  byExtendingSelection:NO];
    } else {
        [self.outline deselectAll:nil];
    }
    _reloading = NO;
}

#pragma mark Instance data

- (IBAction)editInstanceXML:(id)sender
{
    (void)sender;
    NSError *error = nil;
    if (![XFDInstanceXMLEditor editInstanceOfElement:self.formEditor.selection
                                        inFormEditor:self.formEditor error:&error]
        && error != nil) {
        [self presentError:error];
    }
}

- (void)outlineDoubleClicked:(id)sender
{
    NSInteger row = [self.outline clickedRow];
    XFXMLElement *element = row >= 0 ? [self.outline itemAtRow:row] : nil;
    if ([self.formEditor instanceElementOf:element] != nil) {
        [self editInstanceXML:sender];
        return;
    }
    // otherwise a double click opens or closes the row
    if (element != nil && [self outlineView:self.outline isItemExpandable:element]) {
        if ([self.outline isItemExpanded:element]) {
            [self.outline collapseItem:element];
        } else {
            [self.outline expandItem:element];
        }
    }
}

#pragma mark + and −

- (IBAction)plusMinusClicked:(id)sender
{
    if ([sender selectedSegment] == 0) {
        [self insertElement:sender];
    } else {
        [self deleteElement:sender];
    }
}

- (IBAction)insertElement:(id)sender
{
    (void)sender;
    NSSet *valid = [self.formEditor insertableNamesForSelection];
    if (valid.count == 0) {
        XFDBeep();
        return;
    }
    XFXMLElement *start = self.formEditor.selection ?: [self.formEditor bodyElement];
    NSString *name = [XFDPalettePanel runWithValidNames:valid parentName:[start name] ?: @"element"];
    if (name == nil) {
        return;
    }
    NSError *error = nil;
    if ([self.formEditor insertElementNamed:name error:&error] == nil) {
        [self presentError:error];
    }
}

- (IBAction)deleteElement:(id)sender
{
    (void)sender;
    if (![self.formEditor deleteSelection]) {
        XFDBeep();
    }
}

@end
