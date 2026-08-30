#import <Foundation/Foundation.h>

@class NSXMLNode;
@class XFBind;

NS_ASSUME_NONNULL_BEGIN

/// Per-instance-node MIP bag (XsltForms_browser.getMeta / setMeta / setBoolMeta).
@interface XFNodeState : NSObject

@property (nonatomic, strong) NSMutableArray<NSString *> *bindIdentifiers;
@property (nonatomic, copy, nullable) NSString *typeName;
@property (nonatomic, copy, nullable) NSString *repeatIdentifier;
@property (nonatomic, assign) BOOL relevant;
@property (nonatomic, assign) BOOL readonly;
@property (nonatomic, assign) BOOL required;
@property (nonatomic, assign) BOOL valid;
@property (nonatomic, assign) BOOL constraint;

+ (instancetype)stateOnNode:(NSXMLNode *)node;
+ (nullable instancetype)existingStateOnNode:(NSXMLNode *)node;
+ (void)attachBind:(NSString *)bindIdentifier toNode:(NSXMLNode *)node;

@end

NS_ASSUME_NONNULL_END
