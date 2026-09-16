#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <signal.h>

static NSString *const RuntimeRelativePath = @"Library/Application Support/CodexProgressDashboard/runtime.json";
static NSString *const LaunchAgentRelativePath = @"Library/LaunchAgents/com.jiabiao.codex-progress-hud.plist";

@class DashboardModel;

static NSString *FormatDuration(NSDictionary *task) {
    long long milliseconds = [task[@"duration_ms"] longLongValue];
    NSString *status = task[@"status"] ?: @"";
    NSNumber *started = task[@"turn_started_at"];
    if (([status isEqualToString:@"running"] || [status isEqualToString:@"waiting"]) && started != (id)[NSNull null]) {
        milliseconds = MAX(0, (long long)(NSDate.date.timeIntervalSince1970 * 1000) - started.longLongValue);
    }
    long long seconds = milliseconds / 1000;
    long long hours = seconds / 3600;
    long long minutes = (seconds % 3600) / 60;
    if (hours > 0) return [NSString stringWithFormat:@"%lldh %02lldm", hours, minutes];
    return [NSString stringWithFormat:@"%lldm %02llds", minutes, seconds % 60];
}

@interface DashboardModel : NSObject <NSURLSessionDataDelegate>
@property(nonatomic, copy) NSDictionary *snapshot;
@property(nonatomic) BOOL connected;
@property(nonatomic) BOOL expanded;
@property(nonatomic) BOOL loginEnabled;
@property(nonatomic, copy) void (^changeHandler)(void);
- (void)start;
- (NSArray<NSDictionary *> *)priorityTasks;
- (NSInteger)activeCount;
- (void)openDashboard;
- (void)openTask:(NSDictionary *)task;
- (void)toggleLogin;
@end

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
    NSString *bootstrapString = runtime[@"bootstrapURL"];
    NSString *baseString = runtime[@"baseURL"];
    NSURL *bootstrapURL = [NSURL URLWithString:bootstrapString ?: @""];
    NSURL *streamURL = [NSURL URLWithString:@"/events" relativeToURL:[NSURL URLWithString:baseString ?: @""]];
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

@interface HUDView : NSView
@property(nonatomic, weak) DashboardModel *model;
@property(nonatomic, copy) void (^expansionHandler)(BOOL expanded);
@property(nonatomic) CGFloat topInset;
@end

@implementation HUDView

- (BOOL)isFlipped { return YES; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:area];
}

- (void)mouseEntered:(NSEvent *)event { self.model.expanded = YES; if (self.expansionHandler) self.expansionHandler(YES); }
- (void)mouseExited:(NSEvent *)event { self.model.expanded = NO; if (self.expansionHandler) self.expansionHandler(NO); }

- (NSColor *)colorForStatus:(NSString *)status {
    if ([status isEqualToString:@"waiting"]) return [NSColor colorWithRed:0.95 green:0.63 blue:0.2 alpha:1];
    if ([status isEqualToString:@"running"]) return [NSColor colorWithRed:0.33 green:0.48 blue:1 alpha:1];
    if ([status isEqualToString:@"failed"]) return [NSColor colorWithRed:0.94 green:0.3 blue:0.36 alpha:1];
    return NSColor.systemGrayColor;
}

- (NSColor *)overallColor {
    if (!self.model.connected) return NSColor.systemGrayColor;
    NSDictionary *summary = self.model.snapshot[@"summary"];
    if ([summary[@"waiting"] integerValue] > 0) return [self colorForStatus:@"waiting"];
    if ([summary[@"running"] integerValue] > 0) return [self colorForStatus:@"running"];
    if ([summary[@"failed"] integerValue] > 0) return [self colorForStatus:@"failed"];
    return [NSColor colorWithRed:0.28 green:0.7 blue:0.55 alpha:1];
}

