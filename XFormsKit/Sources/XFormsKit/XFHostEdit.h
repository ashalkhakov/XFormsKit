#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFProcessor;

NS_ASSUME_NONNULL_BEGIN

/// The form designer's mutation API over the host document. Authoring
/// writes host XML — the processor recompiles the affected subtree
/// (XSLTForms-style: XFControl/XFBind stay compiled views, never editable
/// objects that serialize themselves). Every command mutates the host
/// document, notifies the processor (attachElement: / detachElement: /
/// noteElementChanged:) instead of tearing it down, registers its inverse
/// with the undo manager, and reports through `changedHandler`. Nothing
/// here touches a view, so the layer is testable without AppKit.
@interface XFHostEdit : NSObject

@property (nonatomic, strong, readonly) XFProcessor *processor;
@property (nonatomic, strong, nullable) NSUndoManager *undoManager;
/// Called after every mutation, undo and redo included — the editor
/// refreshes its outline / preview here.
@property (nonatomic, copy, nullable) void (^changedHandler)(XFXMLElement *element);

+ (instancetype)editWithProcessor:(XFProcessor *)processor
                      undoManager:(nullable NSUndoManager *)undoManager;

/// First free "<prefix>-<n>" id across the host document ("input-1", …).
- (NSString *)uniqueIdentifierWithPrefix:(NSString *)prefix;

/// Insertion zones: model children (instance / bind / submission) only
/// under xf:model; xf:model under the head; UI controls under host markup
/// inside the body or under group / case / repeat / dialog; case only
/// under switch; item only under select / select1. Everything else is
/// refused — palette items never drop into instance data.
+ (BOOL)canInsertElementNamed:(NSString *)localName underParent:(XFXMLElement *)parent;
/// The local names insertable under `parent`, in palette order — the
/// designer's + menu. Empty when nothing may go there.
+ (NSArray<NSString *> *)insertableNamesUnderParent:(XFXMLElement *)parent;

/// Creates an xf: element (resolving the document's prefix for the
/// XForms namespace), gives it a unique id, a starter xf:label where the
/// control kind carries one (and label/value children for item), inserts
/// it and attaches it to the processor. index -1 appends.
- (nullable XFXMLElement *)insertElementNamed:(NSString *)localName
                                  underParent:(XFXMLElement *)parent
                                      atIndex:(NSInteger)index
                                        error:(NSError **)error;

/// Detaches from the processor and removes the subtree. Undo reinserts
/// the same NSXMLElement object, so element identity survives a round
/// trip through undo.
- (void)deleteElement:(XFXMLElement *)element;

/// Moves an existing element to a new position — the designer's
/// drag-reorder. One undoable command (the inverse is the move back),
/// element identity preserved: physical detach + processor detach, then
/// reinsert at `index` among `parent`'s child NODES (-1 appends; when
/// staying under the same parent the index is interpreted against the
/// tree as it was BEFORE the move, like NSArray moves). Refused (NO,
/// nothing changed) when the element has no parent, the target is the
/// element itself or inside its own subtree, the zone rules reject the
/// element's kind under `parent`, or the move is a no-op.
- (BOOL)moveElement:(XFXMLElement *)element
        underParent:(XFXMLElement *)parent
            atIndex:(NSInteger)index;

/// nil or empty removes the attribute.
- (void)setAttribute:(NSString *)name
               value:(nullable NSString *)value
           onElement:(XFXMLElement *)element;

/// Text of the xf:label / hint / help / alert child; nil or empty
/// removes the child, setting creates it when missing (label first).
- (void)setSupportChild:(NSString *)localName
                   text:(nullable NSString *)text
              onElement:(XFXMLElement *)element;
- (nullable NSString *)supportChildText:(NSString *)localName
                              onElement:(XFXMLElement *)element;

/// The support child as markup: XForms 1.1 allows label / hint / help /
/// alert to hold inline host-language markup plus dynamic content
/// (`xf:output`, itext) — see spec 8.3.3's `<xf:label>` example. Returns
/// the child's inner XML (nil when the child is absent; equal to the
/// escaped text for a plain-text child). Setting parses `xml` with the
/// XHTML namespace as the default and the document's XForms prefix (and
/// `xf:`) bound, so fragments like
/// `Name <strong>required</strong> <xf:output value="…"/>` work; nil or
/// empty removes the child, label is inserted first. Undo restores the
/// previous inner XML. Returns NO with `error` when `xml` does not
/// parse; the document is untouched then.
- (BOOL)setSupportChild:(NSString *)localName
             contentXML:(nullable NSString *)xml
              onElement:(XFXMLElement *)element
                  error:(NSError **)error;
- (nullable NSString *)supportChildXML:(NSString *)localName
                             onElement:(XFXMLElement *)element;

/// An attribute of the xf:`localName` support child — the itemset shape,
/// where label / value carry per-node @ref. Setting creates the child
/// when missing (label first); empty removes the attribute (the child
/// stays). nil from the getter = no such child.
- (void)setSupportChildAttribute:(NSString *)attribute
                           child:(NSString *)localName
                           value:(nullable NSString *)value
                       onElement:(XFXMLElement *)element;
- (nullable NSString *)supportChildAttribute:(NSString *)attribute
                                       child:(NSString *)localName
                                   onElement:(XFXMLElement *)element;

/// The element's OWN children as inline mixed content (seam-free, unlike
/// contentXMLOfElement:'s block-shaped "\n" join): what xf:message /
/// xf:setvalue hold directly. Setting parses like
/// setSupportChild:contentXML: (XHTML default namespace, the document's
/// XForms prefix and xf: bound), so message bodies take inline markup and
/// xf:output. Undoable; returns NO with `error` on a parse failure, the
/// document untouched then.
- (BOOL)setInlineContentXML:(nullable NSString *)xml
                  onElement:(XFXMLElement *)element
                      error:(NSError **)error;
- (NSString *)inlineContentXMLOfElement:(XFXMLElement *)element;

/// Replaces the element's children with the parsed `xml` fragment (the
/// instance-data editor's commit). For an instance / bind / submission
/// the element is detached from and re-attached to the processor, so the
/// model re-adopts the new content; anything else gets
/// noteElementChanged:. Undoable — the old content round-trips through
/// its serialization. Returns NO (with `error`) when `xml` does not
/// parse; the document is untouched then.
- (BOOL)setContentXML:(NSString *)xml
            onElement:(XFXMLElement *)element
                error:(NSError **)error;
/// The element's current children, serialized (what setContentXML: edits).
- (NSString *)contentXMLOfElement:(XFXMLElement *)element;

#pragma mark - XPath step building (the designer's node picker)

/// The relative location path from `context` to `target` in the same
/// document: "." for the node itself, "../" per level up to the common
/// ancestor, then child steps by name — with a positional predicate only
/// where same-named siblings make one necessary — and "@name" for an
/// attribute target. nil when the nodes share no document.
+ (nullable NSString *)pathFromNode:(XFXMLNode *)context toNode:(XFXMLNode *)target;

/// The steps from the document element (exclusive) down to `target`,
/// nil-joined for the document element itself — the tail of an
/// "instance('id')/…" or "/data/…" expression. nil when `target` has no
/// document element above it.
+ (nullable NSString *)stepsBelowRootToNode:(XFXMLNode *)target;

@end

NS_ASSUME_NONNULL_END
