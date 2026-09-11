#import "XFLoadAction.h"
#import "XFProcessor.h"
#import "XFBinding.h"
#import "XFXPath.h"
#import "XFExprContext.h"
#import "XFModel.h"
#import "XFInstance.h"
#import "XFXML.h"
#import "XFXMLEvents.h"
#import "XFEvent.h"
#import "XFDeferredUpdates.h"
#import "XFSubmissionTransport.h"
#import "XFSubform.h"
#import "XFNamespaces.h"

@interface XFLoadAction ()
@property (nonatomic, copy, readwrite) NSString *resource;
@property (nonatomic, strong, readwrite) XFXPath *resourceExpr;
@property (nonatomic, strong, readwrite) XFBinding *binding;
@property (nonatomic, copy, readwrite) NSString *show;
@property (nonatomic, copy, readwrite) NSString *targetID;
@property (nonatomic, copy, readwrite) NSString *instanceID;
@property (nonatomic, copy, readwrite) NSString *lastResource;
@property (nonatomic, copy, readwrite) NSDictionary *lastEventContext;
@end

@implementation XFLoadAction

- (instancetype)initWithElement:(XFXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    self.show = [[element attributeForName:@"show"] stringValue] ?: @"replace";
    self.targetID = [[element attributeForName:@"targetid"] stringValue]
        ?: [[element attributeForName:@"target"] stringValue];
    self.instanceID = [[element attributeForName:@"instance"] stringValue];

    NSString *resource = [[element attributeForName:@"resource"] stringValue];
    XFXMLElement *resourceEl =
        [XFXML firstElementWithLocalName:@"resource"
                           namespaceURI:XFXFormsNamespaceURI
                                 inNode:element];
    if (resourceEl) {
        NSString *value = [[resourceEl attributeForName:@"value"] stringValue];
        if (value.length) {
            self.resourceExpr = [XFXPath xpathWithString:value element:element error:error];
            if (self.resourceExpr == nil) {
                return nil;
            }
        } else if ([XFXML stringValueOfNode:resourceEl].length) {
            resource = [XFXML stringValueOfNode:resourceEl];
        }
    }
    self.resource = resource;

    NSError *bindError = nil;
    self.binding = [XFBinding bindingForElement:element attribute:@"ref" error:&bindError];
    if (bindError) {
        if (error) {
            *error = bindError;
        }
        return nil;
    }
    return self;
}

- (NSString *)resolvedResourceWithContextNode:(XFXMLNode *)contextNode
{
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:contextNode];
    ctx.model = self.model;
    if (self.binding) {
        return [self.binding stringValueInContext:ctx error:NULL] ?: @"";
    }
    if (self.resourceExpr) {
        return [self.resourceExpr stringValueInContext:ctx error:NULL] ?: @"";
    }
    return self.resource ?: @"";
}

/// XFLoad.js dispatches on document.getElementById(targetid) when there is
/// a target, else on the action (G-50).
- (id)eventTarget
{
    if (self.targetID.length) {
        NSString *tid = [self.targetID hasPrefix:@"#"] ? [self.targetID substringFromIndex:1] : self.targetID;
        XFXMLElement *el = [XFXML elementWithID:tid inNode:self.element.rootDocument];
        if (el) {
            return [[XFXMLEvents sharedEvents] xfElementForElement:el] ?: (id)el;
        }
    }
    return self;
}

