#import "XFMessageAction.h"
#import "XFProcessor.h"
#import "XFNamespaces.h"
#import "XFBinding.h"
#import "XFBinding.h"
#import "XFExprContext.h"
#import "XFXML.h"
#import "XFDeferredUpdates.h"
#import "XFModel.h"
#import "XFEvent.h"

@interface XFMessageAction ()
@property (nonatomic, strong) XFBinding *binding;
@property (nonatomic, copy, readwrite) NSString *level;
@property (nonatomic, copy, readwrite) NSString *lastText;
@end

@implementation XFMessageAction

- (instancetype)initWithElement:(NSXMLElement *)element
                          model:(XFModel *)model
                          error:(NSError **)error
{
    self = [super initWithElement:element model:model error:error];
    if (self == nil) {
        return nil;
    }
    self.level = [[element attributeForName:@"level"] stringValue] ?: @"modal";
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

- (void)appendTextOf:(NSXMLElement *)element context:(XFExprContext *)ctx into:(NSMutableString *)out
{
    for (NSXMLNode *c in [element children]) {
        if ([c kind] == NSXMLTextKind) {
            [out appendString:[c stringValue] ?: @""];
        } else if ([c kind] == NSXMLElementKind) {
            NSXMLElement *el = (NSXMLElement *)c;
            if ([XFXML element:el hasLocalName:@"output" namespaceURI:XFXFormsNamespaceURI]) {
                NSString *attr = [el attributeForName:@"value"] && ![el attributeForName:@"ref"] ? @"value" : @"ref";
                XFBinding *b = [XFBinding bindingForElement:el attribute:attr error:NULL];
                [out appendString:b ? ([b stringValueInContext:ctx error:NULL] ?: @"") : @""];
            } else {
                [self appendTextOf:el context:ctx into:out];
            }
        }
    }
}

- (void)runWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    (void)event;
    NSString *text = nil;
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:contextNode];
    ctx.model = self.model;
    if (self.binding && contextNode) {
        text = [self.binding stringValueInContext:ctx error:NULL];
    } else {
        // XFMessage.js builds the message content: inline xf:output
        // elements are evaluated in place (G-51)
        NSMutableString *built = [NSMutableString string];
        [self appendTextOf:self.element context:ctx into:built];
        text = built;
    }
    text = [XFXML normalizeSpace:text ?: @""];
    self.lastText = text;
    if (text.length == 0) {
        return;
    }
    XFProcessor *processor = [self.model.owner isKindOfClass:[XFProcessor class]] ? (XFProcessor *)self.model.owner : nil;
    if (processor.messageHandler) {
        processor.messageHandler(text, self.level ?: @"modal");
    } else {
        [[XFDeferredUpdates sharedUpdates].messages addObject:text];
    }
}

@end

@interface XFConfirmAction ()
@property (nonatomic, assign, readwrite) BOOL lastAnswer;
@end

@implementation XFConfirmAction

- (void)runWithContextNode:(NSXMLNode *)contextNode event:(XFEvent *)event
{
    NSString *text = nil;
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:contextNode];
    ctx.model = self.model;
    if (self.binding && contextNode) {
        text = [self.binding stringValueInContext:ctx error:NULL];
    } else {
        NSMutableString *built = [NSMutableString string];
        [self appendTextOf:self.element context:ctx into:built];
        text = built;
    }
    text = [XFXML normalizeSpace:text ?: @""];
    self.lastText = text;
    if (text.length == 0) {
        return;
    }
    XFProcessor *processor = [self.model.owner isKindOfClass:[XFProcessor class]] ? (XFProcessor *)self.model.owner : nil;
    BOOL answer = processor.confirmHandler ? processor.confirmHandler(text) : YES;
    self.lastAnswer = answer;
    if (!answer) {
        [event stopPropagation];
    }
}

@end
