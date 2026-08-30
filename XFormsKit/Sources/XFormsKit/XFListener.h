#import <Foundation/Foundation.h>

@class NSXMLElement;
@class XFEvent;

NS_ASSUME_NONNULL_BEGIN

typedef void (^XFEventHandlerBlock)(XFEvent *event);

/// Translation of XsltForms_listener.
///
/// Constructor attaches a callback to `observer` for `name`. Phase is
/// "capture" or "default" (XML Events 1). `evtTarget` filters the
/// event target (ev:target). `defaultAction` is ev:defaultAction !=
/// "cancel". `propagate` is ev:propagate != "stop" (XSLTForms folds
/// that into the generated handler; we keep it on the listener).
@interface XFListener : NSObject

@property (nonatomic, weak, nullable) id subform;
@property (nonatomic, weak, nullable) NSXMLElement *observer;
@property (nonatomic, weak, nullable) NSXMLElement *evtTarget;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *phase; // @"capture" or @"default"
@property (nonatomic, copy, nullable) XFEventHandlerBlock handler;
@property (nonatomic, assign) BOOL defaultAction;
@property (nonatomic, assign) BOOL propagate;
@property (nonatomic, strong, nullable) NSXMLElement *handlerElement;

+ (NSMutableArray *)destructs;

- (instancetype)initWithSubform:(nullable id)subform
                       observer:(NSXMLElement *)observer
                      evtTarget:(nullable NSXMLElement *)evtTarget
                           name:(NSString *)name
                          phase:(nullable NSString *)phase
                        handler:(nullable XFEventHandlerBlock)handler
                  defaultAction:(BOOL)defaultAction;

- (instancetype)initWithObserver:(NSXMLElement *)observer
                       evtTarget:(nullable NSXMLElement *)evtTarget
                            name:(NSString *)name
                           phase:(nullable NSString *)phase
                         handler:(nullable XFEventHandlerBlock)handler
                   defaultAction:(BOOL)defaultAction;

- (void)attach;
- (void)detach;
- (instancetype)cloneForElement:(NSXMLElement *)element;
/// XsltForms_listener.callback
- (void)invoke:(XFEvent *)event;

@end

NS_ASSUME_NONNULL_END
