/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDAttributesInspector.h"
#import "XFDInspectorSpecs.h"

@implementation XFDAttributesInspector

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

/// The selection's page shown, with the selection; the others empty.
- (void)show
{
    if (![self isViewLoaded]) {
        return;
    }
    XFXMLElement *selection = self.formEditor.selection;
    [self.kindTabView selectTabViewItemAtIndex:[[self class] pageKindForElement:selection]];
    XFDInspectorPage *current = [self currentPage];
    for (XFDInspectorPage *page in [self pages]) {
        [page showElement:page == current ? selection : nil];
    }
}

#pragma mark The form editor's news

- (void)formEditorSelectionDidChange:(XFDFormEditor *)editor
{
    (void)editor;
    [self show];
}

/// The selection may have changed under its editor (an undo, another
/// inspector), which is told to reload.
- (void)formEditor:(XFDFormEditor *)editor hostDidChange:(XFXMLElement *)element
{
    (void)editor;
    (void)element;
    if ([self isViewLoaded]) {
        [[self currentPage] showElement:self.formEditor.selection];
    }
}

- (void)formEditorProcessorWasReplaced:(XFDFormEditor *)editor
{
    (void)editor;
    [self show];
}

@end
