#import <Foundation/Foundation.h>

@class XFModel;
@class XFInstance;
@class XFControl;
@class XFInputControl;
@class XFOutputControl;
@class NSXMLDocument;

NS_ASSUME_NONNULL_BEGIN

@interface XFProcessor : NSObject

@property (nonatomic, strong, readonly) NSXMLDocument *hostDocument;
@property (nonatomic, strong, readonly) XFModel *model;
@property (nonatomic, copy, readonly) NSArray<XFControl *> *controls;
@property (nonatomic, copy, readonly) NSArray<XFInputControl *> *inputControls;
@property (nonatomic, copy, readonly) NSArray<XFOutputControl *> *outputControls;

+ (nullable instancetype)processorWithContentsOfURL:(NSURL *)url
                                              error:(NSError **)error;

+ (nullable instancetype)processorWithXMLString:(NSString *)xml
                                          error:(NSError **)error;

- (nullable XFInstance *)defaultInstance;
- (BOOL)refresh:(NSError **)error;

/// Writes `value` into the input's bound node and refreshes the form.
- (BOOL)setValue:(NSString *)value
      ofControl:(XFInputControl *)control
          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
