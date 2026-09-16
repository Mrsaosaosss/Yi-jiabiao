#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, HUDPresentationState) {
    HUDPresentationStateCompact = 0,
    HUDPresentationStatePeek = 1,
    HUDPresentationStateExpanded = 2,
};

typedef struct {
    NSRect frame;
    NSRect visibleFrame;
    CGFloat safeTop;
    CGFloat auxiliaryLeftWidth;
    CGFloat auxiliaryRightWidth;
    BOOL builtIn;
} HUDScreenMetrics;

typedef struct {
    NSRect panelFrame;
    NSRect panelBounds;
    NSRect islandFrame;
    CGFloat notchHeight;
    CGFloat notchWidth;
    BOOL hasNotch;
} HUDLayout;

FOUNDATION_EXPORT CGFloat HUDNotchHeight(CGFloat frameMaxY, CGFloat visibleFrameMaxY, CGFloat safeTop);
FOUNDATION_EXPORT CGFloat HUDPhysicalNotchWidth(CGFloat screenWidth, CGFloat auxiliaryLeftWidth, CGFloat auxiliaryRightWidth);
FOUNDATION_EXPORT BOOL HUDScreenHasNotch(HUDScreenMetrics metrics);
FOUNDATION_EXPORT HUDLayout HUDLayoutForMetrics(HUDScreenMetrics metrics, HUDPresentationState state);
FOUNDATION_EXPORT NSString *HUDPresentationStateName(HUDPresentationState state);
