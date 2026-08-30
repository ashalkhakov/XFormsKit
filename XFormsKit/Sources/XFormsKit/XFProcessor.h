#import <Foundation/Foundation.h>
#import "XFModel.h"

@class XFInstance;
@class XFControl;
@class XFInputControl;
@class XFOutputControl;
@class XFSelectControl;
@class XFTriggerControl;
@class XFAction;
@class XFAbstractAction;
@class XFGroup;
@class XFRepeat;
@class NSXMLDocument;

@class XFHostNode;

/// Serialise the host document without the whitespace marker comments the
/// parser pre-pass adds inside <body> (see XFProcessor documentFromData:).
FOUNDATION_EXPORT NSString *XFHostXMLString(NSXMLDocument *document, NSUInteger options);
/// The marker comment / its text (`<!--xf:ws-->`).
FOUNDATION_EXPORT NSString * const XFWhitespaceMarkerComment;
FOUNDATION_EXPORT NSString * const XFWhitespaceMarkerText;

NS_ASSUME_NONNULL_BEGIN

@interface XFProcessor : NSObject <XFModelOwner>

@property (nonatomic, strong, readonly) NSXMLDocument *hostDocument;
@property (nonatomic, copy, nullable) NSURL *baseURL;
@property (nonatomic, strong, readonly) XFModel *model;
@property (nonatomic, copy, readonly) NSArray<XFModel *> *models;
@property (nonatomic, copy, readonly) NSArray<XFControl *> *controls;
/// Host-markup tree of the document body (G-20): what the UI lays out.
/// `controls` are the top-level controls found in it, document order.
@property (nonatomic, copy, readonly) NSArray<XFHostNode *> *hostNodes;
/// The element the host tree was built from (`body`, else the root).
@property (nonatomic, strong, readonly, nullable) NSXMLElement *hostRootElement;
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
/// XsltForms_control.focus: blur the previous control (DOMFocusOut), set the
/// repeat index of every repeat item the control sits in, dispatch
/// DOMFocusIn. `fromUI` = the widget already has the keyboard focus (no
/// focusRequestHandler call).
- (void)focusControl:(XFControl *)control fromUI:(BOOL)fromUI;
/// XsltForms_globals.blur(true): DOMFocusOut on the focused control.
- (void)blurFocusedControl;

- (nullable XFAbstractAction *)actionWithIdentifier:(NSString *)identifier;
- (nullable XFRepeat *)repeatWithIdentifier:(NSString *)identifier;

+ (nullable instancetype)processorWithContentsOfURL:(NSURL *)url
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
- (nullable XFModel *)modelContainingNode:(nullable NSXMLNode *)node;


- (void)activateControl:(XFTriggerControl *)control;

- (nullable XFControl *)controlForElement:(NSXMLElement *)element;

/// Live document edits: instantiate / drop / refresh a subtree without
/// reparsing the host document.
- (nullable XFControl *)attachElement:(NSXMLElement *)element error:(NSError **)error;
- (void)detachElement:(NSXMLElement *)element;
- (void)noteElementChanged:(NSXMLElement *)element;

@end

NS_ASSUME_NONNULL_END