- (void)drawLabel:(NSString *)value rect:(NSRect)rect font:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = alignment;
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    [value drawInRect:rect withAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: style}];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    CGFloat radius = self.model.expanded ? 24 : 17;
    [[NSColor colorWithWhite:0.025 alpha:0.95] setFill];
    if (self.topInset > 0) {
        NSRect bridge = NSMakeRect(1, 0, self.bounds.size.width - 2, self.topInset + radius);
        NSRect body = NSMakeRect(1, self.topInset, self.bounds.size.width - 2, self.bounds.size.height - self.topInset - 1);
        NSRectFill(bridge);
        [[NSBezierPath bezierPathWithRoundedRect:body xRadius:radius yRadius:radius] fill];
    } else {
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:radius yRadius:radius] fill];
    }
    CGFloat contentY = self.topInset;
    NSColor *white = NSColor.whiteColor;
    NSColor *secondary = [white colorWithAlphaComponent:0.58];
    [[self overallColor] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(13, contentY + (self.model.expanded ? 18 : 15), 8, 8)] fill];

    if (!self.model.expanded) {
        [self drawLabel:@"Codex" rect:NSMakeRect(29, contentY + 9, 46, 20) font:[NSFont systemFontOfSize:12 weight:NSFontWeightSemibold] color:white alignment:NSTextAlignmentLeft];
        [self drawLabel:[NSString stringWithFormat:@"%ld", (long)self.model.activeCount] rect:NSMakeRect(74, contentY + 9, 22, 20) font:[NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightBold] color:white alignment:NSTextAlignmentLeft];
        NSDictionary *lead = self.model.priorityTasks.firstObject;
        if (lead) [self drawLabel:FormatDuration(lead) rect:NSMakeRect(self.bounds.size.width - 58, contentY + 10, 48, 18) font:[NSFont monospacedDigitSystemFontOfSize:9 weight:NSFontWeightMedium] color:secondary alignment:NSTextAlignmentRight];
        return;
    }

    [self drawLabel:@"Codex Tasks" rect:NSMakeRect(29, contentY + 12, 170, 22) font:[NSFont systemFontOfSize:14 weight:NSFontWeightBold] color:white alignment:NSTextAlignmentLeft];
    [self drawLabel:self.model.connected ? @"实时" : @"重连中" rect:NSMakeRect(self.bounds.size.width - 70, contentY + 14, 50, 18) font:[NSFont systemFontOfSize:10 weight:NSFontWeightMedium] color:secondary alignment:NSTextAlignmentRight];
    NSArray *tasks = self.model.priorityTasks;
    if (tasks.count == 0) {
        [self drawLabel:@"还没有可显示的任务" rect:NSMakeRect(20, contentY + 66, self.bounds.size.width - 40, 22) font:[NSFont systemFontOfSize:12] color:secondary alignment:NSTextAlignmentCenter];
    } else {
        [tasks enumerateObjectsUsingBlock:^(NSDictionary *task, NSUInteger index, BOOL *stop) {
            CGFloat y = contentY + 48 + index * 45;
            [[self colorForStatus:task[@"status"]] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(15, y + 8, 7, 7)] fill];
            [self drawLabel:task[@"title"] ?: @"Untitled" rect:NSMakeRect(31, y, self.bounds.size.width - 115, 18) font:[NSFont systemFontOfSize:12 weight:NSFontWeightSemibold] color:white alignment:NSTextAlignmentLeft];
            [self drawLabel:task[@"current_step"] ?: @"" rect:NSMakeRect(31, y + 19, self.bounds.size.width - 115, 16) font:[NSFont systemFontOfSize:9.5] color:secondary alignment:NSTextAlignmentLeft];
            [self drawLabel:FormatDuration(task) rect:NSMakeRect(self.bounds.size.width - 79, y + 8, 62, 16) font:[NSFont monospacedDigitSystemFontOfSize:9 weight:NSFontWeightRegular] color:secondary alignment:NSTextAlignmentRight];
        }];
    }
    CGFloat footerY = self.bounds.size.height - 34;
    [[white colorWithAlphaComponent:0.12] setStroke];
    NSBezierPath *line = [NSBezierPath bezierPath];
    [line moveToPoint:NSMakePoint(15, footerY - 6)];
    [line lineToPoint:NSMakePoint(self.bounds.size.width - 15, footerY - 6)];
    [line stroke];
    [self drawLabel:@"查看全部" rect:NSMakeRect(16, footerY, 58, 18) font:[NSFont systemFontOfSize:10 weight:NSFontWeightMedium] color:secondary alignment:NSTextAlignmentLeft];
    [self drawLabel:self.model.loginEnabled ? @"关闭登录启动" : @"登录时启动" rect:NSMakeRect(88, footerY, 86, 18) font:[NSFont systemFontOfSize:10 weight:NSFontWeightMedium] color:secondary alignment:NSTextAlignmentLeft];
    [self drawLabel:@"退出" rect:NSMakeRect(self.bounds.size.width - 48, footerY, 32, 18) font:[NSFont systemFontOfSize:10 weight:NSFontWeightMedium] color:secondary alignment:NSTextAlignmentRight];
}

