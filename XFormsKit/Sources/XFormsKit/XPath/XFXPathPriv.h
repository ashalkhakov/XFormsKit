#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"
#import "XFErrors.h"
#import <Foundation/Foundation.h>

@class NSXMLNode;

#pragma mark - Tokens

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
    XFXPathTokenUnion,
    XFXPathTokenColonColon,
    XFXPathTokenDollar
};

@interface XFXPathToken : NSObject
@property (nonatomic, assign) XFXPathTokenKind kind;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) double number;
/// Source span (whitespace excluded) — syntax highlighting reads this.
@property (nonatomic, assign) NSRange range;
@end

@interface XFXPathLexer : NSObject
- (instancetype)initWithString:(NSString *)string;
- (XFXPathToken *)next;
@end

#pragma mark - Namespace resolver (XsltForms_nsResolver)

@interface XFNSResolver : NSObject
@property (nonatomic, assign) BOOL notfound;
- (void)registerPrefix:(NSString *)prefix uri:(NSString *)uri;
- (void)registerAll:(XFNSResolver *)other;
- (nullable NSString *)lookupNamespaceURI:(NSString *)prefix;
@end

#pragma mark - Axes (XsltForms_xpathAxis)

extern NSString * const XFAxisAncestorOrSelf;
extern NSString * const XFAxisAncestor;
extern NSString * const XFAxisAttribute;
extern NSString * const XFAxisChild;
extern NSString * const XFAxisDescendantOrSelf;
extern NSString * const XFAxisDescendant;
extern NSString * const XFAxisFollowingSibling;
extern NSString * const XFAxisFollowing;
extern NSString * const XFAxisNamespace;
extern NSString * const XFAxisParent;
extern NSString * const XFAxisPrecedingSibling;
extern NSString * const XFAxisPreceding;
extern NSString * const XFAxisSelf;

#pragma mark - Expressions (XsltForms xpathexpr classes)

@interface XFExpr : NSObject
- (nullable XFXPathValue *)evaluate:(XFExprContext *)ctx error:(NSError **)error;
@end

@interface XFCteExpr : XFExpr
@property (nonatomic, strong) XFXPathValue *value;
+ (instancetype)string:(NSString *)s;
+ (instancetype)number:(double)n;
@end

@interface XFUnaryMinusExpr : XFExpr
@property (nonatomic, strong) XFExpr *expr;
+ (instancetype)expr:(XFExpr *)expr;
@end

@interface XFVarRef : XFExpr
@property (nonatomic, copy) NSString *name;
+ (instancetype)name:(NSString *)name;
@end

@interface XFPredicateExpr : XFExpr
@property (nonatomic, strong) XFExpr *expr;
+ (instancetype)expr:(XFExpr *)expr;
@end

@interface XFNodeTest : NSObject
- (BOOL)matches:(NSXMLNode *)node resolver:(XFNSResolver *)resolver axis:(NSString *)axis;
@end

@interface XFNodeTestAny : XFNodeTest
@end

@interface XFNodeTestName : XFNodeTest
@property (nonatomic, copy) NSString *prefix;
@property (nonatomic, copy) NSString *name;
+ (instancetype)prefix:(NSString *)prefix name:(NSString *)name;
@end

@interface XFNodeTestType : XFNodeTest
@property (nonatomic, assign) NSXMLNodeKind kind; // NSXMLInvalidKind means node()
@property (nonatomic, assign) BOOL anyNode;
@property (nonatomic, copy) NSString *piTarget; // processing-instruction('target')
+ (instancetype)anyNode;
+ (instancetype)kind:(NSXMLNodeKind)kind;
+ (instancetype)processingInstruction:(NSString *)target;
@end

@interface XFStepExpr : XFExpr
@property (nonatomic, copy) NSString *axis;
@property (nonatomic, strong) XFNodeTest *nodetest;
@property (nonatomic, copy) NSArray<XFExpr *> *predicates;
+ (instancetype)axis:(NSString *)axis test:(XFNodeTest *)test predicates:(NSArray<XFExpr *> *)predicates;
@end

@interface XFLocationExpr : XFExpr
@property (nonatomic, assign) BOOL absolute;
@property (nonatomic, copy) NSArray<XFStepExpr *> *steps;
+ (instancetype)absolute:(BOOL)absolute steps:(NSArray<XFStepExpr *> *)steps;
@end

@interface XFPathExpr : XFExpr
@property (nonatomic, strong) XFExpr *filter;
@property (nonatomic, strong) XFExpr *rel;
+ (instancetype)filter:(XFExpr *)filter rel:(XFExpr *)rel;
@end

@interface XFFilterExpr : XFExpr
@property (nonatomic, strong) XFExpr *expr;
@property (nonatomic, copy) NSArray<XFExpr *> *predicates;
+ (instancetype)expr:(XFExpr *)expr predicates:(NSArray<XFExpr *> *)predicates;
@end

