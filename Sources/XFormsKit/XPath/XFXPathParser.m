#import "XFXPathPriv.h"
#import "XFXPathValue.h"
#import "XFErrors.h"

@implementation XFExpr
- (XFXPathValue *)eval:(XFExprContext *)ctx error:(NSError **)error
{
    (void)ctx;
    if (error) {
        *error = [NSError errorWithDomain:XFErrorDomain
                                     code:XFErrorXPathEvaluation
                                 userInfo:@{ NSLocalizedDescriptionKey: @"abstract expression" }];
    }
    return nil;
}
@end

@implementation XFLiteralExpr
- (XFXPathValue *)eval:(XFExprContext *)ctx error:(NSError **)error
{
    (void)ctx; (void)error;
    return self.value;
}
@end

@implementation XFStep
@end

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

- (NSError *)error:(NSString *)message
{
    return [NSError errorWithDomain:XFErrorDomain
                               code:XFErrorXPathSyntax
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

- (XFExpr *)parseExpression:(NSError **)error
{
    XFExpr *expr = [self parseOr:error];
    if (*error) {
        return nil;
    }
    if (_token.kind != XFXPathTokenEOF) {
        *error = [self error:[NSString stringWithFormat:@"unexpected token '%@'", _token.text]];
        return nil;
    }
    return expr;
}

- (XFExpr *)parseOr:(NSError **)error
{
    XFExpr *left = [self parseAnd:error];
    while (!*error && _token.kind == XFXPathTokenOr) {
        [self advance];
        XFBinaryExpr *bin = [[XFBinaryExpr alloc] init];
        bin.op = @"or";
        bin.left = left;
        bin.right = [self parseAnd:error];
        left = bin;
    }
    return left;
}

- (XFExpr *)parseAnd:(NSError **)error
{
    XFExpr *left = [self parseEquality:error];
    while (!*error && _token.kind == XFXPathTokenAnd) {
        [self advance];
        XFBinaryExpr *bin = [[XFBinaryExpr alloc] init];
        bin.op = @"and";
        bin.left = left;
        bin.right = [self parseEquality:error];
        left = bin;
    }
    return left;
}

- (XFExpr *)parseEquality:(NSError **)error
{
    XFExpr *left = [self parseRelational:error];
    while (!*error && (_token.kind == XFXPathTokenEq || _token.kind == XFXPathTokenNe)) {
        NSString *op = _token.kind == XFXPathTokenEq ? @"=" : @"!=";
        [self advance];
        XFBinaryExpr *bin = [[XFBinaryExpr alloc] init];
        bin.op = op;
        bin.left = left;
        bin.right = [self parseRelational:error];
        left = bin;
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
        XFBinaryExpr *bin = [[XFBinaryExpr alloc] init];
        bin.op = op;
        bin.left = left;
        bin.right = [self parseAdditive:error];
        left = bin;
    }
    return left;
}

- (XFExpr *)parseAdditive:(NSError **)error
{
    XFExpr *left = [self parseUnion:error];
    while (!*error && (_token.kind == XFXPathTokenPlus || _token.kind == XFXPathTokenMinus)) {
        NSString *op = _token.text;
        [self advance];
        XFBinaryExpr *bin = [[XFBinaryExpr alloc] init];
        bin.op = op;
        bin.left = left;
        bin.right = [self parseUnion:error];
        left = bin;
    }
    return left;
}

- (XFExpr *)parseUnion:(NSError **)error
{
    XFExpr *left = [self parsePath:error];
    while (!*error && _token.kind == XFXPathTokenUnion) {
        [self advance];
        XFBinaryExpr *bin = [[XFBinaryExpr alloc] init];
        bin.op = @"|";
        bin.left = left;
        bin.right = [self parsePath:error];
        left = bin;
    }
    return left;
}

- (XFExpr *)parsePath:(NSError **)error
{
    if (_token.kind == XFXPathTokenSlash || _token.kind == XFXPathTokenSlashSlash) {
        return [self parseLocationPath:error];
    }
    if (_token.kind == XFXPathTokenName && [self peekToken].kind == XFXPathTokenLParen) {
        XFExpr *fn = [self parseFunction:error];
        if (*error) {
            return nil;
        }
        return fn;
    }
    if (_token.kind == XFXPathTokenString || _token.kind == XFXPathTokenNumber ||
        _token.kind == XFXPathTokenLParen) {
        return [self parsePrimary:error];
    }
    return [self parseLocationPath:error];
}

- (XFExpr *)parsePrimary:(NSError **)error
{
    if (_token.kind == XFXPathTokenString) {
        XFLiteralExpr *lit = [[XFLiteralExpr alloc] init];
        lit.value = [XFXPathValue string:_token.text];
        [self advance];
        return lit;
    }
    if (_token.kind == XFXPathTokenNumber) {
        XFLiteralExpr *lit = [[XFLiteralExpr alloc] init];
        lit.value = [XFXPathValue number:_token.number];
        [self advance];
        return lit;
    }
    if (_token.kind == XFXPathTokenLParen) {
        [self advance];
        XFExpr *inner = [self parseOr:error];
        if (![self accept:XFXPathTokenRParen]) {
            *error = [self error:@"expected ')'"];
            return nil;
        }
        return inner;
    }
    if (_token.kind == XFXPathTokenName) {
        return [self parseFunction:error];
    }
    *error = [self error:@"expected primary expression"];
    return nil;
}

- (XFExpr *)parseFunction:(NSError **)error
{
    if (_token.kind != XFXPathTokenName) {
        *error = [self error:@"expected function name"];
        return nil;
    }
    NSString *name = _token.text;
    [self advance];
    if (![self accept:XFXPathTokenLParen]) {
        *error = [self error:[NSString stringWithFormat:@"expected '(' after %@", name]];
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
        *error = [self error:@"expected ')' after function arguments"];
        return nil;
    }
    XFFunctionExpr *fn = [[XFFunctionExpr alloc] init];
    fn.name = name;
    fn.args = args;
    return fn;
}

- (XFExpr *)parseLocationPath:(NSError **)error
{
    XFPathExpr *path = [[XFPathExpr alloc] init];
    NSMutableArray *steps = [NSMutableArray array];

    if (_token.kind == XFXPathTokenSlash) {
        path.absolute = YES;
        [self advance];
        if (_token.kind == XFXPathTokenEOF ||
            _token.kind == XFXPathTokenRParen ||
            _token.kind == XFXPathTokenRBrack ||
            _token.kind == XFXPathTokenComma ||
            _token.kind == XFXPathTokenOr ||
            _token.kind == XFXPathTokenAnd ||
            _token.kind == XFXPathTokenUnion ||
            _token.kind == XFXPathTokenEq ||
            _token.kind == XFXPathTokenNe ||
            _token.kind == XFXPathTokenLt ||
            _token.kind == XFXPathTokenGt ||
            _token.kind == XFXPathTokenLe ||
            _token.kind == XFXPathTokenGe ||
            _token.kind == XFXPathTokenPlus ||
            _token.kind == XFXPathTokenMinus) {
            path.steps = @[];
            return path;
        }
    } else if (_token.kind == XFXPathTokenSlashSlash) {
        path.absolute = YES;
        path.descendantOrSelfFirst = YES;
        [self advance];
    }

    XFStep *step = [self parseStep:error];
    if (*error) {
        return nil;
    }
    [steps addObject:step];

    while (_token.kind == XFXPathTokenSlash || _token.kind == XFXPathTokenSlashSlash) {
        BOOL desc = (_token.kind == XFXPathTokenSlashSlash);
        [self advance];
        if (desc) {
            XFStep *dos = [[XFStep alloc] init];
            dos.axis = @"descendant-or-self";
            dos.test = @"node";
            dos.predicates = @[];
            [steps addObject:dos];
        }
        XFStep *next = [self parseStep:error];
        if (*error) {
            return nil;
        }
        [steps addObject:next];
    }
    path.steps = steps;
    return path;
}

- (XFStep *)parseStep:(NSError **)error
{
    XFStep *step = [[XFStep alloc] init];
    step.predicates = @[];

    if (_token.kind == XFXPathTokenDot) {
        step.axis = @"self";
        step.test = @"node";
        [self advance];
        return [self parsePredicatesOnto:step error:error];
    }
    if (_token.kind == XFXPathTokenDotDot) {
        step.axis = @"parent";
        step.test = @"node";
        [self advance];
        return [self parsePredicatesOnto:step error:error];
    }
    if (_token.kind == XFXPathTokenAt) {
        step.axis = @"attribute";
        [self advance];
        if (_token.kind == XFXPathTokenStar) {
            step.test = @"*";
            [self advance];
        } else if (_token.kind == XFXPathTokenName) {
            step.test = _token.text;
            [self advance];
        } else {
            *error = [self error:@"expected attribute name"];
            return nil;
        }
        return [self parsePredicatesOnto:step error:error];
    }

    step.axis = @"child";
    if (_token.kind == XFXPathTokenStar) {
        step.test = @"*";
        [self advance];
    } else if (_token.kind == XFXPathTokenName) {
        NSString *name = _token.text;
        [self advance];
        if (_token.kind == XFXPathTokenLParen &&
            ([name isEqualToString:@"text"] ||
             [name isEqualToString:@"node"] ||
             [name isEqualToString:@"comment"])) {
            [self advance];
            if (![self accept:XFXPathTokenRParen]) {
                *error = [self error:@"expected ')' after node test"];
                return nil;
            }
            step.test = name;
        } else if (_token.kind == XFXPathTokenLParen) {
            *error = [self error:[NSString stringWithFormat:
                                  @"function '%@' cannot start a location step; wrap it or use it as a primary",
                                  name]];
            return nil;
        } else {
            step.test = name;
        }
    } else {
        *error = [self error:@"expected location step"];
        return nil;
    }
    return [self parsePredicatesOnto:step error:error];
}

- (XFStep *)parsePredicatesOnto:(XFStep *)step error:(NSError **)error
{
    NSMutableArray *preds = [NSMutableArray array];
    while (_token.kind == XFXPathTokenLBrack) {
        [self advance];
        XFExpr *pred = [self parseOr:error];
        if (*error) {
            return nil;
        }
        if (![self accept:XFXPathTokenRBrack]) {
            *error = [self error:@"expected ']'"];
            return nil;
        }
        [preds addObject:pred];
    }
    step.predicates = preds;
    return step;
}

@end
