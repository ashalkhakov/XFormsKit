#import "XFXMLEvents.h"
#import "XFEvent.h"
#import "XFListener.h"
#import "XFNamespaces.h"
#import "XFXML.h"
#import "XFDeferredUpdates.h"
#import "XFControl.h"
#import "XFProcessor.h"
#import "XFInstance.h"
#import "XFModel.h"
#import "XFBind.h"
#import "XFSubmission.h"
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLDocument.h>
#import <objc/runtime.h>

static const void *kXFListenersKey = &kXFListenersKey;
static const void *kXFElementKey   = &kXFElementKey;

@implementation XFEventRegistration
@end

@interface XFXMLEvents ()
@property (nonatomic, strong, readwrite) NSMutableArray<NSString *> *exceptionMessages;
- (void)registerStandardEvents;
@end

@implementation XFXMLEvents

+ (instancetype)sharedEvents
{
    static XFXMLEvents *shared = nil;
    @synchronized(self) {
        if (shared == nil) {
            shared = [[self alloc] init];
            [shared registerStandardEvents];
        }
    }
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _registry = [NSMutableDictionary dictionary];
        _eventContexts = [NSMutableArray array];
    }
    return self;
}

#pragma mark - REGISTRY

- (void)define:(NSString *)name
       bubbles:(BOOL)bubbles
    cancelable:(BOOL)cancelable
 defaultAction:(XFEventDefaultAction)defaultAction
{
    XFEventRegistration *reg = [[XFEventRegistration alloc] init];
    reg.bubbles = bubbles;
    reg.cancelable = cancelable;
    reg.defaultAction = defaultAction ?: ^(id xf, XFEvent *ev) { (void)xf; (void)ev; };
    self.registry[name] = reg;
}

+ (void)define:(NSString *)name
       bubbles:(BOOL)bubbles
    cancelable:(BOOL)cancelable
 defaultAction:(XFEventDefaultAction)defaultAction
{
    [[self sharedEvents] define:name bubbles:bubbles cancelable:cancelable defaultAction:defaultAction];
}

+ (NSMutableDictionary *)makeEventContext:(NSDictionary *)evcontext
                                     type:(NSString *)type
                                 targetid:(NSString *)targetid
                                  bubbles:(BOOL)bubbles
                               cancelable:(BOOL)cancelable
{
    NSMutableDictionary *ctx = evcontext ? [evcontext mutableCopy] : [NSMutableDictionary dictionary];
    if (ctx[@"type"] == nil && type) {
        ctx[@"type"] = type;
    }
    if (targetid) {
        ctx[@"targetid"] = targetid;
    }
    ctx[@"bubbles"] = @(bubbles);
    ctx[@"cancelable"] = @(cancelable);
    return ctx;
}

+ (NSMutableDictionary *)currentEventContext
{
    NSArray *stack = [self sharedEvents].eventContexts;
    return stack.count ? stack.lastObject : nil;
}

+ (NSMutableArray<NSMutableDictionary *> *)eventContexts
{
    return [self sharedEvents].eventContexts;
}

+ (void)dispatchList:(NSArray *)list name:(NSString *)name
{
    for (id target in list) {
        [self dispatch:target name:name];
    }
}

+ (void)dispatch:(id)target name:(NSString *)name
{
    [self dispatch:target name:name type:nil bubbles:YES cancelable:YES defaultAction:nil context:nil];
}

+ (void)dispatch:(id)target name:(NSString *)name context:(NSDictionary *)evcontext
{
    [self dispatch:target name:name type:nil bubbles:YES cancelable:YES defaultAction:nil context:evcontext];
}

+ (void)dispatch:(id)target
            name:(NSString *)name
            type:(NSString *)type
         bubbles:(BOOL)bubbles
      cancelable:(BOOL)cancelable
   defaultAction:(XFEventDefaultAction)defaultAction
         context:(NSDictionary *)evcontext
{
    [[self sharedEvents] dispatch:target
                             name:name
                             type:type
                          bubbles:bubbles
                       cancelable:cancelable
                    defaultAction:defaultAction
                          context:evcontext];
}

#pragma mark - xfElement / listeners on NSXMLElement

