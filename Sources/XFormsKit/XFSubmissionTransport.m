#import "XFSubmissionTransport.h"
#if defined(__APPLE__)
#import <CommonCrypto/CommonDigest.h>
#else
#import <openssl/evp.h>
#endif

@implementation XFSubmissionRequest
- (instancetype)init
{
    self = [super init];
    if (self) {
        _method = @"post";
        _headers = @{};
    }
    return self;
}
@end

@implementation XFSubmissionResponse
- (instancetype)init
{
    self = [super init];
    if (self) {
        _statusCode = 200;
        _headers = @{};
    }
    return self;
}
@end

#pragma mark - Small HTTP helpers

/// Case-insensitive header lookup.
static NSString *XFHeaderValue(NSDictionary<NSString *, NSString *> *headers, NSString *name)
{
    for (NSString *k in headers) {
        if ([k caseInsensitiveCompare:name] == NSOrderedSame) {
            return headers[k];
        }
    }
    return nil;
}

static NSString *XFMD5Hex(NSString *input)
{
    NSData *bytes = [input dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[16];
#if defined(__APPLE__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5(bytes.bytes, (CC_LONG)bytes.length, digest);
#pragma clang diagnostic pop
#else
    unsigned int outlen = 16;
    EVP_Digest(bytes.bytes, bytes.length, digest, &outlen, EVP_md5(), NULL);
#endif
    NSMutableString *hex = [NSMutableString stringWithCapacity:32];
    for (int i = 0; i < 16; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

/// Parse `Basic realm="x"` / `Digest realm="y", nonce="…", qop="auth"` —
/// the scheme word, then comma-separated k=v pairs (values optionally
/// quoted; commas inside quotes belong to the value).
static NSDictionary *XFParseAuthChallenge(NSString *header)
{
    NSString *s = [header stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSRange space = [s rangeOfString:@" "];
    NSString *scheme = space.location == NSNotFound ? s : [s substringToIndex:space.location];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"scheme"] = [scheme lowercaseString];
    if (space.location == NSNotFound) {
        return out;
    }
    NSString *params = [s substringFromIndex:space.location + 1];
    NSUInteger i = 0, n = params.length;
    while (i < n) {
        // key
        NSUInteger eq = i;
        while (eq < n && [params characterAtIndex:eq] != '=') { eq++; }
        if (eq >= n) {
            break;
        }
        NSString *key = [[[params substringWithRange:NSMakeRange(i, eq - i)]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
            lowercaseString];
        i = eq + 1;
        NSString *value = @"";
        if (i < n && [params characterAtIndex:i] == '"') {
            i++;
            NSUInteger start = i;
            while (i < n && [params characterAtIndex:i] != '"') { i++; }
            value = [params substringWithRange:NSMakeRange(start, i - start)];
            if (i < n) { i++; }   // closing quote
        } else {
            NSUInteger start = i;
            while (i < n && [params characterAtIndex:i] != ',') { i++; }
            value = [[params substringWithRange:NSMakeRange(start, i - start)]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        if (key.length) {
            out[key] = value;
        }
        // skip separator
        while (i < n && ([params characterAtIndex:i] == ',' || [params characterAtIndex:i] == ' ')) { i++; }
    }
    return out;
}

static NSString *XFBasicAuthorization(NSURLCredential *credential)
{
    NSString *pair = [NSString stringWithFormat:@"%@:%@",
                      credential.user ?: @"", credential.password ?: @""];
    NSString *b64 = [[pair dataUsingEncoding:NSUTF8StringEncoding]
        base64EncodedStringWithOptions:0];
    return [@"Basic " stringByAppendingString:b64];
}

/// RFC 2617 Digest with MD5 (qop=auth or none) — enough for the servers
/// that still challenge with Digest; the password never travels.
static NSString *XFDigestAuthorization(NSURLCredential *credential,
                                       NSDictionary *challenge,
                                       NSString *method,
                                       NSURL *url,
                                       NSString *cnonce)
{
    NSString *user = credential.user ?: @"";
    NSString *realm = challenge[@"realm"] ?: @"";
    NSString *nonce = challenge[@"nonce"] ?: @"";
    NSString *uri = [url path].length ? [url path] : @"/";
    if ([url query].length) {
        uri = [NSString stringWithFormat:@"%@?%@", uri, [url query]];
    }
    NSString *ha1 = XFMD5Hex([NSString stringWithFormat:@"%@:%@:%@",
                              user, realm, credential.password ?: @""]);
    NSString *ha2 = XFMD5Hex([NSString stringWithFormat:@"%@:%@",
                              [method uppercaseString], uri]);
    BOOL qopAuth = [challenge[@"qop"] length] > 0
        && [[challenge[@"qop"] componentsSeparatedByString:@","] indexOfObjectPassingTest:
            ^BOOL(NSString *q, NSUInteger idx, BOOL *stop) {
                (void)idx; (void)stop;
                return [[q stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]] isEqualToString:@"auth"];
            }] != NSNotFound;
    NSString *nc = @"00000001";
    NSString *response;
    if (qopAuth) {
        response = XFMD5Hex([NSString stringWithFormat:@"%@:%@:%@:%@:auth:%@",
                             ha1, nonce, nc, cnonce, ha2]);
    } else {
        response = XFMD5Hex([NSString stringWithFormat:@"%@:%@:%@", ha1, nonce, ha2]);
    }
    NSMutableString *h = [NSMutableString stringWithFormat:
        @"Digest username=\"%@\", realm=\"%@\", nonce=\"%@\", uri=\"%@\", response=\"%@\"",
        user, realm, nonce, uri, response];
    if (qopAuth) {
        [h appendFormat:@", qop=auth, nc=%@, cnonce=\"%@\"", nc, cnonce];
    }
    if ([challenge[@"opaque"] length]) {
        [h appendFormat:@", opaque=\"%@\"", challenge[@"opaque"]];
    }
    if ([challenge[@"algorithm"] length]) {
        [h appendFormat:@", algorithm=%@", challenge[@"algorithm"]];
    }
    return h;
}

#pragma mark - Cookie jar

@interface XFCookieJar ()
/// host → { name → cookie dict (name value domain path secure expires) }
@property (nonatomic, strong) NSMutableDictionary *store;
@end

@implementation XFCookieJar

- (instancetype)init
{
    self = [super init];
    if (self) {
        _store = [NSMutableDictionary dictionary];
    }
    return self;
}

/// Set-Cookie: NAME=value; Path=/; Domain=.example.com; Max-Age=…;
/// Expires=…; Secure; HttpOnly — one cookie per header line (multiple
/// Set-Cookie lines arrive joined by "\n" from the fetcher).
- (void)storeCookiesFromHeaders:(NSDictionary<NSString *, NSString *> *)headers
                         forURL:(NSURL *)url
{
    NSString *setCookie = XFHeaderValue(headers, @"Set-Cookie");
    NSString *host = [[url host] lowercaseString];
    if (setCookie.length == 0 || host.length == 0) {
        return;
    }
    for (NSString *line in [setCookie componentsSeparatedByString:@"\n"]) {
        NSArray *parts = [line componentsSeparatedByString:@";"];
        NSString *nameValue = [parts.firstObject stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSRange eq = [nameValue rangeOfString:@"="];
        if (eq.location == NSNotFound || eq.location == 0) {
            continue;
        }
        NSString *name = [nameValue substringToIndex:eq.location];
        NSMutableDictionary *cookie = [NSMutableDictionary dictionaryWithDictionary:@{
            @"name": name,
            @"value": [nameValue substringFromIndex:eq.location + 1],
            @"domain": host,        // host-only unless Domain= widens it
            @"hostOnly": @YES,
            @"path": @"/",
        }];
        for (NSString *raw in [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)]) {
            NSString *attr = [raw stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSRange aeq = [attr rangeOfString:@"="];
            NSString *aname = [(aeq.location == NSNotFound ? attr
                : [attr substringToIndex:aeq.location]) lowercaseString];
            NSString *avalue = aeq.location == NSNotFound ? @""
                : [attr substringFromIndex:aeq.location + 1];
            if ([aname isEqualToString:@"domain"] && avalue.length) {
                NSString *domain = [[avalue lowercaseString]
                    hasPrefix:@"."] ? [avalue substringFromIndex:1] : avalue;
                domain = [domain lowercaseString];
                // never accept a domain the setting host is not inside
                if ([host isEqualToString:domain]
                    || [host hasSuffix:[@"." stringByAppendingString:domain]]) {
                    cookie[@"domain"] = domain;
                    cookie[@"hostOnly"] = @NO;
                }
            } else if ([aname isEqualToString:@"path"] && avalue.length) {
                cookie[@"path"] = avalue;
            } else if ([aname isEqualToString:@"secure"]) {
                cookie[@"secure"] = @YES;
            } else if ([aname isEqualToString:@"max-age"]) {
                double age = [avalue doubleValue];
                cookie[@"expires"] = [NSDate dateWithTimeIntervalSinceNow:age];
            } else if ([aname isEqualToString:@"expires"]) {
                // best-effort; an unparsable date keeps the cookie session-scoped
            }
        }
        NSString *key = cookie[@"domain"];
        NSMutableDictionary *forHost = self.store[key];
        if (forHost == nil) {
            forHost = [NSMutableDictionary dictionary];
            self.store[key] = forHost;
        }
        NSDate *expires = cookie[@"expires"];
        if (expires != nil && [expires timeIntervalSinceNow] <= 0) {
            [forHost removeObjectForKey:name];   // Max-Age=0 deletes
        } else {
            forHost[name] = cookie;
        }
    }
}

- (NSString *)cookieHeaderForURL:(NSURL *)url
{
    NSString *host = [[url host] lowercaseString];
    NSString *path = [url path].length ? [url path] : @"/";
    BOOL secure = [[[url scheme] lowercaseString] isEqualToString:@"https"];
    if (host.length == 0) {
        return nil;
    }
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *domain in self.store) {
        BOOL match = [host isEqualToString:domain]
            || [host hasSuffix:[@"." stringByAppendingString:domain]];
        if (!match) {
            continue;
        }
        NSDictionary *forHost = self.store[domain];
        for (NSString *name in forHost) {
            NSDictionary *cookie = forHost[name];
            if ([cookie[@"hostOnly"] boolValue] && ![host isEqualToString:domain]) {
                continue;
            }
            NSDate *expires = cookie[@"expires"];
            if (expires != nil && [expires timeIntervalSinceNow] <= 0) {
                continue;
            }
            if ([cookie[@"secure"] boolValue] && !secure) {
                continue;   // Secure cookies never travel over http
            }
            NSString *cpath = cookie[@"path"] ?: @"/";
            if (!([path isEqualToString:cpath] || [path hasPrefix:
                    [cpath hasSuffix:@"/"] ? cpath : [cpath stringByAppendingString:@"/"]])) {
                continue;
            }
            [pairs addObject:[NSString stringWithFormat:@"%@=%@", name, cookie[@"value"]]];
        }
    }
    return pairs.count ? [pairs componentsJoinedByString:@"; "] : nil;
}

- (NSArray<NSDictionary *> *)allCookies
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *domain in self.store) {
        NSDictionary *forHost = self.store[domain];
        for (NSString *name in forHost) {
            [out addObject:forHost[name]];
        }
    }
    return out;
}

- (void)removeAllCookies
{
    [self.store removeAllObjects];
}

@end

#pragma mark - Map transport (tests)

@interface XFMapSubmissionTransport ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, XFSubmissionResponse *> *map;
@property (nonatomic, strong, readwrite) XFSubmissionRequest *lastRequest;
@end

@implementation XFMapSubmissionTransport

- (instancetype)init
{
    self = [super init];
    if (self) {
        _map = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)keyForURL:(NSString *)url
{
    return url ?: @"";
}

- (void)setResponse:(XFSubmissionResponse *)response forURL:(NSString *)url
{
    self.map[[self keyForURL:url]] = response;
}

- (void)setXML:(NSString *)xml forURL:(NSString *)url
{
    XFSubmissionResponse *r = [[XFSubmissionResponse alloc] init];
    r.statusCode = 200;
    r.body = xml;
    r.mediaType = @"application/xml";
    [self setResponse:r forURL:url];
}

- (void)setStatus:(NSInteger)status body:(NSString *)body forURL:(NSString *)url
{
    XFSubmissionResponse *r = [[XFSubmissionResponse alloc] init];
    r.statusCode = status;
    r.body = body;
    [self setResponse:r forURL:url];
}

- (XFSubmissionResponse *)performRequest:(XFSubmissionRequest *)request error:(NSError **)error
{
    (void)error;
    self.lastRequest = request;
    NSString *key = [self keyForURL:request.URLString];
    XFSubmissionResponse *found = self.map[key];
    if (found == nil) {
        // Allow query-stripped lookup for GET urls.
        NSRange q = [key rangeOfString:@"?"];
        if (q.location != NSNotFound) {
            found = self.map[[key substringToIndex:q.location]];
        }
    }
    if (found == nil) {
        XFSubmissionResponse *missing = [[XFSubmissionResponse alloc] init];
        missing.statusCode = 404;
        missing.errorType = @"resource-error";
        missing.body = @"";
        return missing;
    }
    return found;
}

@end

#pragma mark - One HTTP exchange (delegate-driven, redirects NOT followed)

/// Collects one exchange on the current thread's run loop. The redirect
/// hook refuses every redirect — the 3xx response itself is the result;
/// the policy loop above decides whether and how to follow.
@interface XFHTTPFetch : NSObject
@property (nonatomic, strong) NSHTTPURLResponse *response;
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, assign) BOOL done;
@property (nonatomic, strong) NSURLConnection *connection;
@end

@implementation XFHTTPFetch

- (NSURLRequest *)connection:(NSURLConnection *)connection
             willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)redirectResponse
{
    if (redirectResponse == nil) {
        return request;   // the initial (canonical) call
    }
    if ([redirectResponse isKindOfClass:[NSHTTPURLResponse class]]) {
        self.response = (NSHTTPURLResponse *)redirectResponse;
    }
    self.done = YES;
    [connection cancel];
    return nil;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    (void)connection;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        self.response = (NSHTTPURLResponse *)response;
    }
    self.data = [NSMutableData data];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    (void)connection;
    [self.data appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    (void)connection;
    self.done = YES;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    (void)connection;
    self.error = error;
    self.done = YES;
}

@end

#pragma mark - HTTP transport (the conversation policy)

static NSString * const XFHTTPTransportRunLoopMode = @"XFHTTPSubmissionTransportMode";

@interface XFHTTPSubmissionTransport ()
@property (nonatomic, strong, readwrite) XFCookieJar *cookieJar;
@end

@implementation XFHTTPSubmissionTransport

- (instancetype)init
{
    self = [super init];
    if (self) {
        _maxRedirects = 10;
        _timeout = 30;
    }
    return self;
}

- (XFCookieJar *)cookieJar
{
    if (_cookieJar == nil) {
        _cookieJar = [[XFCookieJar alloc] init];
    }
    return _cookieJar;
}

- (NSString *)makeCNonce
{
    return [NSString stringWithFormat:@"%08x%08x", arc4random(), arc4random()];
}

- (XFSubmissionResponse *)performSingleRequest:(XFSubmissionRequest *)request
                                         error:(NSError **)error
{
    NSURL *url = [NSURL URLWithString:request.URLString];
    if (url == nil) {
        if (error) {
            *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
        }
        return nil;
    }
    if ([url isFileURL] && [[request.method lowercaseString] isEqualToString:@"get"]) {
        // XSLTForms special-cases file: in submit rather than trusting
        // XMLHttpRequest with it; NSURLConnection's file loader differs
        // per Foundation too (Apple refuses a file URL carrying the GET
        // query string, 11.9.n) — read the file directly, ignoring the
        // query like an HTTP file server would.
        NSString *path = [url path] ?: @"";
        NSData *data = path.length ? [NSData dataWithContentsOfFile:path] : nil;
        XFSubmissionResponse *out = [[XFSubmissionResponse alloc] init];
        out.statusCode = data ? 200 : 404;
        out.headers = @{};
        out.body = data ? ([[NSString alloc] initWithData:data
                                                 encoding:NSUTF8StringEncoding] ?: @"") : @"";
        return out;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = [request.method uppercaseString] ?: @"GET";
    req.timeoutInterval = self.timeout > 0 ? self.timeout : 30;
    // the process-shared cookie storage never sees this document's
    // traffic — the jar above is the only cookie authority
    [req setHTTPShouldHandleCookies:NO];
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    if (![[req.HTTPMethod lowercaseString] isEqualToString:@"get"]) {
        if (request.bodyData.length) {
            req.HTTPBody = request.bodyData;
        } else if (request.body.length) {
            req.HTTPBody = [request.body dataUsingEncoding:NSUTF8StringEncoding];
        }
    }
    // the author's own Content-Type header wins over the serialization's
    if (request.mediaType.length
        && XFHeaderValue(request.headers, @"Content-Type") == nil) {
        [req setValue:request.mediaType forHTTPHeaderField:@"Content-Type"];
    }
    [request.headers enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        (void)stop;
        [req setValue:v forHTTPHeaderField:k];
    }];

    XFHTTPFetch *fetch = [[XFHTTPFetch alloc] init];
    NSURLConnection *conn = [[NSURLConnection alloc] initWithRequest:req
                                                            delegate:fetch
                                                    startImmediately:NO];
    if (conn == nil) {
        if (error) {
            *error = [NSError errorWithDomain:NSURLErrorDomain
                                         code:NSURLErrorUnknown userInfo:nil];
        }
        return nil;
    }
    fetch.connection = conn;
    [conn scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:XFHTTPTransportRunLoopMode];
    [conn start];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:(self.timeout > 0 ? self.timeout : 30) + 5];
    while (!fetch.done && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:XFHTTPTransportRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    if (!fetch.done) {
        [conn cancel];
        if (error) {
            *error = [NSError errorWithDomain:NSURLErrorDomain
                                         code:NSURLErrorTimedOut userInfo:nil];
        }
        return nil;
    }
    if (fetch.error != nil && fetch.response == nil) {
        if (error) {
            *error = fetch.error;
        }
        return nil;
    }

    XFSubmissionResponse *out = [[XFSubmissionResponse alloc] init];
    NSHTTPURLResponse *http = fetch.response;
    if (http != nil) {
        out.statusCode = http.statusCode;
        NSMutableDictionary *hdrs = [NSMutableDictionary dictionary];
        [http.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            (void)stop;
            hdrs[[key description]] = [obj description];
        }];
        out.headers = hdrs;
        out.mediaType = http.MIMEType;
    }
    out.body = fetch.data ? [[NSString alloc] initWithData:fetch.data
                                                  encoding:NSUTF8StringEncoding] ?: @"" : @"";
    return out;
}

- (NSURLProtectionSpace *)protectionSpaceForURL:(NSURL *)url
                                      challenge:(NSDictionary *)challenge
                                          proxy:(BOOL)proxy
{
    NSString *method = [challenge[@"scheme"] isEqualToString:@"digest"]
        ? NSURLAuthenticationMethodHTTPDigest
        : NSURLAuthenticationMethodHTTPBasic;
    NSInteger port = [url.port integerValue];
    if (port == 0) {
        port = [[url.scheme lowercaseString] isEqualToString:@"https"] ? 443 : 80;
    }
    (void)proxy;
    return [[NSURLProtectionSpace alloc] initWithHost:url.host ?: @""
                                                 port:port
                                             protocol:url.scheme ?: @"http"
                                                realm:challenge[@"realm"]
                                 authenticationMethod:method];
}

- (XFSubmissionResponse *)performRequest:(XFSubmissionRequest *)request error:(NSError **)error
{
    if (request.URLString.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
        }
        return nil;
    }
    NSURL *url = [NSURL URLWithString:request.URLString];
    if (url == nil) {
        if (error) {
            *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
        }
        return nil;
    }
    NSString *scheme = [url.scheme lowercaseString];
    if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
        // file: and friends: one plain exchange, no cookies, no auth
        return [self performSingleRequest:request error:error];
    }

    // the working copy the hops mutate (303 → GET etc.); the caller's
    // request is never touched
    NSString *method = request.method ?: @"get";
    NSString *body = request.body;
    NSData *bodyData = request.bodyData;
    NSString *mediaType = request.mediaType;
    NSDictionary *authorHeaders = request.headers ?: @{};
    NSURL *origin = url;
    BOOL strippedAuthor = NO;     // Authorization dropped after a cross-origin hop
    NSString *challengeAuth = nil;
    NSString *challengeAuthHeader = @"Authorization";
    BOOL triedAuth = NO;
    NSUInteger hops = 0;
    XFSubmissionResponse *resp = nil;

    for (;;) {
        XFSubmissionRequest *hop = [[XFSubmissionRequest alloc] init];
        hop.method = method;
        hop.URLString = [url absoluteString];
        hop.body = body;
        hop.bodyData = bodyData;
        hop.mediaType = mediaType;
        NSMutableDictionary *headers = [authorHeaders mutableCopy];
        if (strippedAuthor) {
            for (NSString *k in [headers allKeys]) {
                if ([k caseInsensitiveCompare:@"Authorization"] == NSOrderedSame) {
                    [headers removeObjectForKey:k];
                }
            }
        }
        NSString *cookie = [self.cookieJar cookieHeaderForURL:url];
        if (cookie.length) {
            NSString *authored = XFHeaderValue(headers, @"Cookie");
            headers[@"Cookie"] = authored.length
                ? [NSString stringWithFormat:@"%@; %@", authored, cookie] : cookie;
        }
        if (challengeAuth.length) {
            headers[challengeAuthHeader] = challengeAuth;
        } else if (request.preemptiveAuth && self.auth != nil
                   && XFHeaderValue(headers, @"Authorization") == nil) {
            // preemptive Basic — only when explicitly asked for
            NSURLProtectionSpace *space =
                [self protectionSpaceForURL:url challenge:@{ @"scheme": @"basic" } proxy:NO];
            NSURLCredential *cred = [self.auth credentialForProtectionSpace:space request:request];
            if (cred.user.length) {
                headers[@"Authorization"] = XFBasicAuthorization(cred);
            }
        }
        hop.headers = headers;

        resp = [self performSingleRequest:hop error:error];
        if (resp == nil) {
            return nil;
        }
        [self.cookieJar storeCookiesFromHeaders:resp.headers forURL:url];

        NSInteger status = resp.statusCode;
        if ((status == 401 || status == 407) && !triedAuth && self.auth != nil) {
            BOOL proxy = status == 407;
            NSString *challengeLine = XFHeaderValue(resp.headers,
                proxy ? @"Proxy-Authenticate" : @"WWW-Authenticate");
            NSDictionary *challenge = challengeLine.length
                ? XFParseAuthChallenge(challengeLine) : nil;
            NSString *authScheme = challenge[@"scheme"];
            if ([authScheme isEqualToString:@"basic"] || [authScheme isEqualToString:@"digest"]) {
                NSURLProtectionSpace *space =
                    [self protectionSpaceForURL:url challenge:challenge proxy:proxy];
                NSURLCredential *cred =
                    [self.auth credentialForProtectionSpace:space request:request];
                if (cred.user.length) {
                    challengeAuth = [authScheme isEqualToString:@"digest"]
                        ? XFDigestAuthorization(cred, challenge, method, url, [self makeCNonce])
                        : XFBasicAuthorization(cred);
                    challengeAuthHeader = proxy ? @"Proxy-Authorization" : @"Authorization";
                    triedAuth = YES;   // exactly one retry, then the 401/407
                                       // flows to xforms-submit-error
                    continue;
                }
            }
            break;
        }

        BOOL redirect = status == 301 || status == 302 || status == 303
            || status == 307 || status == 308;
        NSString *location = XFHeaderValue(resp.headers, @"Location");
        if (redirect && location.length && hops < self.maxRedirects) {
            NSURL *next = [[NSURL URLWithString:location relativeToURL:url] absoluteURL];
            if (next == nil) {
                break;
            }
            BOOL sameOrigin = [[next.scheme lowercaseString]
                    isEqualToString:[origin.scheme lowercaseString]]
                && [[next.host lowercaseString] isEqualToString:[origin.host lowercaseString]]
                && [next.port ?: @80 isEqual:origin.port ?: @80];
            NSString *lower = [method lowercaseString];
            if (status == 303
                || ((status == 301 || status == 302)
                    && !([lower isEqualToString:@"get"] || [lower isEqualToString:@"head"]))) {
                // 303 always becomes GET; browsers rewrite 301/302 POST the
                // same way — the body is NEVER replayed on a naive follow
                method = @"get";
                body = nil;
                bodyData = nil;
                mediaType = nil;
            }
            if (!sameOrigin) {
                // credentials never leak across origins: the author's
                // Authorization stays behind, a challenge may start over
                strippedAuthor = YES;
                challengeAuth = nil;
                triedAuth = NO;
            }
            url = next;
            hops++;
            continue;
        }
        break;
    }
    return resp;
}

@end

#pragma mark - Header-injecting wrapper (host session headers)

@implementation XFHeaderInjectingTransport

- (XFSubmissionResponse *)performRequest:(XFSubmissionRequest *)request error:(NSError **)error
{
    XFSubmissionRequest *wrapped = [[XFSubmissionRequest alloc] init];
    wrapped.method = request.method;
    wrapped.URLString = request.URLString;
    wrapped.body = request.body;
    wrapped.bodyData = request.bodyData;
    wrapped.mediaType = request.mediaType;
    wrapped.preemptiveAuth = request.preemptiveAuth;
    NSMutableDictionary *headers = [request.headers mutableCopy] ?: [NSMutableDictionary dictionary];
    [self.extraHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        (void)stop;
        // the form author's own header wins over the injected one
        if (XFHeaderValue(headers, k) == nil) {
            headers[k] = v;
        }
    }];
    wrapped.headers = headers;
    return [self.inner performRequest:wrapped error:error];
}

@end
