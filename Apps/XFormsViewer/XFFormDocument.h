#import <AppKit/AppKit.h>
#import <XFormsKit/XFormsKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface XFFormDocument : NSDocument

@property (nonatomic, copy, nullable) NSString *sourceXML;
@property (nonatomic, strong, nullable) XFProcessor *processor;
@property (nonatomic, copy, nullable) NSError *loadError;

- (BOOL)reloadProcessor:(NSError **)error;
- (NSString *)instanceXMLString;
- (NSString *)hostXMLString;

@end

NS_ASSUME_NONNULL_END
