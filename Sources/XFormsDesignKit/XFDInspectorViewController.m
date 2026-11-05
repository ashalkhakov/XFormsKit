/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDInspectorViewController.h"
#import "XFDIdentityInspector.h"
#import "XFDAttributesInspector.h"
#import "XFDEventsInspector.h"
#import "XFDInspectorSpecs.h"
#import "DMTabBar.h"
#import "DMTabBarItem.h"

@implementation XFDInspectorViewController

- (instancetype)initWithFormEditor:(XFDFormEditor *)formEditor nibName:(NSString *)nibName
{
    if ((self = [super initWithFormEditor:formEditor nibName:nibName])) {
        _identityInspector = [[XFDIdentityInspector alloc] initWithFormEditor:formEditor];
        _attributesInspector = [[XFDAttributesInspector alloc] initWithFormEditor:formEditor];
        _eventsInspector = [[XFDEventsInspector alloc] initWithFormEditor:formEditor];
    }
    return self;
}

- (NSArray<NSViewController *> *)inspectors
{
    return @[ self.identityInspector, self.attributesInspector, self.eventsInspector ];
}

+ (NSImage *)imageForInspector:(NSViewController *)inspector
{
    if ([inspector isKindOfClass:[XFDIdentityInspector class]]) {
        return XFDBadge(@"ID", 0.47, 0.53, 0.64);
    }
    if ([inspector isKindOfClass:[XFDAttributesInspector class]]) {
        return XFDBadge(@"A", 0.36, 0.49, 0.72);
    }
    if ([inspector isKindOfClass:[XFDEventsInspector class]]) {
        return XFDBadge(@"E", 0.70, 0.48, 0.32);
    }
    return nil;
}

- (void)viewDidLoadFromNib
{
    // each inspector's view in its tab, and a badge for it on the bar
    NSMutableArray *items = [NSMutableArray array];
    NSArray *inspectors = [self inspectors];
    for (NSUInteger i = 0; i < inspectors.count; i++) {
        NSViewController *inspector = inspectors[i];
        NSView *page = [[self.inspectorTabView tabViewItemAtIndex:(NSInteger)i] view];
        NSView *view = [inspector view];
        [view setFrame:[page bounds]];
        [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [page addSubview:view];
        DMTabBarItem *item = [DMTabBarItem tabBarItemWithIcon:[[self class] imageForInspector:inspector] tag:i];
        item.toolTip = inspector.title;
        [items addObject:item];
    }
    DMTabBar *bar = (DMTabBar *)self.inspectorTabBar;
    bar.tabBarItems = items;
    [bar setTarget:self action:@selector(inspectorTabSelected:)];
    // Attributes, the working page
    [self showInspector:self.attributesInspector];
}

- (void)inspectorTabSelected:(id)sender
{
    (void)sender;
    DMTabBar *bar = (DMTabBar *)self.inspectorTabBar;
    [self.inspectorTabView selectTabViewItemAtIndex:(NSInteger)bar.selectedIndex];
}

- (void)showInspector:(NSViewController *)inspector
{
    NSUInteger index = [[self inspectors] indexOfObjectIdenticalTo:inspector];
    if (index == NSNotFound) {
        return;
    }
    [self view];
    DMTabBar *bar = (DMTabBar *)self.inspectorTabBar;
    bar.selectedIndex = index;
    [self.inspectorTabView selectTabViewItemAtIndex:(NSInteger)index];
}

@end
