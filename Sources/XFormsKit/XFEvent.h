#import <Foundation/Foundation.h>
#import <XFormsKit/XFXMLTypes.h>


NS_ASSUME_NONNULL_BEGIN

/// DOM Level 2 event phases. XML Events 1 only names "capture" and
/// "default"; "default" covers both the target and bubbling phases.
typedef NS_ENUM(NSInteger, XFEventPhase) {
    XFEventPhaseCapture = 1,
    XFEventPhaseTarget  = 2,
    XFEventPhaseBubble  = 3
};

/// DOM Event stand-in used by XFXMLEvents. There is no browser Event
/// object on Cocoa, so this is the object handed to listeners and
/// default actions (XSLTForms uses the host DOM Event).
@interface XFEvent : NSObject

@property (nonatomic, copy) NSString *type;
@property (nonatomic, strong, nullable) XFXMLElement *target;
@property (nonatomic, strong, nullable) XFXMLElement *currentTarget;
@property (nonatomic, weak, nullable) id xfElement;
@property (nonatomic, assign) XFEventPhase eventPhase;
/// XML Events / XSLTForms IE-path phase name: @"capture" or @"default".
@property (nonatomic, copy) NSString *phase;
@property (nonatomic, assign) BOOL bubbles;
@property (nonatomic, assign) BOOL cancelable;
@property (nonatomic, assign, readonly) BOOL stopped;
@property (nonatomic, assign, readonly) BOOL defaultPrevented;
@property (nonatomic, assign) BOOL cancelBubble;
@property (nonatomic, assign) BOOL returnValue;
@property (nonatomic, copy, nullable) NSString *targetid;
@property (nonatomic, strong) NSMutableDictionary *context;

- (void)stopPropagation;
- (void)preventDefault;

@end

NS_ASSUME_NONNULL_END
