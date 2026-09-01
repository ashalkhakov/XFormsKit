#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLEvents.h>

@class NSXMLElement;
@class NSXMLNode;
@class XFEvent;
@class XFModel;
@class XFXPath;
@class XFAbstractAction;

NS_ASSUME_NONNULL_BEGIN

/// Translation of XsltForms_abstractAction: if / while / iterate then run.
@interface XFAbstractAction : NSObject <XFXMLEventHandler>

@property (nonatomic, strong, readonly) NSXMLElement *element;
@property (nonatomic, copy, readonly, nullable) NSString *identifier;
@property (nonatomic, weak, nullable) XFModel *model;
@property (nonatomic, weak, nullable) XFAbstractAction *parentAction;
@property (nonatomic, strong, nullable) XFXPath *ifExpr;
@property (nonatomic, strong, nullable) XFXPath *whileExpr;
@property (nonatomic, strong, nullable) XFXPath *iterateExpr;
@property (nonatomic, copy, readonly) NSArray<NSString *> *invokedEvents;
@property (nonatomic, assign, readonly) NSInteger invocationCount;
@property (nonatomic, strong, readonly, nullable) XFEvent *lastEvent;

+ (BOOL)isActionElement:(NSXMLElement *)element;
+ (nullable instancetype)actionWithElement:(NSXMLElement *)element
                                     model:(nullable XFModel *)model
                                     error:(NSError **)error;

- (instancetype)initWithElement:(NSXMLElement *)element
                          model:(nullable XFModel *)model
                          error:(NSError **)error;

- (void)executeWithContextNode:(nullable NSXMLNode *)contextNode event:(nullable XFEvent *)event;
- (BOOL)execWithContextNode:(nullable NSXMLNode *)contextNode event:(nullable XFEvent *)event;
/// Override point (XsltForms_abstractAction.run).
- (void)runWithContextNode:(nullable NSXMLNode *)contextNode event:(nullable XFEvent *)event;

- (BOOL)wasInvokedForEvent:(NSString *)name;

/// The model this action's bindings evaluate in: @model="id" switches it
/// (XForms 1.1 in-scope evaluation context; XsltForms_binding.bind_evaluate).
- (XFModel *)actionTargetModel;

@end

NS_ASSUME_NONNULL_END
