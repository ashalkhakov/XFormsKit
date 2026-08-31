#import <Foundation/Foundation.h>
#import <XFormsKit/XFEvent.h>
#import <XFormsKit/XFListener.h>

@class NSXMLElement;
@class NSXMLDocument;

NS_ASSUME_NONNULL_BEGIN

typedef void (^XFEventDefaultAction)(id _Nullable xfElement, XFEvent *event);

/// One REGISTRY entry (XsltForms_xmlevents.REGISTRY[name]).
@interface XFEventRegistration : NSObject
@property (nonatomic, assign) BOOL bubbles;
@property (nonatomic, assign) BOOL cancelable;
@property (nonatomic, copy, nullable) XFEventDefaultAction defaultAction;
@end

/// Translation of XsltForms_xmlevents: REGISTRY, EventContexts stack,
/// define / makeEventContext / dispatch / dispatchList.
///
/// There is no DOM dispatchEvent on NSXML, so dispatch walks
/// capture → target → bubble itself (the XSLTForms IE / fireEvent path).
@interface XFXMLEvents : NSObject

@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, XFEventRegistration *> *registry;
@property (nonatomic, strong, readonly) NSMutableArray<NSMutableDictionary *> *eventContexts;

+ (instancetype)sharedEvents;

+ (void)define:(NSString *)name
       bubbles:(BOOL)bubbles
    cancelable:(BOOL)cancelable
 defaultAction:(nullable XFEventDefaultAction)defaultAction;

+ (NSMutableDictionary *)makeEventContext:(nullable NSDictionary *)evcontext
                                     type:(NSString *)type
                                 targetid:(nullable NSString *)targetid
                                  bubbles:(BOOL)bubbles
                               cancelable:(BOOL)cancelable;

+ (nullable NSMutableDictionary *)currentEventContext;
+ (NSMutableArray<NSMutableDictionary *> *)eventContexts;

+ (void)dispatchList:(NSArray *)list name:(NSString *)name;

+ (void)dispatch:(id)target name:(NSString *)name;
+ (void)dispatch:(id)target
            name:(NSString *)name
         context:(nullable NSDictionary *)evcontext;
/// Full XsltForms_xmlevents.dispatch(target, name, type, bubbles, cancelable, defaultAction, evcontext).
+ (void)dispatch:(id)target
            name:(NSString *)name
            type:(nullable NSString *)type
         bubbles:(BOOL)bubbles
      cancelable:(BOOL)cancelable
   defaultAction:(nullable XFEventDefaultAction)defaultAction
         context:(nullable NSDictionary *)evcontext;

- (void)registerElement:(NSXMLElement *)element xfElement:(nullable id)xfElement;
- (nullable id)xfElementForElement:(NSXMLElement *)element;

- (NSMutableArray<XFListener *> *)listenersOn:(NSXMLElement *)element;
- (NSArray<XFListener *> *)listenersForElement:(NSXMLElement *)element;

- (nullable NSXMLElement *)elementWithID:(NSString *)identifier
                              inDocument:(NSXMLDocument *)document;

/// Runtime stand-in for the XSLT that emits `new XsltForms_listener(...)`.
- (void)installListenersInDocument:(NSXMLDocument *)document;
- (void)installListenersUnder:(NSXMLNode *)node inDocument:(NSXMLDocument *)document;
/// The inverse the designer needs when a handler subtree is detached or
/// recompiled: drops every listener (on any observer in `document`) whose
/// handler element is `root` or lives under it.
- (void)removeListenersWithHandlersUnder:(NSXMLElement *)root
                              inDocument:(NSXMLDocument *)document;

/// XSLTForms `element.node` for a host element (bound node, else in-scope
/// context of the control registered for it); nil when unknown.
- (nullable NSXMLNode *)inScopeNodeForElement:(NSXMLElement *)element;

/// XsltForms_globals.error: dispatch an exception event (xforms-binding-,
/// -compute-, -link-, -version-exception) on `target` (an xf object or a
/// host element) and remember the message (G-30). XSLTForms then throws;
/// XFormsKit keeps going and reports the error through the usual NSError.
+ (void)raise:(NSString *)eventName on:(nullable id)target message:(nullable NSString *)message;
/// Messages recorded by +raise:on:message:, oldest first.
@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *exceptionMessages;

@end

@protocol XFXMLEventHandler <NSObject>
- (void)handleXMLEvent:(XFEvent *)event;
@optional
/// Preferred: run with the observer's in-scope node as evaluation context.
- (void)handleXMLEvent:(XFEvent *)event contextNode:(nullable NSXMLNode *)contextNode;
@end

NS_ASSUME_NONNULL_END
