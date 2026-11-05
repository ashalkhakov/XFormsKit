/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFUExtension.h"
#import <UDCodeKit/UDCodeDocument.h>
#import <UDCodeKit/UDLanguageMode.h>
#import <UDPieceTable/UDTextModel.h>
#import "XFUEditorViewController.h"

@implementation XFUExtension

+ (NSArray<NSMenuItem *> *)editorMenuItems {
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"XFUEditorMenus"
                                        bundle:[NSBundle bundleForClass:[XFUExtension class]]];
  NSArray *objects = nil;
  // An owner the XIB has no use for: gnustep-gui's NSNib takes no nil one.
  if (![nib instantiateWithOwner:[[NSObject alloc] init] topLevelObjects:&objects])
    return @[];
  for (id object in objects) {
    if ([object isKindOfClass:[NSMenu class]]) {
      NSArray *items = [[(NSMenu *)object itemArray] copy];
      [(NSMenu *)object removeAllItems];
      return items;
    }
  }
  return @[];
}

+ (BOOL)textIsAForm:(NSString *)text {
  return [text rangeOfString:@"http://www.w3.org/2002/xforms"].location != NSNotFound;
}

- (void)extensionDidLoad:(NSBundle *)bundle {
  (void)bundle;
}

- (void)extensionWillUnload:(NSBundle *)bundle {
  (void)bundle;
}

// The mode's grammar is the XML mode's (LanguageInfo.plist's grammarOf).
- (const void *)languageFuncForIdentifier:(NSString *)identifier {
  (void)identifier;
  return NULL;
}

// A form in the designer; any other XHTML as text, in the XML grammar.
- (NSViewController *)workbench:(id<UDWorkbench>)workbench
              editorForDocument:(UDCodeDocument *)document {
  if (![document.languageMode.identifier isEqualToString:@"xforms"])
    return nil;
  if (![XFUExtension textIsAForm:[document.textModel getValue]])
    return nil;
  return [[XFUEditorViewController alloc] initWithDocument:document workbench:workbench];
}

// The Form menu: its items go to the first responder, which in a form's
// tab is its editor; elsewhere nothing takes them, and they are dimmed.
- (NSArray<NSMenuItem *> *)editorMenuItemsForWorkbench:(id<UDWorkbench>)workbench {
  (void)workbench;
  return [XFUExtension editorMenuItems];
}

@end
