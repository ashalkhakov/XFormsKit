/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDAttributesInspector.h"
#import "XFDInspectorSpecs.h"

@implementation XFDAttributesInspector {
    /// A page being filled or applied: the changes it makes are its own.
    BOOL _updating;
}

- (instancetype)initWithFormEditor:(XFDFormEditor *)formEditor nibName:(NSString *)nibName
{
    if ((self = [super initWithFormEditor:formEditor nibName:nibName])) {
        self.title = @"Attributes";
    }
    return self;
}

- (NSArray<XFDInspectorPage *> *)pages
{
    return @[ self.controlPage, self.bindPage, self.submissionPage, self.instancePage,
              self.elementPage, self.actionPage, self.itemPage, self.itemsetPage ];
}

- (void)viewDidLoadFromNib
{
    for (XFDInspectorPage *page in [self pages]) {
        [page setUp];
    }
    [self show];
}

+ (XFDInspectorPageKind)pageKindForElement:(XFXMLElement *)element
{
    if (element == nil
        || ![XFXML element:element hasLocalName:[element localName] namespaceURI:XFXFormsNamespaceURI]) {
        return XFDPageElement;
    }
    NSString *local = [element localName];
    if ([XFDControlKinds() containsObject:local]) {
        return XFDPageControl;
    }
    if ([local isEqualToString:@"bind"]) {
        return XFDPageBind;
    }
    if ([local isEqualToString:@"submission"]) {
        return XFDPageSubmission;
    }
    if ([local isEqualToString:@"instance"]) {
        return XFDPageInstance;
    }
    if (XFDActionSpecs()[local] != nil) {
        return XFDPageAction;
    }
    if ([local isEqualToString:@"item"]) {
        return XFDPageItem;
    }
    if ([local isEqualToString:@"itemset"]) {
        return XFDPageItemset;
    }
    return XFDPageElement;
}

- (XFDInspectorPage *)currentPage
{
    return [self pages][(NSUInteger)[[self class] pageKindForElement:self.formEditor.selection]];
}

/// The selection's page shown and filled.
- (void)show
{
    if (![self isViewLoaded]) {
        return;
    }
    [self.kindTabView selectTabViewItemAtIndex:[[self class] pageKindForElement:self.formEditor.selection]];
    _updating = YES;
    XFDInspectorPage *page = [self currentPage];
    [page fill];
    for (XFDXPathField *field in [page xpathFields]) {
        [field validate];
    }
    _updating = NO;
}

#pragma mark The form editor's news

- (void)formEditorSelectionDidChange:(XFDFormEditor *)editor
{
    (void)editor;
    [self show];
}

- (void)formEditor:(XFDFormEditor *)editor hostDidChange:(XFXMLElement *)element
{
    (void)editor;
    (void)element;
    if (!_updating) {
        [self show];
    }
}

- (void)formEditorProcessorWasReplaced:(XFDFormEditor *)editor
{
    (void)editor;
    [self show];
}

#pragma mark Applying

- (IBAction)inspectorChanged:(id)sender
{
    (void)sender;
    if (_updating || self.formEditor.selection == nil) {
        return;
    }
    // the facades tell the form editor of each set: one refill after them
    _updating = YES;
    [[self currentPage] apply];
    _updating = NO;
    [self.formEditor selectionMayHaveChanged];
}

@end
