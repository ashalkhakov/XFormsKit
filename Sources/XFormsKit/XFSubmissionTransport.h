#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XFSubmissionRequest : NSObject
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *URLString;
@property (nonatomic, copy, nullable) NSString *body;
@property (nonatomic, copy, nullable) NSString *mediaType;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *headers;
@end

@interface XFSubmissionResponse : NSObject
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, copy, nullable) NSString *body;
@property (nonatomic, copy, nullable) NSString *mediaType;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *headers;
@property (nonatomic, copy, nullable) NSString *errorType;
@end

@protocol XFSubmissionTransport <NSObject>
- (nullable XFSubmissionResponse *)performRequest:(XFSubmissionRequest *)request
                                           error:(NSError **)error;
@end

/// In-memory transport for tests: map URL (+ method) → canned response.
@interface XFMapSubmissionTransport : NSObject <XFSubmissionTransport>
@property (nonatomic, strong, readonly) XFSubmissionRequest *lastRequest;
- (void)setResponse:(XFSubmissionResponse *)response forURL:(NSString *)url;
- (void)setXML:(NSString *)xml forURL:(NSString *)url;
- (void)setStatus:(NSInteger)status body:(nullable NSString *)body forURL:(NSString *)url;
@end

/// GET/POST/PUT/DELETE via NSURLConnection (synchronous).
@interface XFHTTPSubmissionTransport : NSObject <XFSubmissionTransport>
@end

NS_ASSUME_NONNULL_END
