#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFExprContext;

NS_ASSUME_NONNULL_BEGIN

/// Attribute Value Templates — the port of XSLTForms' AVT support
/// (avtparser.xsl + XsltForms_avt): any attribute of a NON-XForms host
/// element may hold `text{expr}text…`; `{{` and `}}` escape literal
/// braces, an unmatched `{` stays literal (avtparser's otherwise-branch).
/// XSLTForms compiles the whole value to one concat(...) XPath and keeps
/// an output-like control per attribute that rewrites the live DOM on
/// refresh. XFormsKit rebuilds its host trees on refresh anyway, so the
/// port keeps the pieces separate — literals and compiled XPath
/// fragments — and re-evaluates them wherever the value is consumed (the
/// SVG renderer, first of all: `<circle cx="{../x}">`). The deviation is
/// noted in docs/XSLTForms-gaps.md; the observable behavior matches.
@interface XFAVT : NSObject

/// YES when `value` holds at least one complete `{expr}` (escapes and
/// unmatched braces don't count) — the cheap gate before compiling.
+ (BOOL)stringIsTemplate:(nullable NSString *)value;

/// Compiles the template. nil (no error) when `value` is not a template;
/// nil with `error` when an embedded expression does not compile.
/// `element` resolves namespace prefixes, exactly like
/// [XFXPath xpathWithString:element:error:].
+ (nullable instancetype)avtWithString:(NSString *)value
                               element:(nullable XFXMLElement *)element
                                 error:(NSError **)error;

/// The original template text.
@property (nonatomic, copy, readonly) NSString *sourceString;

/// Literal pieces joined with each expression's string value in
/// `context`. An expression that fails at run time contributes "" —
/// XSLTForms's binding behavior — and reports through `error`.
- (NSString *)evaluateInContext:(XFExprContext *)context
                          error:(NSError **)error;

/// Convenience for consumers holding a raw attribute: the value itself
/// when it is not a template, else the evaluated template (compile
/// failures fall back to the raw value).
+ (NSString *)resolveString:(NSString *)value
                    element:(nullable XFXMLElement *)element
                  inContext:(XFExprContext *)context;

@end

NS_ASSUME_NONNULL_END
