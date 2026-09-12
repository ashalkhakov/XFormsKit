/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
/* The window controller's shared internals: the inspector-page enum, the
   class extension carrying the panes and selection state, and the
   cross-file method declarations â the controller is split over
   XFDWindowController.m (nib assembly, change plumbing, undo, split view)
   plus the +Outline / +Inspector / +Preview categories, with the Events
   group and the Action page owned by XFDEventsPane / XFDActionRowsPane.
   Import this, never redeclare. */
#pragma once
#import "XFDWindowController.h"
#import "XFDEventsPane.h"
#import "XFDActionRowsPane.h"
#import <XFormsKit/XFormsKit.h>

@class XFDDocument;
@class XFDElementEditor;
@class XFDControlEditor;
@class XFBind;

typedef NS_ENUM(NSInteger, XFDInspectorPage) {
    XFDPageControl = 0,
    XFDPageBind,
    XFDPageSubmission,
    XFDPageInstance,
    XFDPageElement,
    XFDPageAction,
    XFDPageItem,
    XFDPageItemset,
};

@interface XFDWindowController ()

/// Guards re-entrant refills (the editors fire hostChanged per set).
@property (nonatomic, assign) BOOL updating;
@property (nonatomic, strong) XFFormView *formView;
@property (nonatomic, strong) NSScrollView *previewScroll;
@property (nonatomic, strong) NSTextView *sourceView;
/* Design mode (the devtools-style element picker): the overlay sits
   over the preview's content area and swallows the mouse while the
   checkbox is on; off = the form is live, as always. */
@property (nonatomic, strong) XFDDesignOverlay *designOverlay;
/// The selection is the host XFXMLElement, never a runtime control.
@property (nonatomic, strong) XFXMLElement *selected;
@property (nonatomic, strong) XFDEventsPane *eventsPane;
@property (nonatomic, strong) XFDActionRowsPane *actionRowsPane;

/* core (implemented in XFDWindowController.m) */
- (XFDDocument *)formDocument;
- (XFProcessor *)processor;

@end

/* Cross-file methods: declaration-only categories (declaring them on the
   class extension would demand primary-class implementations â the
   AppKit split's lesson). Each is implemented by the like-named file. */

@interface XFDWindowController (XFDOutlinePrivate)
- (XFXMLElement *)rootElement;
- (NSArray *)elementChildrenOf:(XFXMLElement *)element;
- (void)reloadOutlineKeepingSelection:(XFXMLElement *)keep;
- (void)selectElement:(XFXMLElement *)element;
- (XFXMLElement *)instanceElementForSelection:(XFXMLElement *)element;
- (void)outlineDoubleClicked:(id)sender;
- (void)insertPaletteName:(NSString *)name;
- (XFXMLElement *)insertParentForSelection:(NSInteger *)indexOut;
@end

@interface XFDWindowController (XFDInspectorPrivate)
- (XFDInspectorPage)pageForElement:(XFXMLElement *)element;
- (void)showInspectorForSelection;
- (void)inspectorTabSelected:(id)sender;
- (void)fillInspector;
- (void)applyAttributeTips;
/// Flip the tab bar to the Attributes group (the Events pane's
/// double-click jump).
- (void)showAttributesGroup;
- (NSArray *)xpathFields;
- (NSArray *)richTextFields;
- (XFXMLElement *)selectedInstanceDataNode;
@end

@interface XFDWindowController (XFDPreviewPrivate)
- (void)buildFormView;
- (void)refreshSourceText;
@end

/* Every split file defines its presence function; the core references
   them all from a used array, so a translation unit missing from the
   GNUmakefile or a pbxproj fails at LINK time (the AppKit split's
   pattern). */
void XFDWindowControllerOutlineFilePresent(void);
void XFDWindowControllerInspectorFilePresent(void);
void XFDWindowControllerPreviewFilePresent(void);
