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
/// Set by `xf:upload` so multipart serialization can emit a file part.
@property (nonatomic, copy, nullable) NSString *fileName;
@property (nonatomic, copy, nullable) NSString *mediaType;
@property (nonatomic, copy, nullable) NSData *fileData;

+ (instancetype)stateOnNode:(XFXMLNode *)node;
+ (nullable instancetype)existingStateOnNode:(XFXMLNode *)node;
+ (void)attachBind:(NSString *)bindIdentifier toNode:(XFXMLNode *)node;

@end

NS_ASSUME_NONNULL_END
