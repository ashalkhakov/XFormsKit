#import <Foundation/Foundation.h>

/* XFormsKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef XFORMSKIT_EXPORT
#define XFORMSKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

XFORMSKIT_EXPORT NSString * const XFErrorDomain;

enum {
    XFErrorDocument = 1,
    XFErrorXPathSyntax,
    XFErrorXPathEvaluation,
    XFErrorBinding,
    XFErrorUnsupported
};
typedef NSInteger XFErrorCode;

NS_ASSUME_NONNULL_END
