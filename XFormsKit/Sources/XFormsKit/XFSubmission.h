#import <Foundation/Foundation.h>

@class XFModel;
@class XFInstance;
@class NSXMLElement;
@class XFBinding;
@class XFXPath;
@protocol XFSubmissionTransport;

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_submission.
@interface XFSubmission : NSObject

@property (nonatomic, copy, nullable) NSString *identifier;
@property (nonatomic, strong, readonly) NSXMLElement *element;
@property (nonatomic, weak, nullable) XFModel *model;
@property (nonatomic, copy, nullable) NSString *resource;
@property (nonatomic, strong, nullable) XFXPath *resourceExpr;
@property (nonatomic, copy) NSString *method;
@property (nonatomic, strong, nullable) XFXPath *methodExpr;
@property (nonatomic, copy) NSString *separator;
@property (nonatomic, copy) NSString *replace;
@property (nonatomic, copy, nullable) NSString *instanceID;
@property (nonatomic, copy, nullable) NSString *targetref;
@property (nonatomic, strong, nullable) XFBinding *targetrefBinding;
@property (nonatomic, copy) NSString *serialization;
@property (nonatomic, assign) BOOL asynchronous;
@property (nonatomic, copy, nullable) NSString *lastAllReplacement;
@property (nonatomic, copy, nullable) NSString *mediatype;
@property (nonatomic, assign) BOOL validate;
@property (nonatomic, assign) BOOL relevant;
@property (nonatomic, assign) BOOL pending;
@property (nonatomic, strong, nullable) XFBinding *refBinding;
@property (nonatomic, strong, nullable) id<XFSubmissionTransport> transport;
@property (nonatomic, copy, nullable) NSDictionary *lastEventContext;
@property (nonatomic, copy, nullable) NSString *lastSerialization;
@property (nonatomic, copy, nullable) NSData *lastBodyData;

+ (nullable instancetype)submissionWithElement:(NSXMLElement *)element
                                         model:(XFModel *)model
                                         error:(NSError **)error;

- (void)submit;
- (nullable XFInstance *)targetInstance;
/// Spin the current run loop until `pending` clears or `timeout` elapses.
- (BOOL)waitUntilFinished:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END