- (void)runWithContextNode:(XFXMLNode *)contextNode event:(XFEvent *)event
{
    (void)event;
    NSString *href = [self resolvedResourceWithContextNode:contextNode];
    self.lastResource = href;
    NSMutableDictionary *evcontext = [@{
        @"method": @"get",
        @"resource-uri": href ?: @""
    } mutableCopy];

    // debugConsole: "Load href"
    XFTraceWrite(XFTraceKindAction, nil, self.element, @"Load %@", href ?: @"");
    if (href.length == 0) {
        evcontext[@"error-type"] = @"resource-error";
        self.lastEventContext = evcontext;
        [XFXMLEvents dispatch:self name:@"xforms-load-error" context:evcontext];
        return;
    }

    if (self.instanceID.length == 0) {
        XFProcessor *processor = [self.model.owner isKindOfClass:[XFProcessor class]] ? (XFProcessor *)self.model.owner : nil;
        NSURL *url = [NSURL URLWithString:href relativeToURL:processor.baseURL] ?: [NSURL URLWithString:href];
        NSString *tid = [self.targetID hasPrefix:@"#"] ? [self.targetID substringFromIndex:1] : self.targetID;
        // XFLoad.js order: show="new" / targetid="_blank" open a window,
        // then show="embed" or any other targetid embeds
        BOOL newWindow = [self.show isEqualToString:@"new"] || [tid isEqualToString:@"_blank"];
        BOOL embed = !newWindow && ([self.show isEqualToString:@"embed"]
            || (tid.length && ![tid isEqualToString:@"_self"]));
        if (embed && processor) {
            // XFLoad.js: a subform is loaded into the target (G-90);
            // failure is an xforms-link-exception on the target with
            // error-type resource-error (issueLoadException_)
            XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
            [du openAction:@"XsltForms_load.prototype.run"];
            NSError *err = nil;
            XFSubform *sf = tid.length ? [processor loadSubformAtURL:url intoTargetID:tid contextNode:contextNode error:&err] : nil;
            [du closeAction:@"XsltForms_load.prototype.run"];
            if (sf == nil) {
                evcontext[@"error-type"] = @"resource-error";
                evcontext[@"message"] = [err localizedDescription] ?: @"";
                self.lastEventContext = evcontext;
                [XFXMLEvents dispatch:[self eventTarget] name:@"xforms-link-exception" context:evcontext];
                return;
            }
            self.lastEventContext = evcontext;
            id targetXF = [[XFXMLEvents sharedEvents] xfElementForElement:sf.targetElement];
            if (targetXF) {
                [XFXMLEvents dispatch:targetXF name:@"xforms-load-done" context:evcontext];
            }
            return;
        }
        // show="new" | "replace": the host opens the URL (G-50)
        BOOL handled = YES;
        if (processor.loadRequestHandler) {
            handled = processor.loadRequestHandler(url, self.show ?: @"replace");
        }
        self.lastEventContext = evcontext;
        [XFXMLEvents dispatch:[self eventTarget] name:handled ? @"xforms-load-done" : @"xforms-load-error" context:evcontext];
        return;
    }

    XFInstance *inst = [self.model instanceWithIdentifier:self.instanceID];
    if (inst == nil) {
        evcontext[@"error-type"] = @"resource-error";
        self.lastEventContext = evcontext;
        [XFXMLEvents dispatch:self name:@"xforms-load-error" context:evcontext];
        return;
    }

    id<XFSubmissionTransport> transport = self.model.transport;
    if (transport == nil && [self.model.owner isKindOfClass:[XFProcessor class]]) {
        transport = [(XFProcessor *)self.model.owner defaultTransport];
    }
    if (transport == nil) {
        transport = [[XFHTTPSubmissionTransport alloc] init];
    }
    XFSubmissionRequest *req = [[XFSubmissionRequest alloc] init];
    req.method = @"get";
    req.URLString = href;
    NSError *net = nil;
    XFSubmissionResponse *resp = [transport performRequest:req error:&net];
    if (resp == nil || net ||
        (resp.statusCode != 0 && (resp.statusCode < 200 || resp.statusCode >= 300))) {
        evcontext[@"error-type"] = resp.errorType ?: @"resource-error";
        evcontext[@"response-status-code"] = @(resp ? resp.statusCode : 0);
        self.lastEventContext = evcontext;
        [XFXMLEvents dispatch:self name:@"xforms-load-error" context:evcontext];
        return;
    }

    XFDeferredUpdates *du = [XFDeferredUpdates sharedUpdates];
    [du openAction:@"load"];
    NSError *parse = nil;
    if (![inst replaceWithXMLString:resp.body ?: @"" error:&parse]) {
        evcontext[@"error-type"] = @"parse-error";
        self.lastEventContext = evcontext;
        [XFXMLEvents dispatch:self name:@"xforms-load-error" context:evcontext];
        [du closeAction:@"load"];
        return;
    }
    [self.model addChange:[inst documentElement]];
    [self.model setRebuilded:YES];
    [du addChangedModel:self.model];
    [XFXMLEvents dispatch:self.model name:@"xforms-rebuild"];
    [self.model refresh];
    evcontext[@"response-status-code"] = @(resp.statusCode);
    evcontext[@"response-body"] = resp.body ?: @"";
    self.lastEventContext = evcontext;
    [XFXMLEvents dispatch:self name:@"xforms-load-done" context:evcontext];
    [du closeAction:@"load"];
}

@end

@implementation XFUnloadAction

- (instancetype)initWithElement:(XFXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self) {
        _targetID = [[element attributeForName:@"targetid"] stringValue];
    }
    return self;
}

- (void)runWithContextNode:(XFXMLNode *)contextNode event:(XFEvent *)event
{
    (void)event;
    XFProcessor *processor = [self.model.owner isKindOfClass:[XFProcessor class]] ? (XFProcessor *)self.model.owner : nil;
    NSString *tid = [self.targetID hasPrefix:@"#"] ? [self.targetID substringFromIndex:1] : self.targetID;
    if (tid.length == 0) {
        // XFUnload.js: the subform holding the action
        XFSubform *own = [processor subformContainingElement:self.element];
        tid = [[own.targetElement attributeForName:@"id"] stringValue];
    }
    if (tid.length) {
        [processor unloadSubformAtTargetID:tid contextNode:contextNode];
    }
}

@end
