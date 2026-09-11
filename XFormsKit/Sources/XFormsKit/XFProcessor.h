#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>
#import "XFModel.h"

@class XFInstance;
@class XFControl;
@class XFDialog;
@class XFSubform;
@class XFExprContext;
@class XFInputControl;
@class XFOutputControl;
@class XFSelectControl;
@class XFTriggerControl;
@class XFAction;
@class XFAbstractAction;
@class XFGroup;
@class XFRepeat;

@class XFHostNode;

/// Serialise the host document without the whitespace marker comments the
/// parser pre-pass adds inside <body> (see XFProcessor documentFromData:).
FOUNDATION_EXPORT NSString *XFHostXMLString(XFXMLDocument *document, NSUInteger options);
/// The marker comment / its text (`<!--xf:ws-->`).
FOUNDATION_EXPORT NSString * const XFWhitespaceMarkerComment;
FOUNDATION_EXPORT NSString * const XFWhitespaceMarkerText;

NS_ASSUME_NONNULL_BEGIN

@class XFHTTPSubmissionTransport;

@interface XFProcessor : NSObject <XFModelOwner>

@property (nonatomic, strong, readonly) XFXMLDocument *hostDocument;
@property (nonatomic, copy, nullable) NSURL *baseURL;
@property (nonatomic, strong, readonly) XFModel *model;
@property (nonatomic, copy, readonly) NSArray<XFModel *> *models;
@property (nonatomic, copy, readonly) NSArray<XFControl *> *controls;
/// Host-markup tree of the document body (G-20): what the UI lays out.
/// `controls` are the top-level controls found in it, document order.
@property (nonatomic, copy, readonly) NSArray<XFHostNode *> *hostNodes;
/// The element the host tree was built from (`body`, else the root).
@property (nonatomic, strong, readonly, nullable) XFXMLElement *hostRootElement;
@property (nonatomic, copy, readonly) NSArray<XFInputControl *> *inputControls;
@property (nonatomic, copy, readonly) NSArray<XFOutputControl *> *outputControls;
@property (nonatomic, copy, readonly) NSArray<XFAbstractAction *> *actions;
@property (nonatomic, copy, readonly) NSArray<XFGroup *> *groups;
@property (nonatomic, copy, readonly) NSArray<XFRepeat *> *repeats;

/// The control holding the XForms focus (XsltForms_globals.focus), G-24.
@property (nonatomic, weak, readonly, nullable) XFControl *focusedControl;
/// Called when the engine moves the focus (xf:setfocus, xforms-focus):
/// hosts make the control's widget first responder.
@property (nonatomic, copy, nullable) void (^focusRequestHandler)(XFControl *control);
/// Host hook for xf:message (G-51): text and level (modal | modeless |
/// ephemeral). Without a handler messages queue in XFDeferredUpdates.messages.
@property (nonatomic, copy, nullable) void (^messageHandler)(NSString *text, NSString *level);
/// Host hook for xf:load with show="new" | "replace" and no @instance
/// (G-50): open the URL. Return YES when handled.
@property (nonatomic, copy, nullable) BOOL (^loadRequestHandler)(NSURL *url, NSString *show);
/// Host hook for xforms-help (G-62): show the control's help (help/@href
/// when set).
@property (nonatomic, copy, nullable) void (^helpRequestHandler)(XFControl *control);
/// Subforms embedded with `xf:load show="embed"` (G-90), load order.
@property (nonatomic, copy, readonly) NSArray<XFSubform *> *subforms;
/// XsltForms_load.run (embed): fetch the XForms document at `url` and embed
/// it into the host element with id `targetID`, replacing its content (and
/// a subform previously loaded there). The subform's models join `models`
/// and get xforms-model-construct(-done) and xforms-subform-ready. nil with
/// an error when the document cannot be loaded or the target is unknown.
- (nullable XFSubform *)loadSubformAtURL:(NSURL *)url intoTargetID:(NSString *)targetID error:(NSError **)error;
/// Like loadSubformAtURL:intoTargetID:error: with the loading action's
/// in-scope context node. When the target lies inside an xf:repeat
/// template that node scopes the subform to ITS repeat item — XSLTForms
/// resolves targetid to the current item's DOM clone; XFormsKit shares
/// one template element, so the owner keeps each item's subform its own.
- (nullable XFSubform *)loadSubformAtURL:(NSURL *)url
                            intoTargetID:(NSString *)targetID
                             contextNode:(nullable XFXMLNode *)contextNode
                                   error:(NSError **)error;
