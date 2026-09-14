//
//  JUInspectorBaseView.h
//  JUInspectorView
//
//  Created by Jon Gilkison on 9/28/11.
//  Copyright 2011 Interfacelab LLC. All rights reserved.
//

// GNUstep has no Cocoa umbrella; AppKit is the half these views use.
#if __has_include(<Cocoa/Cocoa.h>)
#import <Cocoa/Cocoa.h>
#else
#import <AppKit/AppKit.h>
#endif

@interface JUInspectorBaseView : NSView

-(void)setupView;

@end
