#import "XFInstance.h"
#import "XFErrors.h"
#import "XFXML.h"
#import "XFModel.h"
#import "XFBind.h"
#import "XFNodeState.h"
#import "XFMIPBinding.h"
#import "XFExprContext.h"
#import "XFXPathValue.h"
#import <Foundation/NSXMLDocument.h>
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLNode.h>

@interface XFInstance ()
@property (nonatomic, strong, readwrite) NSXMLDocument *document;
@property (nonatomic, strong, readwrite) NSXMLDocument *originalDocument;
@end

@implementation XFInstance

+ (instancetype)instanceWithElement:(NSXMLElement *)instanceElement
                              error:(NSError **)error
{
    XFInstance *instance = [[self alloc] init];
    NSXMLNode *idAttr = [instanceElement attributeForName:@"id"];
    instance.identifier = idAttr ? [idAttr stringValue] : nil;
    instance.element = instanceElement;

    NSXMLElement *dataRoot = nil;
    for (NSXMLNode *child in [instanceElement children]) {
        if ([child kind] == NSXMLElementKind) {
            dataRoot = (NSXMLElement *)child;
            break;
        }
    }
    if (dataRoot == nil) {
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorDocument
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"xf:instance has no inline document element" }];
        }
        return nil;
    }

    // Detach a deep copy so the live instance is a standalone document.
    NSXMLElement *copy = [dataRoot copy];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:copy];
    [doc setVersion:@"1.0"];
    [doc setCharacterEncoding:@"UTF-8"];
    instance.document = doc;
    instance.originalDocument = [doc copy];
    return instance;
}

- (NSXMLElement *)documentElement
{
    return [self.document rootElement];
}

- (void)construct
{
    // Inline instance documents are already loaded by instanceWithElement:.
    // Remote @src is a later slice.
}

- (void)reset
{
    self.document = [self.originalDocument copy];
}

- (BOOL)replaceWithXMLString:(NSString *)xml error:(NSError **)error
{
    if (xml.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorDocument
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"empty instance replacement" }];
        }
        return NO;
    }
    NSError *inner = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:&inner];
    if (doc == nil || [doc rootElement] == nil) {
        if (error) {
            *error = inner ?: [NSError errorWithDomain:XFErrorDomain
                                                  code:XFErrorDocument
                                              userInfo:@{ NSLocalizedDescriptionKey:
                                                              @"could not parse instance replacement" }];
        }
        return NO;
    }
    self.document = doc;
    return YES;
}

- (void)revalidate
{
    NSXMLElement *root = [self documentElement];
    if (root) {
        [self validateNode:root readonly:NO notRelevant:NO];
    }
}

- (BOOL)booleanMIP:(XFMIPBinding *)mip
              node:(NSXMLNode *)node
          position:(NSUInteger)position
          nodeList:(NSArray<NSXMLNode *> *)nodeList
           default:(BOOL)fallback
{
    if (mip == nil) {
        return fallback;
    }
    XFExprContext *ctx = [[XFExprContext alloc] initWithNode:node];
    ctx.model = self.model;
    ctx.position = position;
    ctx.nodeList = nodeList;
    ctx.size = nodeList.count;
    XFXPathValue *value = [mip evaluateInContext:ctx node:node model:self.model error:NULL];
    return value ? [value booleanValue] : fallback;
}

- (void)validateNode:(NSXMLNode *)node readonly:(BOOL)readonly notRelevant:(BOOL)notRelevant
{
    XFNodeState *state = [XFNodeState existingStateOnNode:node];
    if (state.bindIdentifiers.count > 0) {
        NSString *value = [XFXML stringValueOfNode:node];
        BOOL relevantFound = NO;
        BOOL readonlyFound = NO;
        BOOL required = NO;
        BOOL relevant = !notRelevant;
        BOOL isReadonly = readonly;
        BOOL constraintOK = YES;

        for (NSString *bindID in [state.bindIdentifiers copy]) {
            XFBind *bind = [self.model bindWithIdentifier:bindID];
            if (bind == nil) {
                continue;
            }
            NSUInteger position = 1;
            NSUInteger i = 0;
            for (NSXMLNode *n in bind.nodes) {
                if (n == node) {
                    position = i + 1;
                    break;
                }
                i++;
            }
            required = required || [self booleanMIP:bind.required
                                               node:node
                                           position:position
                                           nodeList:bind.nodes
                                            default:NO];
            if (notRelevant || !relevantFound || bind.relevant) {
                BOOL mipRelevant = [self booleanMIP:bind.relevant
                                               node:node
                                           position:position
                                           nodeList:bind.nodes
                                            default:YES];
                relevant = !notRelevant && mipRelevant;
                relevantFound = relevantFound || (bind.relevant != nil);
            }
            if (readonly || !readonlyFound || bind.readonly || bind.calculate) {
                BOOL mipRO = [self booleanMIP:bind.readonly
                                         node:node
                                     position:position
                                     nodeList:bind.nodes
                                      default:(bind.calculate != nil)];
                isReadonly = readonly || mipRO;
                readonlyFound = readonlyFound || (bind.readonly != nil) || (bind.calculate != nil);
            }
            constraintOK = constraintOK && [self booleanMIP:bind.constraint
                                                       node:node
                                                   position:position
                                                   nodeList:bind.nodes
                                                    default:YES];
        }

        BOOL empty = (value.length == 0);
        BOOL valid = YES;
        if (relevant) {
            if (required && empty) {
                valid = NO;
            }
            if (!constraintOK) {
                valid = NO;
            }
        }
        state.required = required;
        state.relevant = relevant;
        state.readonly = isReadonly;
        state.constraint = constraintOK;
        state.valid = valid;
        notRelevant = !relevant;
        readonly = isReadonly;
    } else if (notRelevant || readonly) {
        XFNodeState *inherited = [XFNodeState stateOnNode:node];
        if (notRelevant) {
            inherited.relevant = NO;
        }
        if (readonly) {
            inherited.readonly = YES;
        }
    }

    if ([node kind] == NSXMLElementKind) {
        NSXMLElement *element = (NSXMLElement *)node;
        for (NSXMLNode *attr in [element attributes]) {
            NSString *name = [attr name];
            if ([name hasPrefix:@"xmlns"]) {
                continue;
            }
            [self validateNode:attr readonly:readonly notRelevant:notRelevant];
        }
        for (NSXMLNode *child in [element children]) {
            if ([child kind] == NSXMLElementKind) {
                [self validateNode:child readonly:readonly notRelevant:notRelevant];
            }
        }
    }
}

@end
