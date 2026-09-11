#import <XFormsKit/XFControl.h>
#import <XFormsKit/XFXMLTypes.h>

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

+ (nullable instancetype)uploadWithElement:(XFXMLElement *)element
                                     model:(nullable id)model
                                     error:(NSError **)error;

/// `xf:upload/@mediatype` tokens ("image/*", "application/pdf", …), G-46.
@property (nonatomic, copy, readonly) NSArray<NSString *> *acceptedMediaTypes;
/// YES when `mediaType` matches @mediatype (or there is no restriction).
- (BOOL)acceptsMediaType:(nullable NSString *)mediaType;
- (BOOL)commitFileAtURL:(NSURL *)url error:(NSError **)error;
- (BOOL)commitFileData:(NSData *)data
              fileName:(nullable NSString *)fileName
             mediaType:(nullable NSString *)mediaType
                 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
