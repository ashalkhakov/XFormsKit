#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const XFErrorDomain;

enum {
    XFErrorDocument = 1,
    XFErrorXPathSyntax,
    XFErrorXPathEvaluation,
    XFErrorBinding,
    XFErrorUnsupported
};
typedef NSInteger XFErrorCode;

NS_ASSUME_NONNULL_END
