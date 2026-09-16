#import <Cocoa/Cocoa.h>
#import "HUDGeometry.h"
#import "HUDInteractionController.h"
#import "DashboardModel.h"
#import "HUDIslandView.h"
#import "HUDPresentationModel.h"

static void AssertNear(CGFloat actual, CGFloat expected, NSString *message) {
    if (fabs(actual - expected) > 0.01) {
        NSLog(@"FAIL %@: got %.2f expected %.2f", message, actual, expected);
        exit(1);
    }
}

static void AssertTrue(BOOL value, NSString *message) {
    if (!value) {
        NSLog(@"FAIL %@", message);
        exit(1);
    }
}

static HUDScreenMetrics NotchedMetrics(void) {
    HUDScreenMetrics metrics;
    metrics.frame = NSMakeRect(0, 0, 1470, 956);
    metrics.visibleFrame = NSMakeRect(0, 0, 1470, 921);
    metrics.safeTop = 32;
    metrics.auxiliaryLeftWidth = 643;
    metrics.auxiliaryRightWidth = 643;
    metrics.builtIn = YES;
    return metrics;
}

static void TestNotchMetrics(void) {
    AssertNear(HUDNotchHeight(956, 921, 0), 34, @"menu-bar delta survives scaled-below-notch mode");
    AssertNear(HUDNotchHeight(956, 921, 38), 38, @"safe area can provide the larger notch height");
    AssertNear(HUDPhysicalNotchWidth(1470, 643, 643), 184, @"physical notch width uses auxiliary areas");
    AssertTrue(HUDScreenHasNotch(NotchedMetrics()), @"built-in screen with auxiliary areas is notched");

    HUDScreenMetrics external = NotchedMetrics();
    external.builtIn = NO;
    AssertTrue(!HUDScreenHasNotch(external), @"external screen does not claim a notch");
}

static void TestLayout(void) {
    HUDScreenMetrics metrics = NotchedMetrics();
    HUDLayout compact = HUDLayoutForMetrics(metrics, HUDPresentationStateCompact);
    HUDLayout peek = HUDLayoutForMetrics(metrics, HUDPresentationStatePeek);
    HUDLayout expanded = HUDLayoutForMetrics(metrics, HUDPresentationStateExpanded);

    AssertNear(compact.panelFrame.size.width, 900, @"panel width remains fixed");
    AssertNear(compact.panelFrame.size.height, 360, @"panel height remains fixed");
    AssertNear(NSMaxY(compact.panelFrame), NSMaxY(metrics.frame), @"panel is top anchored");
    AssertNear(compact.islandFrame.origin.y, 0, @"notched island begins at panel top");
    AssertNear(compact.islandFrame.size.width, 336, @"compact width includes notch shoulders");
    AssertTrue(peek.islandFrame.size.width > compact.islandFrame.size.width, @"peek expands horizontally");
    AssertTrue(expanded.islandFrame.size.height > peek.islandFrame.size.height, @"expanded grows downward");
    AssertNear(NSMidX(compact.islandFrame), NSMidX(compact.panelBounds), @"island stays centered");

    HUDScreenMetrics external = metrics;
    external.builtIn = NO;
    external.safeTop = 0;
    external.auxiliaryLeftWidth = 0;
    external.auxiliaryRightWidth = 0;
    HUDLayout fallback = HUDLayoutForMetrics(external, HUDPresentationStateCompact);
    AssertNear(fallback.islandFrame.origin.y, 4, @"non-notch island sits below the menu bar");
}

static void TestStateTransitions(void) {
    AssertTrue(HUDStateAfterPointerEntered(HUDPresentationStateCompact) == HUDPresentationStatePeek, @"hover enters peek");
    AssertTrue(HUDStateAfterPointerEntered(HUDPresentationStateExpanded) == HUDPresentationStateExpanded, @"hover preserves expanded");
    AssertTrue(HUDStateAfterPointerExited(HUDPresentationStatePeek) == HUDPresentationStateCompact, @"hover exit collapses peek");
    AssertTrue(HUDStateAfterPointerExited(HUDPresentationStateExpanded) == HUDPresentationStateExpanded, @"hover exit preserves expanded");
    AssertTrue(HUDStateAfterPrimaryClick(HUDPresentationStateCompact) == HUDPresentationStateExpanded, @"click expands compact");
    AssertTrue(HUDStateAfterPrimaryClick(HUDPresentationStatePeek) == HUDPresentationStateExpanded, @"click expands peek");
    AssertTrue(HUDStateAfterDismiss(HUDPresentationStateExpanded) == HUDPresentationStateCompact, @"dismiss collapses expanded");
}

static void TestPresentationAndHitTesting(void) {
    DashboardModel *dashboard = [[DashboardModel alloc] init];
    dashboard.connected = YES;
    dashboard.snapshot = @{
        @"summary": @{@"running": @1, @"waiting": @0, @"failed": @0},
        @"tasks": @[
            @{@"title": @"运行任务", @"current_step": @"实现交互", @"status": @"running", @"duration_ms": @12000, @"turn_started_at": [NSNull null], @"changed_file_count": @12},
            @{@"title": @"最近任务", @"current_step": @"已完成", @"status": @"completed", @"duration_ms": @5000, @"turn_started_at": [NSNull null], @"changed_file_count": @0},
            @{@"title": @"更早任务", @"current_step": @"空闲", @"status": @"idle", @"duration_ms": @0, @"turn_started_at": [NSNull null], @"changed_file_count": @3},
            @{@"title": @"不可见任务", @"current_step": @"空闲", @"status": @"idle", @"duration_ms": @0, @"turn_started_at": [NSNull null], @"changed_file_count": @1},
        ],
    };
    HUDPresentationModel *presentation = [[HUDPresentationModel alloc] initWithDashboard:dashboard];
    AssertTrue(presentation.tasks.count == 3, @"presentation uses exactly the first three sorted tasks");
    AssertTrue([presentation.tasks[1][@"title"] isEqualToString:@"最近任务"], @"presentation preserves server ordering");
    AssertTrue([[presentation fileCountForTask:presentation.tasks[0]] isEqualToString:@"12 个文件"], @"expanded file count is formatted");

    HUDIslandView *view = [[HUDIslandView alloc] initWithFrame:NSMakeRect(0, 0, 240, 74)];
    view.presentation = presentation;
    view.state = HUDPresentationStateCompact;
    AssertTrue([view containsLocalPoint:NSMakePoint(120, 20)], @"island center accepts pointer input");
    AssertTrue(![view containsLocalPoint:NSMakePoint(1, 73)], @"rounded transparent corner rejects pointer input");
}

int main(void) {
    @autoreleasepool {
        TestNotchMetrics();
        TestLayout();
        TestStateTransitions();
        TestPresentationAndHitTesting();
        NSLog(@"HUD core tests passed");
    }
    return 0;
}
