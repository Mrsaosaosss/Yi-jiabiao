#import "HUDInteractionController.h"

HUDPresentationState HUDStateAfterPointerEntered(HUDPresentationState state) {
    return state == HUDPresentationStateCompact ? HUDPresentationStatePeek : state;
}

HUDPresentationState HUDStateAfterPointerExited(HUDPresentationState state) {
    return state == HUDPresentationStatePeek ? HUDPresentationStateCompact : state;
}

HUDPresentationState HUDStateAfterPrimaryClick(HUDPresentationState state) {
    return state == HUDPresentationStateExpanded ? state : HUDPresentationStateExpanded;
}

HUDPresentationState HUDStateAfterDismiss(HUDPresentationState state) {
    return HUDPresentationStateCompact;
}

@interface HUDInteractionController ()
@property(nonatomic) HUDPresentationState state;
@property(nonatomic) NSUInteger exitGeneration;
@end

@implementation HUDInteractionController

- (void)setStateValue:(HUDPresentationState)state animated:(BOOL)animated {
    if (_state == state) return;
    _state = state;
    if (self.stateDidChange) self.stateDidChange(state, animated && !self.reduceMotion);
}

- (void)pointerEntered {
    self.exitGeneration += 1;
    [self setStateValue:HUDStateAfterPointerEntered(self.state) animated:YES];
}

- (void)pointerExited {
    NSUInteger generation = ++self.exitGeneration;
    NSTimeInterval delay = self.reduceMotion ? 0 : 0.16;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!weakSelf || generation != weakSelf.exitGeneration) return;
        [weakSelf setStateValue:HUDStateAfterPointerExited(weakSelf.state) animated:YES];
    });
}

- (void)primaryClick {
    self.exitGeneration += 1;
    [self setStateValue:HUDStateAfterPrimaryClick(self.state) animated:YES];
}

- (void)dismiss {
    self.exitGeneration += 1;
    [self setStateValue:HUDStateAfterDismiss(self.state) animated:YES];
}

@end
