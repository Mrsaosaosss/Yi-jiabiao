#import "HUDWindowController.h"
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import "HUDGeometry.h"
#import "HUDInteractionController.h"
#import "HUDIslandView.h"
#import "HUDPresentationModel.h"

@interface HUDPanel : NSPanel @end
@implementation HUDPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface HUDContainerView : NSView @end
@implementation HUDContainerView
- (BOOL)isFlipped { return YES; }
@end

@interface HUDWindowController ()
@property(nonatomic, weak) DashboardModel *dashboard;
@property(nonatomic, strong) HUDPresentationModel *presentation;
@property(nonatomic, strong) HUDInteractionController *interaction;
@property(nonatomic, strong) HUDPanel *panel;
@property(nonatomic, strong) HUDContainerView *containerView;
@property(nonatomic, strong) HUDIslandView *islandView;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSTimer *pointerTimer;
@property(nonatomic, strong) NSTimer *clockTimer;
@property(nonatomic, strong) id globalMouseMonitor;
@property(nonatomic, strong) id localKeyMonitor;
@property(nonatomic, weak) NSScreen *selectedScreen;
@property(nonatomic) HUDLayout layout;
@property(nonatomic) BOOL pointerInside;
@end

@implementation HUDWindowController

- (instancetype)initWithDashboard:(DashboardModel *)dashboard {
    if ((self = [super init])) {
        _dashboard = dashboard;
        _presentation = [[HUDPresentationModel alloc] initWithDashboard:dashboard];
        _interaction = [[HUDInteractionController alloc] init];
        _interaction.reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    }
    return self;
}

- (void)dealloc {
    if (self.globalMouseMonitor) [NSEvent removeMonitor:self.globalMouseMonitor];
    if (self.localKeyMonitor) [NSEvent removeMonitor:self.localKeyMonitor];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)show {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(toggleFromStatusItem:);

    self.panel = [[HUDPanel alloc] initWithContentRect:NSMakeRect(0, 0, 900, 360)
                                             styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = NO;
    self.panel.level = NSPopUpMenuWindowLevel;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
        | NSWindowCollectionBehaviorStationary
        | NSWindowCollectionBehaviorIgnoresCycle
        | NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.panel.hidesOnDeactivate = NO;
    self.panel.becomesKeyOnlyIfNeeded = YES;

    self.containerView = [[HUDContainerView alloc] initWithFrame:NSMakeRect(0, 0, 900, 360)];
    self.containerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.panel.contentView = self.containerView;

    self.islandView = [[HUDIslandView alloc] initWithFrame:NSZeroRect];
    self.islandView.presentation = self.presentation;
    [self.containerView addSubview:self.islandView];

    __weak typeof(self) weakSelf = self;
    self.islandView.primaryAction = ^{ [weakSelf.interaction primaryClick]; };
    self.islandView.dismissAction = ^{ [weakSelf.interaction dismiss]; };
    self.islandView.taskAction = ^(NSUInteger index) {
        NSArray *tasks = weakSelf.presentation.tasks;
        if (index < tasks.count) [weakSelf.dashboard openTask:tasks[index]];
    };
    self.islandView.dashboardAction = ^{ [weakSelf.dashboard openDashboard]; };
    self.islandView.loginAction = ^{ [weakSelf.dashboard toggleLogin]; };
    self.islandView.quitAction = ^{ [NSApp terminate:nil]; };
    self.interaction.stateDidChange = ^(HUDPresentationState state, BOOL animated) {
        [weakSelf applyState:state animated:animated];
    };

    self.pointerTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) {
        [weakSelf updatePointerRouting];
    }];
    self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refresh];
    }];
    self.globalMouseMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown handler:^(NSEvent *event) {
        if (weakSelf.interaction.state == HUDPresentationStateExpanded && ![weakSelf pointIsInsideIsland:NSEvent.mouseLocation]) {
            [weakSelf.interaction dismiss];
        }
    }];
    self.localKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (event.keyCode == 53 && weakSelf.interaction.state == HUDPresentationStateExpanded) {
            [weakSelf.interaction dismiss];
            return nil;
        }
        return event;
    }];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screenChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accessibilityChanged:) name:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification object:nil];
    [self applyState:HUDPresentationStateCompact animated:NO];
    [self.panel orderFrontRegardless];
    [self refresh];
}

- (void)toggleFromStatusItem:(id)sender {
    if (self.interaction.state == HUDPresentationStateExpanded) [self.interaction dismiss];
    else [self.interaction primaryClick];
    [self.panel orderFrontRegardless];
}

- (void)screenChanged:(NSNotification *)notification { [self applyState:self.interaction.state animated:NO]; }

- (void)accessibilityChanged:(NSNotification *)notification {
    self.interaction.reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    [self.islandView setNeedsDisplay:YES];
}

