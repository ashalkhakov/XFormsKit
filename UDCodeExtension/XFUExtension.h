/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import <UDCodeKit/UDExtension.h>

// UDCode's XForms extension (docs/UDCODE.md): XHTML+XForms forms (.xhtml)
// edited in UDCode with XFormsDesigner's designer (XFormsDesignKit), in a
// tab of their own, as part of a project. A form is its document's text:
// the designer writes each change into it (XFUEditorViewController), so
// undo, saving, the tab's dot and source control are UDCode's, and a tab
// of its text shows it as XML (its grammar is the XML mode's). An .xhtml
// file that is no form (no XForms in it) opens as text. The designer's
// Form menu is in UDCode's Editor menu.
@interface XFUExtension : NSObject <UDExtension>
// The Editor menu's items, from XFUEditorMenus.xib.
+ (NSArray<NSMenuItem *> *)editorMenuItems;
// Whether the text is a form's: XHTML with the XForms namespace in it.
+ (BOOL)textIsAForm:(NSString *)text;
@end
