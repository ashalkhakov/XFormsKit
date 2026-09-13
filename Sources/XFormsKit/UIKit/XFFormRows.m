/* XFFormRows.m — the host tree flattened into the sections and rows an
   iOS form shows. No view framework: the same rows drive whatever
   renders them, and this is the half that can be tested without a screen.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#import <XFormsKit/XFFormRows.h>
#import <XFormsKit/XFProcessor.h>
#import <XFormsKit/XFHostNode.h>
#import <XFormsKit/XFControl.h>
#import <XFormsKit/XFInputControl.h>
#import <XFormsKit/XFSecretControl.h>
#import <XFormsKit/XFTextareaControl.h>
#import <XFormsKit/XFOutputControl.h>
#import <XFormsKit/XFTriggerControl.h>
#import <XFormsKit/XFSelectControl.h>
#import <XFormsKit/XFRangeControl.h>
#import <XFormsKit/XFUploadControl.h>
#import <XFormsKit/XFGroup.h>
#import <XFormsKit/XFRepeat.h>
#import <XFormsKit/XFTableModel.h>
#import <XFormsKit/XFDialog.h>
#import <XFormsKit/XFSwitch.h>
#import <XFormsKit/XFNodeState.h>

/// Above this many items a full-appearance select stops being a segmented
/// control and becomes a list of check rows: a segment gets unreadable
/// long before the screen runs out, and the check list scrolls.
static const NSUInteger kXFMaxSegments = 4;

@implementation XFFormRow
@end

@implementation XFFormSection
@end

@implementation XFFormRows

+ (BOOL)isBooleanControl:(XFControl *)control
{
    // the same test the AppKit widget factory makes
    XFNodeState *state = [XFNodeState existingStateOnNode:control.boundNode];
    if ([(state.typeName ?: @"") rangeOfString:@"boolean"].location != NSNotFound) {
        return YES;
    }
    NSString *value = control.stringValue ?: @"";
    return [value isEqualToString:@"true"] || [value isEqualToString:@"false"];
}

+ (XFFormRowKind)kindForControl:(XFControl *)control
{
    if ([control isKindOfClass:[XFUploadControl class]]) {
        return XFFormRowKindUpload;
    }
    if ([control isKindOfClass:[XFTriggerControl class]]) {
        return XFFormRowKindButton;   // xf:submit is a trigger subclass
    }
    if ([control isKindOfClass:[XFOutputControl class]]) {
        // an image output's value is base64; shown as text it is a wall of
        // it, so it gets a row that draws the picture instead
        return [(XFOutputControl *)control displaysImage] ? XFFormRowKindImage
                                                          : XFFormRowKindValue;
    }
    if ([control isKindOfClass:[XFRangeControl class]]) {
        return XFFormRowKindSlider;
    }
    if ([control isKindOfClass:[XFTextareaControl class]]) {
        return XFFormRowKindTextView;
    }
    if ([control isKindOfClass:[XFSelectControl class]]) {
        XFSelectControl *select = (XFSelectControl *)control;
        BOOL full = [control.appearance isEqualToString:@"full"];
        if (select.multiple || full) {
            return (!select.multiple && full && select.items.count <= kXFMaxSegments)
                ? XFFormRowKindSegmented : XFFormRowKindCheck;
        }
        return XFFormRowKindSelector;
    }
    if ([control isKindOfClass:[XFInputControl class]]) {
        if ([(XFInputControl *)control resolvedDateType] != XFDateTypeNone) {
            return XFFormRowKindDate;
        }
        if ([self isBooleanControl:control]) {
            return XFFormRowKindSwitch;
        }
    }
    return XFFormRowKindTextField;   // xf:input, xf:secret, anything else
}

#pragma mark - Flattening

/// Rows for one control. Usually one; a full-appearance select becomes one
/// check row per item, which is what makes it scroll instead of overflow.
+ (void)appendRowsForControl:(XFControl *)control
                       depth:(NSUInteger)depth
                        into:(NSMutableArray<XFFormRow *> *)rows
{
    XFFormRowKind kind = [self kindForControl:control];
    if (kind == XFFormRowKindCheck) {
        XFSelectControl *select = (XFSelectControl *)control;
        for (NSUInteger i = 0; i < select.items.count; i++) {
            XFFormRow *row = [[XFFormRow alloc] init];
            row.kind = XFFormRowKindCheck;
            row.control = control;
            row.itemIndex = i;
            row.depth = depth;
            row.label = i == 0 ? control.label : nil;   // the caption once
            [rows addObject:row];
        }
        return;
    }
    XFFormRow *row = [[XFFormRow alloc] init];
    row.kind = kind;
    row.control = control;
    row.depth = depth;
    row.label = control.label;
    [rows addObject:row];
    [self appendNoteForControl:control depth:depth into:rows];
}

/// A row under the control carrying its xf:hint, or its xf:alert while it
/// is invalid.
///
/// AppKit shows both as hover badges, which a phone has no gesture for,
/// and XLForm's answer -- an alert sheet when the form is submitted --
/// says nothing while the field is being filled in. Explanatory text
/// directly under the field is what iOS does, in Settings and in Apple's
/// own sign-up forms, so a form built this way reads as an iOS form.
///
/// A row rather than a second line inside the cell: the cells mix
/// UITableViewCell's own textLabel with custom constraints, and a label
/// anchored under both fights whichever laid out first.
///
/// A minimal hint is the field's placeholder (XSLTForms' rule) and is not
/// repeated here.
+ (void)appendNoteForControl:(XFControl *)control
                       depth:(NSUInteger)depth
                        into:(NSMutableArray<XFFormRow *> *)rows
{
    NSString *text = nil;
    NSString *markup = nil;
    BOOL problem = NO;
    if (!control.valid && ![control isKindOfClass:[XFTriggerControl class]]) {
        text = control.alert.length ? control.alert : @"This value is not valid.";
        markup = control.alert.length ? control.alertMarkup : nil;
        problem = YES;
    } else if (control.hint.length && !control.hintMinimal) {
        text = control.hint;
        markup = control.hintMarkup;
    }
    if (text.length == 0) {
        return;
    }
    XFFormRow *note = [[XFFormRow alloc] init];
    note.kind = XFFormRowKindNote;
    note.control = control;
    note.depth = depth;
    note.note = text;
    note.noteMarkup = markup;
    note.noteIsProblem = problem;
    [rows addObject:note];
}

/// Markup runs are gathered rather than emitted per node: consecutive
/// prose, images and SVG belong in one cell, the way they share a line in
/// the AppKit layout.
+ (BOOL)runShowsAnything:(NSArray<XFHostNode *> *)nodes
{
    for (XFHostNode *node in nodes) {
        if (node.kind == XFHostNodeKindSVG || node.kind == XFHostNodeKindTable
            || node.kind == XFHostNodeKindRule) {
            return YES;
        }
        NSString *text = [[node textContent] stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (text.length) {
            return YES;
        }
    }
    return NO;
}

+ (void)flushMarkup:(NSMutableArray<XFHostNode *> *)pending
              depth:(NSUInteger)depth
            context:(XFXMLNode *)context
               into:(NSMutableArray<XFFormRow *> *)rows
{
    if (pending.count == 0) {
        return;
    }
    // The host tree keeps the whitespace between elements on purpose --
    // "<b>is</b> <xf:output/>" needs its space. A run that is ONLY that
    // whitespace is not a row, though; it would be an empty cell between
    // every pair of controls.
    if (![self runShowsAnything:pending]) {
        [pending removeAllObjects];
        return;
    }
    XFFormRow *row = [[XFFormRow alloc] init];
    row.kind = XFFormRowKindMarkup;
    row.hostNodes = [pending copy];
    row.depth = depth;
    row.contextNode = context;
    [rows addObject:row];
    [pending removeAllObjects];
}

/// A node the markup cell renders whole, rather than one to descend into
/// looking for controls.
///
/// A BLOCK counts when it holds no control: keeping it intact is what
/// preserves its tag, and the tag is what makes an <h2> a heading and a
/// <pre> monospaced. Descending into it would leave a bare run of text
/// with nothing to say how it should look. A block that does hold a
/// control has to be walked, so the control gets its own row.
/// Lays out a block that has controls in it.
///
/// A block is not all one thing: `<p><xf:output ref="@firstname"/>
/// <xf:output ref="@lastname"/> <xf:trigger>…</xf:trigger>
/// <xf:group id="subform"/></p>` — the writers sample — is a sentence
/// (two names and a button) followed by a placeholder that a subform
/// gets embedded into. A browser flows the sentence and lets the group
/// follow as a block, and so does this: maximal runs of INLINE material
/// become one flowed line each, and anything block-level between them is
/// laid out the way it would be anywhere else.
///
/// Giving each control its own full-width row instead — which is what the
/// port did until now — turned that sentence into three disconnected rows.
+ (void)appendBlock:(XFHostNode *)node
              depth:(NSUInteger)depth
            context:(XFXMLNode *)context
           sections:(NSMutableArray<XFFormSection *> *)sections
            current:(NSMutableArray<XFFormRow *> *)rows
            pending:(NSMutableArray<XFHostNode *> *)pending
{
    NSMutableArray<XFHostNode *> *run = [NSMutableArray array];
    for (XFHostNode *child in node.children) {
        if ([self isInlineRunMaterial:child]) {
            [run addObject:child];
            continue;
        }
        [self flushInlineRun:run depth:depth context:context
                    sections:sections current:rows pending:pending];
        [self walkNodes:@[ child ] depth:depth context:context
               sections:sections current:rows pending:pending];
    }
    [self flushInlineRun:run depth:depth context:context
                sections:sections current:rows pending:pending];
}

/// Can this child share a line? Text and inline markup can; a control
/// can unless it wants a block of its own (a group, repeat, switch or
/// textarea).
+ (BOOL)isInlineRunMaterial:(XFHostNode *)node
{
    switch (node.kind) {
        case XFHostNodeKindText:
        case XFHostNodeKindBreak:
            return YES;
        case XFHostNodeKindInline:
            for (XFHostNode *child in node.children) {
                if (![self isInlineRunMaterial:child]) {
                    return NO;
                }
            }
            return YES;
        case XFHostNodeKindControl:
            return node.control != nil && ![node.control isBlockLevel];
        default:
            return NO;
    }
}

/// Emits the run gathered so far and empties it.
///
/// Text with no controls is prose and joins the surrounding markup run,
/// so a paragraph split by a control still reads as one piece. A single
/// control with no words around it is NOT a sentence — on a phone a lone
/// field is better as an ordinary labelled row, which is what it gets.
+ (void)flushInlineRun:(NSMutableArray<XFHostNode *> *)run
                 depth:(NSUInteger)depth
               context:(XFXMLNode *)context
              sections:(NSMutableArray<XFFormSection *> *)sections
               current:(NSMutableArray<XFFormRow *> *)rows
               pending:(NSMutableArray<XFHostNode *> *)pending
{
    if (run.count == 0) {
        return;
    }
    NSUInteger controls = 0;
    BOOL text = NO;
    for (XFHostNode *node in run) {
        [self countInlineRun:@[ node ] controls:&controls text:&text];
    }
    if (controls == 0) {
        [pending addObjectsFromArray:run];   // prose: let the markup run have it
        [run removeAllObjects];
        return;
    }
    if (controls == 1 && !text) {
        // a lone control: an ordinary row for it, and whatever whitespace
        // came with it is not worth a line
        [self walkNodes:run depth:depth context:context
               sections:sections current:rows pending:pending];
        [run removeAllObjects];
        return;
    }
    [self flushMarkup:pending depth:depth context:context into:rows];
    XFFormRow *row = [[XFFormRow alloc] init];
    row.kind = XFFormRowKindInlineFlow;
    row.hostNodes = [run copy];
    row.depth = depth;
    row.contextNode = context;
    [rows addObject:row];
    [run removeAllObjects];
}

+ (void)countInlineRun:(NSArray<XFHostNode *> *)nodes
              controls:(NSUInteger *)controls
                  text:(BOOL *)text
{
    for (XFHostNode *node in nodes) {
        if (node.kind == XFHostNodeKindControl) {
            if (node.control != nil && node.control.relevant) {
                (*controls)++;
            }
        } else if (node.kind == XFHostNodeKindText) {
            NSString *trimmed = [[node textContent] stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length) {
                *text = YES;
            }
        } else if (node.kind == XFHostNodeKindInline) {
            [self countInlineRun:node.children controls:controls text:text];
        }
    }
}

+ (BOOL)nodeIsMarkup:(XFHostNode *)node
{
    switch (node.kind) {
        case XFHostNodeKindText:
        case XFHostNodeKindBreak:
        case XFHostNodeKindRule:
        case XFHostNodeKindInline:
        case XFHostNodeKindSVG:
            return YES;
        case XFHostNodeKindTable:
            // a table is always its own row (a grid), never swept into a
            // prose run: it is emitted by the branch above
            return NO;
        case XFHostNodeKindBlock:
            return ![node containsControls];
        default:
            return NO;
    }
}

/// `context` is the in-scope evaluation context node: the bound node of
/// the enclosing group, or the node of the repeat item being walked. It
/// rides along because host MARKUP is evaluated against it — an SVG's
/// AVTs and its xf:output children resolve there, so a `fill="{@code}"`
/// inside a repeat means this item's colour. The AppKit layout carries
/// the same thing in -svgContextNode; without it every flag in the
/// flags sample painted the same fallback grey, its @code having been
/// looked up on the wrong node.
+ (void)walkNodes:(NSArray<XFHostNode *> *)nodes
            depth:(NSUInteger)depth
          context:(XFXMLNode *)context
         sections:(NSMutableArray<XFFormSection *> *)sections
          current:(NSMutableArray<XFFormRow *> *)rows
          pending:(NSMutableArray<XFHostNode *> *)pending
{
    for (XFHostNode *node in nodes) {
        if (node.kind == XFHostNodeKindControl) {
            XFControl *control = node.control;
            if (control == nil || !control.relevant) {
                continue;   // non-relevant controls take no space, as on macOS
            }
            if ([control isKindOfClass:[XFDialog class]]) {
                // An xf:dialog is hidden until xf:show and is presented by
                // the host, not laid out in the form — its content would
                // otherwise appear inline, permanently, AND again in the
                // sheet. XFDialog is an XFGroup, so it has to be turned
                // away before the group branch below claims it.
                continue;
            }
            if ([control isKindOfClass:[XFGroup class]]) {
                [self flushMarkup:pending depth:depth context:context into:rows];
                [self appendGroup:(XFGroup *)control depth:depth context:context
                         sections:sections current:rows pending:pending];
                continue;
            }
            if ([control isKindOfClass:[XFSwitch class]]) {
                XFCase *selected = [(XFSwitch *)control selectedCase];
                if (selected != nil) {
                    [self walkNodes:selected.hostNodes depth:depth context:context
                           sections:sections current:rows pending:pending];
                }
                continue;
            }
            if ([control isKindOfClass:[XFRepeat class]]) {
                [self flushMarkup:pending depth:depth context:context into:rows];
                [self appendRepeat:(XFRepeat *)control depth:depth context:context
                          sections:sections current:rows pending:pending];
                continue;
            }
            [self flushMarkup:pending depth:depth context:context into:rows];
            [self appendRowsForControl:control depth:depth into:rows];
            continue;
        }
        if (node.kind == XFHostNodeKindTable) {
            [self flushMarkup:pending depth:depth context:context into:rows];
            XFFormRow *row = [[XFFormRow alloc] init];
            row.kind = XFFormRowKindTable;
            row.hostNodes = @[ node ];
            row.depth = depth;
            row.contextNode = context;
            [rows addObject:row];
            continue;
        }
        if ([self nodeIsMarkup:node]) {
            [pending addObject:node];
            continue;
        }
        // a block with controls in it: sentences flow, blocks carry on
        [self appendBlock:node depth:depth context:context
                 sections:sections current:rows pending:pending];
    }
}

/// Whatever sits outside a group becomes an untitled section at the point
/// it was reached. Collecting it all and prepending once would be simpler
/// and wrong: a control after a group would jump above it.
+ (void)flushLoose:(NSMutableArray<XFFormRow *> *)loose
              into:(NSMutableArray<XFFormSection *> *)sections
{
    if (loose.count == 0) {
        return;
    }
    XFFormSection *section = [[XFFormSection alloc] init];
    section.rows = [loose copy];
    [sections addObject:section];
    [loose removeAllObjects];
}

/// A group becomes a section when it is at the top, and indented rows
/// under a header row when it is nested — a table view has two levels and
/// XForms nests without limit.
+ (void)appendGroup:(XFGroup *)group
              depth:(NSUInteger)depth
            context:(XFXMLNode *)context
           sections:(NSMutableArray<XFFormSection *> *)sections
            current:(NSMutableArray<XFFormRow *> *)rows
            pending:(NSMutableArray<XFHostNode *> *)pending
{
    // a bound group shifts the context its children evaluate against
    XFXMLNode *inner = group.boundNode ?: context;
    if (depth == 0) {
        [self flushLoose:rows into:sections];   // keep document order
        XFFormSection *section = [[XFFormSection alloc] init];
        section.title = group.label;
        NSMutableArray<XFFormRow *> *groupRows = [NSMutableArray array];
        NSMutableArray<XFHostNode *> *groupPending = [NSMutableArray array];
        [self walkNodes:group.hostNodes depth:1 context:inner
               sections:sections current:groupRows pending:groupPending];
        [self flushMarkup:groupPending depth:1 context:inner into:groupRows];
        section.rows = groupRows;
        if (groupRows.count) {
            [sections addObject:section];
        }
        return;
    }
    [self walkNodes:group.hostNodes depth:depth + 1 context:inner
           sections:sections current:rows pending:pending];
}

/// Each item of a repeat contributes its rows in order. A top-level repeat
/// is its own section, so the table view's insert / delete affordance has
/// somewhere to live; those map onto xf:insert and xf:delete.
+ (void)appendRepeat:(XFRepeat *)repeat
               depth:(NSUInteger)depth
             context:(XFXMLNode *)context
            sections:(NSMutableArray<XFFormSection *> *)sections
             current:(NSMutableArray<XFFormRow *> *)rows
             pending:(NSMutableArray<XFHostNode *> *)pending
{
    if (depth == 0) {
        [self flushLoose:rows into:sections];   // keep document order
    }
    NSMutableArray<XFFormRow *> *itemRows = depth == 0 ? [NSMutableArray array] : rows;
    for (XFRepeatItem *item in repeat.items) {
        NSUInteger first = itemRows.count;
        NSMutableArray<XFHostNode *> *itemPending = [NSMutableArray array];
        [self walkNodes:item.hostNodes depth:depth + (depth == 0 ? 0 : 1)
                context:item.node ?: context
               sections:sections current:itemRows pending:itemPending];
        [self flushMarkup:itemPending depth:depth context:item.node ?: context
                     into:itemRows];
        // tag what this item produced, so a gesture on a row knows which
        // node it would remove; a nested repeat got there first and keeps
        // its rows, being the one a swipe on them means
        for (NSUInteger i = first; i < itemRows.count; i++) {
            if (itemRows[i].repeat == nil) {
                itemRows[i].repeat = repeat;
                itemRows[i].repeatPosition = item.position;
            }
        }
    }
    if (depth == 0 && itemRows.count) {
        // The affordance row closing the section. Only where there is an
        // item to copy: an empty repeat has no section at all, and
        // nothing to make the new node from.
        XFFormRow *add = [[XFFormRow alloc] init];
        add.kind = XFFormRowKindRepeatAdd;
        add.repeat = repeat;
        [itemRows addObject:add];
        XFFormSection *section = [[XFFormSection alloc] init];
        section.title = repeat.label;
        section.repeat = repeat;
        section.rows = itemRows;
        [sections addObject:section];
    }
    (void)pending;
}

#pragma mark - Entry points

+ (NSArray<XFFormSection *> *)sectionsForHostNodes:(NSArray<XFHostNode *> *)nodes
{
    NSMutableArray<XFFormSection *> *sections = [NSMutableArray array];
    NSMutableArray<XFFormRow *> *loose = [NSMutableArray array];
    NSMutableArray<XFHostNode *> *pending = [NSMutableArray array];
    [self walkNodes:nodes depth:0 context:nil sections:sections current:loose pending:pending];
    [self flushMarkup:pending depth:0 context:nil into:loose];
    [self flushLoose:loose into:sections];
    return sections;
}

+ (NSArray<XFFormSection *> *)sectionsForProcessor:(XFProcessor *)processor
{
    return [self sectionsForHostNodes:processor.hostNodes];
}

@end
