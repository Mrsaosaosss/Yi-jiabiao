#import "DashboardModel.h"
#import <signal.h>

static NSString *const RuntimeRelativePath = @"Library/Application Support/CodexProgressDashboard/runtime.json";
static NSString *const LaunchAgentRelativePath = @"Library/LaunchAgents/com.jiabiao.codex-progress-hud.plist";

@interface DashboardModel ()
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionDataTask *streamTask;
@property(nonatomic, strong) NSMutableData *eventBuffer;
@property(nonatomic, strong) NSTimer *runtimeTimer;
@property(nonatomic, strong) NSTask *observerTask;
@property(nonatomic) pid_t runtimePID;
@end

@implementation DashboardModel

- (instancetype)init {
    if ((self = [super init])) {
        _eventBuffer = [NSMutableData data];
        _runtimePID = 0;
        _loginEnabled = [NSFileManager.defaultManager fileExistsAtPath:self.class.launchAgentURL.path];
    }
    return self;
}

+ (NSURL *)runtimeURL {
    return [NSFileManager.defaultManager.homeDirectoryForCurrentUser URLByAppendingPathComponent:RuntimeRelativePath];
}

+ (NSURL *)launchAgentURL {
    return [NSFileManager.defaultManager.homeDirectoryForCurrentUser URLByAppendingPathComponent:LaunchAgentRelativePath];
}

+ (NSDictionary *)readRuntime {
    NSData *data = [NSData dataWithContentsOfURL:self.runtimeURL];
    if (!data) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

+ (BOOL)processExists:(pid_t)pid {
    return pid > 0 && (kill(pid, 0) == 0 || errno == EPERM);
}

- (void)start {
    [self locateRuntime];
    __weak typeof(self) weakSelf = self;
    self.runtimeTimer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) {
        [weakSelf locateRuntime];
    }];
}

- (void)notifyChange {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.changeHandler) self.changeHandler();
    });
}

- (void)locateRuntime {
    NSDictionary *runtime = self.class.readRuntime;
    pid_t pid = [runtime[@"pid"] intValue];
    if (!runtime || ![self.class processExists:pid]) {
        self.connected = NO;
        self.runtimePID = 0;
        [self notifyChange];
        [self startObserverIfNeeded];
        return;
    }
    if (self.runtimePID != pid) {
        self.runtimePID = pid;
        [self connectRuntime:runtime];
    }
}

- (void)startObserverIfNeeded {
    if (self.observerTask.running) return;
    NSURL *bundle = NSBundle.mainBundle.bundleURL;
    NSURL *pluginRoot = bundle.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent;
    NSURL *launcher = [pluginRoot URLByAppendingPathComponent:@"scripts/run_dashboard.py"];
    if (![NSFileManager.defaultManager fileExistsAtPath:launcher.path]) return;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/python3"];
    task.arguments = @[launcher.path, @"--no-browser"];
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    [task launchAndReturnError:nil];
    self.observerTask = task;
}

- (void)connectRuntime:(NSDictionary *)runtime {
    NSURL *bootstrapURL = [NSURL URLWithString:runtime[@"bootstrapURL"] ?: @""];
    NSURL *streamURL = [NSURL URLWithString:@"/events" relativeToURL:[NSURL URLWithString:runtime[@"baseURL"] ?: @""]];
    if (!bootstrapURL || !streamURL) return;
    [self.streamTask cancel];
    [self.session invalidateAndCancel];
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
    configuration.HTTPCookieStorage = NSHTTPCookieStorage.sharedHTTPCookieStorage;
    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sessionWithConfiguration:configuration] dataTaskWithURL:bootstrapURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            weakSelf.connected = NO;
            [weakSelf notifyChange];
            return;
        }
        NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:weakSelf delegateQueue:nil];
        weakSelf.session = session;
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:streamURL];
        [request setValue:@"text/event-stream" forHTTPHeaderField:@"Accept"];
        weakSelf.streamTask = [session dataTaskWithRequest:request];
        [weakSelf.streamTask resume];
    }] resume];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.connected = YES;
    [self notifyChange];
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    @synchronized (self.eventBuffer) {
        [self.eventBuffer appendData:data];
        NSData *separator = [@"\n\n" dataUsingEncoding:NSUTF8StringEncoding];
        while (YES) {
            NSRange range = [self.eventBuffer rangeOfData:separator options:0 range:NSMakeRange(0, self.eventBuffer.length)];
            if (range.location == NSNotFound) break;
            NSData *event = [self.eventBuffer subdataWithRange:NSMakeRange(0, range.location)];
            [self.eventBuffer replaceBytesInRange:NSMakeRange(0, NSMaxRange(range)) withBytes:NULL length:0];
            [self decodeEvent:event];
        }
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    self.connected = NO;
    [self notifyChange];
}

- (void)decodeEvent:(NSData *)event {
    NSString *text = [[NSString alloc] initWithData:event encoding:NSUTF8StringEncoding];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (![line hasPrefix:@"data: "]) continue;
        NSData *payload = [[line substringFromIndex:6] dataUsingEncoding:NSUTF8StringEncoding];
        id value = [NSJSONSerialization JSONObjectWithData:payload options:0 error:nil];
        if ([value isKindOfClass:NSDictionary.class]) {
            self.snapshot = value;
            [self notifyChange];
        }
    }
}

- (NSInteger)activeCount {
    NSDictionary *summary = self.snapshot[@"summary"];
    return [summary[@"running"] integerValue] + [summary[@"waiting"] integerValue];
}

- (NSArray<NSDictionary *> *)priorityTasks {
    NSArray *tasks = self.snapshot[@"tasks"];
    if (![tasks isKindOfClass:NSArray.class]) return @[];
    return [tasks subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)3, tasks.count))];
}

- (void)openDashboard {
    NSURL *url = [NSURL URLWithString:[self.class readRuntime][@"bootstrapURL"] ?: @""];
    if (url) [NSWorkspace.sharedWorkspace openURL:url];
}

- (void)openTask:(NSDictionary *)task {
    NSURL *url = [NSURL URLWithString:task[@"deep_link"] ?: @""];
    if (url) [NSWorkspace.sharedWorkspace openURL:url];
}

- (void)toggleLogin {
    self.loginEnabled = !self.loginEnabled;
    NSURL *url = self.class.launchAgentURL;
    if (!self.loginEnabled) {
        [NSFileManager.defaultManager removeItemAtURL:url error:nil];
        [self notifyChange];
        return;
    }
    [NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *payload = @{
        @"Label": @"com.jiabiao.codex-progress-hud",
        @"ProgramArguments": @[@"/usr/bin/open", @"-a", NSBundle.mainBundle.bundlePath],
        @"RunAtLoad": @YES,
        @"KeepAlive": @NO,
    };
    if (![payload writeToURL:url error:nil]) self.loginEnabled = NO;
    [self notifyChange];
}

@end
