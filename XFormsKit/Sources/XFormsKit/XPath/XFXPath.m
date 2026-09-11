#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "XFXPath.h"
#import "XFXPathPriv.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFErrors.h"
#import <XFormsKit/XFXMLTypes.h>

@interface XFXPath ()
@property (nonatomic, copy, readwrite) NSString *expression;
@property (nonatomic, strong) XFExpr *compiled;
@property (nonatomic, strong) XFNSResolver *nsresolver;
@end

/// name → XFXPathFunction; consulted by XFXPathCoreFunctions after the
/// built-in tables miss.
NSMutableDictionary *XFXPathHostFunctionTable(void)
{
    static NSMutableDictionary *table;
    if (table == nil) {
        table = [NSMutableDictionary dictionary];
    }
    return table;
}

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

+ (void)registerHostFunctionNamed:(NSString *)name
                        evaluator:(XFXPathHostFunction)evaluator
{
    if (name.length == 0 || evaluator == nil) {
        return;
    }
    XFXPathHostFunctionTable()[name] =
        [XFXPathFunction acceptContext:NO defaultTo:XFXPathFnDefaultNone
                                  body:evaluator];
}

+ (void)unregisterHostFunctionNamed:(NSString *)name
{
    if (name != nil) {
        [XFXPathHostFunctionTable() removeObjectForKey:name];
    }
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
                        element:(XFXMLElement *)element
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

- (void)registerPrefixesFromElement:(XFXMLElement *)element
{
    if (element == nil) {
        return;
    }
    for (NSString *prefix in [[self class] prefixesInExpression:self.expression]) {
        if ([self.nsresolver lookupNamespaceURI:prefix] != nil) {
            continue;
        }
        XFXMLNode *ns = [element resolveNamespaceForName:[prefix stringByAppendingString:@":x"]];
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
    // XSLT current(): the context node of the EXPRESSION as a whole —
    // (re)stamped at the top of each full evaluation, so a predicate's
    // inner context can still see it (month[@code = current()] inside a
    // repeat item, 7.10.2.b). Kept SEPARATE from currentNode, which the
    // XForms context() function reads as the outer in-scope context
    // (setvalue value="context()", 7.10.4.a).
    XFXMLNode *prevStart = context.expressionStartNode;
    context.expressionStartNode = context.contextNode;
    NSError *inner = nil;
    XFXPathValue *value = [self.compiled evaluate:context error:&inner];
    context.expressionStartNode = prevStart;
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

- (NSArray<XFXMLNode *> *)nodesInContext:(XFExprContext *)context error:(NSError **)error
{
    XFXPathValue *value = [self evaluateInContext:context error:error];
    return value ? value.nodes : nil;
}

- (NSDictionary *)structure
{
    return [self.compiled xfStructure];
}

- (NSString *)canonicalSource
{
    return [self.compiled xfSource];
}

- (NSString *)sourceReplacingNodeAtPath:(NSArray<NSNumber *> *)path
                                   with:(NSString *)source
{
    XFExpr *target = self.compiled;
    for (NSNumber *index in path) {
        NSArray *children = [target xfChildren];
        NSUInteger i = [index unsignedIntegerValue];
        if (i >= children.count) {
            return nil;
        }
        target = children[i];
    }
    if (target == nil) {
        return nil;
    }
    NSMapTable *overrides = [NSMapTable strongToStrongObjectsMapTable];
    [overrides setObject:source ?: @"" forKey:target];
    return [self.compiled xfSourceWithOverrides:overrides];
}

/// Do the token kinds/texts to the LEFT leave us after an operand? The
/// lexer's own rule (XPath 1.0 §3.7), mirrored for classification.
static BOOL XFTokenEndsOperand(XFXPathToken *t)
{
    switch (t.kind) {
        case XFXPathTokenNumber:
        case XFXPathTokenString:
        case XFXPathTokenRParen:
        case XFXPathTokenRBrack:
        case XFXPathTokenDot:
        case XFXPathTokenDotDot:
        case XFXPathTokenStar:
        case XFXPathTokenName:
            return YES;
        default:
            return NO;
    }
}

+ (NSArray<NSDictionary *> *)highlightTokensForString:(NSString *)expression
{
    XFXPathLexer *lexer = [[XFXPathLexer alloc] initWithString:expression ?: @""];
    NSMutableArray *tokens = [NSMutableArray array];
    for (;;) {
        XFXPathToken *t = [lexer next];
        if (t.kind == XFXPathTokenEOF) {
            break;
        }
        [tokens addObject:t];
        if (tokens.count > 4096) {
            break;   // hostile input guard
        }
    }
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:tokens.count];
    for (NSUInteger i = 0; i < tokens.count; i++) {
        XFXPathToken *t = tokens[i];
        XFXPathToken *prev = i > 0 ? tokens[i - 1] : nil;
        XFXPathToken *next = i + 1 < tokens.count ? tokens[i + 1] : nil;
        NSString *kind;
        switch (t.kind) {
            case XFXPathTokenString: kind = @"string"; break;
            case XFXPathTokenNumber: kind = @"number"; break;
            case XFXPathTokenAnd:
            case XFXPathTokenOr:
            case XFXPathTokenPlus:
            case XFXPathTokenMinus:
            case XFXPathTokenEq:
            case XFXPathTokenNe:
            case XFXPathTokenLt:
            case XFXPathTokenGt:
            case XFXPathTokenLe:
            case XFXPathTokenGe:
            case XFXPathTokenUnion:
                kind = @"operator";
                break;
            case XFXPathTokenDollar:
                kind = @"variable";
                break;
            case XFXPathTokenStar:
                kind = (prev != nil && XFTokenEndsOperand(prev)) ? @"operator" : @"name";
                break;
            case XFXPathTokenName:
                if (prev != nil && prev.kind == XFXPathTokenDollar) {
                    kind = @"variable";
                } else if (next != nil && next.kind == XFXPathTokenLParen) {
                    kind = @"function";
                } else if (next != nil && next.kind == XFXPathTokenColonColon) {
                    kind = @"axis";
                } else if (prev != nil && XFTokenEndsOperand(prev)
                           && ([t.text isEqualToString:@"div"] || [t.text isEqualToString:@"mod"])) {
                    kind = @"operator";
                } else {
                    kind = @"name";
                }
                break;
            default:
                kind = @"punct";
                break;
        }
        [out addObject:@{ @"kind": kind,
                          @"range": [NSValue valueWithRange:t.range] }];
    }
    return out;
}

+ (BOOL)hasFunctionNamed:(NSString *)name
{
    return name.length > 0 && [XFXPathCoreFunctions functionNamed:name] != nil;
}

@end
