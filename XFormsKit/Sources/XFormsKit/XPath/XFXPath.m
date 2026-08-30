#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "XFXPath.h"
#import "XFXPathPriv.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFErrors.h"
#import <Foundation/NSXMLElement.h>

@interface XFXPath ()
@property (nonatomic, copy, readwrite) NSString *expression;
@property (nonatomic, strong) XFExpr *compiled;
@property (nonatomic, strong) XFNSResolver *nsresolver;
@end

@implementation XFXPath

+ (NSMutableDictionary<NSString *, XFXPath *> *)expressions
{
    static NSMutableDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = [NSMutableDictionary dictionary];
    });
    return map;
}

+ (instancetype)xpathWithString:(NSString *)expression error:(NSError **)error
{
    return [self xpathWithString:expression element:nil error:error];
}

/// Prefixes used in QName tokens of the expression (name tests and
/// function names), skipping axis specifiers (`child::`).
+ (NSArray<NSString *> *)prefixesInExpression:(NSString *)expression
{
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
              @"(?<![A-Za-z0-9_.:-])([A-Za-z_][A-Za-z0-9_.-]*):(?!:)(?=[A-Za-z_*])"
                                                       options:0 error:NULL];
    });
    NSMutableArray *out = [NSMutableArray array];
    // strip string literals first
    NSString *bare = [[NSRegularExpression regularExpressionWithPattern:@"'[^']*'|\"[^\"]*\"" options:0 error:NULL]
                      stringByReplacingMatchesInString:expression options:0 range:NSMakeRange(0, expression.length) withTemplate:@"''"];
    for (NSTextCheckingResult *m in [re matchesInString:bare options:0 range:NSMakeRange(0, bare.length)]) {
        NSString *prefix = [bare substringWithRange:[m rangeAtIndex:1]];
        if (![out containsObject:prefix]) {
            [out addObject:prefix];
        }
    }
    return out;
}

/// XSLTForms compiles namespace prefixes into each expression from the
/// in-scope declarations of the element carrying it (js2ns.xsl). Passing
/// the host element here does the same; prefixes already registered (by an
/// earlier element using the same expression) are kept.
+ (instancetype)xpathWithString:(NSString *)expression
                        element:(NSXMLElement *)element
                          error:(NSError **)error
{
    if (expression == nil) {
        return nil;
    }
    XFXPath *cached = [self expressions][expression];
    if (cached) {
        [cached registerPrefixesFromElement:element];
        return cached;
    }
    NSError *inner = nil;
    XFXPathParser *parser = [[XFXPathParser alloc] initWithString:expression];
    XFExpr *ast = [parser parseExpression:&inner];
    if (ast == nil) {
        if (error) {
            *error = inner;
        }
        return nil;
    }
    XFXPath *xp = [[self alloc] init];
    xp.expression = expression;
    xp.compiled = ast;
    xp.nsresolver = [[XFNSResolver alloc] init];
    [xp registerPrefixesFromElement:element];
    [self expressions][expression] = xp;
    return xp;
}

- (void)registerPrefixesFromElement:(NSXMLElement *)element
{
    if (element == nil) {
        return;
    }
    for (NSString *prefix in [[self class] prefixesInExpression:self.expression]) {
        if ([self.nsresolver lookupNamespaceURI:prefix] != nil) {
            continue;
        }
        NSXMLNode *ns = [element resolveNamespaceForName:[prefix stringByAppendingString:@":x"]];
        NSString *uri = [ns stringValue];
        if (uri.length) {
            [self.nsresolver registerPrefix:prefix uri:uri];
        }
    }
}

- (XFNSResolver *)namespaceResolver
{
    return self.nsresolver;
}

- (XFXPathValue *)evaluateInContext:(XFExprContext *)context error:(NSError **)error
{
    if (context.nsResolver == nil) {
        context.nsResolver = self.nsresolver;
    } else if (context.nsResolver != self.nsresolver) {
        [context.nsResolver registerAll:self.nsresolver];
    }
    NSError *inner = nil;
    XFXPathValue *value = [self.compiled evaluate:context error:&inner];
    if (value == nil) {
        if (error) {
            *error = inner ?: [NSError errorWithDomain:XFErrorDomain
                                                  code:XFErrorXPathEvaluation
                                              userInfo:@{ NSLocalizedDescriptionKey:
                                                              [NSString stringWithFormat:
                                                               @"Error evaluating XPath: %@", self.expression] }];
        }
        return nil;
    }
    return value;
}

- (NSString *)stringValueInContext:(XFExprContext *)context error:(NSError **)error
{
    XFXPathValue *value = [self evaluateInContext:context error:error];
    return value ? [value stringValue] : nil;
}

- (NSArray<NSXMLNode *> *)nodesInContext:(XFExprContext *)context error:(NSError **)error
{
    XFXPathValue *value = [self evaluateInContext:context error:error];
    return value ? value.nodes : nil;
}

@end