- (void)mouseDown:(NSEvent *)event {
    if (!self.model.expanded) {
        self.model.expanded = YES;
        if (self.expansionHandler) self.expansionHandler(YES);
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSArray *tasks = self.model.priorityTasks;
    CGFloat taskStart = self.topInset + 45;
    if (point.y >= taskStart && point.y < taskStart + tasks.count * 45) {
        NSInteger index = (NSInteger)((point.y - taskStart) / 45);
        if (index >= 0 && index < tasks.count) [self.model openTask:tasks[index]];
        return;
    }
    if (point.y >= self.bounds.size.height - 45) {
        if (point.x < 82) [self.model openDashboard];
        else if (point.x < 190) [self.model toggleLogin];
        else if (point.x > self.bounds.size.width - 70) [NSApp terminate:nil];
    }
}

@end

@interface HUDPanel : NSPanel @end
@implementation HUDPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) DashboardModel *model;
@property(nonatomic, strong) HUDPanel *panel;
@property(nonatomic, strong) HUDView *hudView;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSTimer *clockTimer;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.model = [[DashboardModel alloc] init];
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"◉ Codex";
    self.statusItem.button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(togglePanel:);

    self.panel = [[HUDPanel alloc] initWithContentRect:NSMakeRect(0, 0, 154, 38) styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = NO;
    self.panel.level = NSStatusWindowLevel;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle;
    self.panel.hidesOnDeactivate = NO;
    self.hudView = [[HUDView alloc] initWithFrame:self.panel.contentView.bounds];
    self.hudView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.hudView.model = self.model;
    __weak typeof(self) weakSelf = self;
    self.hudView.expansionHandler = ^(BOOL expanded) { [weakSelf updatePanel:expanded]; };
    self.model.changeHandler = ^{ [weakSelf refresh]; };
    self.panel.contentView = self.hudView;
    [self.model start];
    [self updatePanel:NO];
    [self.panel orderFrontRegardless];
    self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screenChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
}

- (void)refresh {
    self.statusItem.button.title = [NSString stringWithFormat:@"◉ Codex %ld", (long)self.model.activeCount];
    [self.hudView setNeedsDisplay:YES];
    [self updateScreenVisibility];
}

- (void)togglePanel:(id)sender {
    self.model.expanded = !self.model.expanded;
    [self updatePanel:self.model.expanded];
    [self.panel orderFrontRegardless];
}

- (void)screenChanged:(NSNotification *)notification { [self updatePanel:self.model.expanded]; }

- (void)updatePanel:(BOOL)expanded {
    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    if (!screen) return;
    BOOL hasNotch = screen.safeAreaInsets.top > 0
        && !NSIsEmptyRect(screen.auxiliaryTopLeftArea)
        && !NSIsEmptyRect(screen.auxiliaryTopRightArea);
    CGFloat topInset = hasNotch ? ceil(screen.safeAreaInsets.top) : 0;
    CGFloat notchWidth = hasNotch
        ? MAX(0, NSMinX(screen.auxiliaryTopRightArea) - NSMaxX(screen.auxiliaryTopLeftArea))
        : 0;
    CGFloat collapsedWidth = MAX(154, notchWidth + 12);
    NSSize size = expanded ? NSMakeSize(356, 224 + topInset) : NSMakeSize(collapsedWidth, 38 + topInset);
    CGFloat x = hasNotch ? NSMidX(screen.frame) - size.width / 2 : NSMaxX(screen.visibleFrame) - size.width - 14;
    CGFloat top = hasNotch ? NSMaxY(screen.frame) : NSMaxY(screen.visibleFrame) - 4;
    self.hudView.topInset = topInset;
    [self.panel setFrame:NSMakeRect(x, top - size.height, size.width, size.height) display:YES animate:NO];
    [self.hudView setNeedsDisplay:YES];
}

- (void)updateScreenVisibility {
    if ([self frontmostApplicationIsFullScreen] && !self.model.expanded) [self.panel orderOut:nil];
    else if (!self.panel.visible) [self.panel orderFrontRegardless];
}

- (BOOL)frontmostApplicationIsFullScreen {
    pid_t pid = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
    NSScreen *screen = NSScreen.mainScreen;
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

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
