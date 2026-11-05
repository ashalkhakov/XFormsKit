/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDPartViewController.h"

@implementation XFDPartViewController

+ (NSBundle *)designKitBundle
{
    return [NSBundle bundleForClass:[XFDPartViewController class]];
}

- (instancetype)initWithFormEditor:(XFDFormEditor *)formEditor
{
    return [self initWithFormEditor:formEditor nibName:NSStringFromClass([self class])];
}

- (instancetype)initWithFormEditor:(XFDFormEditor *)formEditor nibName:(NSString *)nibName
{
    if ((self = [super initWithNibName:nibName bundle:[[self class] designKitBundle]])) {
        _formEditor = formEditor;
        [formEditor addObserver:self];
    }
    return self;
}

- (void)dealloc
{
    [_formEditor removeObserver:self];
}

// gnustep-gui's NSViewController has no -viewDidLoad: the parts set up in
// a method of their own, called on both.
- (void)loadView
{
    [super loadView];
    [self viewDidLoadFromNib];
}

- (void)viewDidLoadFromNib
{
}

@end
