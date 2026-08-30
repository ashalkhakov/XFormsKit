#import <Foundation/Foundation.h>

@class XFControl;

NS_ASSUME_NONNULL_BEGIN

/// The kind of a node in the host-markup tree. XSLTForms keeps the whole
/// XHTML DOM and renders controls in place; XFormsKit keeps only this
/// reduced tree: every host element is a block or an inline, except tables
/// and SVG which the UI maps to dedicated views (G-20).
typedef NS_ENUM(NSInteger, XFHostNodeKind) {
    XFHostNodeKindBlock,        // div, p, h1–h6, fieldset, ul/ol/li, pre, …
    XFHostNodeKindInline,       // span, a, b, i, em, strong, code, …
    XFHostNodeKindText,         // a run of character data
    XFHostNodeKindBreak,        // br
    XFHostNodeKindRule,         // hr
    XFHostNodeKindTable,        // table
    XFHostNodeKindTableSection, // thead / tbody / tfoot
    XFHostNodeKindTableRow,     // tr
    XFHostNodeKindTableCell,    // td / th
    XFHostNodeKindSVG,          // svg (children kept for the SVG renderer)
    XFHostNodeKindControl,      // an instantiated XForms control
};

@interface XFHostNode : NSObject

@property (nonatomic, assign) XFHostNodeKind kind;
/// Source element (nil for text nodes).
@property (nonatomic, strong, nullable) NSXMLElement *element;
/// Lower-cased local name of the source element (`"#text"` for text).
@property (nonatomic, copy) NSString *tag;
/// Character data for text nodes (whitespace collapsed unless `preformatted`).
@property (nonatomic, copy, nullable) NSString *text;
/// 1–6 for h1–h6, 0 otherwise.
@property (nonatomic, assign) NSInteger headingLevel;
/// fieldset legend / table caption text.
@property (nonatomic, copy, nullable) NSString *title;
/// Inside `pre`: text is kept verbatim.
@property (nonatomic, assign) BOOL preformatted;
/// `th` cells.
@property (nonatomic, assign) BOOL header;
/// The control for XFHostNodeKindControl nodes.
@property (nonatomic, strong, nullable) XFControl *control;
@property (nonatomic, copy) NSArray<XFHostNode *> *children;
@property (nonatomic, weak, nullable) XFHostNode *parent;

+ (instancetype)nodeWithKind:(XFHostNodeKind)kind tag:(NSString *)tag;

/// Build the host tree for the children of `element`, instantiating every
/// XForms control found at any depth (like the XSLT `node.xsl` templates
/// that copy host markup and emit controls in place). Controls are appended
/// to `controls` in document order; a control whose element is a key of
/// `existing` is reused instead of being created again.
+ (nullable NSArray<XFHostNode *> *)hostNodesForChildrenOf:(NSXMLElement *)element
                                                    model:(nullable id)model
                                                 controls:(NSMutableArray<XFControl *> *)controls
                                                 existing:(nullable NSDictionary<NSValue *, XFControl *> *)existing
                                                    error:(NSError **)error;

/// Convenience: `existing` built from `controls`' elements.
+ (nullable NSDictionary<NSValue *, XFControl *> *)controlMapFor:(NSArray<XFControl *> *)controls;

/// YES when the element is an HTML block-level container.
+ (BOOL)isBlockTag:(NSString *)tag;

/// YES for nodes that take part in an inline run (text, inline, break,
/// and controls whose widget is inline).
- (BOOL)isInlineLevel;
/// YES if this subtree holds at least one control.
- (BOOL)containsControls;
/// Every control in the subtree, document order.
- (NSArray<XFControl *> *)allControls;
/// Concatenated text of the subtree (controls contribute their value).
- (NSString *)textContent;
/// One-line-per-node dump used by tests (`block:p`, `text:"Hi"`, `control:input`).
- (NSString *)treeDescription;

@end

NS_ASSUME_NONNULL_END
