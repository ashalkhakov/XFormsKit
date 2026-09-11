#import "XFDeferredUpdates.h"
#import "XFModel.h"
#import "XFXMLEvents.h"

@interface XFDeferredUpdates ()
@property (nonatomic, strong) NSMutableArray<NSString *> *openActions;
@property (nonatomic, assign) NSInteger cont;
@property (nonatomic, strong, readwrite) NSMutableArray *changedModels;
@property (nonatomic, strong) NSMutableArray *pendingChangedModels;
@property (nonatomic, strong, readwrite) NSMutableArray<NSString *> *messages;
@end

@implementation XFDeferredUpdates {
    NSMutableArray<NSMutableDictionary *> *_variableScopes;
}

+ (instancetype)sharedUpdates
{
    static XFDeferredUpdates *shared = nil;
    @synchronized(self) {
        if (shared == nil) {
            shared = [[self alloc] init];
        }
    }
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _openActions = [NSMutableArray array];
        _changedModels = [NSMutableArray array];
        _pendingChangedModels = [NSMutableArray array];
        _messages = [NSMutableArray array];
    }
    return self;
}

- (void)reset
{
    [self.openActions removeAllObjects];
    [self.changedModels removeAllObjects];
    [self.pendingChangedModels removeAllObjects];
    [self.messages removeAllObjects];
    self.cont = 0;
    self.building = NO;
}

- (void)openAction:(NSString *)name
{
    [self.openActions addObject:name ?: @""];
    self.cont += 1;
}

- (void)addChangedModel:(XFModel *)model
{
    if (model == nil) {
        return;
    }
    // XsltForms_globals.addChange: during a refresh the change is queued
    NSMutableArray *list = self.building ? self.pendingChangedModels : self.changedModels;
    if ([list indexOfObjectIdenticalTo:model] == NSNotFound) {
        [list addObject:model];
    }
}

- (void)closeAction:(NSString *)name
{
    (void)name;
    if (self.openActions.count) {
        [self.openActions removeLastObject];
    }
    if (self.cont == 1) {
        [self closeChanges];
    }
    if (self.cont > 0) {
        self.cont -= 1;
    }
}

#pragma mark - variable scopes (G-77)

- (NSMutableArray<NSMutableDictionary *> *)variableScopes
{
    if (_variableScopes == nil) {
        _variableScopes = [NSMutableArray array];
    }
    return _variableScopes;
}

- (void)pushVariableScope
{
    [[self variableScopes] addObject:[NSMutableDictionary dictionary]];
}

- (void)popVariableScope
{
    if ([self variableScopes].count) {
        [[self variableScopes] removeLastObject];
    }
}

- (void)setVariable:(XFXPathValue *)value named:(NSString *)name
{
    if (name.length == 0) {
        return;
    }
    if ([self variableScopes].count == 0) {
        [self pushVariableScope];
    }
    NSMutableDictionary *scope = [self variableScopes].lastObject;
    if (value) {
        scope[name] = value;
    } else {
        [scope removeObjectForKey:name];
    }
}

- (XFXPathValue *)variableNamed:(NSString *)name
{
    NSArray *scopes = [self variableScopes];
    for (NSInteger i = (NSInteger)scopes.count - 1; i >= 0; i--) {
        XFXPathValue *v = scopes[(NSUInteger)i][name];
        if (v) {
            return v;
        }
    }
    return nil;
}

- (void)closeChanges
{
    // XsltForms_globals.closeChanges: rebuild or recalculate every changed
    // model (each cycle ends with xforms-refresh → the UI refresh, during
    // which `building` is set), then promote the change lists.
    NSArray *models = [self.changedModels copy];
    for (XFModel *model in models) {
        if (model.rebuilded) {
            [XFXMLEvents dispatch:model name:@"xforms-rebuild"];
        } else {
            [XFXMLEvents dispatch:model name:@"xforms-recalculate"];
        }
    }
    if (models.count > 0) {
        [self finishRefreshForModels:models];
        if (self.changedModels.count > 0) {
            [self closeChanges];
        }
    }
}

- (void)finishRefreshForModels:(NSArray<XFModel *> *)models
{
    // XsltForms_globals.refresh (after build): changes = newChanges or empty
    NSMutableArray *all = [NSMutableArray arrayWithArray:models];
    for (XFModel *m in self.changedModels) {
        if ([all indexOfObjectIdenticalTo:m] == NSNotFound) [all addObject:m];
    }
    for (XFModel *m in self.pendingChangedModels) {
        if ([all indexOfObjectIdenticalTo:m] == NSNotFound) [all addObject:m];
    }
    [self.changedModels removeAllObjects];
    [self.changedModels addObjectsFromArray:self.pendingChangedModels];
    [self.pendingChangedModels removeAllObjects];
    for (XFModel *model in all) {
        [model swapChangeLists];
    }
    self.building = NO;
}

@end