- (HUDScreenMetrics)metricsForScreen:(NSScreen *)screen {
    HUDScreenMetrics metrics;
    metrics.frame = screen.frame;
    metrics.visibleFrame = screen.visibleFrame;
    metrics.safeTop = screen.safeAreaInsets.top;
    metrics.auxiliaryLeftWidth = NSIsEmptyRect(screen.auxiliaryTopLeftArea) ? 0 : screen.auxiliaryTopLeftArea.size.width;
    metrics.auxiliaryRightWidth = NSIsEmptyRect(screen.auxiliaryTopRightArea) ? 0 : screen.auxiliaryTopRightArea.size.width;
    CGDirectDisplayID displayID = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
    metrics.builtIn = displayID != 0 && CGDisplayIsBuiltin(displayID);
    return metrics;
}

- (NSScreen *)screenForHUD {
    for (NSScreen *screen in NSScreen.screens) {
        if (HUDScreenHasNotch([self metricsForScreen:screen])) return screen;
    }
    return NSScreen.mainScreen ?: NSScreen.screens.firstObject;
}

- (void)applyState:(HUDPresentationState)state animated:(BOOL)animated {
    NSScreen *screen = [self screenForHUD];
    if (!screen) return;
    self.selectedScreen = screen;
    HUDLayout layout = HUDLayoutForMetrics([self metricsForScreen:screen], state);
    self.layout = layout;
    [self.panel setFrame:layout.panelFrame display:YES animate:NO];
    self.statusItem.visible = !layout.hasNotch;
    self.islandView.notchHeight = layout.notchHeight;
    self.islandView.notchWidth = layout.notchWidth;

    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    BOOL shouldAnimate = animated && !reduceMotion && !NSEqualRects(self.islandView.frame, NSZeroRect);
    if (!shouldAnimate) {
        self.islandView.state = state;
        self.islandView.frame = layout.islandFrame;
    } else {
        if (state != HUDPresentationStateExpanded) self.islandView.state = state;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.22;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            self.islandView.animator.frame = layout.islandFrame;
        } completionHandler:nil];
        if (state == HUDPresentationStateExpanded) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self.interaction.state == HUDPresentationStateExpanded) self.islandView.state = state;
            });
        }
    }
    if (state == HUDPresentationStateExpanded) [self.panel makeKeyAndOrderFront:nil];
    else [self.panel orderFrontRegardless];
    [self.islandView setNeedsDisplay:YES];
    [self updatePointerRouting];
}

- (BOOL)pointIsInsideIsland:(NSPoint)screenPoint {
    if (!self.panel.visible) return NO;
    NSRect islandFrame = self.islandView.frame;
    NSRect panelFrame = self.panel.frame;
    NSRect islandScreenFrame = NSMakeRect(
        NSMinX(panelFrame) + NSMinX(islandFrame),
        NSMaxY(panelFrame) - NSMaxY(islandFrame),
        islandFrame.size.width,
        islandFrame.size.height
    );
    if (!NSPointInRect(screenPoint, islandScreenFrame)) return NO;
    NSPoint islandPoint = NSMakePoint(
        screenPoint.x - NSMinX(islandScreenFrame),
        NSMaxY(islandScreenFrame) - screenPoint.y
    );
    return [self.islandView containsLocalPoint:islandPoint];
}

- (void)updatePointerRouting {
    BOOL inside = [self pointIsInsideIsland:NSEvent.mouseLocation];
    if (inside != self.pointerInside) {
        self.pointerInside = inside;
        if (inside) [self.interaction pointerEntered];
        else [self.interaction pointerExited];
    }
    self.panel.ignoresMouseEvents = !inside;
}

- (void)refresh {
    self.statusItem.button.title = [NSString stringWithFormat:@"◉ Codex %ld", (long)self.presentation.activeCount];
    [self.islandView setNeedsDisplay:YES];
    [self updateScreenVisibility];
}

- (void)updateScreenVisibility {
    BOOL shouldHide = [self frontmostApplicationIsFullScreen] && self.interaction.state == HUDPresentationStateCompact;
    if (shouldHide) [self.panel orderOut:nil];
    else if (!self.panel.visible) [self.panel orderFrontRegardless];
}

- (BOOL)frontmostApplicationIsFullScreen {
    pid_t pid = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    NSScreen *screen = self.selectedScreen;
    if (!pid || !screen) return NO;
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
    for (NSDictionary *window in windows) {
        if ([window[(id)kCGWindowOwnerPID] intValue] != pid) continue;
        CGRect bounds = CGRectZero;
        if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)window[(id)kCGWindowBounds], &bounds)) continue;
        if (fabs(bounds.size.width - screen.frame.size.width) < 2 && fabs(bounds.size.height - screen.frame.size.height) < 2) return YES;
    }
    return NO;
}

@end
