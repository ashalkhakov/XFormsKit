#import "XFBind.h"
#import "XFModel.h"
#import "XFInstance.h"
#import "XFBinding.h"
#import "XFMIPBinding.h"
#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFNodeState.h"
#import "XFXML.h"
#import "XFNamespaces.h"
#import "XFType.h"
#import "XFXMLEvents.h"
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLNode.h>

static NSInteger XFNextDepsId(void)
{
    static NSInteger next = 1;
    @synchronized([XFBind class]) {
        return next++;
    }
}

@interface XFBind ()
@property (nonatomic, strong, readwrite) NSXMLElement *element;
@property (nonatomic, strong, readwrite) XFBinding *nodesetBinding;
@property (nonatomic, strong, readwrite) NSMutableArray<NSXMLNode *> *nodes;
@property (nonatomic, strong, readwrite) NSMutableArray<NSXMLNode *> *depsNodes;
@property (nonatomic, strong, readwrite) NSMutableArray *depsElements;
@property (nonatomic, strong, readwrite) NSMutableArray<XFBind *> *binds;
@end

@implementation XFBind

+ (instancetype)bindWithElement:(NSXMLElement *)element
                          model:(XFModel *)model
                         parent:(XFBind *)parent
                          error:(NSError **)error
{
    XFBind *bind = [[self alloc] init];
    bind.element = element;
    bind.model = model;
    bind.parent = parent;
    bind.nodes = [NSMutableArray array];
    bind.depsNodes = [NSMutableArray array];
    bind.depsElements = [NSMutableArray array];
    bind.binds = [NSMutableArray array];
    bind.depsId = XFNextDepsId();

    NSString *identifier = [[element attributeForName:@"id"] stringValue];
    if (identifier.length == 0) {
        identifier = [NSString stringWithFormat:@"xf-bind-%ld", (long)bind.depsId];
    }
    bind.identifier = identifier;

    NSString *nodeset = [[element attributeForName:@"ref"] stringValue];
    if (nodeset.length == 0) {
        nodeset = [[element attributeForName:@"nodeset"] stringValue];
    }
    if (nodeset.length) {
        bind.nodesetBinding = [XFBinding bindingWithExpression:nodeset element:element error:error];
        if (bind.nodesetBinding == nil) {
            return nil;
        }
    }

    // @type resolved with the in-scope namespaces of the bind element
    // (XsltForms_schema.getType through the document prefixes): stored as
    // {ns}local so user schema types are found (G-57)
    NSString *typeName = [[element attributeForName:@"type"] stringValue];
    if (typeName.length) {
        NSRange colon = [typeName rangeOfString:@":"];
        if (colon.location != NSNotFound) {
            NSString *prefix = [typeName substringToIndex:colon.location];
            NSString *ns = [[element resolveNamespaceForName:[prefix stringByAppendingString:@":x"]] stringValue];
            if (ns.length) {
                typeName = [NSString stringWithFormat:@"{%@}%@", ns, [typeName substringFromIndex:colon.location + 1]];
            }
        }
    }
    bind.typeName = typeName;

    NSError *inner = nil;
    NSString *calculate = [[element attributeForName:@"calculate"] stringValue];
    if (calculate.length) {
        bind.calculate = [XFXPath xpathWithString:calculate element:element error:&inner];
        if (bind.calculate == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
    }

    NSDictionary *mips = @{
        @"relevant"   : @"relevant",
        @"required"   : @"required",
        @"readonly"   : @"readonly",
        @"constraint" : @"constraint"
    };
    for (NSString *attr in mips) {
        NSString *expr = [[element attributeForName:attr] stringValue];
        if (expr.length == 0) {
            continue;
        }
        XFMIPBinding *mip = [XFMIPBinding mipBindingWithExpression:expr element:element error:&inner];
        if (mip == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
        [bind setValue:mip forKey:mips[attr]];
    }

    NSArray<NSXMLElement *> *children =
        [XFXML childElementsWithLocalName:@"bind"
                            namespaceURI:XFXFormsNamespaceURI
                               ofElement:element];
    for (NSXMLElement *child in children) {
        XFBind *childBind = [XFBind bindWithElement:child
                                              model:model
                                             parent:bind
                                              error:&inner];
        if (childBind == nil) {
            if (error) {
                *error = inner;
            }
            return nil;
        }
        [bind addBind:childBind];
    }
    return bind;
}

- (void)addBind:(XFBind *)bind
{
    if (bind) {
        [self.binds addObject:bind];
    }
}

- (void)clear
{
    [self.depsNodes removeAllObjects];
    [self.depsElements removeAllObjects];
    [self.nodes removeAllObjects];
    for (XFBind *child in self.binds) {
        [child clear];
    }
}

- (XFExprContext *)contextWithNode:(NSXMLNode *)node
                          position:(NSUInteger)position
                          nodeList:(NSArray<NSXMLNode *> *)nodeList
{
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:node];
    ctx.model = self.model;
    if (position > 0) {
        ctx.position = position;
    }
    if (nodeList) {
        ctx.nodeList = nodeList;
        ctx.size = nodeList.count;
    }
    return ctx;
}

- (void)refresh
{
    [self refreshWithContextNode:nil index:0];
}

- (void)refreshWithContextNode:(NSXMLNode *)ctx index:(NSUInteger)index
{
    (void)index;
    if (ctx == nil) {
        [self clear];
        ctx = [[self.model defaultInstance] documentElement];
    }

    if (self.nodesetBinding) {
        XFExprContext *eval = [self contextWithNode:ctx position:1 nodeList:ctx ? @[ ctx ] : @[]];
        NSError *inner = nil;
        NSArray<NSXMLNode *> *selected = [self.nodesetBinding evaluateInContext:eval error:&inner].nodes;
        [self.nodes removeAllObjects];
        [self.nodes addObjectsFromArray:selected ?: @[]];
        for (NSXMLNode *dep in eval.dependencyNodes) {
            if (![self.depsNodes containsObject:dep]) {
                [self.depsNodes addObject:dep];
            }
        }
        if (self.model && ![self.depsElements containsObject:self.model]) {
            [self.depsElements addObject:self.model];
        }
    } else if (ctx) {
        [self.nodes removeAllObjects];
        [self.nodes addObject:ctx];
    }

    NSUInteger i = 0;
    for (NSXMLNode *node in [self.nodes copy]) {
        [XFNodeState attachBind:self.identifier toNode:node];
        if (self.typeName.length) {
            // XFBind.js: a node typed by xsi:type cannot also be typed by a bind
            NSXMLNode *xsi = [node kind] == NSXMLElementKind
                ? [(NSXMLElement *)node attributeForLocalName:@"type" URI:@"http://www.w3.org/2001/XMLSchema-instance"] : nil;
            if (xsi) {
                [XFXMLEvents raise:@"xforms-binding-exception" on:self.element
                           message:@"Type especified in xsi:type attribute"];
            } else {
                [XFNodeState stateOnNode:node].typeName = self.typeName;
            }
        }
        if (self.calculate) {
            [XFNodeState stateOnNode:node].readonly = YES;
        }
        for (XFBind *child in self.binds) {
            [child refreshWithContextNode:node index:i];
        }
        i++;
    }
}

- (void)recalculate
{
    if (self.calculate) {
        NSUInteger i = 0;
        for (NSXMLNode *node in [self.nodes copy]) {
            XFExprContext *ctx = [self contextWithNode:node
                                              position:i + 1
                                              nodeList:self.nodes];
            NSError *inner = nil;
            NSString *value = [self.calculate stringValueInContext:ctx error:&inner] ?: @"";
            // XFBind.js recalculate: type.normalize(value) (G-57)
            XFType *type = [XFType typeNamed:[XFNodeState existingStateOnNode:node].typeName ?: self.typeName];
            if (type) {
                value = [type normalizeValue:value];
            }
            [XFXML setStringValue:value ofNode:node];
            [self.model addChange:node];
            i++;
        }
    }
    for (XFBind *child in self.binds) {
        [child recalculate];
    }
}


+ (void)disposeNode:(NSXMLNode *)node model:(XFModel *)model
{
    if (node == nil) {
        return;
    }
    XFNodeState *state = [XFNodeState existingStateOnNode:node];
    for (NSString *bindID in state.bindIdentifiers) {
        XFBind *bind = [model bindWithIdentifier:bindID];
        for (XFMIPBinding *mip in @[ bind.relevant ?: (id)[NSNull null], bind.required ?: (id)[NSNull null],
                                     bind.readonly ?: (id)[NSNull null], bind.constraint ?: (id)[NSNull null] ]) {
            if ([mip isKindOfClass:[XFMIPBinding class]]) {
                [mip disposeNode:node];
            }
        }
        NSUInteger i = [bind.nodes indexOfObjectIdenticalTo:node];
        if (i != NSNotFound) {
            [bind.nodes removeObjectAtIndex:i];
        }
    }
    if ([node kind] == NSXMLElementKind) {
        for (NSXMLNode *attr in [(NSXMLElement *)node attributes]) {
            [self disposeNode:attr model:model];
        }
    }
    for (NSXMLNode *child in [node children]) {
        [self disposeNode:child model:model];
    }
}

@end
