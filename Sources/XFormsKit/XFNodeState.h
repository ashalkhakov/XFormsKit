#import <Foundation/Foundation.h>

@class NSXMLNode;
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

+ (instancetype)stateOnNode:(NSXMLNode *)node;
+ (nullable instancetype)existingStateOnNode:(NSXMLNode *)node;
+ (void)attachBind:(NSString *)bindIdentifier toNode:(NSXMLNode *)node;

@end

NS_ASSUME_NONNULL_END
