#import <Foundation/Foundation.h>

@class XFExprContext;
@class XFXPathValue;
@class NSXMLNode;
@class NSXMLElement;

NS_ASSUME_NONNULL_BEGIN

/// A host-supplied XPath extension function (see registerHostFunctionNamed:).
typedef XFXPathValue *_Nullable (^XFXPathHostFunction)(
    XFExprContext *context, NSArray<XFXPathValue *> *arguments,
    NSError *_Nullable *_Nullable error);

@interface XFXPath : NSObject

@property (nonatomic, copy, readonly) NSString *expression;

/// Host-registered XPath extension functions. XSLTForms lets a page
/// define plain JavaScript functions that unknown XPath function names
/// fall through to (gantt.xhtml's lastday()); a native host registers
/// the equivalent here. Consulted only when no built-in matches, so a
/// host function can never shadow the spec functions. `name` is the
/// plain function name as written in expressions.
+ (void)registerHostFunctionNamed:(NSString *)name
                        evaluator:(XFXPathHostFunction)evaluator;
+ (void)unregisterHostFunctionNamed:(NSString *)name;

+ (nullable instancetype)xpathWithString:(NSString *)expression
                                   error:(NSError **)error;

/// Compile (or fetch from the cache) and register the namespace prefixes
/// used by the expression from the in-scope declarations of `element`
/// (the host element carrying the expression). Prefer this form.
+ (nullable instancetype)xpathWithString:(NSString *)expression
                                 element:(nullable NSXMLElement *)element
                                   error:(NSError **)error;

- (nullable XFXPathValue *)evaluateInContext:(XFExprContext *)context
                                       error:(NSError **)error;

- (nullable NSString *)stringValueInContext:(XFExprContext *)context
                                      error:(NSError **)error;

- (nullable NSArray<NSXMLNode *> *)nodesInContext:(XFExprContext *)context
                                            error:(NSError **)error;

/// YES when an XPath / XForms function with this name is available
/// (core, XForms 1.1 and XSLTForms extensions), for xf:model/@functions.
+ (BOOL)hasFunctionNamed:(NSString *)name;

#pragma mark - Structure (the designer's expression introspection)

/// The compiled expression tree as data — no AST classes leak. Each node
/// is { kind, source, children } plus kind-specific keys: kind ∈ number,
/// string, variable, unary-minus, binary (op), union, location
/// (absolute), step (axis, test), predicate, path, filter, function
/// (name). `source` is the node re-rendered as XPath, precedence-aware
/// (parentheses survive where the grammar needs them). The designer's
/// picker decomposes location paths into steps from this, and shows the
/// tree for computed expressions like `../in - ../out`.
- (NSDictionary *)structure;

/// The whole expression re-rendered from the tree (canonical spelling:
/// single-spaced operators, `..`/`.`/`@name` shorthands).
- (NSString *)canonicalSource;

/// Source with ONE subexpression replaced: `path` indexes into the same
/// `children` arrays `structure` reports, `source` is spliced verbatim.
/// How the picker edits the `../in` inside `../in - ../out` without
/// touching the rest. nil when the path indexes nothing.
- (nullable NSString *)sourceReplacingNodeAtPath:(NSArray<NSNumber *> *)path
                                            with:(NSString *)source;

/// Token spans for syntax highlighting: one { kind, range } per token,
/// in order, kind ∈ name, function (name before '('), axis (name before
/// '::'), string, number, variable ('$' and its name), operator
/// (arithmetic, comparison, and/or/div/mod/|, '*' at operator position),
/// punct (slashes, @, dots, brackets, parens, commas). Lexes only — a
/// half-typed expression highlights fine; nothing needs to parse.
+ (NSArray<NSDictionary *> *)highlightTokensForString:(NSString *)expression;

@end

NS_ASSUME_NONNULL_END
