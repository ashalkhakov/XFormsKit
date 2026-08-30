#import "XFSubmissionTransport.h"

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

@implementation XFHTTPSubmissionTransport

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
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = [request.method uppercaseString] ?: @"GET";
    if (request.body.length && ![[req.HTTPMethod lowercaseString] isEqualToString:@"get"]) {
        req.HTTPBody = [request.body dataUsingEncoding:NSUTF8StringEncoding];
    }
    if (request.mediaType.length) {
        [req setValue:request.mediaType forHTTPHeaderField:@"Content-Type"];
    }
    [request.headers enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        (void)stop;
        [req setValue:v forHTTPHeaderField:k];
    }];
    NSURLResponse *urlResp = nil;
    NSError *inner = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:req returningResponse:&urlResp error:&inner];
    if (inner) {
        if (error) {
            *error = inner;
        }
        return nil;
    }
    XFSubmissionResponse *out = [[XFSubmissionResponse alloc] init];
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)urlResp;
    if ([http isKindOfClass:[NSHTTPURLResponse class]]) {
        out.statusCode = http.statusCode;
        NSMutableDictionary *hdrs = [NSMutableDictionary dictionary];
        [http.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            (void)stop;
            hdrs[[key description]] = [obj description];
        }];
        out.headers = hdrs;
        out.mediaType = http.MIMEType;
    } else {
        out.statusCode = 200;
    }
    out.body = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
    return out;
}

@end
