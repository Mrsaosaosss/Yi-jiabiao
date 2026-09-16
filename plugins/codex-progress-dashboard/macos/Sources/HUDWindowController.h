#import <Cocoa/Cocoa.h>
#import "DashboardModel.h"

@interface HUDWindowController : NSObject
- (instancetype)initWithDashboard:(DashboardModel *)dashboard;
- (void)show;
- (void)refresh;
@end
