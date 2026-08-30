#import "XFBinding.h"
#import "XFXPath.h"
#import "XFXPathValue.h"
#import "XFExprContext.h"

@interface XFBinding ()
@property (nonatomic, strong, readwrite) XFXPath *xpath;
@property (nonatomic, copy, readwrite) NSString *expression;
@end

@implementation XFBinding

+ (instancetype)bindingWithExpression:(NSString *)expression error:(NSError **)error
{
    return [self bindingWithExpression:expression element:nil error:error];
}

+ (instancetype)bindingWithExpression:(NSString *)expression
                              element:(NSXMLElement *)element
                                error:(NSError **)error
{
    XFXPath *xp = [XFXPath xpathWithString:expression element:element error:error];
    if (xp == nil) {
        return nil;
    }
    XFBinding *binding = [[self alloc] init];
    binding.xpath = xp;
    binding.expression = expression;
    return binding;
}

- (XFXPathValue *)evaluateInContext:(XFExprContext *)context error:(NSError **)error
{
    return [self.xpath evaluateInContext:context error:error];
}

- (NSXMLNode *)boundNodeInContext:(XFExprContext *)context error:(NSError **)error
{
    XFXPathValue *value = [self evaluateInContext:context error:error];
    return value.firstNode;
}

- (NSString *)stringValueInContext:(XFExprContext *)context error:(NSError **)error
{
    return [self.xpath stringValueInContext:context error:error];
}

@end
