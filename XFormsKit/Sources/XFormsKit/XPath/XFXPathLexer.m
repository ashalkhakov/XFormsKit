#import "XFXPathPriv.h"
#import <ctype.h>

@implementation XFXPathToken
@end

@implementation XFXPathLexer {
    NSString *_s;
    NSUInteger _i;
    NSUInteger _n;
    // XPath 1.0 3.7: a token that can end an operand makes a following
    // '-' (or '*', 'div', 'mod', 'and', 'or') an operator, never the start
    // of a negative literal / name test (XSLTForms xp2js.xsl does the same).
    BOOL _lastWasOperand;
}

- (instancetype)initWithString:(NSString *)string
{
    self = [super init];
    if (self) {
        _s = string ?: @"";
        _n = [_s length];
        _i = 0;
    }
    return self;
}

- (unichar)peek
{
    return _i < _n ? [_s characterAtIndex:_i] : 0;
}

- (unichar)peekAt:(NSUInteger)offset
{
    NSUInteger j = _i + offset;
    return j < _n ? [_s characterAtIndex:j] : 0;
}

- (void)skipSpace
{
    while (_i < _n) {
        unichar c = [_s characterAtIndex:_i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            _i++;
        } else {
            break;
        }
    }
}

static BOOL XFIsNameStart(unichar c)
{
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_' || c >= 0x80;
}

static BOOL XFIsNameChar(unichar c)
{
    return XFIsNameStart(c) || (c >= '0' && c <= '9') || c == '-' || c == '.';
}

- (XFXPathToken *)token:(XFXPathTokenKind)kind text:(NSString *)text
{
    XFXPathToken *t = [[XFXPathToken alloc] init];
    t.kind = kind;
    t.text = text;
    return t;
}

- (XFXPathToken *)next
{
    XFXPathToken *t = [self scan];
    switch (t.kind) {
        case XFXPathTokenName:
            _lastWasOperand = !([t.text isEqualToString:@"div"] || [t.text isEqualToString:@"mod"]);
            break;
        case XFXPathTokenNumber:
        case XFXPathTokenString:
        case XFXPathTokenRParen:
        case XFXPathTokenRBrack:
        case XFXPathTokenDot:
        case XFXPathTokenDotDot:
            _lastWasOperand = YES;
            break;
        case XFXPathTokenStar:
            // '*' after an operand is multiplication; otherwise a name test.
            _lastWasOperand = !_lastWasOperand;
            break;
        default:
            _lastWasOperand = NO;
            break;
    }
    return t;
}

- (XFXPathToken *)scan
{
    [self skipSpace];
    if (_i >= _n) {
        return [self token:XFXPathTokenEOF text:@""];
    }
    unichar c = [self peek];

    if (c == '/' ) {
        _i++;
        if ([self peek] == '/') {
            _i++;
            return [self token:XFXPathTokenSlashSlash text:@"//"];
        }
        return [self token:XFXPathTokenSlash text:@"/"];
    }
    if (c == '@') { _i++; return [self token:XFXPathTokenAt text:@"@"]; }
    if (c == '*') { _i++; return [self token:XFXPathTokenStar text:@"*"]; }
    if (c == '(') { _i++; return [self token:XFXPathTokenLParen text:@"("]; }
    if (c == ')') { _i++; return [self token:XFXPathTokenRParen text:@")"]; }
    if (c == '[') { _i++; return [self token:XFXPathTokenLBrack text:@"["]; }
    if (c == ']') { _i++; return [self token:XFXPathTokenRBrack text:@"]"]; }
    if (c == ',') { _i++; return [self token:XFXPathTokenComma text:@","]; }
    if (c == '+') { _i++; return [self token:XFXPathTokenPlus text:@"+"]; }
    if (c == '|') { _i++; return [self token:XFXPathTokenUnion text:@"|"]; }
    if (c == '$') { _i++; return [self token:XFXPathTokenDollar text:@"$"]; }
    if (c == ':' && [self peekAt:1] == ':') {
        _i += 2;
        return [self token:XFXPathTokenColonColon text:@"::"];
    }
    if (c == '=') { _i++; return [self token:XFXPathTokenEq text:@"="]; }
    if (c == '!') {
        if ([self peekAt:1] == '=') {
            _i += 2;
            return [self token:XFXPathTokenNe text:@"!="];
        }
    }
    if (c == '<') {
        _i++;
        if ([self peek] == '=') {
            _i++;
            return [self token:XFXPathTokenLe text:@"<="];
        }
        return [self token:XFXPathTokenLt text:@"<"];
    }
    if (c == '>') {
        _i++;
        if ([self peek] == '=') {
            _i++;
            return [self token:XFXPathTokenGe text:@">="];
        }
        return [self token:XFXPathTokenGt text:@">"];
    }
    if (c == '.') {
        if ([self peekAt:1] == '.') {
            _i += 2;
            return [self token:XFXPathTokenDotDot text:@".."];
        }
        if (!isdigit([self peekAt:1])) {
            _i++;
            return [self token:XFXPathTokenDot text:@"."];
        }
        // fall through to number
    }
    if (c == '-' && (_lastWasOperand || (!isdigit([self peekAt:1]) && [self peekAt:1] != '.'))) {
        _i++;
        return [self token:XFXPathTokenMinus text:@"-"];
    }

    if (c == '\'' || c == '"') {
        unichar quote = c;
        _i++;
        NSUInteger start = _i;
        while (_i < _n && [_s characterAtIndex:_i] != quote) {
            _i++;
        }
        NSString *text = [_s substringWithRange:NSMakeRange(start, _i - start)];
        if (_i < _n) {
            _i++;
        }
        return [self token:XFXPathTokenString text:text];
    }

    if (isdigit(c) || (c == '.' && isdigit([self peekAt:1])) ||
        (c == '-' && (isdigit([self peekAt:1]) || [self peekAt:1] == '.'))) {
        NSUInteger start = _i;
        if (c == '-') {
            _i++;
        }
        while (_i < _n && isdigit([self peek])) {
            _i++;
        }
        if ([self peek] == '.') {
            _i++;
            while (_i < _n && isdigit([self peek])) {
                _i++;
            }
        }
        NSString *text = [_s substringWithRange:NSMakeRange(start, _i - start)];
        XFXPathToken *t = [self token:XFXPathTokenNumber text:text];
        t.number = [text doubleValue];
        return t;
    }

    if (XFIsNameStart(c)) {
        NSUInteger start = _i;
        _i++;
        while (_i < _n && XFIsNameChar([self peek])) {
            _i++;
        }
        // qname prefix:name or ncname:* — but not axis '::'
        if ([self peek] == ':' && [self peekAt:1] != ':') {
            if (XFIsNameStart([self peekAt:1]) || [self peekAt:1] == '*') {
                _i++;
                if ([self peek] == '*') {
                    _i++;
                } else {
                    while (_i < _n && XFIsNameChar([self peek])) {
                        _i++;
                    }
                }
            }
        }
        NSString *text = [_s substringWithRange:NSMakeRange(start, _i - start)];
        // 'and' / 'or' are operators only after an operand; at operand
        // position they are ordinary element names (//or).
        if (_lastWasOperand && [text isEqualToString:@"and"]) {
            return [self token:XFXPathTokenAnd text:text];
        }
        if (_lastWasOperand && [text isEqualToString:@"or"]) {
            return [self token:XFXPathTokenOr text:text];
        }
        return [self token:XFXPathTokenName text:text];
    }

    // Unknown character: consume and treat as name so the parser can fail clearly.
    _i++;
    return [self token:XFXPathTokenName text:[NSString stringWithCharacters:&c length:1]];
}

@end