/// XsltForms_subform.dispose (xf:unload): remove the subform loaded into the
/// element with id `targetID`. Returns NO when none is loaded there.
- (BOOL)unloadSubformAtTargetID:(NSString *)targetID;
/// Context-aware unload: inside a repeat template only the item owning
/// the subform unloads (the writers.xhtml Show/Hide pair).
- (BOOL)unloadSubformAtTargetID:(NSString *)targetID
                    contextNode:(nullable XFXMLNode *)contextNode;
/// The subform whose imported content holds `element` (nil = main form).
- (nullable XFSubform *)subformContainingElement:(XFXMLNode *)element;
/// The document's default HTTP transport (created lazily): ONE per
/// processor, so its cookie jar and credential retries persist across
/// this document's submissions and loads (never the process-shared
/// cookie storage). A model.transport override still wins per model;
/// hosts set auth / inject headers here.
@property (nonatomic, strong, readonly) XFHTTPSubmissionTransport *defaultTransport;

/// XsltForms_globals.language: the language used by itext() (G-94). nil =
/// the user's preferred language (NSLocale).
@property (nonatomic, copy, nullable) NSString *language;
/// The language itext() resolves against: `language`, else the first
/// preferred language of the user.
- (NSString *)effectiveLanguage;
/// Host hook for ajx:confirm (G-95): return NO to stop the event.
@property (nonatomic, copy, nullable) BOOL (^confirmHandler)(NSString *text);
/// Host hook for xf:dialog (G-93): present (`show` = YES) or dismiss the
/// dialog's content when xforms-dialog-open / -close reach it.
@property (nonatomic, copy, nullable) void (^dialogRequestHandler)(XFDialog *dialog, BOOL show);
/// XsltForms_control.focus: blur the previous control (DOMFocusOut), set the
/// repeat index of every repeat item the control sits in, dispatch
/// DOMFocusIn. `fromUI` = the widget already has the keyboard focus (no
/// focusRequestHandler call).
- (void)focusControl:(XFControl *)control fromUI:(BOOL)fromUI;
/// XsltForms_globals.blur(true): DOMFocusOut on the focused control.
- (void)blurFocusedControl;
/// XsltForms_globals.close: run every xforms-model-destruct listener (one
/// action) and drop the registrations; the processor is unusable after
/// this (G-54). Hosts call it when a form document closes.
- (void)close;

- (nullable XFAbstractAction *)actionWithIdentifier:(NSString *)identifier;
- (nullable XFRepeat *)repeatWithIdentifier:(NSString *)identifier;
/// The control whose element has this id (any depth; the template control
/// for repeat content).
- (nullable XFControl *)controlWithIdentifier:(NSString *)identifier;

+ (nullable instancetype)processorWithContentsOfURL:(NSURL *)url
                                              error:(NSError **)error;

/// Like processorWithXMLString:error: with a base URL for the relative
/// references resolved DURING construction — instance/@src, xf:include,
/// schemas, submission resources. Setting .baseURL afterwards is too
/// late for those (they have already resolved), so any host that knows
/// where the document came from must construct through this.
+ (nullable instancetype)processorWithXMLString:(NSString *)xml
                                        baseURL:(nullable NSURL *)baseURL
                                          error:(NSError **)error;
+ (nullable instancetype)processorWithXMLString:(NSString *)xml
                                          error:(NSError **)error;

- (nullable XFInstance *)defaultInstance;
- (BOOL)refresh:(NSError **)error;
- (void)refreshControls;

/// Writes `value` into the control's bound node and refreshes the form.
- (BOOL)setValue:(NSString *)value
      ofControl:(XFControl *)control
          error:(NSError **)error;
/// Run the deferred-update cycle for a control that already wrote its bound
/// node itself (select/select1, range, date input, upload): records the
/// change on the model, dispatches `xforms-value-changed`, then
/// rebuild/recalculate/revalidate/refresh as needed.
- (void)controlDidChangeValue:(XFControl *)control;
/// The model whose instances hold `node` (nil if none).
- (nullable XFModel *)modelContainingNode:(nullable XFXMLNode *)node;


- (void)activateControl:(XFTriggerControl *)control;

- (nullable XFControl *)controlForElement:(XFXMLElement *)element;

/// Live document edits: instantiate / drop / refresh a subtree without
/// reparsing the host document.
- (nullable XFControl *)attachElement:(XFXMLElement *)element error:(NSError **)error;
- (void)detachElement:(XFXMLElement *)element;
- (void)noteElementChanged:(XFXMLElement *)element;

@end

NS_ASSUME_NONNULL_END
