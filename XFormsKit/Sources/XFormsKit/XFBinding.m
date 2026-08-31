#import "XFBinding.h"
#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFModel.h"
#import "XFInstance.h"
#import "XFBind.h"
#import "XFProcessor.h"
#import "XFErrors.h"
#import "XFXMLEvents.h"
#import <Foundation/NSXMLElement.h>

@interface XFBinding ()
@property (nonatomic, strong, readwrite) XFXPath *xpath;
@property (nonatomic, copy, readwrite) NSString *expression;
@property (nonatomic, copy, readwrite) NSString *bindID;
@property (nonatomic, copy, readwrite) NSString *modelID;
@property (nonatomic, weak) NSXMLElement *element;
@end

@implementation XFBinding

+ (instancetype)bindingWithExpression:(NSString *)expression error:(NSError **)error
{
    return [self bindingWithExpression:expression element:nil error:error];
}

+ (instancetype)bindingWithExpression:(NSString *)expression
                              element:(NSXMLElement *)element
                                error:(NSError **)error
{
    XFXPath *xp = [XFXPath xpathWithString:expression element:element error:error];
    if (xp == nil) {
        return nil;
    }
    XFBinding *binding = [[self alloc] init];
    binding.xpath = xp;
    binding.expression = expression;
    binding.element = element;
    NSString *modelID = [[element attributeForName:@"model"] stringValue];
    binding.modelID = modelID.length ? modelID : nil;
    return binding;
}

+ (instancetype)bindingForElement:(NSXMLElement *)element
                        attribute:(NSString *)attribute
                            error:(NSError **)error
{
    NSString *bindID = [[element attributeForName:@"bind"] stringValue];
    if (bindID.length) {
        XFBinding *binding = [[self alloc] init];
        binding.bindID = bindID;
        binding.element = element;
        binding.expression = [NSString stringWithFormat:@"bind(%@)", bindID];
        NSString *modelID = [[element attributeForName:@"model"] stringValue];
        binding.modelID = modelID.length ? modelID : nil;
        return binding;
    }
    // nodeset and ref are interchangeable; `value` only when asked for
    // (xf:output/@value, xf:label/@value) or when nothing is preferred
    NSArray<NSString *> *candidates;
    if (attribute.length) {
        candidates = @[ attribute, [attribute isEqualToString:@"nodeset"] ? @"ref" : @"nodeset" ];
    } else {
        candidates = @[ @"nodeset", @"ref", @"value" ];
    }
    for (NSString *attr in candidates) {
        NSString *expr = [[element attributeForName:attr] stringValue];
        if (expr.length) {
            return [self bindingWithExpression:expr element:element error:error];
        }
    }
    return nil;
}

#pragma mark - resolution

static NSArray<XFModel *> *XFModelsOf(XFModel *model)
{
    if ([model.owner isKindOfClass:[XFProcessor class]]) {
        return [(XFProcessor *)model.owner models];
    }
    return model ? @[ model ] : @[];
}

- (XFModel *)targetModelInContext:(XFExprContext *)context
{
    if (self.modelID.length == 0) {
        return nil;
    }
    for (XFModel *m in XFModelsOf(context.model)) {
        if ([m.identifier isEqualToString:self.modelID]) {
            return m;
        }
    }
    return nil;
}

/// XsltForms_binding.bind_evaluate: with a `model`, the context node is
/// kept only when it belongs to that model; otherwise the model's default
/// instance root is the context.
- (XFExprContext *)contextForEvaluation:(XFExprContext *)context
{
    XFModel *target = [self targetModelInContext:context];
    if (target == nil) {
        return context;
    }
    if (context.contextNode && [target instanceOwningNode:context.contextNode]) {
        if (context.model == target) {
            return context;
        }
        XFExprContext *c = [context cloneWithNode:context.contextNode position:context.position nodeList:context.nodeList];
        c.model = target;
        return c;
    }
    NSXMLElement *root = [[target defaultInstance] documentElement];
    XFExprContext *c = [context cloneWithNode:root position:1 nodeList:root ? @[ root ] : @[]];
    c.model = target;
    return c;
}

- (XFBind *)resolveBindInContext:(XFExprContext *)context
{
    XFModel *first = [self targetModelInContext:context] ?: context.model;
    XFBind *bind = [first bindWithIdentifier:self.bindID];
    if (bind) {
        return bind;
    }
    for (XFModel *m in XFModelsOf(context.model)) {
        bind = [m bindWithIdentifier:self.bindID];
        if (bind) {
            return bind;
        }
    }
    return nil;
}

- (XFXPathValue *)evaluateInContext:(XFExprContext *)context error:(NSError **)error
{
    XFExprContext *ctx = [self contextForEvaluation:context];
    if (self.bindID) {
        XFBind *bind = [self resolveBindInContext:ctx];
        if (bind == nil) {
            // XsltForms_element.evaluateBinding → globals.error (G-30)
            [XFXMLEvents raise:@"xforms-binding-exception" on:self.element
                       message:[NSString stringWithFormat:@"no bind with id '%@'", self.bindID]];
            if (error) {
                *error = [NSError errorWithDomain:XFErrorDomain
                                             code:XFErrorBinding
                                         userInfo:@{ NSLocalizedDescriptionKey:
                                                         [NSString stringWithFormat:@"no bind with id '%@'", self.bindID] }];
            }
            return nil;
        }
        // XsltForms_binding: result = bind.nodes (+ its dependencies)
        NSArray<NSXMLNode *> *nodes = [bind.nodes copy];
        for (NSXMLNode *n in nodes) {
            [context addDependency:n];
        }
        [context addDepElement:bind];
        return [XFXPathValue nodeSet:nodes];
    }
    // XsltForms_exprContext carries the evaluating subform: stamp the host
    // element so subform-instance()/subform-context() resolve THIS form's
    // subform even when the inherited context belongs to the parent form
    NSXMLElement *prevSource = ctx.sourceElement;
    if (self.element) {
        ctx.sourceElement = self.element;
    }
    XFXPathValue *value = [self.xpath evaluateInContext:ctx error:error];
    ctx.sourceElement = prevSource;
    if (ctx != context) {
        for (NSXMLNode *n in [ctx dependencyNodes]) {
            [context addDependency:n];
        }
    }
    return value;
}

- (NSXMLNode *)boundNodeInContext:(XFExprContext *)context error:(NSError **)error
{
    XFXPathValue *value = [self evaluateInContext:context error:error];
    return value.firstNode;
}

- (NSString *)stringValueInContext:(XFExprContext *)context error:(NSError **)error
{
    if (self.bindID || self.modelID) {
        XFXPathValue *value = [self evaluateInContext:context error:error];
        return value ? [value stringValue] : nil;
    }
    return [self.xpath stringValueInContext:context error:error];
}

@end
