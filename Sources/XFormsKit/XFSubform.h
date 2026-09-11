#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>

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
@property (nonatomic, strong) XFXMLElement *targetElement;
/// When the target lies inside an xf:repeat template, the repeat-item
/// node the loading action ran against. XSLTForms clones the item's DOM
/// and IdManager resolves targetid to the CURRENT clone; XFormsKit
/// shares one template element across items, so the owner node is what
/// keeps each item's subform its own — content renders (and unloads)
/// only in the owning item. nil outside repeats.
@property (nonatomic, strong, nullable) XFXMLNode *ownerNode;

/// Tags an imported node with the owning repeat-item node — the host
/// tree builder skips imported nodes whose owner is not the item being
/// built. Owner nil removes the tag.
+ (void)tagImportedNode:(XFXMLNode *)node ownerNode:(nullable XFXMLNode *)owner;
+ (nullable XFXMLNode *)ownerNodeOfImportedNode:(XFXMLNode *)node;
/// The URL the subform was loaded from.
@property (nonatomic, strong, nullable) NSURL *URL;
/// The subform's models (in the processor's `models` too).
@property (nonatomic, copy) NSArray<XFModel *> *models;
/// The nodes imported into `targetElement` (models and body markup).
@property (nonatomic, copy) NSArray<XFXMLNode *> *importedNodes;
/// Subforms embedded inside this one.
@property (nonatomic, copy) NSArray<XFSubform *> *subforms;
/// After xforms-subform-ready.
@property (nonatomic, assign) BOOL ready;

/// The subform's first model (the default model of its controls).
- (nullable XFModel *)defaultModel;
/// YES when `element` lies inside the subform's imported content (and
/// not inside a nested subform's content).
- (BOOL)containsElement:(XFXMLNode *)element;

@end

NS_ASSUME_NONNULL_END
