#import "HUDGeometry.h"

static CGFloat Clamp(CGFloat value, CGFloat minimum, CGFloat maximum) {
    return MIN(MAX(value, minimum), maximum);
}

CGFloat HUDNotchHeight(CGFloat frameMaxY, CGFloat visibleFrameMaxY, CGFloat safeTop) {
    CGFloat menuBarDelta = MAX(0, frameMaxY - visibleFrameMaxY - 1);
    return Clamp(MAX(menuBarDelta, safeTop), 0, 64);
}

CGFloat HUDPhysicalNotchWidth(CGFloat screenWidth, CGFloat auxiliaryLeftWidth, CGFloat auxiliaryRightWidth) {
    if (screenWidth <= 0 || auxiliaryLeftWidth <= 0 || auxiliaryRightWidth <= 0) return 0;
    return MAX(0, screenWidth - auxiliaryLeftWidth - auxiliaryRightWidth);
}

BOOL HUDScreenHasNotch(HUDScreenMetrics metrics) {
    CGFloat height = HUDNotchHeight(NSMaxY(metrics.frame), NSMaxY(metrics.visibleFrame), metrics.safeTop);
    CGFloat width = HUDPhysicalNotchWidth(metrics.frame.size.width, metrics.auxiliaryLeftWidth, metrics.auxiliaryRightWidth);
    return metrics.builtIn && height >= 20 && width >= 40;
}

HUDLayout HUDLayoutForMetrics(HUDScreenMetrics metrics, HUDPresentationState state) {
    HUDLayout layout;
    layout.hasNotch = HUDScreenHasNotch(metrics);
    layout.notchHeight = layout.hasNotch ? HUDNotchHeight(NSMaxY(metrics.frame), NSMaxY(metrics.visibleFrame), metrics.safeTop) : 0;
    layout.notchWidth = layout.hasNotch ? HUDPhysicalNotchWidth(metrics.frame.size.width, metrics.auxiliaryLeftWidth, metrics.auxiliaryRightWidth) : 0;

    CGFloat panelWidth = MIN(900, MAX(360, metrics.frame.size.width));
    CGFloat panelHeight = MIN(360, MAX(280, metrics.frame.size.height));
    CGFloat top = layout.hasNotch ? NSMaxY(metrics.frame) : NSMaxY(metrics.visibleFrame);
    layout.panelFrame = NSMakeRect(NSMidX(metrics.frame) - panelWidth / 2, top - panelHeight, panelWidth, panelHeight);
    layout.panelBounds = NSMakeRect(0, 0, panelWidth, panelHeight);

    CGFloat compactWidth = layout.hasNotch ? MAX(240, layout.notchWidth + 152) : 240;
    CGFloat islandWidth = compactWidth;
    CGFloat islandHeight = 40 + layout.notchHeight;
    if (state == HUDPresentationStatePeek) {
        islandWidth = MAX(compactWidth, 520);
        islandHeight = 48 + layout.notchHeight;
    } else if (state == HUDPresentationStateExpanded) {
        islandWidth = MAX(compactWidth, 520);
        islandHeight = 238 + layout.notchHeight;
    }
    islandWidth = MIN(islandWidth, panelWidth - 24);
    islandHeight = MIN(islandHeight, panelHeight - 8);
    CGFloat islandY = layout.hasNotch ? 0 : 4;
    layout.islandFrame = NSMakeRect((panelWidth - islandWidth) / 2, islandY, islandWidth, islandHeight);
    return layout;
}

NSString *HUDPresentationStateName(HUDPresentationState state) {
    switch (state) {
        case HUDPresentationStatePeek: return @"peek";
        case HUDPresentationStateExpanded: return @"expanded";
        default: return @"compact";
    }
}
