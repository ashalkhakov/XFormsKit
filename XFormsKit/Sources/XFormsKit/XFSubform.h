#import <Foundation/Foundation.h>

@class XFModel;
@class XFProcessor;

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_subform (G-90): an XForms document embedded by
/// `xf:load show="embed" targetid="…"` into a host element of the running
/// form. Its models are added to the processor's `models`, its body markup
/// replaces the target's content, and its controls evaluate against its
/// own first model (`subform-instance()`, `subform-context()`). The main
/// form is not represented by an XFSubform (XSLTForms' "xsltforms-mainform"
/// subform is the processor itself).
/// The properties are maintained by XFProcessor (`loadSubformAtURL:…`).
@interface XFSubform : NSObject

/// "xsltforms-subform-N" (XSLTForms' numbering).
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, weak, nullable) XFProcessor *processor;
/// The enclosing subform (nil when embedded in the main form).
@property (nonatomic, weak, nullable) XFSubform *parent;
/// The host element (`@targetid`) whose content the subform replaced.
@property (nonatomic, strong) NSXMLElement *targetElement;
/// The URL the subform was loaded from.
@property (nonatomic, strong, nullable) NSURL *URL;
/// The subform's models (in the processor's `models` too).
@property (nonatomic, copy) NSArray<XFModel *> *models;
/// The nodes imported into `targetElement` (models and body markup).
@property (nonatomic, copy) NSArray<NSXMLNode *> *importedNodes;
/// Subforms embedded inside this one.
@property (nonatomic, copy) NSArray<XFSubform *> *subforms;
/// After xforms-subform-ready.
@property (nonatomic, assign) BOOL ready;

/// The subform's first model (the default model of its controls).
- (nullable XFModel *)defaultModel;
/// YES when `element` lies inside the subform's imported content (and
/// not inside a nested subform's content).
- (BOOL)containsElement:(NSXMLNode *)element;

@end

NS_ASSUME_NONNULL_END
