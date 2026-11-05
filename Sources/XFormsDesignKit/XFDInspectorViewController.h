/* The designer window's inspector pane (XFDInspectorViewController.xib):
   the Identity, Attributes and Events inspectors under a tab bar of their
   badges, as Interface Builder's are. Which one shows is the user's choice; the
   Attributes inspector's page follows the selection. A host with an
   inspector pane of its own shows the inspectors there instead.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import "XFDPartViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class XFDIdentityInspector, XFDAttributesInspector, XFDEventsInspector;

@interface XFDInspectorViewController : XFDPartViewController

@property (nonatomic, strong) IBOutlet id inspectorTabBar;    /* DMTabBar */
@property (nonatomic, strong) IBOutlet NSTabView *inspectorTabView;

@property (nonatomic, strong, readonly) XFDIdentityInspector *identityInspector;
@property (nonatomic, strong, readonly) XFDAttributesInspector *attributesInspector;
@property (nonatomic, strong, readonly) XFDEventsInspector *eventsInspector;
/// The three, in their tabs' order.
@property (nonatomic, copy, readonly) NSArray<NSViewController *> *inspectors;

/// An inspector's badge: ID, A, E.
+ (NSImage *)imageForInspector:(NSViewController *)inspector;

/// The tab of `inspector` brought forward.
- (void)showInspector:(NSViewController *)inspector;

@end

NS_ASSUME_NONNULL_END
