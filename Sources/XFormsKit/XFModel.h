#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFInstance;
@class XFBind;
@class XFSubmission;
@class XFRepeat;
@protocol XFSubmissionTransport;

NS_ASSUME_NONNULL_BEGIN

@protocol XFModelOwner <NSObject>
- (void)refreshControls;
@end

@class XFSubform;

@interface XFModel : NSObject

/// The subform this model was loaded with (nil for the main form), G-90.
@property (nonatomic, weak, nullable) XFSubform *subform;
@property (nonatomic, copy, nullable) NSString *identifier;
@property (nonatomic, strong, nullable) XFXMLElement *element;
@property (nonatomic, weak, nullable) id<XFModelOwner> owner;
@property (nonatomic, copy, readonly) NSArray<XFInstance *> *instances;
@property (nonatomic, copy, readonly) NSArray<XFBind *> *binds;
@property (nonatomic, copy, readonly) NSArray<XFSubmission *> *submissions;
@property (nonatomic, weak, nullable) XFSubmission *defaultSubmission;
@property (nonatomic, copy, readonly) NSArray<XFRepeat *> *repeats;
@property (nonatomic, strong, nullable) id<XFSubmissionTransport> transport;

/// `xf:itext` translations (jsgen/itext.xsl → XsltForms_model.additext):
/// language → (text id → value); `defaultLanguage` is the first
/// translation's @lang — G-94.
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *translations;
@property (nonatomic, copy, readonly, nullable) NSString *defaultLanguage;
/// itext(): the text for `identifier` in `language` (a BCP-47 tag matched
/// exactly, then by primary subtag), else in the default language.
- (nullable NSString *)itextForIdentifier:(NSString *)identifier language:(nullable NSString *)language;

/// After `xforms-ready`. Matches XsltForms_globals.ready for this model.
@property (nonatomic, assign) BOOL ready;
@property (nonatomic, assign) BOOL rebuilded;
/// XSLTForms `newRebuilded`. Not named `new*` — that prefix is an ARC owned-object getter.
@property (nonatomic, assign) BOOL pendingRebuild;
@property (nonatomic, assign) BOOL building;

@property (nonatomic, strong, readonly) NSMutableArray<XFXMLNode *> *nodesChanged;
/// XSLTForms `newNodesChanged`.
@property (nonatomic, strong, readonly) NSMutableArray<XFXMLNode *> *pendingNodesChanged;

+ (nullable instancetype)modelWithElement:(XFXMLElement *)modelElement
                                    error:(NSError **)error;

- (nullable XFInstance *)instanceWithIdentifier:(nullable NSString *)identifier;
- (nullable XFInstance *)defaultInstance;
/// The instance holding `node`, else the default instance.
- (nullable XFInstance *)instanceContainingNode:(nullable XFXMLNode *)node;
/// The instance holding `node`, or nil when no instance of this model does.
- (nullable XFInstance *)instanceOwningNode:(nullable XFXMLNode *)node;
- (nullable XFBind *)bindWithIdentifier:(NSString *)identifier;
- (nullable XFSubmission *)submissionWithIdentifier:(nullable NSString *)identifier;
- (nullable XFRepeat *)repeatWithIdentifier:(nullable NSString *)identifier;
- (void)addRepeat:(XFRepeat *)repeat;

- (void)addBind:(XFBind *)bind;
- (BOOL)adoptElement:(XFXMLElement *)element error:(NSError **)error;
- (void)dropElement:(XFXMLElement *)element;
- (void)addChange:(XFXMLNode *)node;
- (void)setRebuilded:(BOOL)rebuilded;
- (void)swapChangeLists;

- (void)construct;
- (void)rebuild;
- (void)recalculate;
- (void)revalidate;
- (void)refresh;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
