/* Copyright (c) 2026 the XFormsKit contributors. LGPL 2.1. */
#pragma once
#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>

@class XFControl;

NS_ASSUME_NONNULL_BEGIN

/// Dates as a person reads them, rather than as the instance stores them.
///
/// An `xsd:date` node holds `2025-01-01`, and that lexical form is what
/// the instance must keep — it is the value, and submissions, calculates
/// and comparisons all depend on it. It is not what a host should PRINT:
/// a date shown to the reader belongs in their locale and calendar, which
/// is what `NSDatePicker` and `UIDatePicker` already do for the editable
/// case. Only the read-only paths — an `xf:output`, the text beside a
/// date picker — were still showing the raw lexical value, on both
/// platforms.
///
/// Foundation-only, so the GNUstep build formats the same way.
@interface XFDateDisplay : NSObject

/// `control`'s value written for a human, or nil when it is not a
/// date/time/dateTime — in which case the caller shows `stringValue` as
/// before. An unparseable value also answers nil: a half-typed date is
/// better shown as typed than as a guess.
+ (nullable NSString *)localizedStringForControl:(nullable XFControl *)control;

/// The same for a value whose type is already known.
+ (nullable NSString *)localizedStringForValue:(nullable NSString *)value
                                      typeName:(nullable NSString *)typeName;

@end

NS_ASSUME_NONNULL_END
