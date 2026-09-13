#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface XFFormDocument : NSDocument

@property (nonatomic, copy, nullable) NSString *sourceXML;
/// Where the document came from — captured at read time (NSDocument sets
/// fileURL only after the read returns) so relative instance/@src,
/// includes and schemas resolve on the very first processor build.
@property (nonatomic, copy, nullable) NSURL *documentBaseURL;
@property (nonatomic, strong, nullable) XFProcessor *processor;
@property (nonatomic, copy, nullable) NSError *loadError;

+ (NSString *)blankXML;

- (BOOL)reloadProcessor:(NSError **)error;
- (BOOL)replaceHostWithXMLString:(NSString *)xml error:(NSError **)error;
- (BOOL)commitHostTree:(NSError **)error;
- (void)markHostEdited;

- (nullable XFXMLElement *)hostRoot;
- (nullable XFXMLElement *)modelElement;
- (nullable XFXMLElement *)bodyElement;
- (nullable XFXMLElement *)elementWithID:(NSString *)identifier;
- (NSString *)uniqueIdentifierWithPrefix:(NSString *)prefix;

- (NSString *)instanceXMLString;
- (NSString *)hostXMLString;

@end

NS_ASSUME_NONNULL_END
