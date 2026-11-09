#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFBind;

NS_ASSUME_NONNULL_BEGIN

/// Per-instance-node MIP bag (XsltForms_browser.getMeta / setMeta / setBoolMeta).
@interface XFNodeState : NSObject

@property (nonatomic, strong) NSMutableArray<NSString *> *bindIdentifiers;
@property (nonatomic, copy, nullable) NSString *typeName;
@property (nonatomic, copy, nullable) NSString *repeatIdentifier;
@property (nonatomic, assign) BOOL relevant;   // default YES
@property (nonatomic, assign) BOOL readonly;   // default NO
@property (nonatomic, assign) BOOL required;   // default NO
@property (nonatomic, assign) BOOL valid;      // default YES
@property (nonatomic, assign) BOOL constraint; // default YES
/// What the host said of the node after a refused submission (a server's
/// rule, a store's validation): the control shows it as its alert and is
/// invalid until the node's value changes. Not a MIP: it never blocks a
/// submission, the host's own refusal does (-[XFModel setHostError:forNode:]).
@property (nonatomic, copy, nullable) NSString *hostError;
/// A warning: shown at the control, never invalid, never in the way of a
/// submission. The host's (-[XFModel setHostWarning:forNode:]) wins over
/// the document's (an `xfk:warning` whose test holds).
@property (nonatomic, copy, nullable) NSString *hostWarning;
@property (nonatomic, copy, nullable) NSString *documentWarning;
/// Set by `xf:upload` so multipart serialization can emit a file part.
@property (nonatomic, copy, nullable) NSString *fileName;
@property (nonatomic, copy, nullable) NSString *mediaType;
@property (nonatomic, copy, nullable) NSData *fileData;

+ (instancetype)stateOnNode:(XFXMLNode *)node;
+ (nullable instancetype)existingStateOnNode:(XFXMLNode *)node;
+ (void)attachBind:(NSString *)bindIdentifier toNode:(XFXMLNode *)node;

@end

NS_ASSUME_NONNULL_END
