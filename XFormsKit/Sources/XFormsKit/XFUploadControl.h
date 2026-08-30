#import <XFormsKit/XFControl.h>

@class XFBinding;

NS_ASSUME_NONNULL_BEGIN

/// `xf:upload`: file → bound node as base64Binary / hexBinary / anyURI / string.
/// Optional `xf:filename` and `xf:mediatype` children bind the name and type.
@interface XFUploadControl : XFControl

@property (nonatomic, strong, nullable) XFBinding *filenameBinding;
@property (nonatomic, strong, nullable) XFBinding *mediatypeBinding;
@property (nonatomic, copy, nullable) NSString *fileName;
@property (nonatomic, copy, nullable) NSString *mediaType;
@property (nonatomic, copy, nullable) NSData *fileData;

+ (nullable instancetype)uploadWithElement:(NSXMLElement *)element
                                     model:(nullable id)model
                                     error:(NSError **)error;

- (BOOL)commitFileAtURL:(NSURL *)url error:(NSError **)error;
- (BOOL)commitFileData:(NSData *)data
              fileName:(nullable NSString *)fileName
             mediaType:(nullable NSString *)mediaType
                 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
