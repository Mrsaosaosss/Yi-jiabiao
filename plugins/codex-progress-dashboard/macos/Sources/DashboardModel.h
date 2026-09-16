#import <Cocoa/Cocoa.h>

@interface DashboardModel : NSObject <NSURLSessionDataDelegate>
@property(nonatomic, copy) NSDictionary *snapshot;
@property(nonatomic) BOOL connected;
@property(nonatomic) BOOL loginEnabled;
@property(nonatomic, copy) void (^changeHandler)(void);
+ (NSDictionary *)readRuntime;
- (void)start;
- (NSArray<NSDictionary *> *)priorityTasks;
- (NSInteger)activeCount;
- (void)openDashboard;
- (void)openTask:(NSDictionary *)task;
- (void)toggleLogin;
@end
