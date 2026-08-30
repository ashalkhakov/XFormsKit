#import <Foundation/Foundation.h>

@class XFBinding;
@class XFExprContext;
@class NSXMLElement;
@class NSXMLNode;

NS_ASSUME_NONNULL_BEGIN

@interface XFControl : NSObject

@property (nonatomic, strong, readonly) NSXMLElement *element;
@property (nonatomic, copy, readonly, nullable) NSString *identifier;
@property (nonatomic, copy, readonly, nullable) NSString *label;
@property (nonatomic, strong, readonly, nullable) XFBinding *binding;
@property (nonatomic, strong, nullable) NSXMLNode *boundNode;
@property (nonatomic, copy) NSString *stringValue;
@property (nonatomic, assign) BOOL relevant;
@property (nonatomic, assign) BOOL readonly;
@property (nonatomic, assign) BOOL required;
@property (nonatomic, assign) BOOL valid;
@property (nonatomic, assign) BOOL focused;
@property (nonatomic, copy, nullable) NSString *hint;
@property (nonatomic, copy, nullable) NSString *appearance;
@property (nonatomic, weak, nullable) id owner;
@property (nonatomic, weak, nullable) XFControl *parentControl;

- (instancetype)initWithElement:(NSXMLElement *)element
                        binding:(nullable XFBinding *)binding
                          label:(nullable NSString *)label;

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error;
- (void)focus;
- (BOOL)commitStringValue:(nullable NSString *)value error:(NSError **)error;
- (void)applyMIPsFromBoundNode;

+ (BOOL)isControlElement:(NSXMLElement *)element;
+ (nullable NSString *)labelForElement:(NSXMLElement *)element;
+ (nullable XFBinding *)bindingOnElement:(NSXMLElement *)element
                    preferredAttribute:(nullable NSString *)preferred
                                 error:(NSError **)error;
+ (nullable instancetype)controlWithElement:(NSXMLElement *)element
                                      model:(nullable id)model
                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
