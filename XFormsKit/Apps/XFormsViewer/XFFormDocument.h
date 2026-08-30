#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface XFFormDocument : NSDocument

@property (nonatomic, copy, nullable) NSString *sourceXML;
@property (nonatomic, strong, nullable) XFProcessor *processor;
@property (nonatomic, copy, nullable) NSError *loadError;

+ (NSString *)blankXML;

- (BOOL)reloadProcessor:(NSError **)error;
- (BOOL)replaceHostWithXMLString:(NSString *)xml error:(NSError **)error;
- (BOOL)commitHostTree:(NSError **)error;
- (void)markHostEdited;

- (nullable NSXMLElement *)hostRoot;
- (nullable NSXMLElement *)modelElement;
- (nullable NSXMLElement *)bodyElement;
- (nullable NSXMLElement *)elementWithID:(NSString *)identifier;
- (NSString *)uniqueIdentifierWithPrefix:(NSString *)prefix;

- (NSString *)instanceXMLString;
- (NSString *)hostXMLString;

@end

NS_ASSUME_NONNULL_END
