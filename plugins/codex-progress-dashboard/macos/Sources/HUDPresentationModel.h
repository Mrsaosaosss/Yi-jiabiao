#import <Cocoa/Cocoa.h>
#import "DashboardModel.h"

@interface HUDPresentationModel : NSObject
@property(nonatomic, weak, readonly) DashboardModel *dashboard;
- (instancetype)initWithDashboard:(DashboardModel *)dashboard;
- (NSArray<NSDictionary *> *)tasks;
- (NSDictionary *)leadTask;
- (NSInteger)activeCount;
- (NSString *)overallStatus;
- (NSString *)compactTitle;
- (NSString *)peekTitle;
- (NSString *)peekProgress;
- (NSString *)durationForTask:(NSDictionary *)task;
- (NSString *)fileCountForTask:(NSDictionary *)task;
@end
