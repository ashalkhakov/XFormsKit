#include <Foundation/NSString.h>
@interface NSFramework_XFormsDesignKit : NSObject
+ (NSString *)frameworkVersion;
+ (NSString *const*)frameworkClasses;
@end
@implementation NSFramework_XFormsDesignKit
+ (NSString *)frameworkVersion { return @"A"; }
static NSString *allClasses[] = {@"XFDFormEditor", @"XFDDocument", @"XFDActionAttributes", @"XFDActionEditor", @"XFDBindEditor", @"XFDControlEditor", @"XFDElementEditor", @"XFDInstanceEditor", @"XFDItemEditor", @"XFDItemsetEditor", @"XFDSubmissionEditor", @"XFDPartViewController", @"XFDOutlineViewController", @"XFDPreviewViewController", @"XFDInspectorViewController", @"XFDIdentityInspector", @"XFDAttributesInspector", @"XFDBindPage", @"XFDControlPage", @"XFDElementPage", @"XFDInspectorPage", @"XFDInstancePage", @"XFDItemPage", @"XFDItemsetPage", @"XFDSubmissionPage", @"XFDActionPage", @"XFDActionRowTemplate", @"XFDEventsInspector", @"XFDLibraryViewController", @"XFDWindowController", @"XFDPalettePanel", @"XFDInstanceXMLEditor", @"XFDCaptureTransport", @"XFDEchoTransport", @"XFDSubmissionTester", @"XFDEventsConsole", @"XFDEventsConsoleViewController", @"XFDEventsLog", @"XFDEventsLogEntry", @"XFDPredicateEditor", @"XFDXPathPicker", @"XFDXPathField", @"XFDXPathTextStorage", @"XFDExpressionField", @"XFDRichTextPanel", @"XFDRichTextField", @"XFDFieldBinding", @"XFDIDRefField", @"XFDDesignOverlay", @"DMTabBar", @"DMTabBarButtonCell", @"DMTabBarItem", @"JUInspectorBaseView", @"JUInspectorView", @"JUInspectorViewContainer", @"JUInspectorViewHeader", NULL};
+ (NSString *const*)frameworkClasses { return allClasses; }
@end
