#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XFSubmissionRequest : NSObject
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *URLString;
@property (nonatomic, copy, nullable) NSString *body;
@property (nonatomic, copy, nullable) NSData *bodyData;
@property (nonatomic, copy, nullable) NSString *mediaType;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *headers;
/// Send Basic credentials on the FIRST request instead of waiting for a
/// 401 challenge. Off by default (preemptive Basic is wrong for shared
/// transports); the form author opts in with a
/// `preemptive-authentication="true"` attribute (Orbeon's xxf: spelling
/// accepted), the host by setting it on the request.
@property (nonatomic, assign) BOOL preemptiveAuth;
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

/// The host's credential port (layer 3): the transport asks
/// it when an HTTP challenge arrives; the host reads the Keychain, a
/// secrets file, or shows a login sheet. Secrets never live in the form.
@protocol XFSubmissionAuth <NSObject>
/// Basic / Digest material for `space` (host, port, realm,
/// authenticationMethod). nil = no credentials — the 401/407 flows to
/// xforms-submit-error like any other HTTP error.
- (nullable NSURLCredential *)credentialForProtectionSpace:(NSURLProtectionSpace *)space
                                                   request:(XFSubmissionRequest *)request;
@optional
/// TLS client identity (PKCS#12 data) for `space`. Host only, never from
/// instance XML. Wired where the platform's TLS stack accepts it.
- (nullable NSData *)clientCertificateForSpace:(NSURLProtectionSpace *)space;
/// Full interactive challenge control for hosts that need it (session
/// URL stacks). The default policy never calls this; a host transport
/// subclass may.
/// `disposition` follows NSURLSessionAuthChallengeDisposition's values
/// (spelled as NSInteger: GNUstep ships no NSURLSession header).
- (void)didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
                 completion:(void (^)(NSInteger disposition, NSURLCredential *_Nullable credential))done;
@end

/// One document's cookies (one jar per processor, never the process-shared
/// storage — file: and http: origins must not leak into each other
/// or across documents). Host-keyed: a cookie returns to the host that
/// set it (or subdomains when it carried Domain=), honors Path, Secure,
/// and Max-Age/Expires.
@interface XFCookieJar : NSObject
- (void)storeCookiesFromHeaders:(NSDictionary<NSString *, NSString *> *)headers
                         forURL:(NSURL *)url;
/// The Cookie header value for a request to `url` — nil when no cookie
/// applies.
- (nullable NSString *)cookieHeaderForURL:(NSURL *)url;
/// name / value / domain / path / secure dicts, for inspection (the
/// designer's submission tester shows the jar).
- (NSArray<NSDictionary *> *)allCookies;
- (void)removeAllCookies;
@end

/// In-memory transport for tests: map URL (+ method) → canned response.
@interface XFMapSubmissionTransport : NSObject <XFSubmissionTransport>
@property (nonatomic, strong, readonly) XFSubmissionRequest *lastRequest;
- (void)setResponse:(XFSubmissionResponse *)response forURL:(NSString *)url;
- (void)setXML:(NSString *)xml forURL:(NSString *)url;
- (void)setStatus:(NSInteger)status body:(nullable NSString *)body forURL:(NSString *)url;
@end

/// The HTTP conversation (layer 1): redirects with a hop
/// limit and the browser method rules, a per-transport cookie jar, and
/// 401/407 Basic/Digest challenge-response through the host's
/// XFSubmissionAuth — one retry, then the response flows to
/// xforms-submit-error like any other HTTP error. XFSubmission decides
/// WHAT to send; this decides HOW the conversation runs; the host
/// decides where secrets come from.
@interface XFHTTPSubmissionTransport : NSObject <XFSubmissionTransport>
/// The host's credential port. nil = challenges are never answered.
@property (nonatomic, weak, nullable) id<XFSubmissionAuth> auth;
/// This transport's cookie jar (created lazily). XFProcessor keeps one
/// transport per document, so cookies persist across its submissions.
@property (nonatomic, strong, readonly) XFCookieJar *cookieJar;
/// Redirect hop limit (default 10). The final 3xx is returned when the
/// chain is longer.
@property (nonatomic, assign) NSUInteger maxRedirects;
/// Per-request timeout in seconds (default 30).
@property (nonatomic, assign) NSTimeInterval timeout;

/// ONE request / response exchange, redirects NOT followed (a 3xx comes
/// back as the response) and cookies/auth NOT attached — the policy in
/// performRequest: does all of that. Subclass override point: tests
/// script the conversation here.
- (nullable XFSubmissionResponse *)performSingleRequest:(XFSubmissionRequest *)request
                                                  error:(NSError **)error;
/// The Digest client nonce — random; tests override for reproducible
/// RFC 2617 vectors.
- (NSString *)makeCNonce;
@end

/// Wrapper transport (layer 3): the host injects headers — an Authorization
/// from its own session, an API key — without touching the form markup.
/// Author headers win over injected ones.
@interface XFHeaderInjectingTransport : NSObject <XFSubmissionTransport>
@property (nonatomic, strong) id<XFSubmissionTransport> inner;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *extraHeaders;
@end

NS_ASSUME_NONNULL_END
