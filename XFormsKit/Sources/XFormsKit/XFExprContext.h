#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFModel;
@class XFNSResolver;
@class XFXPathValue;

NS_ASSUME_NONNULL_BEGIN

@interface XFExprContext : NSObject <NSCopying>

@property (nonatomic, strong, nullable) XFXMLNode *contextNode;
@property (nonatomic, strong, nullable) XFXMLNode *currentNode;
/// The context node the CURRENT full expression evaluation started from
/// (XSLT current()); stamped by XFXPath evaluateInContext: and inherited
/// by predicate sub-contexts. Distinct from currentNode, which carries
/// the OUTER in-scope context for the XForms context() function.
@property (nonatomic, strong, nullable) XFXMLNode *expressionStartNode;
@property (nonatomic, copy, nullable) NSArray<XFXMLNode *> *nodeList;
@property (nonatomic, assign) NSUInteger position; // 1-based
@property (nonatomic, assign) NSUInteger size;
@property (nonatomic, weak, nullable) XFModel *model;
/// The host element whose expression is being evaluated (XsltForms_exprContext
/// carries the evaluating subform the same way): subform-instance() and
/// subform-context() resolve their subform from it.
@property (nonatomic, weak, nullable) XFXMLElement *sourceElement;
@property (nonatomic, strong, nullable) XFNSResolver *nsResolver;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, XFXPathValue *> *variables;
@property (nonatomic, strong, readonly) NSHashTable *dependencies;
@property (nonatomic, strong, readonly) NSHashTable *depElements;

- (instancetype)initWithNode:(nullable XFXMLNode *)node;

- (instancetype)cloneWithNode:(nullable XFXMLNode *)node
                     position:(NSUInteger)position
                     nodeList:(nullable NSArray<XFXMLNode *> *)nodeList;

- (void)addDependency:(XFXMLNode *)node;
- (void)addDepElement:(id)element;
- (NSArray<XFXMLNode *> *)dependencyNodes;

@end

NS_ASSUME_NONNULL_END