- (void)registerElement:(NSXMLElement *)element xfElement:(id)xfElement
{
    if (element == nil) {
        return;
    }
    objc_setAssociatedObject(element, kXFElementKey, xfElement, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id)xfElementForElement:(NSXMLElement *)element
{
    return element ? objc_getAssociatedObject(element, kXFElementKey) : nil;
}

- (NSMutableArray<XFListener *> *)listenersOn:(NSXMLElement *)element
{
    if (element == nil) {
        return [NSMutableArray array];
    }
    NSMutableArray *list = objc_getAssociatedObject(element, kXFListenersKey);
    if (list == nil) {
        list = [NSMutableArray array];
        objc_setAssociatedObject(element, kXFListenersKey, list, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return list;
}

- (NSArray<XFListener *> *)listenersForElement:(NSXMLElement *)element
{
    NSMutableArray *list = element ? objc_getAssociatedObject(element, kXFListenersKey) : nil;
    return list ? [list copy] : @[];
}

- (NSXMLElement *)elementWithID:(NSString *)identifier inDocument:(NSXMLDocument *)document
{
    return [XFXML elementWithID:identifier inNode:document];
}

- (NSXMLElement *)resolveElement:(id)target xfElement:(id *)outXF
{
    if (target == nil) {
        return nil;
    }
    if ([target isKindOfClass:[NSXMLElement class]]) {
        if (outXF) {
            *outXF = [self xfElementForElement:target];
        }
        return target;
    }
    // XsltForms: target = target.element || target
    if ([target respondsToSelector:@selector(element)]) {
        NSXMLElement *el = [target element];
        [self registerElement:el xfElement:target];
        if (outXF) {
            *outXF = target;
        }
        return el;
    }
    return nil;
}

#pragma mark - dispatch (IE / fireEvent path)

- (void)dispatch:(id)target
            name:(NSString *)name
            type:(NSString *)type
         bubbles:(BOOL)bubbles
      cancelable:(BOOL)cancelable
   defaultAction:(XFEventDefaultAction)defaultAction
         context:(NSDictionary *)evcontext
{
    (void)type; // XSLTForms accepts `type` then overwrites from `name` in makeEventContext
    if (target == nil) {
        NSLog(@"XFormsKit: cannot dispatch event %@ as the target is null", name);
        return;
    }
    id xfElement = nil;
    NSXMLElement *element = [self resolveElement:target xfElement:&xfElement];
    if (element == nil) {
        return;
    }

    XFEventRegistration *reg = self.registry[name];
    if (reg) {
        bubbles = reg.bubbles;
        cancelable = reg.cancelable;
        defaultAction = reg.defaultAction;
    }
    if (defaultAction == nil) {
        defaultAction = ^(id xf, XFEvent *ev) { (void)xf; (void)ev; };
    }

    NSString *targetid = [[element attributeForName:@"id"] stringValue];
    NSMutableDictionary *ctx = [XFXMLEvents makeEventContext:evcontext
                                                        type:name
                                                    targetid:targetid
                                                     bubbles:bubbles
                                                  cancelable:cancelable];
    [self.eventContexts addObject:ctx];

    XFEvent *event = [[XFEvent alloc] init];
    event.type = name;
    event.target = element;
    event.xfElement = xfElement;
    event.bubbles = bubbles;
    event.cancelable = cancelable;
    event.targetid = targetid;
    event.context = ctx;

    @try {
        NSMutableArray<NSXMLElement *> *ancestors = [NSMutableArray array];
        for (NSXMLNode *a = [element parent]; a; a = [a parent]) {
            if ([a kind] == NSXMLElementKind) {
                [ancestors insertObject:(NSXMLElement *)a atIndex:0];
            }
        }

        // Capture phase (root → parent), then capture on the target.
        event.eventPhase = XFEventPhaseCapture;
        event.phase = @"capture";
        if (!event.stopped) {
            for (NSXMLElement *ancestor in ancestors) {
                [self fire:event on:ancestor];
                if (event.stopped) {
                    break;
                }
            }
        }
        if (!event.stopped) {
            [self fire:event on:element];
        }

        // Default phase on the target (XML Events "default" = target + bubble).
        if (!event.stopped) {
            event.eventPhase = XFEventPhaseTarget;
            event.phase = @"default";
            [self fire:event on:element];
        }

        if (bubbles && !event.stopped && !event.cancelBubble) {
            event.eventPhase = XFEventPhaseBubble;
            event.phase = @"default";
            for (NSInteger i = (NSInteger)ancestors.count - 1; i >= 0; i--) {
                [self fire:event on:ancestors[(NSUInteger)i]];
                if (event.stopped || event.cancelBubble) {
                    break;
                }
            }
        }

        // XSLTForms: if ((res && !event.stopped) || !cancelable) defaultAction.call(xfElement, event)
        BOOL res = event.returnValue && !event.defaultPrevented;
        if ((res && !event.stopped) || !cancelable) {
            defaultAction(xfElement, event);
        }
    } @finally {
        NSMutableDictionary *top = self.eventContexts.lastObject;
        [top removeObjectForKey:@"rheadsdoc"];
        [top removeObjectForKey:@"response-body"];
        [self.eventContexts removeLastObject];
    }
}

- (void)fire:(XFEvent *)event on:(NSXMLElement *)observer
{
    event.currentTarget = observer;
    NSArray<XFListener *> *list = [[self listenersForElement:observer] copy];
    for (XFListener *listener in list) {
        if (![listener.name isEqualToString:event.type]) {
            continue;
        }
        [listener invoke:event];
        if (event.stopped) {
            return;
        }
    }
}

#pragma mark - document install (XSLT stand-in)

- (NSString *)ev:(NSString *)local on:(NSXMLElement *)element
{
    return [XFXML attributeValue:local namespaceURI:XFXMLEventsNamespaceURI onElement:element];
}

- (void)installListenersInDocument:(NSXMLDocument *)document
{
    NSArray<NSXMLElement *> *listenerElements =
        [XFXML elementsWithLocalName:@"listener"
                       namespaceURI:XFXMLEventsNamespaceURI
                             inNode:document];
    for (NSXMLElement *el in listenerElements) {
        [self installListenerElement:el inDocument:document];
    }
    [self installAttributeListenersUnder:document inDocument:document];
}

- (void)installListenersUnder:(NSXMLNode *)node inDocument:(NSXMLDocument *)document
{
    if (node == nil) {
        return;
    }
    if ([node kind] == NSXMLElementKind) {
        NSXMLElement *el = (NSXMLElement *)node;
        if ([XFXML element:el hasLocalName:@"listener" namespaceURI:XFXMLEventsNamespaceURI]) {
            [self installListenerElement:el inDocument:document];
        }
    }
    [self installAttributeListenersUnder:node inDocument:document];
}

- (void)installAttributeListenersUnder:(NSXMLNode *)node inDocument:(NSXMLDocument *)document
{
    if ([node kind] == NSXMLElementKind) {
        NSXMLElement *element = (NSXMLElement *)node;
        NSString *eventName = [self ev:@"event" on:element];
        if (eventName.length &&
            !([XFXML element:element hasLocalName:@"listener" namespaceURI:XFXMLEventsNamespaceURI])) {
            // XML Events attribute module: observer defaults to the parent
            // of the element bearing ev:event (XForms actions under model,
            // setvalue under trigger, etc.).
            NSXMLElement *parent = nil;
            if ([element parent].kind == NSXMLElementKind) {
                parent = (NSXMLElement *)[element parent];
            }
            [self installListenerOnElement:element
                                 eventName:eventName
                                inDocument:document
                           observerDefault:parent ?: element];
        }
    }
    for (NSXMLNode *child in [node children]) {
        [self installAttributeListenersUnder:child inDocument:document];
    }
}

- (void)installListenerElement:(NSXMLElement *)el inDocument:(NSXMLDocument *)document
{
    NSString *eventName = [self ev:@"event" on:el] ?: [[el attributeForName:@"event"] stringValue];
    if (eventName.length == 0) {
        return;
    }
    NSXMLElement *defaultObserver = nil;
    if ([el parent].kind == NSXMLElementKind) {
        defaultObserver = (NSXMLElement *)[el parent];
    }
    [self installListenerOnElement:el
                         eventName:eventName
                        inDocument:document
                   observerDefault:defaultObserver];
}

- (void)installListenerOnElement:(NSXMLElement *)el
                       eventName:(NSString *)eventName
                      inDocument:(NSXMLDocument *)document
                 observerDefault:(NSXMLElement *)observerDefault
{
    // unprefixed XML Events attributes only on non-XForms elements
    // (ev:listener): on xf:load / xf:dispatch a plain `target` is the
    // action's own attribute (G-50)
    BOOL xfElement = [[el URI] isEqualToString:XFXFormsNamespaceURI];
    NSString *(^plain)(NSString *) = ^NSString *(NSString *name) {
        return xfElement ? nil : [[el attributeForName:name] stringValue];
    };
    NSString *observerID = [self ev:@"observer" on:el] ?: plain(@"observer");
    NSString *targetID = [self ev:@"target" on:el] ?: plain(@"target");
    NSString *handlerRef = [self ev:@"handler" on:el] ?: plain(@"handler");
    NSString *phase = [self ev:@"phase" on:el] ?: plain(@"phase");
    NSString *propagate = [self ev:@"propagate" on:el] ?: plain(@"propagate");
    NSString *defaultAction = [self ev:@"defaultAction" on:el] ?: plain(@"defaultAction");

    NSXMLElement *observer = observerDefault;
    if (observerID.length) {
        if ([observerID hasPrefix:@"#"]) {
            observerID = [observerID substringFromIndex:1];
        }
        observer = [self elementWithID:observerID inDocument:document] ?: observer;
    }
    NSXMLElement *evtTarget = nil;
    if (targetID.length) {
        evtTarget = [self elementWithID:targetID inDocument:document];
    }
    NSXMLElement *handlerElement = el;
    if (handlerRef.length) {
        if ([handlerRef hasPrefix:@"#"]) {
            handlerRef = [handlerRef substringFromIndex:1];
        }
        NSXMLElement *resolved = [self elementWithID:handlerRef inDocument:document];
        if (resolved) {
            handlerElement = resolved;
        }
    }
    if (observer == nil) {
        return;
    }

    BOOL performDefault = ![defaultAction isEqualToString:@"cancel"];
    XFEventHandlerBlock handler = ^(XFEvent *event) {
        id xf = [[XFXMLEvents sharedEvents] xfElementForElement:handlerElement];
        if ([xf respondsToSelector:@selector(handleXMLEvent:contextNode:)]) {
            // XsltForms_browser.run: one openAction/closeAction around the
            // whole handler (G-09), evaluated in the observer's in-scope
            // context (`element.node`, G-10)
            NSXMLNode *ctx = [[XFXMLEvents sharedEvents] inScopeNodeForElement:observer];
            XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
            [du openAction:@"run"];
            [xf handleXMLEvent:event contextNode:ctx];
            [du closeAction:@"run"];
        } else if ([xf respondsToSelector:@selector(handleXMLEvent:)]) {
            [xf handleXMLEvent:event];
        }
        event.context[@"handler-element"] = handlerElement;
    };

    XFListener *listener = [[XFListener alloc] initWithSubform:nil
                                                      observer:observer
                                                     evtTarget:evtTarget
                                                          name:eventName
                                                         phase:phase
                                                       handler:handler
                                                 defaultAction:performDefault];
    listener.propagate = ![propagate isEqualToString:@"stop"];
    listener.handlerElement = handlerElement;
}

#pragma mark - XsltForms_xmlevents.define table

- (void)registerStandardEvents
{
    [self define:@"xforms-model-construct" bubbles:YES cancelable:NO defaultAction:^(id xf, XFEvent *ev) {
        (void)ev;
        if ([xf isKindOfClass:[XFInstance class]]) {
            [(XFInstance *)xf construct];
        } else if ([xf isKindOfClass:[XFModel class]]) {
            [(XFModel *)xf construct];
        }
    }];
    [self define:@"xforms-model-construct-done" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-ready" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-model-destruct" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-rebuild" bubbles:YES cancelable:YES defaultAction:^(id xf, XFEvent *ev) {
        (void)ev;
        if ([xf isKindOfClass:[XFModel class]]) {
            [(XFModel *)xf rebuild];
        }
    }];
    [self define:@"xforms-recalculate" bubbles:YES cancelable:YES defaultAction:^(id xf, XFEvent *ev) {
        (void)ev;
        if ([xf isKindOfClass:[XFBind class]]) {
            [(XFBind *)xf recalculate];
        } else if ([xf isKindOfClass:[XFModel class]]) {
            [(XFModel *)xf recalculate];
        }
    }];
    [self define:@"xforms-revalidate" bubbles:YES cancelable:YES defaultAction:^(id xf, XFEvent *ev) {
        (void)ev;
        if ([xf isKindOfClass:[XFInstance class]]) {
            [(XFInstance *)xf revalidate];
        } else if ([xf isKindOfClass:[XFModel class]]) {
            [(XFModel *)xf revalidate];
        }
    }];
    [self define:@"xforms-reset" bubbles:YES cancelable:YES defaultAction:^(id xf, XFEvent *ev) {
        (void)ev;
        if ([xf isKindOfClass:[XFInstance class]]) {
            [(XFInstance *)xf reset];
        } else if ([xf isKindOfClass:[XFModel class]]) {
            [(XFModel *)xf reset];
        } else if ([xf isKindOfClass:[XFDeferredUpdates class]]) {
            [(XFDeferredUpdates *)xf reset];
        }
    }];
    [self define:@"xforms-submit" bubbles:YES cancelable:YES defaultAction:^(id xf, XFEvent *ev) {
        (void)ev;
        if ([xf isKindOfClass:[XFSubmission class]]) {
            [(XFSubmission *)xf submit];
        }
    }];
    [self define:@"xforms-submit-serialize" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-refresh" bubbles:YES cancelable:YES defaultAction:^(id xf, XFEvent *ev) {
        (void)ev;
        if ([xf respondsToSelector:@selector(refresh)]) {
            [xf refresh];
        }
    }];
    [self define:@"xforms-help" bubbles:YES cancelable:YES defaultAction:^(id xf, XFEvent *ev) {
        (void)ev;
        if ([xf isKindOfClass:[XFControl class]]) {
            // the host shows the help (G-62); without a host it is queued
            XFControl *control = xf;
            XFProcessor *processor = [control processor];
            if (processor.helpRequestHandler) {
                processor.helpRequestHandler(control);
            } else if (control.help.length) {
                [[XFDeferredUpdates sharedUpdates].messages addObject:control.help];
            }
        }
    }];
    [self define:@"xforms-hint" bubbles:YES cancelable:YES defaultAction:^(id xf, XFEvent *ev) {
        (void)ev;
        if ([xf respondsToSelector:@selector(hint)]) {
            NSString *text = [xf hint];
            if ([text isKindOfClass:[NSString class]] && text.length) {
                [[XFDeferredUpdates sharedUpdates].messages addObject:text];
            }
        }
    }];
    [self define:@"xforms-focus" bubbles:YES cancelable:YES defaultAction:^(id xf, XFEvent *ev) {
        (void)ev;
        if ([xf respondsToSelector:@selector(focus)]) {
            [xf focus];
        }
    }];
    [self define:@"DOMActivate" bubbles:YES cancelable:YES defaultAction:nil];
    [self define:@"DOMFocusIn" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"DOMFocusOut" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-select" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-deselect" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-value-changed" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-insert" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-delete" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-valid" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-invalid" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-enabled" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-disabled" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-optional" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-required" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-readonly" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-readwrite" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-in-range" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-out-of-range" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-submit-done" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-submit-error" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-compute-exception" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-binding-exception" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-link-exception" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-upload-done" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-upload-error" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-version-exception" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"ajx-start" bubbles:YES cancelable:YES defaultAction:^(id xf, XFEvent *ev) {
        (void)ev;
        if ([xf respondsToSelector:@selector(start)]) {
            [xf start];
        }
    }];
    [self define:@"ajx-stop" bubbles:YES cancelable:YES defaultAction:^(id xf, XFEvent *ev) {
        (void)ev;
        if ([xf respondsToSelector:@selector(stop)]) {
            [xf stop];
        }
    }];
    [self define:@"ajx-time" bubbles:YES cancelable:YES defaultAction:nil];
    [self define:@"xforms-dialog-open" bubbles:YES cancelable:YES defaultAction:nil];
    [self define:@"xforms-dialog-close" bubbles:YES cancelable:YES defaultAction:nil];
    [self define:@"xforms-scroll-first" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-scroll-last" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-load-done" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-load-error" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-unload-done" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-upload-done" bubbles:YES cancelable:NO defaultAction:nil];
    [self define:@"xforms-upload-error" bubbles:YES cancelable:NO defaultAction:nil];
}


+ (void)raise:(NSString *)eventName on:(id)target message:(NSString *)message
{
    XFXMLEvents *events = [self sharedEvents];
    if (events.exceptionMessages == nil) {
        events.exceptionMessages = [NSMutableArray array];
    }
    [events.exceptionMessages addObject:[NSString stringWithFormat:@"%@: %@", eventName, message ?: @""]];
    id xf = target;
    if ([target isKindOfClass:[NSXMLElement class]]) {
        xf = [events xfElementForElement:target] ?: target;
    }
    if (xf) {
        [self dispatch:xf name:eventName];
    }
}

- (NSXMLNode *)inScopeNodeForElement:(NSXMLElement *)element
{
    // XSLTForms: element.node — the bound node of a bound element, the
    // in-scope context of an unbound one; nil for model-level observers
    // (the action then falls back to the default instance root).
    id xf = [self xfElementForElement:element];
    if ([xf isKindOfClass:[XFControl class]]) {
        XFControl *c = xf;
        return c.boundNode ?: c.inScopeContextNode;
    }
    return nil;
}

@end
