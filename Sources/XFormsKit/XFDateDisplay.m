/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */

#import "XFDateDisplay.h"
#import "XFControl.h"
#import "XFInputControl.h"
#import "XFNodeState.h"

@implementation XFDateDisplay

+ (NSDateFormatter *)formatterForType:(XFDateType)type
{
    // one formatter per kind, cached: building one is expensive and this
    // is called for every row of every refresh
    static NSMutableDictionary<NSNumber *, NSDateFormatter *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSMutableDictionary dictionary];
    });
    @synchronized (cache) {
        NSDateFormatter *formatter = cache[@(type)];
        if (formatter == nil) {
            formatter = [[NSDateFormatter alloc] init];
            formatter.locale = [NSLocale currentLocale];
            switch (type) {
                case XFDateTypeTime:
                    formatter.dateStyle = NSDateFormatterNoStyle;
                    formatter.timeStyle = NSDateFormatterShortStyle;
                    break;
                case XFDateTypeDateTime:
                    formatter.dateStyle = NSDateFormatterMediumStyle;
                    formatter.timeStyle = NSDateFormatterShortStyle;
                    break;
                default:
                    formatter.dateStyle = NSDateFormatterMediumStyle;
                    formatter.timeStyle = NSDateFormatterNoStyle;
                    break;
            }
            // the instance's dates carry no zone; reading them as UTC is
            // what XFInputControl parses them as, so print them the same
            // way or a date can come out a day early
            formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            cache[@(type)] = formatter;
        }
        return formatter;
    }
}

+ (NSString *)localizedStringForValue:(NSString *)value typeName:(NSString *)typeName
{
    if (value.length == 0) {
        return nil;
    }
    XFDateType type = [XFInputControl dateTypeFromTypeName:typeName];
    if (type == XFDateTypeNone) {
        return nil;
    }
    NSDate *date = [XFInputControl parseDateString:value type:type];
    if (date == nil) {
        return nil;   // not a date yet; show what is there
    }
    return [[self formatterForType:type] stringFromDate:date];
}

+ (NSString *)localizedStringForControl:(XFControl *)control
{
    if (control == nil) {
        return nil;
    }
    // a date-typed input knows its own kind (@type, appearance, the bound
    // node's datatype); anything else is judged by the bound node alone
    if ([control isKindOfClass:[XFInputControl class]]) {
        XFDateType type = [(XFInputControl *)control resolvedDateType];
        if (type == XFDateTypeNone) {
            return nil;
        }
        NSDate *date = [(XFInputControl *)control dateValue];
        return date ? [[self formatterForType:type] stringFromDate:date] : nil;
    }
    XFNodeState *state = [XFNodeState existingStateOnNode:control.boundNode];
    return [self localizedStringForValue:control.stringValue typeName:state.typeName];
}

@end
