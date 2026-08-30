#import <Foundation/Foundation.h>
#import "XFModel.h"

@class XFModel;
@class XFInstance;
@class XFControl;
@class XFInputControl;
@class XFOutputControl;
@class XFSelectControl;
@class XFTriggerControl;
@class XFAction;
@class XFAbstractAction;
@class XFGroup;
@class XFRepeat;
@class NSXMLDocument;

NS_ASSUME_NONNULL_BEGIN

@interface XFProcessor : NSObject <XFModelOwner>

@property (nonatomic, strong, readonly) NSXMLDocument *hostDocument;
@property (nonatomic, strong, readonly) XFModel *model;
@property (nonatomic, copy, readonly) NSArray<XFControl *> *controls;
@property (nonatomic, copy, readonly) NSArray<XFInputControl *> *inputControls;
@property (nonatomic, copy, readonly) NSArray<XFOutputControl *> *outputControls;
@property (nonatomic, copy, readonly) NSArray<XFAbstractAction *> *actions;
@property (nonatomic, copy, readonly) NSArray<XFGroup *> *groups;
@property (nonatomic, copy, readonly) NSArray<XFRepeat *> *repeats;

- (nullable XFAbstractAction *)actionWithIdentifier:(NSString *)identifier;
- (nullable XFRepeat *)repeatWithIdentifier:(NSString *)identifier;

+ (nullable instancetype)processorWithContentsOfURL:(NSURL *)url
                                              error:(NSError **)error;

+ (nullable instancetype)processorWithXMLString:(NSString *)xml
                                          error:(NSError **)error;

- (nullable XFInstance *)defaultInstance;
- (BOOL)refresh:(NSError **)error;
- (void)refreshControls;

/// Writes `value` into the control's bound node and refreshes the form.
- (BOOL)setValue:(NSString *)value
      ofControl:(XFControl *)control
          error:(NSError **)error;

- (void)activateControl:(XFTriggerControl *)control;

- (nullable XFControl *)controlForElement:(NSXMLElement *)element;

@end

NS_ASSUME_NONNULL_END
