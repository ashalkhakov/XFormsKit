#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFErrors.h"
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, XFXPathTokenKind) {
    XFXPathTokenEOF = 0,
    XFXPathTokenName,
    XFXPathTokenString,
    XFXPathTokenNumber,
    XFXPathTokenSlash,
    XFXPathTokenSlashSlash,
    XFXPathTokenAt,
    XFXPathTokenDot,
    XFXPathTokenDotDot,
    XFXPathTokenStar,
    XFXPathTokenLParen,
    XFXPathTokenRParen,
    XFXPathTokenLBrack,
    XFXPathTokenRBrack,
    XFXPathTokenComma,
    XFXPathTokenPlus,
    XFXPathTokenMinus,
    XFXPathTokenEq,
    XFXPathTokenNe,
    XFXPathTokenLt,
    XFXPathTokenGt,
    XFXPathTokenLe,
    XFXPathTokenGe,
    XFXPathTokenAnd,
    XFXPathTokenOr,
    XFXPathTokenUnion
};

@interface XFXPathToken : NSObject
@property (nonatomic, assign) XFXPathTokenKind kind;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) double number;
@end

@interface XFExpr : NSObject
- (XFXPathValue *)eval:(XFExprContext *)ctx error:(NSError **)error;
@end

@interface XFLiteralExpr : XFExpr
@property (nonatomic, strong) XFXPathValue *value;
@end

@interface XFFunctionExpr : XFExpr
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray<XFExpr *> *args;
@end

@interface XFPathExpr : XFExpr
@property (nonatomic, assign) BOOL absolute;
@property (nonatomic, assign) BOOL descendantOrSelfFirst;
@property (nonatomic, copy) NSArray *steps;
@end

@interface XFStep : NSObject
@property (nonatomic, copy) NSString *axis;
@property (nonatomic, copy) NSString *test;
@property (nonatomic, copy) NSArray<XFExpr *> *predicates;
@end

@interface XFBinaryExpr : XFExpr
@property (nonatomic, copy) NSString *op;
@property (nonatomic, strong) XFExpr *left;
@property (nonatomic, strong) XFExpr *right;
@end

@interface XFXPathLexer : NSObject
- (instancetype)initWithString:(NSString *)string;
- (XFXPathToken *)next;
@end

@interface XFXPathParser : NSObject
- (instancetype)initWithString:(NSString *)string;
- (XFExpr *)parseExpression:(NSError **)error;
@end
