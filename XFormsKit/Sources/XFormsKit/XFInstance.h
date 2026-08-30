#import <Foundation/Foundation.h>

@class NSXMLDocument;
@class NSXMLElement;
@class NSXMLNode;
@class XFModel;

NS_ASSUME_NONNULL_BEGIN

@interface XFInstance : NSObject

@property (nonatomic, copy, nullable) NSString *identifier;
@property (nonatomic, strong, nullable) NSXMLElement *element;
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
@property (nonatomic, copy, nullable) NSURL *baseURL;
@property (nonatomic, strong, readonly) NSXMLDocument *document;
@property (nonatomic, strong, readonly) NSXMLDocument *originalDocument;

+ (nullable instancetype)instanceWithElement:(NSXMLElement *)instanceElement
                                       error:(NSError **)error;

- (NSXMLElement *)documentElement;
- (void)construct;
- (void)reset;
- (void)revalidate;
/// XsltForms_instance.setDoc: replace the live document from a submission/load response.
- (BOOL)replaceWithXMLString:(NSString *)xml error:(NSError **)error;
/// Replace one element (or the whole instance if it is the document element).
- (BOOL)replaceNode:(NSXMLNode *)node withXMLString:(NSString *)xml error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
