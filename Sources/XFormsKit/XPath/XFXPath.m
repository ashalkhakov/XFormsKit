#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFModel.h"
#import "XFInstance.h"
#import "XFXML.h"
#import "XFErrors.h"
#import <Foundation/NSXMLNode.h>
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSXMLDocument.h>

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

@implementation XFXPathToken
@end

#pragma mark - AST

@interface XFExpr : NSObject
- (XFXPathValue *)eval:(XFExprContext *)ctx error:(NSError **)error;
@end

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

@interface XFLiteralExpr : XFExpr
@property (nonatomic, strong) XFXPathValue *value;
@end

@implementation XFLiteralExpr
- (XFXPathValue *)eval:(XFExprContext *)ctx error:(NSError **)error
{
    (void)ctx; (void)error;
    return self.value;
}
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

@implementation XFStep
@end

@interface XFBinaryExpr : XFExpr
@property (nonatomic, copy) NSString *op;
@property (nonatomic, strong) XFExpr *left;
@property (nonatomic, strong) XFExpr *right;
@end
