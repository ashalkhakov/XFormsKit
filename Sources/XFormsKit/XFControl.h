#import <Foundation/Foundation.h>

@class XFBinding;
@class XFExprContext;
@class NSXMLElement;
@class NSXMLNode;

NS_ASSUME_NONNULL_BEGIN

@interface XFControl : NSObject

@property (nonatomic, strong, readonly) NSXMLElement *element;
@property (nonatomic, copy, readonly, nullable) NSString *label;
@property (nonatomic, strong, readonly, nullable) XFBinding *binding;
@property (nonatomic, strong, nullable) NSXMLNode *boundNode;
@property (nonatomic, copy) NSString *stringValue;
@property (nonatomic, weak, nullable) id owner; // XFProcessor

- (instancetype)initWithElement:(NSXMLElement *)element
                        binding:(nullable XFBinding *)binding
                          label:(nullable NSString *)label;

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