@interface XFUnionExpr : XFExpr
@property (nonatomic, strong) XFExpr *expr1;
@property (nonatomic, strong) XFExpr *expr2;
+ (instancetype)expr1:(XFExpr *)e1 expr2:(XFExpr *)e2;
@end

@interface XFBinaryExpr : XFExpr
@property (nonatomic, copy) NSString *op;
@property (nonatomic, strong) XFExpr *expr1;
@property (nonatomic, strong) XFExpr *expr2;
+ (instancetype)expr1:(XFExpr *)e1 op:(NSString *)op expr2:(XFExpr *)e2;
@end

@interface XFFunctionCallExpr : XFExpr
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray<XFExpr *> *args;
+ (instancetype)name:(NSString *)name args:(NSArray<XFExpr *> *)args;
@end

#pragma mark - Source rendering / introspection (XFExprSource.m)

@interface XFExpr (XFSource)
/// "number" "string" "variable" "unary-minus" "binary" "union"
/// "location" "step" "predicate" "path" "filter" "function".
- (NSString *)xfKind;
- (NSArray<XFExpr *> *)xfChildren;
- (NSInteger)xfPrecedence;
/// XPath source for this subtree. `overrides` maps a subexpression to
/// replacement source taken verbatim (the designer's splice).
- (NSString *)xfSourceWithOverrides:(nullable NSMapTable *)overrides;
- (NSString *)xfSource;
- (NSString *)xfRenderWithOverrides:(nullable NSMapTable *)overrides;
- (NSString *)xfChildSource:(XFExpr *)child
                  overrides:(nullable NSMapTable *)overrides
              parensBelow:(NSInteger)floor;
/// Recursive {kind, source, children, op?/name?/axis?/test?/absolute?}.
- (NSDictionary *)xfStructure;
- (NSDictionary *)xfStructureExtras;
@end

@interface XFNodeTest (XFSource)
- (NSString *)xfTestSource;
@end

@interface XFXPathParser : NSObject
- (instancetype)initWithString:(NSString *)string;
- (nullable XFExpr *)parseExpression:(NSError **)error;
@end

#pragma mark - Core functions (XsltForms_xpathFunction / XsltForms_xpathCoreFunctions)

typedef NS_ENUM(NSInteger, XFXPathFnDefault) {
    XFXPathFnDefaultNone = -1,
    XFXPathFnDefaultNode = 0,
    XFXPathFnDefaultNodeSet = 1,
    XFXPathFnDefaultString = 2
};

typedef XFXPathValue * _Nullable (^XFXPathFnBody)(XFExprContext *ctx, NSArray<XFXPathValue *> *args, NSError **error);

@interface XFXPathFunction : NSObject
@property (nonatomic, assign) BOOL acceptContext;
@property (nonatomic, assign) XFXPathFnDefault defaultTo;
@property (nonatomic, copy) XFXPathFnBody body;
+ (instancetype)acceptContext:(BOOL)accept
                    defaultTo:(XFXPathFnDefault)defaultTo
                         body:(XFXPathFnBody)body;
- (nullable XFXPathValue *)call:(XFExprContext *)ctx
                      arguments:(NSArray<XFXPathValue *> *)args
                          error:(NSError **)error;
@end

@interface XFXPathCoreFunctions : NSObject
+ (nullable XFXPathFunction *)functionNamed:(NSString *)name;
@end

/// XPath 2 string helpers, aggregates, format-number, EXSLT math, XSLTForms
/// extras (XFXPathExtraFunctions.m). A plain function rather than a category
/// so a missing compilation unit fails at link time, not at runtime.
FOUNDATION_EXPORT NSDictionary<NSString *, XFXPathFunction *> *XFXPathExtraFunctionTable(void);

#pragma mark - Helpers

/// XsltForms_globals.xmlValue: the string value of an instance node as the
/// XPath layer sees it. For a node typed with an XSLTForms eval type
/// (xsltforms:decimal family) the text is an arithmetic expression: "" is
/// 0 and the expression is evaluated (5+5 → 10); anything unparsable stays
/// text. Everything in the XPath layer must read nodes through this, not
/// [XFXML stringValueOfNode:], so sum()/comparisons/outputs agree.
FOUNDATION_EXPORT NSString *XFXPathNodeValue(NSXMLNode *node);
FOUNDATION_EXPORT NSXMLNode *XFRootNode(NSXMLNode *node);
FOUNDATION_EXPORT BOOL XFNodeInArray(NSXMLNode *node, NSArray<NSXMLNode *> *array);
FOUNDATION_EXPORT NSComparisonResult XFCompareDocumentOrder(NSXMLNode *a, NSXMLNode *b);
FOUNDATION_EXPORT NSArray<NSXMLNode *> *XFSortDocumentOrder(NSArray<NSXMLNode *> *nodes);
