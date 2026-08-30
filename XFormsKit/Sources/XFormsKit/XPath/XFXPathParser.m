#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "XFXPathPriv.h"
#import "XFXPathValue.h"
#import "XFErrors.h"

@implementation XFXPathParser {
    XFXPathLexer *_lexer;
    XFXPathToken *_token;
    XFXPathToken *_ahead;
}

- (instancetype)initWithString:(NSString *)string
{
    self = [super init];
    if (self) {
        _lexer = [[XFXPathLexer alloc] initWithString:string];
        _token = [_lexer next];
        _ahead = nil;
    }
    return self;
}

- (XFXPathToken *)peekToken
{
    if (_ahead == nil) {
        _ahead = [_lexer next];
    }
    return _ahead;
}

- (void)advance
{
    if (_ahead) {
        _token = _ahead;
        _ahead = nil;
    } else {
        _token = [_lexer next];
    }
}

- (BOOL)accept:(XFXPathTokenKind)kind
{
    if (_token.kind == kind) {
        [self advance];
        return YES;
    }
    return NO;
}

- (NSError *)syntaxError:(NSString *)message
{
    return [NSError errorWithDomain:XFErrorDomain
                               code:XFErrorXPathSyntax
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

- (BOOL)isDivOrMod
{
    return _token.kind == XFXPathTokenName &&
           ([_token.text isEqualToString:@"div"] || [_token.text isEqualToString:@"mod"]);
}

- (XFExpr *)parseExpression:(NSError **)error
{
    NSError *local = nil;
    XFExpr *expr = [self parseOr:&local];
    if (local) {
        if (error) *error = local;
        return nil;
    }
    if (_token.kind != XFXPathTokenEOF) {
        local = [self syntaxError:[NSString stringWithFormat:@"unexpected token '%@'", _token.text]];
        if (error) *error = local;
        return nil;
    }
    return expr;
}

- (XFExpr *)parseOr:(NSError **)error
{
    XFExpr *left = [self parseAnd:error];
    while (!*error && _token.kind == XFXPathTokenOr) {
        [self advance];
        left = [XFBinaryExpr expr1:left op:@"or" expr2:[self parseAnd:error]];
    }
    return left;
}

- (XFExpr *)parseAnd:(NSError **)error
{
    XFExpr *left = [self parseEquality:error];
    while (!*error && _token.kind == XFXPathTokenAnd) {
        [self advance];
        left = [XFBinaryExpr expr1:left op:@"and" expr2:[self parseEquality:error]];
    }
    return left;
}

- (XFExpr *)parseEquality:(NSError **)error
{
    XFExpr *left = [self parseRelational:error];
    while (!*error && (_token.kind == XFXPathTokenEq || _token.kind == XFXPathTokenNe)) {
        NSString *op = _token.kind == XFXPathTokenEq ? @"=" : @"!=";
        [self advance];
        left = [XFBinaryExpr expr1:left op:op expr2:[self parseRelational:error]];
    }
    return left;
}

- (XFExpr *)parseRelational:(NSError **)error
{
    XFExpr *left = [self parseAdditive:error];
    while (!*error && (_token.kind == XFXPathTokenLt || _token.kind == XFXPathTokenGt ||
                       _token.kind == XFXPathTokenLe || _token.kind == XFXPathTokenGe)) {
        NSString *op = _token.text;
        [self advance];
        left = [XFBinaryExpr expr1:left op:op expr2:[self parseAdditive:error]];
    }
    return left;
}

- (XFExpr *)parseAdditive:(NSError **)error
{
    XFExpr *left = [self parseMultiplicative:error];
    while (!*error && (_token.kind == XFXPathTokenPlus || _token.kind == XFXPathTokenMinus)) {
        NSString *op = _token.text;
        [self advance];
        left = [XFBinaryExpr expr1:left op:op expr2:[self parseMultiplicative:error]];
    }
    return left;
}

- (XFExpr *)parseMultiplicative:(NSError **)error
{
    XFExpr *left = [self parseUnary:error];
    while (!*error && (_token.kind == XFXPathTokenStar || [self isDivOrMod])) {
        NSString *op = _token.kind == XFXPathTokenStar ? @"*" : _token.text;
        [self advance];
        left = [XFBinaryExpr expr1:left op:op expr2:[self parseUnary:error]];
    }
    return left;
}

- (XFExpr *)parseUnary:(NSError **)error
{
    if (_token.kind == XFXPathTokenMinus) {
        [self advance];
        return [XFUnaryMinusExpr expr:[self parseUnary:error]];
    }
    return [self parseUnion:error];
}

- (XFExpr *)parseUnion:(NSError **)error
{
    XFExpr *left = [self parsePath:error];
    while (!*error && _token.kind == XFXPathTokenUnion) {
        [self advance];
        left = [XFUnionExpr expr1:left expr2:[self parsePath:error]];
    }
    return left;
}

- (BOOL)startsLocationPath
{
    if (_token.kind == XFXPathTokenSlash || _token.kind == XFXPathTokenSlashSlash ||
        _token.kind == XFXPathTokenDot || _token.kind == XFXPathTokenDotDot ||
        _token.kind == XFXPathTokenAt || _token.kind == XFXPathTokenStar) {
        return YES;
    }
    if (_token.kind == XFXPathTokenName) {
        XFXPathToken *peek = [self peekToken];
        if (peek.kind == XFXPathTokenLParen) {
            return NO; // function call
        }
        return YES;
    }
    return NO;
}

- (XFExpr *)parsePath:(NSError **)error
{
    if (_token.kind == XFXPathTokenSlash || _token.kind == XFXPathTokenSlashSlash ||
        [self startsLocationPath]) {
        return [self parseLocationPath:error];
    }
    XFExpr *filter = [self parseFilter:error];
    if (*error) {
        return nil;
    }
    if (_token.kind == XFXPathTokenSlash || _token.kind == XFXPathTokenSlashSlash) {
        XFExpr *rel = [self parseRelativeAfterSlash:error];
        if (*error) {
            return nil;
        }
        return [XFPathExpr filter:filter rel:rel];
    }
    return filter;
}

- (XFExpr *)parseFilter:(NSError **)error
{
    XFExpr *primary = [self parsePrimary:error];
    if (*error) {
        return nil;
    }
    NSArray *preds = [self parsePredicateList:error];
    if (*error) {
        return nil;
    }
    if (preds.count == 0) {
        return primary;
    }
    NSMutableArray *wrapped = [NSMutableArray array];
    for (XFExpr *p in preds) {
        [wrapped addObject:[XFPredicateExpr expr:p]];
    }
    return [XFFilterExpr expr:primary predicates:wrapped];
}

- (XFExpr *)parsePrimary:(NSError **)error
{
    if (_token.kind == XFXPathTokenString) {
        XFExpr *lit = [XFCteExpr string:_token.text];
        [self advance];
        return lit;
    }
    if (_token.kind == XFXPathTokenNumber) {
        XFExpr *lit = [XFCteExpr number:_token.number];
        [self advance];
        return lit;
    }
    if (_token.kind == XFXPathTokenDollar) {
        [self advance];
        if (_token.kind != XFXPathTokenName) {
            *error = [self syntaxError:@"expected variable name"];
            return nil;
        }
        XFVarRef *v = [XFVarRef name:_token.text];
        [self advance];
        return v;
    }
    if (_token.kind == XFXPathTokenLParen) {
        [self advance];
        XFExpr *inner = [self parseOr:error];
        if (![self accept:XFXPathTokenRParen]) {
            *error = [self syntaxError:@"expected ')'"];
            return nil;
        }
        return inner;
    }
    if (_token.kind == XFXPathTokenName && [self peekToken].kind == XFXPathTokenLParen) {
        return [self parseFunction:error];
    }
    *error = [self syntaxError:@"expected primary expression"];
    return nil;
}

- (XFExpr *)parseFunction:(NSError **)error
{
    NSString *name = _token.text;
    [self advance];
    if (![self accept:XFXPathTokenLParen]) {
        *error = [self syntaxError:[NSString stringWithFormat:@"expected '(' after %@", name]];
        return nil;
    }
    NSMutableArray *args = [NSMutableArray array];
    if (_token.kind != XFXPathTokenRParen) {
        while (YES) {
            XFExpr *arg = [self parseOr:error];
            if (*error) {
                return nil;
            }
            [args addObject:arg];
            if (![self accept:XFXPathTokenComma]) {
                break;
            }
        }
    }
    if (![self accept:XFXPathTokenRParen]) {
        *error = [self syntaxError:@"expected ')' after function arguments"];
        return nil;
    }
    return [XFFunctionCallExpr name:name args:args];
}

- (XFExpr *)parseLocationPath:(NSError **)error
{
    BOOL absolute = NO;
    NSMutableArray *steps = [NSMutableArray array];

    if (_token.kind == XFXPathTokenSlash) {
        absolute = YES;
        [self advance];
        if (![self startsStep]) {
            return [XFLocationExpr absolute:YES steps:@[]];
        }
    } else if (_token.kind == XFXPathTokenSlashSlash) {
        absolute = YES;
        [self advance];
        XFStepExpr *dos = [XFStepExpr axis:XFAxisDescendantOrSelf
                                      test:[XFNodeTestType anyNode]
                                predicates:@[]];
        [steps addObject:dos];
    }

    XFStepExpr *step = [self parseStep:error];
    if (*error) {
        return nil;
    }
    [steps addObject:step];

    while (_token.kind == XFXPathTokenSlash || _token.kind == XFXPathTokenSlashSlash) {
        BOOL desc = (_token.kind == XFXPathTokenSlashSlash);
        [self advance];
        if (desc) {
            [steps addObject:[XFStepExpr axis:XFAxisDescendantOrSelf
                                         test:[XFNodeTestType anyNode]
                                   predicates:@[]]];
        }
        XFStepExpr *next = [self parseStep:error];
        if (*error) {
            return nil;
        }
        [steps addObject:next];
    }
    return [XFLocationExpr absolute:absolute steps:steps];
}

- (XFExpr *)parseRelativeAfterSlash:(NSError **)error
{
    // Current token is / or //. Build a relative location path.
    NSMutableArray *steps = [NSMutableArray array];
    if (_token.kind == XFXPathTokenSlashSlash) {
        [self advance];
        [steps addObject:[XFStepExpr axis:XFAxisDescendantOrSelf
                                     test:[XFNodeTestType anyNode]
                               predicates:@[]]];
    } else {
        [self advance];
    }
    XFStepExpr *step = [self parseStep:error];
    if (*error) {
        return nil;
    }
    [steps addObject:step];
    while (_token.kind == XFXPathTokenSlash || _token.kind == XFXPathTokenSlashSlash) {
        BOOL desc = (_token.kind == XFXPathTokenSlashSlash);
        [self advance];
        if (desc) {
            [steps addObject:[XFStepExpr axis:XFAxisDescendantOrSelf
                                         test:[XFNodeTestType anyNode]
                                   predicates:@[]]];
        }
        XFStepExpr *next = [self parseStep:error];
        if (*error) {
            return nil;
        }
        [steps addObject:next];
    }
    return [XFLocationExpr absolute:NO steps:steps];
}

- (BOOL)startsStep
{
    return _token.kind == XFXPathTokenDot || _token.kind == XFXPathTokenDotDot ||
           _token.kind == XFXPathTokenAt || _token.kind == XFXPathTokenStar ||
           _token.kind == XFXPathTokenName;
}

- (XFStepExpr *)parseStep:(NSError **)error
{
    if (_token.kind == XFXPathTokenDot) {
        [self advance];
        NSArray *preds = [self parsePredicateList:error];
        return [XFStepExpr axis:XFAxisSelf test:[XFNodeTestType anyNode] predicates:[self wrapPreds:preds]];
    }
    if (_token.kind == XFXPathTokenDotDot) {
        [self advance];
        NSArray *preds = [self parsePredicateList:error];
        return [XFStepExpr axis:XFAxisParent test:[XFNodeTestType anyNode] predicates:[self wrapPreds:preds]];
    }

    NSString *axis = XFAxisChild;
    if (_token.kind == XFXPathTokenAt) {
        axis = XFAxisAttribute;
        [self advance];
    } else if (_token.kind == XFXPathTokenName && [self peekToken].kind == XFXPathTokenColonColon) {
        axis = [self axisForName:_token.text];
        if (axis == nil) {
            *error = [self syntaxError:[NSString stringWithFormat:@"unknown axis %@", _token.text]];
            return nil;
        }
        [self advance];
        [self advance]; // ::
    }

    XFNodeTest *test = [self parseNodeTest:error];
    if (*error) {
        return nil;
    }
    NSArray *preds = [self parsePredicateList:error];
    if (*error) {
        return nil;
    }
    return [XFStepExpr axis:axis test:test predicates:[self wrapPreds:preds]];
}

- (NSArray *)wrapPreds:(NSArray<XFExpr *> *)preds
{
    NSMutableArray *out = [NSMutableArray array];
    for (XFExpr *p in preds) {
        [out addObject:[XFPredicateExpr expr:p]];
    }
    return out;
}

- (NSString *)axisForName:(NSString *)name
{
    static NSSet *axes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        axes = [NSSet setWithObjects:
                XFAxisAncestorOrSelf, XFAxisAncestor, XFAxisAttribute, XFAxisChild,
                XFAxisDescendantOrSelf, XFAxisDescendant, XFAxisFollowingSibling,
                XFAxisFollowing, XFAxisNamespace, XFAxisParent, XFAxisPrecedingSibling,
                XFAxisPreceding, XFAxisSelf, nil];
    });
    return [axes containsObject:name] ? name : nil;
}

