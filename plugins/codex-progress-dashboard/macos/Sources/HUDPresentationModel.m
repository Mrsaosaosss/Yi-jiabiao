#import "HUDPresentationModel.h"

@interface HUDPresentationModel ()
@property(nonatomic, weak) DashboardModel *dashboard;
@end

@implementation HUDPresentationModel

- (instancetype)initWithDashboard:(DashboardModel *)dashboard {
    if ((self = [super init])) _dashboard = dashboard;
    return self;
}

- (NSArray<NSDictionary *> *)tasks { return self.dashboard.priorityTasks; }
- (NSDictionary *)leadTask { return self.tasks.firstObject; }
- (NSInteger)activeCount { return self.dashboard.activeCount; }

- (NSString *)overallStatus {
    if (!self.dashboard.connected) return @"disconnected";
    NSDictionary *summary = self.dashboard.snapshot[@"summary"];
    if ([summary[@"waiting"] integerValue] > 0) return @"waiting";
    if ([summary[@"running"] integerValue] > 0) return @"running";
    if ([summary[@"failed"] integerValue] > 0) return @"failed";
    return @"idle";
}

- (NSString *)compactTitle {
    return [NSString stringWithFormat:@"Codex %ld", (long)self.activeCount];
}

- (NSString *)peekTitle {
    return self.leadTask[@"title"] ?: @"暂无任务";
}

- (NSString *)peekProgress {
    return self.leadTask[@"current_step"] ?: @"等待新的任务";
}

- (NSString *)durationForTask:(NSDictionary *)task {
    if (!task) return @"--:--";
    long long milliseconds = [task[@"duration_ms"] longLongValue];
    NSString *status = task[@"status"] ?: @"";
    NSNumber *started = task[@"turn_started_at"];
    if (([status isEqualToString:@"running"] || [status isEqualToString:@"waiting"]) && started != (id)[NSNull null]) {
        milliseconds = MAX(0, (long long)(NSDate.date.timeIntervalSince1970 * 1000) - started.longLongValue);
    }
    long long seconds = milliseconds / 1000;
    long long hours = seconds / 3600;
    long long minutes = (seconds % 3600) / 60;
    if (hours > 0) return [NSString stringWithFormat:@"%lld:%02lld:%02lld", hours, minutes, seconds % 60];
    return [NSString stringWithFormat:@"%02lld:%02lld", minutes, seconds % 60];
}

- (NSString *)fileCountForTask:(NSDictionary *)task {
    NSInteger count = [task[@"changed_file_count"] integerValue];
    return [NSString stringWithFormat:@"%ld 个文件", (long)count];
}

@end
