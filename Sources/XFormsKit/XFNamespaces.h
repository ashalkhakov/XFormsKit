#import <Foundation/Foundation.h>

/* XFormsKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef XFORMSKIT_EXPORT
#define XFORMSKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

XFORMSKIT_EXPORT NSString * const XFXFormsNamespaceURI;
XFORMSKIT_EXPORT NSString * const XFXHTMLNamespaceURI;
XFORMSKIT_EXPORT NSString * const XFXMLEventsNamespaceURI;
XFORMSKIT_EXPORT NSString * const XFXMLNamespaceURI;
XFORMSKIT_EXPORT NSString * const XFXMLSchemaNamespaceURI;
XFORMSKIT_EXPORT NSString * const XFXMLSchemaInstanceNamespaceURI;
/// XSLTForms extensions (ajx:confirm, …): http://www.ajaxforms.net/2006/ajx
XFORMSKIT_EXPORT NSString * const XFAJXNamespaceURI;

NS_ASSUME_NONNULL_END
