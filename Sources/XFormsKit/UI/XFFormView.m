#import "XFFormView.h"
#import "XFProcessor.h"
#import "XFControl.h"
#import "XFInputControl.h"
#import "XFOutputControl.h"

static const CGFloat kLabelWidth = 90.0;
static const CGFloat kRowHeight = 24.0;
static const CGFloat kRowGap = 8.0;
static const CGFloat kMargin = 12.0;

@interface XFFormView ()
@property (nonatomic, strong, readwrite) XFProcessor *processor;
@property (nonatomic, strong) NSMutableArray<NSTextField *> *valueFields;
@end

@implementation XFFormView

- (instancetype)initWithProcessor:(XFProcessor *)processor
{
    NSUInteger rows = processor.controls.count;
    CGFloat height = kMargin * 2 + rows * kRowHeight + MAX((NSInteger)rows - 1, 0) * kRowGap;
    self = [super initWithFrame:NSMakeRect(0, 0, 420, height)];
    if (self) {
        _processor = processor;
        _valueFields = [NSMutableArray array];
        [self buildRows];
    }
    return self;
}

- (NSTextField *)labelField:(NSString *)text
{
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [field setStringValue:text ?: @""];
    [field setBezeled:NO];
    [field setDrawsBackground:NO];
    [field setEditable:NO];
    [field setSelectable:NO];
    return field;
}

- (void)buildRows
{
    NSArray<XFControl *> *controls = self.processor.controls;
    NSUInteger count = controls.count;
    for (NSUInteger i = 0; i < count; i++) {
        XFControl *control = controls[i];
        CGFloat y = kMargin + (count - 1 - i) * (kRowHeight + kRowGap);

        NSTextField *label = [self labelField:control.label];
        [label setFrame:NSMakeRect(kMargin, y, kLabelWidth, kRowHeight)];
        [self addSubview:label];

        NSTextField *value = [[NSTextField alloc] initWithFrame:
            NSMakeRect(kMargin + kLabelWidth + 8, y, 280, kRowHeight)];
        [value setStringValue:control.stringValue ?: @""];
        [value setTag:(NSInteger)i];
        if ([control isKindOfClass:[XFInputControl class]]) {
            [value setEditable:YES];
            [value setTarget:self];
            [value setAction:@selector(inputChanged:)];
        } else {
            [value setEditable:NO];
            [value setBezeled:NO];
            [value setDrawsBackground:NO];
        }
        [self addSubview:value];
        [self.valueFields addObject:value];
    }
}

- (void)inputChanged:(NSTextField *)sender
{
    NSInteger index = [sender tag];
    if (index < 0 || (NSUInteger)index >= self.processor.controls.count) {
        return;
    }
    XFControl *control = self.processor.controls[(NSUInteger)index];
    if (![control isKindOfClass:[XFInputControl class]]) {
        return;
    }
    [self.processor setValue:[sender stringValue]
                   ofControl:(XFInputControl *)control
                       error:NULL];
    [self reloadFromProcessor];
}

- (void)reloadFromProcessor
{
    NSArray<XFControl *> *controls = self.processor.controls;
    for (NSUInteger i = 0; i < controls.count && i < self.valueFields.count; i++) {
        [self.valueFields[i] setStringValue:controls[i].stringValue ?: @""];
    }
}

@end
