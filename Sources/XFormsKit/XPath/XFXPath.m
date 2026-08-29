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
