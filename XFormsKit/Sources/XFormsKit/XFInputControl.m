#import "XFInputControl.h"
#import "XFXML.h"
#import "XFErrors.h"
#import "XFNodeState.h"
#import "XFExprContext.h"
#import <Foundation/NSXMLNode.h>

@implementation XFInputControl

+ (NSString *)localTypeName:(NSString *)typeName
{
    if (typeName.length == 0) {
        return @"";
    }
    if ([typeName hasPrefix:@"{"]) {
        NSRange close = [typeName rangeOfString:@"}"];
        return close.location == NSNotFound ? typeName : [typeName substringFromIndex:close.location + 1];
    }
    NSRange colon = [typeName rangeOfString:@":"];
    if (colon.location == NSNotFound) {
        return typeName;
    }
    return [typeName substringFromIndex:colon.location + 1];
}

+ (XFDateType)dateTypeFromTypeName:(NSString *)typeName
{
    NSString *local = [[self localTypeName:typeName] lowercaseString];
    if ([local isEqualToString:@"datetime"] || [local isEqualToString:@"dateTime"]) {
        return XFDateTypeDateTime;
    }
    if ([local isEqualToString:@"date"]) {
        return XFDateTypeDate;
    }
    if ([local isEqualToString:@"time"]) {
        return XFDateTypeTime;
    }
    return XFDateTypeNone;
}

+ (NSDate *)parseDateString:(NSString *)string type:(XFDateType)type
{
    if (string.length == 0 || type == XFDateTypeNone) {
        return nil;
    }
    NSCalendar *cal = [NSCalendar currentCalendar];
    [cal setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    NSDateComponents *c = [[NSDateComponents alloc] init];
    if (type == XFDateTypeDate || type == XFDateTypeDateTime) {
        if (string.length < 10) {
            return nil;
        }
        c.year = [[string substringWithRange:NSMakeRange(0, 4)] integerValue];
        c.month = [[string substringWithRange:NSMakeRange(5, 2)] integerValue];
        c.day = [[string substringWithRange:NSMakeRange(8, 2)] integerValue];
        // an invalid value in a typed node ("non-empty-content", W3C
        // suite 5.2.1) must yield nil, not a garbage NSDate — GNUstep's
        // Gregorian conversion effectively never returns for year 0
        if (c.year < 1 || c.year > 9999 || c.month < 1 || c.month > 12
            || c.day < 1 || c.day > 31) {
            return nil;
        }
    }
    if (type == XFDateTypeTime) {
        NSArray *parts = [string componentsSeparatedByString:@":"];
        if (parts.count < 2) {
            return nil;
        }
        c.hour = [parts[0] integerValue];
        c.minute = [parts[1] integerValue];
        if (parts.count > 2) {
            c.second = [parts[2] integerValue];
        }
    } else if (type == XFDateTypeDateTime) {
        NSRange t = [string rangeOfString:@"T"];
        if (t.location != NSNotFound && t.location + 1 < string.length) {
            NSString *rest = [string substringFromIndex:t.location + 1];
            NSArray *parts = [rest componentsSeparatedByString:@":"];
            if (parts.count >= 2) {
                c.hour = [parts[0] integerValue];
                c.minute = [parts[1] integerValue];
                if (parts.count > 2) {
                    c.second = [parts[2] integerValue];
                }
            }
        }
    } else {
        c.hour = 0;
        c.minute = 0;
        c.second = 0;
    }
    return [cal dateFromComponents:c];
}

+ (NSString *)formatDate:(NSDate *)date type:(XFDateType)type
{
    if (date == nil || type == XFDateTypeNone) {
        return @"";
    }
    NSCalendar *cal = [NSCalendar currentCalendar];
    [cal setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    NSUInteger units = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
        | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
    NSDateComponents *c = [cal components:units fromDate:date];
    if (type == XFDateTypeDate) {
        return [NSString stringWithFormat:@"%04ld-%02ld-%02ld",
                (long)c.year, (long)c.month, (long)c.day];
    }
    if (type == XFDateTypeTime) {
        return [NSString stringWithFormat:@"%02ld:%02ld:%02ld",
                (long)c.hour, (long)c.minute, (long)c.second];
    }
    return [NSString stringWithFormat:@"%04ld-%02ld-%02ldT%02ld:%02ld:%02ld",
            (long)c.year, (long)c.month, (long)c.day,
            (long)c.hour, (long)c.minute, (long)c.second];
}

+ (XFDateType)dateTypeFromStringValue:(NSString *)value
{
    if (value.length >= 19 && [value characterAtIndex:10] == 'T') {
        return XFDateTypeDateTime;
    }
    if (value.length >= 10 && [value characterAtIndex:4] == '-' && [value characterAtIndex:7] == '-') {
        return XFDateTypeDate;
    }
    if (value.length >= 5 && [value characterAtIndex:2] == ':') {
        return XFDateTypeTime;
    }
    return XFDateTypeNone;
}

- (XFDateType)resolvedDateType
{
    if (self.dateType != XFDateTypeNone) {
        return self.dateType;
    }
    XFNodeState *state = [XFNodeState existingStateOnNode:self.boundNode];
    XFDateType typed = [[self class] dateTypeFromTypeName:state.typeName];
    if (typed != XFDateTypeNone) {
        return typed;
    }
    NSString *attr = [[self.element attributeForName:@"type"] stringValue];
    typed = [[self class] dateTypeFromTypeName:attr];
    if (typed != XFDateTypeNone) {
        return typed;
    }
    typed = [[self class] dateTypeFromTypeName:self.appearance];
    if (typed != XFDateTypeNone) {
        return typed;
    }
    return [[self class] dateTypeFromStringValue:self.stringValue];
}

- (NSDate *)dateValue
{
    return [[self class] parseDateString:self.stringValue type:[self resolvedDateType]];
}

- (BOOL)commitDateValue:(NSDate *)date error:(NSError **)error
{
    XFDateType type = [self resolvedDateType];
    if (type == XFDateTypeNone) {
        type = XFDateTypeDate;
    }
    NSString *text = [[self class] formatDate:date type:type];
    return [self commitStringValue:text error:error];
}

- (BOOL)commitStringValue:(NSString *)value error:(NSError **)error
{
    if (self.boundNode == nil) {
        if (error) {
            *error = [NSError errorWithDomain:XFErrorDomain
                                         code:XFErrorBinding
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     @"xf:input has no bound node" }];
        }
        return NO;
    }
    [XFXML setStringValue:value ?: @"" ofNode:self.boundNode];
    self.stringValue = value ?: @"";
    return YES;
}

- (void)refreshWithContext:(XFExprContext *)context error:(NSError **)error
{
    [super refreshWithContext:context error:error];
    self.dateType = [self resolvedDateType];
}

@end
