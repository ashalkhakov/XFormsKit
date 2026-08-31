/* XFormsDesigner — document-based XHTML+XForms form designer.
   The runner is XFormsViewer; this app edits the host XML through
   XFormsKit's XFHostEdit command layer, with the processor kept alive as
   a rebuildable projection for the live preview.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>
#import "XFDDocument.h"
#import "XFDRichTextField.h"
#import "XFDIDRefField.h"
#import "XFDXPathField.h"
#import "XFDDesignOverlay.h"

static BOOL XFDLoadNib(NSString *name, id owner)
{
#if defined(__APPLE__)
    NSArray *top = nil;
    return [[NSBundle mainBundle] loadNibNamed:name owner:owner topLevelObjects:&top];
#else
    return [NSBundle loadNibNamed:name owner:owner];
#endif
}

/* XFD_SELFTEST=<form path>: open the document, load the window nib, run a
   scripted edit pass and exit — the headless smoke test both platforms can
   run (`XFD_SELFTEST=... ./XFormsDesigner`). */
static int XFDRunSelfTest(NSString *path)
{
    NSError *error = nil;
    XFDDocument *doc = [[XFDDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]
                                                           ofType:@"XHTML+XForms"
                                                            error:&error];
    if (doc == nil) {
        NSLog(@"SELFTEST open failed: %@", error);
        return 1;
    }
    [doc makeWindowControllers];
    NSWindowController *wc = [[doc windowControllers] firstObject];
    if ([wc window] == nil) {   // triggers the nib load
        NSLog(@"SELFTEST window/nib failed");
        return 1;
    }
    for (NSString *outlet in @[ @"outline", @"centerTabView", @"inspectorTabView",
                                @"inspectorTabBar", @"previewHost", @"sourceHost",
                                @"designModeCheckbox",
                                @"controlRefField", @"controlValueField",
                                @"bindNodesetField",
                                @"identityIdField", @"inspectorKindTabView",
                                @"controlBindField", @"controlBindingStatusField",
                                @"controlModelField", @"controlSubmissionField",
                                @"submissionInstanceField", @"submissionBindField" ]) {
        if ([wc valueForKey:outlet] == nil) {
            NSLog(@"SELFTEST outlet not wired: %@", outlet);
            return 1;
        }
    }
    // instances loaded from a relative @src that exists next to the
    // document must carry data — the base URL rides into construction
    // (the select-from-file regression)
    for (XFModel *model in doc.processor.models) {
        for (XFInstance *inst in model.instances) {
            NSString *src = [[inst.element attributeForName:@"src"] stringValue];
            if (src.length == 0 || [src containsString:@":"]) {
                continue;   // absolute or none
            }
            NSString *local = [[[path stringByDeletingLastPathComponent]
                stringByAppendingPathComponent:src] stringByStandardizingPath];
            if (![[NSFileManager defaultManager] fileExistsAtPath:local]) {
                continue;
            }
            if ([[inst.document rootElement] childCount] == 0
                && [[inst.document rootElement] attributes].count == 0) {
                NSLog(@"SELFTEST relative src '%@' produced an empty instance", src);
                return 1;
            }
        }
    }
    NSOutlineView *outline = [wc valueForKey:@"outline"];
    if ([outline numberOfRows] < 4) {
        NSLog(@"SELFTEST outline shows %ld rows", (long)[outline numberOfRows]);
        return 1;
    }
    NSXMLElement *body = nil;
    for (NSXMLNode *c in [[doc.processor.hostDocument rootElement] children]) {
        if ([c kind] == NSXMLElementKind && [[(NSXMLElement *)c localName] isEqualToString:@"body"]) {
            body = (NSXMLElement *)c;
        }
    }
    NSUInteger before = doc.processor.controls.count;
    NSUndoManager *undo = [doc undoManager];
    [undo beginUndoGrouping];
    NSXMLElement *input = [doc.hostEdit insertElementNamed:@"input" underParent:body atIndex:-1 error:&error];
    [undo endUndoGrouping];
    if (input == nil || doc.processor.controls.count != before + 1) {
        NSLog(@"SELFTEST insert failed: %@", error);
        return 1;
    }
    [undo beginUndoGrouping];
    [doc.hostEdit setAttribute:@"ref" value:@"name" onElement:input];
    [undo endUndoGrouping];
    NSString *saved = [doc hostXMLString];
    if (![saved containsString:@"ref=\"name\""]) {
        NSLog(@"SELFTEST save missing edit");
        return 1;
    }
    // inspector round trip: select the new input, the fill pass must show
    // its ref; an applied label must land in the host XML
    [wc performSelector:@selector(selectElement:) withObject:input];
    id refField = [wc valueForKey:@"controlRefField"];
    if (![[refField stringValue] isEqualToString:@"name"]) {
        NSLog(@"SELFTEST inspector fill shows '%@'", [refField stringValue]);
        return 1;
    }
    id labelField = [wc valueForKey:@"controlLabelField"];
    [labelField setStringValue:@"Your name"];
    [undo beginUndoGrouping];
    [wc performSelector:@selector(inspectorChanged:) withObject:labelField];
    [undo endUndoGrouping];
    if (![[doc.hostEdit supportChildText:@"label" onElement:input] isEqualToString:@"Your name"]) {
        NSLog(@"SELFTEST inspector apply failed");
        return 1;
    }
    // rich label content (XForms 1.1 inline markup + xf:output): the XML
    // command stores it, the fill pass flags the field rich and shows the
    // flattened text, and a later apply pass must NOT flatten the markup
    [undo beginUndoGrouping];
    if (![doc.hostEdit setSupportChild:@"label"
                            contentXML:@"Nom <strong>complet</strong> <xf:output value=\"'x'\"/>"
                             onElement:input error:&error]) {
        NSLog(@"SELFTEST rich label set failed: %@", error);
        return 1;
    }
    [undo endUndoGrouping];
    [wc performSelector:@selector(selectElement:) withObject:input];
    if (![[labelField valueForKey:@"rich"] boolValue]) {
        NSLog(@"SELFTEST rich label not flagged rich");
        return 1;
    }
    if (![[labelField stringValue] containsString:@"Nom complet"]) {
        NSLog(@"SELFTEST rich label summary shows '%@'", [labelField stringValue]);
        return 1;
    }
    [undo beginUndoGrouping];
    [wc performSelector:@selector(inspectorChanged:) withObject:labelField];
    [undo endUndoGrouping];
    if (![[doc.hostEdit supportChildXML:@"label" onElement:input]
             containsString:@"<strong>complet</strong>"]) {
        NSLog(@"SELFTEST apply pass flattened the rich label");
        return 1;
    }
    [undo beginUndoGrouping];
    [doc.hostEdit setSupportChild:@"label" text:@"Your name" onElement:input];
    [undo endUndoGrouping];
    [wc performSelector:@selector(selectElement:) withObject:input];
    if ([[labelField valueForKey:@"rich"] boolValue]) {
        NSLog(@"SELFTEST plain label still flagged rich");
        return 1;
    }
    // output token transforms: xf:output value= rides the rich view as a
    // ⟦expr⟧ token and comes back as the same element
    NSString *frag = @"Total: <strong>sum</strong> <xf:output value=\"../price\"/>";
    NSString *tokenized = XFDTokenizeFragment(frag);
    if (![tokenized containsString:@"⟦../price⟧"]
        || [tokenized containsString:@"output"]) {
        NSLog(@"SELFTEST tokenize gave '%@'", tokenized);
        return 1;
    }
    NSString *back = XFDDetokenizeFragment(tokenized);
    if (![back containsString:@"<xf:output value=\"../price\""]
        || ![back containsString:@"<strong>sum</strong>"]) {
        NSLog(@"SELFTEST detokenize gave '%@'", back);
        return 1;
    }
    // an unmatched bracket stays literal text, never a broken output
    if ([XFDDetokenizeFragment(@"a ⟦b") containsString:@"output"]) {
        NSLog(@"SELFTEST unmatched bracket became an output");
        return 1;
    }
    // an xf:output computing @value is bound — to an expression — so the
    // outline must not flag it; strip the attribute and the flag returns
    NSXMLElement *computed = [NSXMLElement elementWithName:@"xf:output"];
    [computed addAttribute:[NSXMLNode attributeWithName:@"value"
                                            stringValue:@"event('xforms-insert')/position"]];
    NSString *computedTitle = [(id)wc outlineView:nil objectValueForTableColumn:nil byItem:computed];
    if ([computedTitle containsString:@"unbound"]) {
        NSLog(@"SELFTEST computed output flagged unbound: '%@'", computedTitle);
        return 1;
    }
    [computed removeAttributeForName:@"value"];
    if (![[(id)wc outlineView:nil objectValueForTableColumn:nil byItem:computed]
             containsString:@"unbound"]) {
        NSLog(@"SELFTEST bare output not flagged unbound");
        return 1;
    }
    // palette insert path (the modal panel funnels into insertPaletteName:)
    NSUInteger beforePalette = doc.processor.controls.count;
    [undo beginUndoGrouping];
    [wc performSelector:@selector(insertPaletteName:) withObject:@"trigger"];
    [undo endUndoGrouping];
    if (doc.processor.controls.count != beforePalette + 1) {
        NSLog(@"SELFTEST palette insert failed");
        return 1;
    }
    // idref combo: a fresh bind's id shows up as a live id, a picked id
    // lands as @bind, a dangling id flags invalid
    NSXMLElement *modelEl = (NSXMLElement *)doc.processor.model.element;
    [undo beginUndoGrouping];
    NSXMLElement *bindEl = [doc.hostEdit insertElementNamed:@"bind" underParent:modelEl atIndex:-1 error:&error];
    [undo endUndoGrouping];
    if (bindEl == nil) {
        NSLog(@"SELFTEST bind insert failed: %@", error);
        return 1;
    }
    NSString *bindID = [[bindEl attributeForName:@"id"] stringValue];
    if (![[XFDIDRefField identifiersOfKind:@"bind" inProcessor:doc.processor]
             containsObject:bindID]) {
        NSLog(@"SELFTEST live bind id not listed");
        return 1;
    }
    [wc performSelector:@selector(selectElement:) withObject:input];
    XFDIDRefField *bindField = [wc valueForKey:@"controlBindField"];
    [bindField setStringValue:bindID];
    if (![bindField isValid]) {
        NSLog(@"SELFTEST live bind id flagged invalid");
        return 1;
    }
    [undo beginUndoGrouping];
    [wc performSelector:@selector(inspectorChanged:) withObject:bindField];
    [undo endUndoGrouping];
    if (![[[input attributeForName:@"bind"] stringValue] isEqualToString:bindID]) {
        NSLog(@"SELFTEST bind idref apply failed");
        return 1;
    }
    [bindField setStringValue:@"no-such-bind"];
    if ([bindField isValid]) {
        NSLog(@"SELFTEST dangling bind id not flagged");
        return 1;
    }
    [bindField setStringValue:bindID];

    // action authoring: setvalue under a trigger gets its ev:event
    // starter, routes to the data-driven Action page, and a row applies
    [undo beginUndoGrouping];
    NSXMLElement *trigger2 = [doc.hostEdit insertElementNamed:@"trigger" underParent:body atIndex:-1 error:&error];
    NSXMLElement *setvalue = trigger2
        ? [doc.hostEdit insertElementNamed:@"setvalue" underParent:trigger2 atIndex:-1 error:&error] : nil;
    [undo endUndoGrouping];
    if (setvalue == nil) {
        NSLog(@"SELFTEST action insert failed: %@", error);
        return 1;
    }
    if (![[[setvalue attributeForName:@"ev:event"] stringValue] isEqualToString:@"DOMActivate"]) {
        NSLog(@"SELFTEST action starter event missing");
        return 1;
    }
    [wc performSelector:@selector(selectElement:) withObject:setvalue];
    NSTabView *kindTabs = [wc valueForKey:@"inspectorKindTabView"];
    if ([kindTabs indexOfTabViewItem:[kindTabs selectedTabViewItem]] != 5) {
        NSLog(@"SELFTEST action page not selected");
        return 1;
    }
    NSArray *actionRows = [wc valueForKey:@"actionRows"];
    if (actionRows.count < 4) {   // Event + Node + Bind + Value + Text
        NSLog(@"SELFTEST action rows not built (%lu)", (unsigned long)actionRows.count);
        return 1;
    }
    id refRow = nil;
    for (NSDictionary *row in actionRows) {
        if ([row[@"attr"] isEqualToString:@"ref"]) {
            refRow = row[@"view"];
        }
    }
    [refRow setStringValue:@"name"];
    [undo beginUndoGrouping];
    [wc performSelector:@selector(inspectorChanged:) withObject:refRow];
    [undo endUndoGrouping];
    if (![[[setvalue attributeForName:@"ref"] stringValue] isEqualToString:@"name"]) {
        NSLog(@"SELFTEST action row apply failed");
        return 1;
    }
    // the XForms 1.1 conditionals ride every action page
    id ifRow = nil;
    for (NSDictionary *row in [wc valueForKey:@"actionRows"]) {
        if ([row[@"attr"] isEqualToString:@"if"]) {
            ifRow = row[@"view"];
        }
    }
    if (ifRow == nil) {
        NSLog(@"SELFTEST if row missing");
        return 1;
    }
    [ifRow setStringValue:@"name != ''"];
    [undo beginUndoGrouping];
    [wc performSelector:@selector(inspectorChanged:) withObject:ifRow];
    [undo endUndoGrouping];
    if (![[[setvalue attributeForName:@"if"] stringValue] isEqualToString:@"name != ''"]) {
        NSLog(@"SELFTEST if attribute apply failed");
        return 1;
    }
    // the Events group lists the trigger's handlers (actions observe
    // their parent)
    [wc performSelector:@selector(selectElement:) withObject:trigger2];
    NSArray *handlers = [wc valueForKey:@"handlerElements"];
    if (handlers.count != 1 || handlers[0] != setvalue) {
        NSLog(@"SELFTEST events table shows %lu handlers", (unsigned long)handlers.count);
        return 1;
    }
    NSTableView *eventsTable = [wc valueForKey:@"eventsTable"];
    if ([eventsTable numberOfRows] != 1) {
        NSLog(@"SELFTEST events table rows %ld", (long)[eventsTable numberOfRows]);
        return 1;
    }
    // ev:observer redirects a handler (XML Events attribute module): the
    // Observer row applies through the ev: prefix rewrite, the handler
    // leaves its parent's Events table and shows on the observed element
    [undo beginUndoGrouping];
    [doc.hostEdit setAttribute:@"id" value:@"obs-target" onElement:input];
    [undo endUndoGrouping];
    [wc performSelector:@selector(selectElement:) withObject:setvalue];
    id observerRow = nil;
    for (NSDictionary *row in [wc valueForKey:@"actionRows"]) {
        if ([row[@"attr"] isEqualToString:@"ev:observer"]) {
            observerRow = row[@"view"];
        }
    }
    if (observerRow == nil) {
        NSLog(@"SELFTEST observer row missing");
        return 1;
    }
    [observerRow setStringValue:@"obs-target"];
    [undo beginUndoGrouping];
    [wc performSelector:@selector(inspectorChanged:) withObject:observerRow];
    [undo endUndoGrouping];
    [wc performSelector:@selector(selectElement:) withObject:input];
    handlers = [wc valueForKey:@"handlerElements"];
    if (handlers.count != 1 || handlers[0] != setvalue) {
        NSLog(@"SELFTEST observed element misses the remote handler (%lu)",
              (unsigned long)handlers.count);
        return 1;
    }
    [wc performSelector:@selector(selectElement:) withObject:trigger2];
    if ([[wc valueForKey:@"handlerElements"] count] != 0) {
        NSLog(@"SELFTEST redirected handler still listed on its parent");
        return 1;
    }
    // dispatch carries the §10.9 bubbles/cancelable rows, popup-applied
    [undo beginUndoGrouping];
    NSXMLElement *dispatchEl = [doc.hostEdit insertElementNamed:@"dispatch"
                                                    underParent:trigger2 atIndex:-1 error:&error];
    [undo endUndoGrouping];
    if (dispatchEl == nil) {
        NSLog(@"SELFTEST dispatch insert failed: %@", error);
        return 1;
    }
    [wc performSelector:@selector(selectElement:) withObject:dispatchEl];
    id bubblesRow = nil;
    for (NSDictionary *row in [wc valueForKey:@"actionRows"]) {
        if ([row[@"attr"] isEqualToString:@"bubbles"]) {
            bubblesRow = row[@"view"];
        }
    }
    if (bubblesRow == nil) {
        NSLog(@"SELFTEST bubbles row missing");
        return 1;
    }
    [(NSPopUpButton *)bubblesRow selectItemWithTitle:@"false"];
    [undo beginUndoGrouping];
    [wc performSelector:@selector(inspectorChanged:) withObject:bubblesRow];
    [undo endUndoGrouping];
    if (![[[dispatchEl attributeForName:@"bubbles"] stringValue] isEqualToString:@"false"]) {
        NSLog(@"SELFTEST bubbles apply failed");
        return 1;
    }
    // design mode: the checkbox arms the overlay, the engine's layout
    // introspection hit-tests a widget back to its host element, and a
    // pick lands in the outline selection
    id overlay = [wc valueForKey:@"designOverlay"];
    if (overlay == nil || ![overlay isHidden]) {
        NSLog(@"SELFTEST overlay missing or armed before design mode");
        return 1;
    }
    id designCheckbox = [wc valueForKey:@"designModeCheckbox"];
    [designCheckbox setState:1];
    [wc performSelector:@selector(toggleDesignMode:) withObject:nil];
    if ([overlay isHidden]) {
        NSLog(@"SELFTEST overlay hidden in design mode");
        return 1;
    }
    XFFormView *formView = [wc valueForKey:@"formView"];
    XFControl *inputControl = [doc.processor controlForElement:input];
    if (formView == nil || inputControl == nil) {
        NSLog(@"SELFTEST design leg: form view or control missing");
        return 1;
    }
    NSRect inputRect = [formView layoutFrameOfControl:inputControl];
    if (NSIsEmptyRect(inputRect)) {
        NSLog(@"SELFTEST layout frame empty for the input");
        return 1;
    }
    XFControl *hit = [formView controlAtPoint:NSMakePoint(NSMidX(inputRect), NSMidY(inputRect))];
    if (hit == nil || hit.element != input) {
        NSLog(@"SELFTEST hit test missed the input (got %@)", [[hit element] localName]);
        return 1;
    }
    [wc performSelector:@selector(selectElement:) withObject:trigger2];
    [(id<XFDDesignOverlayDelegate>)wc overlay:overlay pickedElement:hit.element];
    if ([wc valueForKey:@"selected"] != input) {
        NSLog(@"SELFTEST overlay pick did not select the host element");
        return 1;
    }
    // drag-reorder: a drop slot in the trigger's bottom edge band moves
    // the input to right after it; undo walks the move back
    XFControl *trigControl = [doc.processor controlForElement:trigger2];
    NSRect trigRect = [formView layoutFrameOfControl:trigControl];
    if (NSIsEmptyRect(trigRect)) {
        NSLog(@"SELFTEST trigger frame empty");
        return 1;
    }
    NSPoint below = NSMakePoint(NSMidX(trigRect), NSMaxY(trigRect) - 2);
    NSDictionary *slot = [(id<XFDDesignOverlayDelegate>)wc overlay:overlay
        dropSlotAtFormPoint:below forElement:input];
    if (slot == nil || slot[@"parent"] != body || slot[@"line"] == nil) {
        NSLog(@"SELFTEST drop slot wrong: %@", slot);
        return 1;
    }
    NSInteger inputBefore = (NSInteger)[input index];
    [(id<XFDDesignOverlayDelegate>)wc overlay:overlay dropElement:input slot:slot];
    if ([input parent] != body || (NSInteger)[input index] != (NSInteger)[trigger2 index] + 1) {
        NSLog(@"SELFTEST drop did not land after the trigger (input %ld trigger %ld)",
              (long)[input index], (long)[trigger2 index]);
        return 1;
    }
    [undo undo];
    if ((NSInteger)[input index] != inputBefore) {
        NSLog(@"SELFTEST move undo did not restore the input's slot");
        return 1;
    }
    // dropping a control onto its own middle finds no slot
    NSRect selfRect = [formView layoutFrameOfControl:inputControl];
    if ([(id<XFDDesignOverlayDelegate>)wc overlay:overlay
              dropSlotAtFormPoint:NSMakePoint(NSMidX(selfRect), NSMidY(selfRect))
              forElement:input] != nil) {
        NSLog(@"SELFTEST self-drop produced a slot");
        return 1;
    }
    // SVG hit-testing: when the sample paints SVG, at least one svg-ns
    // path/rect must report a painted frame, and hitting its center must
    // come back to a host element inside that svg (piechart/flags/gantt)
    BOOL hasSVG = NO;
    for (NSView *sub in [formView subviews]) {
        if ([sub isKindOfClass:[XFSVGView class]]) {
            hasSVG = YES;
        }
    }
    if (hasSVG) {
        NSXMLElement *painted = nil;
        NSRect paintedRect = NSZeroRect;
        for (NSString *shapeName in @[ @"path", @"rect" ]) {
            for (NSXMLElement *e in [XFXML elementsWithLocalName:shapeName
                                                    namespaceURI:@"http://www.w3.org/2000/svg"
                                                          inNode:doc.processor.hostDocument]) {
                NSRect r = [formView layoutFrameOfSVGElement:e];
                if (!NSIsEmptyRect(r)) {
                    painted = e;
                    paintedRect = r;
                    break;
                }
            }
            if (painted != nil) {
                break;
            }
        }
        if (painted == nil) {
            NSLog(@"SELFTEST svg present but no shape painted a frame");
            return 1;
        }
        NSXMLElement *svgHit = [formView svgElementAtPoint:
            NSMakePoint(NSMidX(paintedRect), NSMidY(paintedRect))];
        if (svgHit == nil) {
            NSLog(@"SELFTEST svg hit test found nothing at a painted center");
            return 1;
        }
        [(id<XFDDesignOverlayDelegate>)wc overlay:overlay pickedElement:svgHit];
        if ([wc valueForKey:@"selected"] != svgHit) {
            NSLog(@"SELFTEST svg pick did not select the shape element");
            return 1;
        }
    }
    [designCheckbox setState:0];
    [wc performSelector:@selector(toggleDesignMode:) withObject:nil];
    if (![overlay isHidden]) {
        NSLog(@"SELFTEST overlay still armed after leaving design mode");
        return 1;
    }

    // item / itemset inspectors: itemset starter compiles, routes to its
    // page, and the Label Ref row writes the child's @ref
    [undo beginUndoGrouping];
    NSXMLElement *select1 = [doc.hostEdit insertElementNamed:@"select1" underParent:body atIndex:-1 error:&error];
    NSXMLElement *itemset = select1
        ? [doc.hostEdit insertElementNamed:@"itemset" underParent:select1 atIndex:-1 error:&error] : nil;
    [undo endUndoGrouping];
    if (itemset == nil) {
        NSLog(@"SELFTEST itemset insert failed: %@", error);
        return 1;
    }
    [wc performSelector:@selector(selectElement:) withObject:itemset];
    if ([kindTabs indexOfTabViewItem:[kindTabs selectedTabViewItem]] != 7) {
        NSLog(@"SELFTEST itemset page not selected");
        return 1;
    }
    id labelRefField = [wc valueForKey:@"itemsetLabelRefField"];
    [labelRefField setStringValue:@"name"];
    [undo beginUndoGrouping];
    [wc performSelector:@selector(inspectorChanged:) withObject:labelRefField];
    [undo endUndoGrouping];
    if (![[doc.hostEdit supportChildAttribute:@"ref" child:@"label" onElement:itemset]
             isEqualToString:@"name"]) {
        NSLog(@"SELFTEST itemset label ref apply failed");
        return 1;
    }
    // item page routes too
    NSXMLElement *item = nil;
    [undo beginUndoGrouping];
    item = [doc.hostEdit insertElementNamed:@"item" underParent:select1 atIndex:-1 error:&error];
    [undo endUndoGrouping];
    if (item == nil) {
        NSLog(@"SELFTEST item insert failed: %@", error);
        return 1;
    }
    [wc performSelector:@selector(selectElement:) withObject:item];
    if ([kindTabs indexOfTabViewItem:[kindTabs selectedTabViewItem]] != 6) {
        NSLog(@"SELFTEST item page not selected");
        return 1;
    }
    id itemValue = [wc valueForKey:@"itemValueField"];
    if (![[itemValue stringValue] isEqualToString:@"item"]) {
        NSLog(@"SELFTEST item value fill shows '%@'", [itemValue stringValue]);
        return 1;
    }

    // location-path step model: simple paths decompose and rebuild
    // canonically, complex expressions refuse (steps stay raw-only)
    NSDictionary *split = XFDSplitLocationPath(@"../line[2]/@qty");
    NSArray *steps = split[@"steps"];
    if (steps.count != 3
        || ![steps[0][@"axis"] isEqualToString:@"parent"]
        || ![steps[1][@"predicates"] isEqualToString:@"[2]"]
        || ![steps[2][@"axis"] isEqualToString:@"attribute"]
        || ![steps[2][@"test"] isEqualToString:@"qty"]) {
        NSLog(@"SELFTEST step split wrong: %@", split);
        return 1;
    }
    if (![XFDJoinLocationPath(split) isEqualToString:@"../line[2]/@qty"]) {
        NSLog(@"SELFTEST step join gave '%@'", XFDJoinLocationPath(split));
        return 1;
    }
    split = XFDSplitLocationPath(@"instance('main')/order/item[@sku='a[1]']/price");
    if (![split[@"start"] isEqualToString:@"instance"]
        || ![split[@"instance"] isEqualToString:@"main"]
        || [split[@"steps"] count] != 3) {
        NSLog(@"SELFTEST instance split wrong: %@", split);
        return 1;
    }
    // predicates re-render canonically now (the engine AST spells them)
    if (![XFDJoinLocationPath(split) isEqualToString:
             @"instance('main')/order/item[@sku = 'a[1]']/price"]) {
        NSLog(@"SELFTEST instance join gave '%@'", XFDJoinLocationPath(split));
        return 1;
    }
    if (XFDSplitLocationPath(@"concat(a,b)") != nil
        || XFDSplitLocationPath(@"a | b") != nil
        || XFDSplitLocationPath(@"../in - ../out") != nil
        || XFDSplitLocationPath(@"a[1") != nil) {
        NSLog(@"SELFTEST computed expression not refused by the splitter");
        return 1;
    }
    // // is a real location path now — the parser expands it to steps
    split = XFDSplitLocationPath(@"//name");
    if ([split[@"steps"] count] != 2
        || ![split[@"steps"][0][@"axis"] isEqualToString:@"descendant-or-self"]) {
        NSLog(@"SELFTEST // split wrong: %@", split);
        return 1;
    }
    split = XFDSplitLocationPath(@"/data/ancestor-or-self::node()[position()=1]");
    if (split == nil || ![split[@"start"] isEqualToString:@"root"]) {
        NSLog(@"SELFTEST explicit-axis split failed");
        return 1;
    }

    // workflow shortcuts: ref promotes to a named bind in one gesture
    [undo beginUndoGrouping];
    NSXMLElement *input2 = [doc.hostEdit insertElementNamed:@"input" underParent:body atIndex:-1 error:&error];
    [doc.hostEdit setAttribute:@"ref" value:@"name" onElement:input2];
    [undo endUndoGrouping];
    [wc performSelector:@selector(selectElement:) withObject:input2];
    [undo beginUndoGrouping];
    [wc performSelector:@selector(createBindFromRef:) withObject:nil];
    [undo endUndoGrouping];
    NSString *newBindID = [[input2 attributeForName:@"bind"] stringValue];
    if (newBindID.length == 0 || [[input2 attributeForName:@"ref"] stringValue].length) {
        NSLog(@"SELFTEST create-bind-from-ref failed");
        return 1;
    }
    NSXMLElement *createdBind = nil;
    for (NSXMLElement *b in [XFXML elementsWithLocalName:@"bind"
                                            namespaceURI:XFXFormsNamespaceURI
                                                  inNode:modelEl]) {
        if ([[[b attributeForName:@"id"] stringValue] isEqualToString:newBindID]) {
            createdBind = b;
        }
    }
    if (![[[createdBind attributeForName:@"nodeset"] stringValue] isEqualToString:@"name"]) {
        NSLog(@"SELFTEST created bind nodeset wrong");
        return 1;
    }
    // …and a control can be built straight from an instance data node
    NSXMLElement *instanceHost = [XFXML childElementWithLocalName:@"instance"
                                                     namespaceURI:XFXFormsNamespaceURI
                                                        ofElement:modelEl];
    NSXMLElement *dataRoot = nil;
    NSXMLElement *dataNode = nil;
    for (NSXMLNode *c in [instanceHost children]) {
        if ([c kind] == NSXMLElementKind) {
            dataRoot = (NSXMLElement *)c;
        }
    }
    for (NSXMLNode *c in [dataRoot children]) {
        if ([c kind] == NSXMLElementKind) {
            dataNode = (NSXMLElement *)c;
            break;
        }
    }
    if (dataNode != nil) {
        NSUInteger beforeBound = doc.processor.controls.count;
        [wc performSelector:@selector(selectElement:) withObject:dataNode];
        [undo beginUndoGrouping];
        [wc performSelector:@selector(createBoundControlOfKind:) withObject:@"input"];
        [undo endUndoGrouping];
        if (doc.processor.controls.count != beforeBound + 1) {
            NSLog(@"SELFTEST bound-control creation failed");
            return 1;
        }
    }
    // schema suggestions + spec knowledge helpers
    NSXMLElement *schemaRoot = [[doc.processor defaultInstance] documentElement];
    NSArray *schemaPaths = XFDSchemaPathsFromNode(schemaRoot, 40);
    if (dataNode != nil && ![schemaPaths containsObject:[dataNode name]]) {
        NSLog(@"SELFTEST schema paths missing '%@': %@", [dataNode name], schemaPaths);
        return 1;
    }
    if (![XFDEventContextProperties(@"xforms-submit-error")
             containsObject:@"response-status-code"]) {
        NSLog(@"SELFTEST event property table wrong");
        return 1;
    }
    // every editable row carries its spec tip
    if ([[(NSView *)[wc valueForKey:@"controlRefField"] toolTip] length] == 0
        || [[(NSView *)[wc valueForKey:@"bindCalculateField"] toolTip] length] == 0) {
        NSLog(@"SELFTEST attribute tips missing");
        return 1;
    }

    // syntax highlight tokens come from the engine's lexer
    NSArray *hl = [XFXPath highlightTokensForString:@"instance('m')/a div $x"];
    NSMutableArray *hlKinds = [NSMutableArray array];
    for (NSDictionary *t in hl) {
        [hlKinds addObject:t[@"kind"]];
    }
    if (![hlKinds isEqualToArray:(@[ @"function", @"punct", @"string", @"punct",
                                    @"punct", @"name", @"operator", @"variable",
                                    @"variable" ])]) {
        NSLog(@"SELFTEST highlight kinds %@", hlKinds);
        return 1;
    }

    // xpath validation: garbage flips the component invalid
    [refField setStringValue:@"//[bad(("];
    if ([[refField valueForKey:@"valid"] boolValue]) {
        NSLog(@"SELFTEST xpath validation did not flag garbage");
        return 1;
    }
    [refField setStringValue:@"name"];
    if (![[refField valueForKey:@"valid"] boolValue]) {
        NSLog(@"SELFTEST xpath validation flagged a good path");
        return 1;
    }
    while ([undo canUndo]) {
        [undo undo];
    }
    if (doc.processor.controls.count != before) {
        NSLog(@"SELFTEST undo failed (%lu controls)", (unsigned long)doc.processor.controls.count);
        return 1;
    }
    NSLog(@"SELFTEST OK (%lu controls, %lu chars)",
          (unsigned long)before, (unsigned long)saved.length);
    return 0;
}

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
    XFRegisterSampleFunctions();
    (void)argc;
    (void)argv;
    @autoreleasepool {
        [NSApplication sharedApplication];
#ifdef __APPLE__
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
#endif
        (void)[NSDocumentController sharedDocumentController];
        if (!XFDLoadNib(@"MainMenu", NSApp)) {
            NSLog(@"XFormsDesigner: failed to load MainMenu.xib");
        }
        const char *selfTest = getenv("XFD_SELFTEST");
        if (selfTest != NULL) {
            return XFDRunSelfTest(@(selfTest));
        }
        [NSApp run];
    }
    return 0;
}
