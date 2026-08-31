/* AST introspection and source rendering — the designer's view of a
   compiled expression. Every XFExpr learns to name its kind, hand out its
   children, and render itself back to XPath source (precedence-aware, so
   `(a + b) * c` keeps its parentheses). Rendering takes an optional
   override table mapping a subexpression to replacement source — how the
   designer splices an edited location path back into `../in - ../out`
   without re-lexing anything. The public face is on XFXPath (structure /
   canonicalSource / sourceReplacingNodeAtPath:with:); these categories
   stay inside the framework.
   Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFXPathPriv.h"
#import "XFXPathValue.h"

/// XPath 1.0 grammar levels, loosest first: or < and < equality <
/// relational < additive < multiplicative < unary < union < path/primary.
static NSInteger XFPrecedenceOfOp(NSString *op)
{
    if ([op isEqualToString:@"or"]) return 1;
    if ([op isEqualToString:@"and"]) return 2;
    if ([op isEqualToString:@"="] || [op isEqualToString:@"!="]) return 3;
    if ([op isEqualToString:@"<"] || [op isEqualToString:@">"]
        || [op isEqualToString:@"<="] || [op isEqualToString:@">="]) return 4;
    if ([op isEqualToString:@"+"] || [op isEqualToString:@"-"]) return 5;
    return 6;   // * div mod
}

@implementation XFExpr (XFSource)

- (NSString *)xfKind { return @"expr"; }
- (NSArray<XFExpr *> *)xfChildren { return @[]; }
- (NSInteger)xfPrecedence { return 9; }

- (NSString *)xfRenderWithOverrides:(NSMapTable *)overrides
{
    return @"?";
}

- (NSString *)xfSourceWithOverrides:(NSMapTable *)overrides
{
    NSString *replacement = [overrides objectForKey:self];
    if (replacement != nil) {
        return replacement;
    }
    return [self xfRenderWithOverrides:overrides];
}

- (NSString *)xfSource
{
    return [self xfSourceWithOverrides:nil];
}

/// Child source, parenthesized when the child binds looser than `floor`.
- (NSString *)xfChildSource:(XFExpr *)child
                  overrides:(NSMapTable *)overrides
              parensBelow:(NSInteger)floor
{
    NSString *source = [child xfSourceWithOverrides:overrides];
    if ([overrides objectForKey:child] != nil) {
        return source;   // spliced text is taken verbatim
    }
    if ([child xfPrecedence] < floor) {
        return [NSString stringWithFormat:@"(%@)", source];
    }
    return source;
}

- (NSDictionary *)xfStructure
{
    NSMutableArray *children = [NSMutableArray array];
    for (XFExpr *child in [self xfChildren]) {
        [children addObject:[child xfStructure]];
    }
    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithDictionary:@{
        @"kind": [self xfKind],
        @"source": [self xfSource],
        @"children": children,
    }];
    [out addEntriesFromDictionary:[self xfStructureExtras]];
    return out;
}

- (NSDictionary *)xfStructureExtras { return @{}; }

@end

#pragma mark - Leaves

@implementation XFCteExpr (XFSource)

- (NSString *)xfKind
{
    return self.value.type == XFXPathValueTypeNumber ? @"number" : @"string";
}

- (NSString *)xfRenderWithOverrides:(NSMapTable *)overrides
{
    (void)overrides;
    if (self.value.type == XFXPathValueTypeNumber) {
        return XFNumberToString(self.value.number);
    }
    NSString *s = self.value.string ?: @"";
    if ([s rangeOfString:@"'"].location == NSNotFound) {
        return [NSString stringWithFormat:@"'%@'", s];
    }
    return [NSString stringWithFormat:@"\"%@\"", s];
}

@end

@implementation XFVarRef (XFSource)

- (NSString *)xfKind { return @"variable"; }

- (NSString *)xfRenderWithOverrides:(NSMapTable *)overrides
{
    (void)overrides;
    return [@"$" stringByAppendingString:self.name ?: @""];
}

@end

#pragma mark - Operators

@implementation XFUnaryMinusExpr (XFSource)

- (NSString *)xfKind { return @"unary-minus"; }
- (NSArray<XFExpr *> *)xfChildren { return self.expr ? @[ self.expr ] : @[]; }
- (NSInteger)xfPrecedence { return 7; }

- (NSString *)xfRenderWithOverrides:(NSMapTable *)overrides
{
    return [@"-" stringByAppendingString:
        [self xfChildSource:self.expr overrides:overrides parensBelow:7]];
}

@end

@implementation XFBinaryExpr (XFSource)

- (NSString *)xfKind { return @"binary"; }
- (NSArray<XFExpr *> *)xfChildren
{
    NSMutableArray *out = [NSMutableArray array];
    if (self.expr1) { [out addObject:self.expr1]; }
    if (self.expr2) { [out addObject:self.expr2]; }
    return out;
}
- (NSInteger)xfPrecedence { return XFPrecedenceOfOp(self.op); }
- (NSDictionary *)xfStructureExtras { return @{ @"op": self.op ?: @"" }; }

- (NSString *)xfRenderWithOverrides:(NSMapTable *)overrides
{
    NSInteger mine = [self xfPrecedence];
    // left-associative chains: the right operand needs parens at EQUAL
    // precedence too (a - (b - c) must not flatten)
    return [NSString stringWithFormat:@"%@ %@ %@",
        [self xfChildSource:self.expr1 overrides:overrides parensBelow:mine],
        self.op ?: @"?",
        [self xfChildSource:self.expr2 overrides:overrides parensBelow:mine + 1]];
}

@end

@implementation XFUnionExpr (XFSource)

- (NSString *)xfKind { return @"union"; }
- (NSArray<XFExpr *> *)xfChildren
{
    NSMutableArray *out = [NSMutableArray array];
    if (self.expr1) { [out addObject:self.expr1]; }
    if (self.expr2) { [out addObject:self.expr2]; }
    return out;
}
- (NSInteger)xfPrecedence { return 8; }

- (NSString *)xfRenderWithOverrides:(NSMapTable *)overrides
{
    return [NSString stringWithFormat:@"%@ | %@",
        [self xfChildSource:self.expr1 overrides:overrides parensBelow:8],
        [self xfChildSource:self.expr2 overrides:overrides parensBelow:8]];
}

@end

#pragma mark - Node tests

@implementation XFNodeTest (XFSource)
- (NSString *)xfTestSource { return @"?"; }
@end

@implementation XFNodeTestAny (XFSource)
- (NSString *)xfTestSource { return @"*"; }
@end

@implementation XFNodeTestName (XFSource)
- (NSString *)xfTestSource
{
    return self.prefix.length
        ? [NSString stringWithFormat:@"%@:%@", self.prefix, self.name]
        : (self.name ?: @"*");
}
@end

@implementation XFNodeTestType (XFSource)
- (NSString *)xfTestSource
{
    if (self.anyNode) {
        return @"node()";
    }
    if (self.piTarget != nil) {
        return self.piTarget.length
            ? [NSString stringWithFormat:@"processing-instruction('%@')", self.piTarget]
            : @"processing-instruction()";
    }
    switch (self.kind) {
        case NSXMLTextKind: return @"text()";
        case NSXMLCommentKind: return @"comment()";
        case NSXMLProcessingInstructionKind: return @"processing-instruction()";
        default: return @"node()";
    }
}
@end

#pragma mark - Paths

@implementation XFPredicateExpr (XFSource)

- (NSString *)xfKind { return @"predicate"; }
- (NSArray<XFExpr *> *)xfChildren { return self.expr ? @[ self.expr ] : @[]; }

- (NSString *)xfRenderWithOverrides:(NSMapTable *)overrides
{
    return [self.expr xfSourceWithOverrides:overrides] ?: @"";
}

@end

@implementation XFStepExpr (XFSource)

- (NSString *)xfKind { return @"step"; }
- (NSArray<XFExpr *> *)xfChildren { return self.predicates ?: @[]; }
- (NSDictionary *)xfStructureExtras
{
    return @{ @"axis": self.axis ?: @"child",
              @"test": [self.nodetest xfTestSource] ?: @"?" };
}

- (NSString *)xfRenderWithOverrides:(NSMapTable *)overrides
{
    NSString *test = [self.nodetest xfTestSource];
    NSString *head;
    BOOL anyNode = [test isEqualToString:@"node()"];
    if ([self.axis isEqualToString:XFAxisSelf] && anyNode) {
        head = @".";
    } else if ([self.axis isEqualToString:XFAxisParent] && anyNode) {
        head = @"..";
    } else if ([self.axis isEqualToString:XFAxisAttribute]) {
        head = [@"@" stringByAppendingString:test];
    } else if ([self.axis isEqualToString:XFAxisChild]) {
        head = test;
    } else {
        head = [NSString stringWithFormat:@"%@::%@", self.axis, test];
    }
    NSMutableString *out = [head mutableCopy];
    for (XFExpr *predicate in self.predicates) {
        [out appendFormat:@"[%@]", [predicate xfSourceWithOverrides:overrides]];
    }
    return out;
}

@end

@implementation XFLocationExpr (XFSource)

- (NSString *)xfKind { return @"location"; }
- (NSArray<XFExpr *> *)xfChildren { return self.steps ?: @[]; }
- (NSDictionary *)xfStructureExtras { return @{ @"absolute": @(self.absolute) }; }

- (NSString *)xfRenderWithOverrides:(NSMapTable *)overrides
{
    NSMutableArray *rendered = [NSMutableArray array];
    for (XFStepExpr *step in self.steps) {
        [rendered addObject:[step xfSourceWithOverrides:overrides]];
    }
    NSString *tail = [rendered componentsJoinedByString:@"/"];
    if (self.absolute) {
        return [@"/" stringByAppendingString:tail];
    }
    return tail.length ? tail : @".";
}

@end

@implementation XFFilterExpr (XFSource)

- (NSString *)xfKind { return @"filter"; }
- (NSArray<XFExpr *> *)xfChildren
{
    NSMutableArray *out = [NSMutableArray array];
    if (self.expr) { [out addObject:self.expr]; }
    [out addObjectsFromArray:self.predicates ?: @[]];
    return out;
}

- (NSString *)xfRenderWithOverrides:(NSMapTable *)overrides
{
    // the base must be a primary expression: parenthesize operators
    NSString *base = [self.expr xfSourceWithOverrides:overrides];
    if ([overrides objectForKey:self.expr] == nil && [self.expr xfPrecedence] < 8) {
        base = [NSString stringWithFormat:@"(%@)", base];
    }
    NSMutableString *out = [base mutableCopy];
    for (XFExpr *predicate in self.predicates) {
        [out appendFormat:@"[%@]", [predicate xfSourceWithOverrides:overrides]];
    }
    return out;
}

@end

@implementation XFPathExpr (XFSource)

- (NSString *)xfKind { return @"path"; }
- (NSArray<XFExpr *> *)xfChildren
{
    NSMutableArray *out = [NSMutableArray array];
    if (self.filter) { [out addObject:self.filter]; }
    if (self.rel) { [out addObject:self.rel]; }
    return out;
}

- (NSString *)xfRenderWithOverrides:(NSMapTable *)overrides
{
    return [NSString stringWithFormat:@"%@/%@",
        [self.filter xfSourceWithOverrides:overrides],
        [self.rel xfSourceWithOverrides:overrides]];
}

@end

@implementation XFFunctionCallExpr (XFSource)

- (NSString *)xfKind { return @"function"; }
- (NSArray<XFExpr *> *)xfChildren { return self.args ?: @[]; }
- (NSDictionary *)xfStructureExtras { return @{ @"name": self.name ?: @"" }; }

- (NSString *)xfRenderWithOverrides:(NSMapTable *)overrides
{
    NSMutableArray *rendered = [NSMutableArray array];
    for (XFExpr *arg in self.args) {
        [rendered addObject:[arg xfSourceWithOverrides:overrides]];
    }
    return [NSString stringWithFormat:@"%@(%@)", self.name ?: @"?",
            [rendered componentsJoinedByString:@", "]];
}

@end
