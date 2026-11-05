/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#import "XFDFieldBinding.h"

static void *XFDFieldBindingContext = &XFDFieldBindingContext;

@implementation XFDFieldBinding {
    __weak NSView<XFDBindableField> *_field;
    NSString *_binding;
    id _object;
    NSString *_keyPath;
    NSDictionary *_options;
    BOOL _observing;
    /// A value being committed: its own change is not shown back.
    BOOL _committing;
}

- (instancetype)initWithField:(NSView<XFDBindableField> *)field
                      binding:(NSString *)binding
                     toObject:(id)object
                  withKeyPath:(NSString *)keyPath
                      options:(NSDictionary *)options
{
    if ((self = [super init])) {
        _field = field;
        _binding = [binding copy];
        _object = object;
        _keyPath = [keyPath copy];
        _options = [options copy] ?: @{};
        [_object addObserver:self forKeyPath:_keyPath options:0 context:XFDFieldBindingContext];
        _observing = YES;
        [self show];
    }
    return self;
}

- (void)dealloc
{
    [self invalidate];
}

- (void)invalidate
{
    if (_observing) {
        [_object removeObserver:self forKeyPath:_keyPath context:XFDFieldBindingContext];
        _observing = NO;
    }
}

- (NSDictionary *)info
{
    return @{ NSObservedObjectKey: _object, NSObservedKeyPathKey: _keyPath, NSOptionsKey: _options };
}

/// The bound value given to the field.
- (void)show
{
    NSView<XFDBindableField> *field = _field;
    id value = [_object valueForKeyPath:_keyPath];
    if ([_binding isEqualToString:NSEnabledBinding]) {
        [field setEnabled:[value boolValue]];
    } else {
        [field setBoundValue:value];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context
{
    if (context != XFDFieldBindingContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if (!_committing) {
        [self show];
    }
}

- (BOOL)commitValue:(id)value
{
    if (![_binding isEqualToString:NSValueBinding]) {
        return YES;
    }
    id current = [_object valueForKeyPath:_keyPath];
    if (value == current || [value isEqual:current]) {
        return YES;
    }
    id validated = value;
    if ([_options[NSValidatesImmediatelyBindingOption] boolValue]) {
        NSError *error = nil;
        if (![_object validateValue:&validated forKeyPath:_keyPath error:&error]) {
            NSView *field = _field;
            if (error != nil && field != nil) {
                [field presentError:error modalForWindow:[field window] delegate:nil
                 didPresentSelector:NULL contextInfo:NULL];
            } else {
                NSBeep();
            }
            return NO;
        }
    }
    _committing = YES;
    [_object setValue:validated forKeyPath:_keyPath];
    _committing = NO;
    // the value set, as the bound object keeps it (a validator's
    // replacement, a setter's normal form)
    [self show];
    return YES;
}

@end

BOOL XFDFieldBind(NSView<XFDBindableField> *field, NSMutableDictionary *bindings,
                  NSString *binding, id object, NSString *keyPath, NSDictionary *options)
{
    if (![binding isEqualToString:NSValueBinding] && ![binding isEqualToString:NSEnabledBinding]) {
        return NO;
    }
    XFDFieldUnbind(bindings, binding);
    bindings[binding] = [[XFDFieldBinding alloc] initWithField:field binding:binding
                                                       toObject:object withKeyPath:keyPath
                                                        options:options];
    return YES;
}

BOOL XFDFieldUnbind(NSMutableDictionary *bindings, NSString *binding)
{
    XFDFieldBinding *existing = bindings[binding];
    if (existing == nil) {
        return NO;
    }
    [existing invalidate];
    [bindings removeObjectForKey:binding];
    return YES;
}
