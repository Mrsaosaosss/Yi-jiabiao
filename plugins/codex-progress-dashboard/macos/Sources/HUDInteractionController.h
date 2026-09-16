#import <Foundation/Foundation.h>
#import "HUDGeometry.h"

FOUNDATION_EXPORT HUDPresentationState HUDStateAfterPointerEntered(HUDPresentationState state);
FOUNDATION_EXPORT HUDPresentationState HUDStateAfterPointerExited(HUDPresentationState state);
FOUNDATION_EXPORT HUDPresentationState HUDStateAfterPrimaryClick(HUDPresentationState state);
FOUNDATION_EXPORT HUDPresentationState HUDStateAfterDismiss(HUDPresentationState state);

@interface HUDInteractionController : NSObject
@property(nonatomic, readonly) HUDPresentationState state;
@property(nonatomic) BOOL reduceMotion;
@property(nonatomic, copy) void (^stateDidChange)(HUDPresentationState state, BOOL animated);
- (void)pointerEntered;
- (void)pointerExited;
- (void)primaryClick;
- (void)dismiss;
@end
