/* Internals of the portable rich-text converter: it maps between the
   XHTML subset the instance stores and an NSAttributedString carrying
   XFRich* markers. Foundation and the DOM only — no fonts, no attribute
   names from a UI framework. */

#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>
#import <XFormsKit/XFRichText.h>
#import <XFormsKit/XFXML.h>
