#import "XFDeferredUpdates.h"
#import "XFModel.h"
#import "XFXMLEvents.h"

@interface XFDeferredUpdates ()
@property (nonatomic, strong) NSMutableArray<NSString *> *openActions;
@property (nonatomic, assign) NSInteger cont;
@property (nonatomic, strong, readwrite) NSMutableArray *changedModels;
@property (nonatomic, strong, readwrite) NSMutableArray<NSString *> *messages;
@end

@implementation XFDeferredUpdates

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
        _messages = [NSMutableArray array];
    }
    return self;
}

- (void)reset
{
    [self.openActions removeAllObjects];
    [self.changedModels removeAllObjects];
    [self.messages removeAllObjects];
    self.cont = 0;
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
    if ([self.changedModels indexOfObjectIdenticalTo:model] == NSNotFound) {
        [self.changedModels addObject:model];
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

- (void)closeChanges
{
    NSArray *models = [self.changedModels copy];
    [self.changedModels removeAllObjects];
    for (XFModel *model in models) {
        if (model.rebuilded || model.newRebuilded) {
            [XFXMLEvents dispatch:model name:@"xforms-rebuild"];
        } else {
            [XFXMLEvents dispatch:model name:@"xforms-recalculate"];
        }
    }
    for (XFModel *model in models) {
        [model refresh];
    }
    if (self.changedModels.count > 0) {
        [self closeChanges];
    }
}

@end
