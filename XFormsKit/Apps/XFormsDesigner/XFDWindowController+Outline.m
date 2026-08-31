/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* The left pane: host-document outline (elements only), selection,
   instance-data editing entry points, and the +/â palette insert /
   delete â XFHostEdit's insertion zones are the single validity
   authority. */
#import "XFDWindowControllerPriv.h"
#import "XFDDocument.h"
#import "XFDInspectorSpecs.h"
#import "XFDPalettePanel.h"
#import "XFDInstanceXMLEditor.h"

@implementation XFDWindowController (XFDOutline)

#pragma mark - Outline (host document)

- (NSXMLElement *)rootElement
{
    return [[self processor].hostDocument rootElement];
}

- (NSArray *)elementChildrenOf:(NSXMLElement *)element
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSXMLNode *c in [element children]) {
        if ([c kind] == NSXMLElementKind) {
            [out addObject:c];
        }
    }
    return out;
}

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item
{
    (void)ov;
    if (item == nil) {
        return [self rootElement] ? 1 : 0;
    }
    return (NSInteger)[self elementChildrenOf:item].count;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(id)item
{
    (void)ov;
    if (item == nil) {
        return [self rootElement];
    }
    return [self elementChildrenOf:item][(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item
{
    (void)ov;
    return [self elementChildrenOf:item].count > 0;
}

- (id)outlineView:(NSOutlineView *)ov objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
    (void)ov;
    (void)column;
    NSXMLElement *e = item;
    NSString *name = [e name] ?: [e localName] ?: @"?";
    NSString *detail = nil;
    XFHostEdit *edit = [self formDocument].hostEdit;
    NSString *labelText = [edit supportChildText:@"label" onElement:e];
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
    if (self.updating) {
        return;
    }
    NSInteger row = [self.outline selectedRow];
    self.selected = row >= 0 ? [self.outline itemAtRow:row] : nil;
    [self showInspectorForSelection];
    [self.designOverlay setNeedsDisplay:YES];
}

- (void)reloadOutlineKeepingSelection:(NSXMLElement *)keep
{
    self.updating = YES;
    [self.outline reloadData];
    // the always-open levels
    NSXMLElement *root = [self rootElement];
    [self.outline expandItem:root];
    for (NSXMLElement *top in [self elementChildrenOf:root]) {
        [self.outline expandItem:top];
        for (NSXMLElement *second in [self elementChildrenOf:top]) {
            if ([[second localName] isEqualToString:@"model"]) {
                [self.outline expandItem:second];
            }
        }
    }
    if (keep) {
        // expand the ancestors, then reselect by identity
        NSMutableArray *chain = [NSMutableArray array];
        NSXMLNode *walk = [keep parent];
        while (walk && [walk kind] == NSXMLElementKind) {
            [chain insertObject:walk atIndex:0];
            walk = [walk parent];
        }
        for (id ancestor in chain) {
            [self.outline expandItem:ancestor];
        }
        NSInteger row = [self.outline rowForItem:keep];
        if (row >= 0) {
            [self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                      byExtendingSelection:NO];
        }
    }
    self.updating = NO;
    self.selected = keep;
}

- (void)selectElement:(NSXMLElement *)element
{
    [self reloadOutlineKeepingSelection:element];
    [self showInspectorForSelection];
    [self.designOverlay setNeedsDisplay:YES];
}

#pragma mark - Instance data editing

/// The xf:instance the selection lives in (the selection itself, or an
/// instance-data ancestor). nil when the selection has nothing to do with
/// an instance.
- (NSXMLElement *)instanceElementForSelection:(NSXMLElement *)element
{
    for (NSXMLNode *walk = element; walk != nil; walk = [walk parent]) {
        if ([walk kind] == NSXMLElementKind
            && [XFXML element:(NSXMLElement *)walk hasLocalName:@"instance"
                 namespaceURI:XFXFormsNamespaceURI]) {
            return (NSXMLElement *)walk;
        }
    }
    return nil;
}

- (IBAction)editInstanceXML:(id)sender
{
    (void)sender;
    NSXMLElement *instance = [self instanceElementForSelection:self.selected];
    if (instance == nil) {
        XFDBeep();
        return;
    }
    XFHostEdit *edit = [self formDocument].hostEdit;
    NSString *xml = [XFDInstanceXMLEditor
        runWithXML:[edit contentXMLOfElement:instance]
             title:[NSString stringWithFormat:@"Instance data — %@",
                    [[instance attributeForName:@"id"] stringValue] ?: @"instance"]];
    if (xml == nil) {
        return;
    }
    NSError *error = nil;
    if (![edit setContentXML:xml onElement:instance error:&error]) {
        [self presentError:error];
        return;
    }
    [self selectElement:instance];
}

- (void)outlineDoubleClicked:(id)sender
{
    NSInteger row = [self.outline clickedRow];
    NSXMLElement *element = row >= 0 ? [self.outline itemAtRow:row] : nil;
    if ([self instanceElementForSelection:element] != nil) {
        [self editInstanceXML:sender];
        return;
    }
    // otherwise a double-click toggles expansion
    if (element != nil && [self outlineView:self.outline isItemExpandable:element]) {
        if ([self.outline isItemExpanded:element]) {
            [self.outline collapseItem:element];
        } else {
            [self.outline expandItem:element];
        }
    }
}

#pragma mark - Palette

/// Shared by the palette panel and the Form menu.
- (void)insertPaletteName:(NSString *)name
{
    NSInteger index = -1;
    NSXMLElement *parent = [self insertParentForName:name index:&index];
    if (parent == nil) {
        XFDBeep();
        return;
    }
    NSError *error = nil;
    NSXMLElement *element = [[self formDocument].hostEdit insertElementNamed:name
                                                                underParent:parent
                                                                    atIndex:index
                                                                      error:&error];
    if (element == nil) {
        [self presentError:error ?: [NSError errorWithDomain:@"XFormsDesigner" code:2 userInfo:@{
            NSLocalizedDescriptionKey: @"Cannot insert here." }]];
        return;
    }
    [self selectElement:element];
}

#pragma mark - Palette (+ / −)

- (IBAction)plusMinusClicked:(NSSegmentedControl *)sender
{
    if ([sender selectedSegment] == 0) {
        [self insertElement:sender];
    } else {
        [self deleteElement:sender];
    }
}

- (NSXMLElement *)insertStartParent
{
    if (self.selected != nil) {
        return self.selected;
    }
    NSXMLElement *body = nil;
    for (NSXMLElement *top in [self elementChildrenOf:[self rootElement]]) {
        if ([[top localName] isEqualToString:@"body"]) {
            body = top;
        }
    }
    return body;
}

/// Where a palette insert would go: the selection itself when it can
/// contain children, else the nearest ancestor that can — inserting AFTER
/// the selection there (so "+ with an input selected" adds a sibling,
/// like Xcode's outline). No selection targets the body.
- (NSXMLElement *)insertParentForSelection:(NSInteger *)indexOut
{
    NSXMLElement *parent = [self insertStartParent];
    NSXMLElement *child = nil;
    while (parent != nil && [XFHostEdit insertableNamesUnderParent:parent].count == 0) {
        child = parent;
        NSXMLNode *up = [child parent];
        parent = (up != nil && [up kind] == NSXMLElementKind) ? (NSXMLElement *)up : nil;
    }
    if (indexOut) {
        *indexOut = (parent != nil && child != nil) ? (NSInteger)[child index] + 1 : -1;
    }
    return parent;
}

/// The parent that would receive `name` specifically — different depths
/// accept different sets now that actions nest inside controls: with an
/// input selected, setvalue goes INTO the input while another input lands
/// as its SIBLING in the container above. Nearest accepting ancestor
/// wins; nil when nothing on the chain takes the name.
- (NSXMLElement *)insertParentForName:(NSString *)name index:(NSInteger *)indexOut
{
    NSXMLElement *parent = [self insertStartParent];
    NSXMLElement *child = nil;
    while (parent != nil && ![XFHostEdit canInsertElementNamed:name underParent:parent]) {
        child = parent;
        NSXMLNode *up = [child parent];
        parent = (up != nil && [up kind] == NSXMLElementKind) ? (NSXMLElement *)up : nil;
    }
    if (indexOut) {
        *indexOut = (parent != nil && child != nil) ? (NSInteger)[child index] + 1 : -1;
    }
    return parent;
}

/// Every name insertable SOMEWHERE on the selection's ancestor chain —
/// what the palette panel offers (each name resolves its own depth on
/// insert).
- (NSSet *)insertableNamesForSelection
{
    NSMutableSet *names = [NSMutableSet set];
    NSXMLElement *parent = [self insertStartParent];
    while (parent != nil) {
        [names addObjectsFromArray:[XFHostEdit insertableNamesUnderParent:parent]];
        NSXMLNode *up = [parent parent];
        parent = (up != nil && [up kind] == NSXMLElementKind) ? (NSXMLElement *)up : nil;
    }
    return names;
}

- (IBAction)insertElement:(id)sender
{
    (void)sender;
    NSSet *valid = [self insertableNamesForSelection];
    if (valid.count == 0) {
        XFDBeep();
        return;
    }
    NSXMLElement *start = [self insertStartParent];
    NSString *name = [XFDPalettePanel
        runWithValidNames:valid
               parentName:[start name] ?: @"element"];
    if (name != nil) {
        [self insertPaletteName:name];
    }
}

- (IBAction)deleteElement:(id)sender
{
    (void)sender;
    NSXMLElement *element = self.selected;
    if (element == nil) {
        XFDBeep();
        return;
    }
    NSString *local = [element localName];
    BOOL structural = [local isEqualToString:@"html"] || [local isEqualToString:@"head"]
        || [local isEqualToString:@"body"] || [local isEqualToString:@"model"];
    if (structural || [element parent] == nil) {
        XFDBeep();
        return;
    }
    NSXMLElement *parent = (NSXMLElement *)[element parent];
    [[self formDocument].hostEdit deleteElement:element];
    [self selectElement:parent];
}

@end

void XFDWindowControllerOutlineFilePresent(void) {}
