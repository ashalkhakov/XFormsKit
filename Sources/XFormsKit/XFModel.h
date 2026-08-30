#import <Foundation/Foundation.h>

@class XFInstance;
@class XFBind;
@class XFSubmission;
@class XFRepeat;
@class NSXMLElement;
@class NSXMLNode;
@protocol XFSubmissionTransport;

NS_ASSUME_NONNULL_BEGIN

@protocol XFModelOwner <NSObject>
- (void)refreshControls;
@end

@interface XFModel : NSObject

@property (nonatomic, copy, nullable) NSString *identifier;
@property (nonatomic, strong, nullable) NSXMLElement *element;
@property (nonatomic, weak, nullable) id<XFModelOwner> owner;
@property (nonatomic, copy, readonly) NSArray<XFInstance *> *instances;
@property (nonatomic, copy, readonly) NSArray<XFBind *> *binds;
@property (nonatomic, copy, readonly) NSArray<XFSubmission *> *submissions;
@property (nonatomic, weak, nullable) XFSubmission *defaultSubmission;
@property (nonatomic, copy, readonly) NSArray<XFRepeat *> *repeats;
@property (nonatomic, strong, nullable) id<XFSubmissionTransport> transport;

@property (nonatomic, assign) BOOL ready;
@property (nonatomic, assign) BOOL rebuilded;
@property (nonatomic, assign) BOOL newRebuilded;
@property (nonatomic, assign) BOOL building;

@property (nonatomic, strong, readonly) NSMutableArray<NSXMLNode *> *nodesChanged;
@property (nonatomic, strong, readonly) NSMutableArray<NSXMLNode *> *newNodesChanged;

+ (nullable instancetype)modelWithElement:(NSXMLElement *)modelElement
                                    error:(NSError **)error;

- (nullable XFInstance *)instanceWithIdentifier:(nullable NSString *)identifier;
- (nullable XFInstance *)defaultInstance;
- (nullable XFInstance *)instanceContainingNode:(nullable NSXMLNode *)node;
- (nullable XFBind *)bindWithIdentifier:(NSString *)identifier;
- (nullable XFSubmission *)submissionWithIdentifier:(nullable NSString *)identifier;
- (nullable XFRepeat *)repeatWithIdentifier:(nullable NSString *)identifier;
- (void)addRepeat:(XFRepeat *)repeat;

- (void)addBind:(XFBind *)bind;
- (void)addChange:(NSXMLNode *)node;
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
