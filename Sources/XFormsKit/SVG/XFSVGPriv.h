/* Internals of the portable SVG renderer. It draws through CoreGraphics
   and measures text through CoreText — on GNUstep both come from Opal —
   so it needs no view layer and builds on every target. */

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>

#import <XFormsKit/XFXMLTypes.h>
#import <XFormsKit/XFSVG.h>
#import <XFormsKit/XFHostNode.h>
#import <XFormsKit/XFProcessor.h>
#import <XFormsKit/XFAVT.h>
#import <XFormsKit/XFExprContext.h>
#import <XFormsKit/XFXML.h>
#import <XFormsKit/XFOutputControl.h>
#import <XFormsKit/XFControl.h>
#import <XFormsKit/XFRepeat.h>
#import <XFormsKit/XFGroup.h>
#import <XFormsKit/XFSwitch.h>