- (XFNodeTest *)parseNodeTest:(NSError **)error
{
    if (_token.kind == XFXPathTokenStar) {
        [self advance];
        return [[XFNodeTestAny alloc] init];
    }
    if (_token.kind != XFXPathTokenName) {
        *error = [self syntaxError:@"expected node test"];
        return nil;
    }
    NSString *name = _token.text;
    [self advance];

    if (_token.kind == XFXPathTokenLParen &&
        ([name isEqualToString:@"text"] ||
         [name isEqualToString:@"node"] ||
         [name isEqualToString:@"comment"] ||
         [name isEqualToString:@"processing-instruction"])) {
        [self advance];
        NSString *pi = nil;
        if ([name isEqualToString:@"processing-instruction"] && _token.kind == XFXPathTokenString) {
            pi = _token.text;
            [self advance];
        }
        if (![self accept:XFXPathTokenRParen]) {
            *error = [self syntaxError:@"expected ')' after node test"];
            return nil;
        }
        if ([name isEqualToString:@"node"]) {
            return [XFNodeTestType anyNode];
        }
        if ([name isEqualToString:@"text"]) {
            return [XFNodeTestType kind:NSXMLTextKind];
        }
        if ([name isEqualToString:@"comment"]) {
            return [XFNodeTestType kind:NSXMLCommentKind];
        }
        return [XFNodeTestType processingInstruction:pi];
    }

    NSString *prefix = nil;
    NSString *local = name;
    NSRange colon = [name rangeOfString:@":"];
    if (colon.location != NSNotFound) {
        prefix = [name substringToIndex:colon.location];
        local = [name substringFromIndex:colon.location + 1];
    }
    return [XFNodeTestName prefix:prefix name:local];
}

- (NSArray<XFExpr *> *)parsePredicateList:(NSError **)error
{
    NSMutableArray *preds = [NSMutableArray array];
    while (_token.kind == XFXPathTokenLBrack) {
        [self advance];
        XFExpr *pred = [self parseOr:error];
        if (*error) {
            return nil;
        }
        if (![self accept:XFXPathTokenRBrack]) {
            *error = [self syntaxError:@"expected ']'"];
            return nil;
        }
        [preds addObject:pred];
    }
    return preds;
}

@end
