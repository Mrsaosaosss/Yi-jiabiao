#import <Cocoa/Cocoa.h>
#import "DashboardModel.h"
#import "HUDWindowController.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) DashboardModel *dashboard;
@property(nonatomic, strong) HUDWindowController *hudController;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.dashboard = [[DashboardModel alloc] init];
    self.hudController = [[HUDWindowController alloc] initWithDashboard:self.dashboard];
    __weak typeof(self) weakSelf = self;
    self.dashboard.changeHandler = ^{ [weakSelf.hudController refresh]; };
    [self.dashboard start];
    [self.hudController show];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
