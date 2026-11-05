/* The Attributes inspector (XFDAttributesInspector.xib): the page for
   the selection's kind, showing the selection's editor; its fields are
   bound to it, so every change in a field is one undoable change.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import "XFDPartViewController.h"
#import "XFDInspectorPages.h"
#import "XFDActionPage.h"

NS_ASSUME_NONNULL_BEGIN

/// The kind pages, as the tab view's items are ordered.
typedef NS_ENUM(NSInteger, XFDInspectorPageKind) {
    XFDPageControl = 0,
    XFDPageBind,
    XFDPageSubmission,
    XFDPageInstance,
    XFDPageElement,
    XFDPageAction,
    XFDPageItem,
    XFDPageItemset,
};

@interface XFDAttributesInspector : XFDPartViewController

@property (nonatomic, strong) IBOutlet NSTabView *kindTabView;
@property (nonatomic, strong) IBOutlet XFDControlPage *controlPage;
@property (nonatomic, strong) IBOutlet XFDBindPage *bindPage;
@property (nonatomic, strong) IBOutlet XFDSubmissionPage *submissionPage;
@property (nonatomic, strong) IBOutlet XFDInstancePage *instancePage;
@property (nonatomic, strong) IBOutlet XFDElementPage *elementPage;
@property (nonatomic, strong) IBOutlet XFDActionPage *actionPage;
@property (nonatomic, strong) IBOutlet XFDItemPage *itemPage;
@property (nonatomic, strong) IBOutlet XFDItemsetPage *itemsetPage;

/// The page for an element's kind.
+ (XFDInspectorPageKind)pageKindForElement:(nullable XFXMLElement *)element;
/// The page shown.
- (XFDInspectorPage *)currentPage;

@end

NS_ASSUME_NONNULL_END
