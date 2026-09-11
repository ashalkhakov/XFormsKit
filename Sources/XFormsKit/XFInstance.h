#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFModel;

NS_ASSUME_NONNULL_BEGIN

@interface XFInstance : NSObject

@property (nonatomic, copy, nullable) NSString *identifier;
@property (nonatomic, strong, nullable) XFXMLElement *element;
@property (nonatomic, weak, nullable) XFModel *model;
@property (nonatomic, copy, nullable) NSString *src;
/// `readonly="true"`: the instance is never validated (XsltForms_instance
/// revalidate), G-55.
@property (nonatomic, assign) BOOL readonly;
/// `mediatype` (attribute, parameters stripped): application/xml (default),
/// application/json | text/json, text/csv (`;header=present;separator=,`).
/// JSON and CSV sources are converted to XML like XsltForms_browser.json2xml
/// / csv2xml (exml:anonymous documents), G-55.
@property (nonatomic, copy, nullable) NSString *mediatype;
@property (nonatomic, assign) BOOL csvHeader;
@property (nonatomic, copy, nullable) NSString *csvSeparator;

/// XsltForms_browser.json2xml / csv2xml: XML text for foreign data.
+ (nullable NSString *)xmlStringFromJSONData:(NSData *)data error:(NSError **)error;
+ (NSString *)xmlStringFromCSV:(NSString *)csv separator:(NSString *)separator header:(BOOL)header;
/// Inverse conversions for submission bodies (XsltForms_browser.xml2json /
/// xml2csv, G-97). `jsonStringFromNode:` is the exact inverse of
/// `xmlStringFromJSONData:` and emits strict JSON (XSLTForms emits a JS
/// literal with unquoted keys and `new Date(...)`); `csvStringFromNode:`
/// writes one line per child element of `node`, the first one's child names
/// as the header ("field decimal" separators as in @separator).
+ (NSString *)jsonStringFromNode:(XFXMLNode *)node;
+ (NSString *)csvStringFromNode:(XFXMLNode *)node separator:(nullable NSString *)separator;
@property (nonatomic, copy, nullable) NSURL *baseURL;
/// Inline content held MORE than one top-level element (only the first
/// became the root): an xforms-link-exception at construct (3.3.2.g/h).
@property (nonatomic, assign) BOOL inlineContentMalformed;
@property (nonatomic, strong, readonly) XFXMLDocument *document;
@property (nonatomic, strong, readonly) XFXMLDocument *originalDocument;

+ (nullable instancetype)instanceWithElement:(XFXMLElement *)instanceElement
                                       error:(NSError **)error;

- (XFXMLElement *)documentElement;
- (void)construct;
/// Re-reads the inline data document from the host element (the designer
/// edited the instance content in place): both the live document and the
/// reset baseline are replaced by a fresh standalone copy.
- (void)reloadInlineDocument;
- (void)reset;
- (void)revalidate;
/// XsltForms_instance.setDoc: replace the live document from a submission/load response.
- (BOOL)replaceWithXMLString:(NSString *)xml error:(NSError **)error;
/// Replace one element (or the whole instance if it is the document element).
- (BOOL)replaceNode:(XFXMLNode *)node withXMLString:(NSString *)xml error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
