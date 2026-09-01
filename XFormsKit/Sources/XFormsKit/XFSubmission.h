#import <Foundation/Foundation.h>

@class XFModel;
@class XFInstance;
@class NSXMLElement;
@class XFBinding;
@class XFXPath;
@protocol XFSubmissionTransport;
@class XFSubmissionRequest;

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_submission.
@interface XFSubmission : NSObject

@property (nonatomic, copy, nullable) NSString *identifier;
@property (nonatomic, strong, readonly) NSXMLElement *element;
@property (nonatomic, weak, nullable) XFModel *model;
@property (nonatomic, copy, nullable) NSString *resource;
/// The form document's URL. A relative @resource/@action resolves
/// against it (in XSLTForms the browser resolves XMLHttpRequest URIs
/// against the page; headless, the submission does it itself, the way
/// instance/@src does).
@property (nonatomic, copy, nullable) NSURL *baseURL;
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
/// XML-serialization attributes (XForms 1.1 11.1): the character encoding
/// named in the XML declaration, the standalone declaration ("true"/
/// "false", nil = omitted), and whether the declaration is omitted.
@property (nonatomic, copy, nullable) NSString *encoding;
@property (nonatomic, copy, nullable) NSString *standalone;
@property (nonatomic, assign) BOOL omitXMLDeclaration;
@property (nonatomic, assign) BOOL validate;
@property (nonatomic, assign) BOOL relevant;
/// `cdata-section-elements`: local names whose text is serialised as CDATA (G-58).
@property (nonatomic, copy, nullable) NSArray<NSString *> *cdataSectionElements;
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
/// The exact request `submit` would send from the CURRENT instance state
/// — no events, no validation gate, no state change: the designer's
/// submission tester previews with this.
- (nullable XFSubmissionRequest *)previewRequest;
- (nullable XFInstance *)targetInstance;
/// Spin the current run loop until `pending` clears or `timeout` elapses.
- (BOOL)waitUntilFinished:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END
