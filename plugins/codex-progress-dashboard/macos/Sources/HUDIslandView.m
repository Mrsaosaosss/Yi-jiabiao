#import "HUDIslandView.h"

@implementation HUDIslandView

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.wantsLayer = YES;
        self.layer.masksToBounds = NO;
        self.accessibilityRole = NSAccessibilityGroupRole;
        self.accessibilityLabel = @"Codex 任务进度";
    }
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (void)setState:(HUDPresentationState)state {
    _state = state;
    [self setNeedsDisplay:YES];
}

- (void)setNotchHeight:(CGFloat)notchHeight {
    _notchHeight = notchHeight;
    [self setNeedsDisplay:YES];
}

- (NSBezierPath *)islandPath {
    NSRect rect = NSInsetRect(self.bounds, 0.75, 0.75);
    CGFloat radius = self.state == HUDPresentationStateExpanded ? 28 : 20;
    radius = MIN(radius, rect.size.height / 2);
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(NSMinX(rect), NSMinY(rect))];
    [path lineToPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect))];
    [path lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect) - radius)];
    [path curveToPoint:NSMakePoint(NSMaxX(rect) - radius, NSMaxY(rect))
         controlPoint1:NSMakePoint(NSMaxX(rect), NSMaxY(rect) - radius * 0.42)
         controlPoint2:NSMakePoint(NSMaxX(rect) - radius * 0.42, NSMaxY(rect))];
    [path lineToPoint:NSMakePoint(NSMinX(rect) + radius, NSMaxY(rect))];
    [path curveToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect) - radius)
         controlPoint1:NSMakePoint(NSMinX(rect) + radius * 0.42, NSMaxY(rect))
         controlPoint2:NSMakePoint(NSMinX(rect), NSMaxY(rect) - radius * 0.42)];
    [path closePath];
    return path;
}

- (BOOL)containsLocalPoint:(NSPoint)point {
    return NSPointInRect(point, self.bounds) && [self.islandPath containsPoint:point];
}

- (NSColor *)colorForStatus:(NSString *)status {
    if ([status isEqualToString:@"waiting"]) return [NSColor colorWithRed:1.0 green:0.68 blue:0.20 alpha:1];
    if ([status isEqualToString:@"running"]) return [NSColor colorWithRed:0.25 green:0.82 blue:0.48 alpha:1];
    if ([status isEqualToString:@"failed"]) return [NSColor colorWithRed:1.0 green:0.30 blue:0.36 alpha:1];
    if ([status isEqualToString:@"idle"]) return [NSColor colorWithRed:0.42 green:0.46 blue:0.54 alpha:1];
    return NSColor.systemGrayColor;
}

- (void)drawLabel:(NSString *)value rect:(NSRect)rect font:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = alignment;
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    [value ?: @"" drawInRect:rect withAttributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: style,
    }];
}

- (void)drawStatusDot:(NSString *)status rect:(NSRect)rect {
    [[self colorForStatus:status] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:rect] fill];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    BOOL reduceTransparency = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency;
    CGFloat alpha = (reduceTransparency || self.state != HUDPresentationStateExpanded) ? 1.0 : 0.985;
    NSBezierPath *path = self.islandPath;
    [[NSColor colorWithWhite:0.018 alpha:alpha] setFill];
    [path fill];
    [[NSColor colorWithWhite:1 alpha:0.12] setStroke];
    path.lineWidth = 1;
    [path stroke];

    NSColor *primary = NSColor.whiteColor;
    NSColor *secondary = [primary colorWithAlphaComponent:0.60];
    CGFloat y = self.notchHeight;

    if (self.state == HUDPresentationStateCompact) {
        [self drawStatusDot:self.presentation.overallStatus rect:NSMakeRect(14, y + 15, 9, 9)];
        [self drawLabel:self.presentation.compactTitle
                   rect:NSMakeRect(31, y + 9, 88, 22)
                   font:[NSFont systemFontOfSize:12 weight:NSFontWeightSemibold]
                  color:primary
              alignment:NSTextAlignmentLeft];
        [self drawLabel:[self.presentation durationForTask:self.presentation.leadTask]
                   rect:NSMakeRect(self.bounds.size.width - 77, y + 10, 62, 20)
                   font:[NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium]
                  color:secondary
              alignment:NSTextAlignmentRight];
        return;
    }

    if (self.state == HUDPresentationStatePeek) {
        [self drawStatusDot:self.presentation.overallStatus rect:NSMakeRect(18, y + 18, 9, 9)];
        [self drawLabel:[NSString stringWithFormat:@"%ld 个活跃", (long)self.presentation.activeCount]
                   rect:NSMakeRect(35, y + 11, 92, 23)
                   font:[NSFont systemFontOfSize:12 weight:NSFontWeightSemibold]
                  color:primary
              alignment:NSTextAlignmentLeft];
        [self drawLabel:self.presentation.peekTitle
                   rect:NSMakeRect(138, y + 7, 212, 19)
                   font:[NSFont systemFontOfSize:11.5 weight:NSFontWeightSemibold]
                  color:primary
              alignment:NSTextAlignmentLeft];
        [self drawLabel:self.presentation.peekProgress
                   rect:NSMakeRect(138, y + 25, 250, 16)
                   font:[NSFont systemFontOfSize:9.5 weight:NSFontWeightRegular]
                  color:secondary
              alignment:NSTextAlignmentLeft];
        [self drawLabel:[self.presentation durationForTask:self.presentation.leadTask]
                   rect:NSMakeRect(self.bounds.size.width - 77, y + 15, 62, 20)
                   font:[NSFont monospacedDigitSystemFontOfSize:10.5 weight:NSFontWeightMedium]
                  color:secondary
              alignment:NSTextAlignmentRight];
        return;
    }

    [self drawLabel:@"Codex 任务"
               rect:NSMakeRect(22, y + 12, 150, 24)
               font:[NSFont systemFontOfSize:15 weight:NSFontWeightBold]
              color:primary
          alignment:NSTextAlignmentLeft];
    [self drawStatusDot:self.presentation.overallStatus rect:NSMakeRect(self.bounds.size.width - 98, y + 19, 8, 8)];
    NSString *live = self.presentation.dashboard.connected
        ? [NSString stringWithFormat:@"%ld 个活跃", (long)self.presentation.activeCount]
        : @"重连中";
    [self drawLabel:live
               rect:NSMakeRect(self.bounds.size.width - 86, y + 13, 66, 20)
               font:[NSFont systemFontOfSize:10 weight:NSFontWeightMedium]
              color:secondary
          alignment:NSTextAlignmentRight];

    CGFloat taskStart = y + 50;
    NSArray<NSDictionary *> *tasks = self.presentation.tasks;
    if (tasks.count == 0) {
        [self drawLabel:@"还没有可显示的任务"
                   rect:NSMakeRect(20, taskStart + 38, self.bounds.size.width - 40, 22)
                   font:[NSFont systemFontOfSize:12]
                  color:secondary
              alignment:NSTextAlignmentCenter];
    } else {
        [tasks enumerateObjectsUsingBlock:^(NSDictionary *task, NSUInteger index, BOOL *stop) {
            CGFloat rowY = taskStart + index * 48;
            if (index > 0) {
                [[primary colorWithAlphaComponent:0.10] setStroke];
                NSBezierPath *separator = [NSBezierPath bezierPath];
                [separator moveToPoint:NSMakePoint(20, rowY - 5)];
                [separator lineToPoint:NSMakePoint(self.bounds.size.width - 20, rowY - 5)];
                [separator stroke];
            }
            [self drawStatusDot:task[@"status"] rect:NSMakeRect(21, rowY + 8, 8, 8)];
            [self drawLabel:task[@"title"] ?: @"未命名任务"
                       rect:NSMakeRect(39, rowY, self.bounds.size.width - 205, 19)
                       font:[NSFont systemFontOfSize:11.5 weight:NSFontWeightSemibold]
                      color:primary
                  alignment:NSTextAlignmentLeft];
            [self drawLabel:task[@"current_step"] ?: @""
                       rect:NSMakeRect(39, rowY + 20, self.bounds.size.width - 205, 16)
                       font:[NSFont systemFontOfSize:9.5]
                      color:secondary
                  alignment:NSTextAlignmentLeft];
            [self drawLabel:[self.presentation durationForTask:task]
                       rect:NSMakeRect(self.bounds.size.width - 157, rowY + 8, 72, 17)
                       font:[NSFont monospacedDigitSystemFontOfSize:9.5 weight:NSFontWeightRegular]
                      color:secondary
                  alignment:NSTextAlignmentRight];
            [self drawLabel:[self.presentation fileCountForTask:task]
                       rect:NSMakeRect(self.bounds.size.width - 78, rowY + 8, 58, 17)
                       font:[NSFont systemFontOfSize:9.5 weight:NSFontWeightRegular]
                      color:secondary
                  alignment:NSTextAlignmentRight];
        }];
    }

    CGFloat footerY = self.bounds.size.height - 32;
    [[primary colorWithAlphaComponent:0.12] setStroke];
    NSBezierPath *line = [NSBezierPath bezierPath];
    [line moveToPoint:NSMakePoint(20, footerY - 6)];
    [line lineToPoint:NSMakePoint(self.bounds.size.width - 20, footerY - 6)];
    [line stroke];
    [self drawLabel:@"查看全部" rect:NSMakeRect(21, footerY, 64, 18) font:[NSFont systemFontOfSize:10 weight:NSFontWeightMedium] color:secondary alignment:NSTextAlignmentLeft];
    [self drawLabel:self.presentation.dashboard.loginEnabled ? @"关闭登录启动" : @"登录时启动" rect:NSMakeRect(104, footerY, 86, 18) font:[NSFont systemFontOfSize:10 weight:NSFontWeightMedium] color:secondary alignment:NSTextAlignmentLeft];
    [self drawLabel:@"退出" rect:NSMakeRect(self.bounds.size.width - 54, footerY, 34, 18) font:[NSFont systemFontOfSize:10 weight:NSFontWeightMedium] color:secondary alignment:NSTextAlignmentRight];
}

- (void)mouseDown:(NSEvent *)event {
    if (self.state != HUDPresentationStateExpanded) {
        if (self.primaryAction) self.primaryAction();
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat taskStart = self.notchHeight + 50;
    NSArray *tasks = self.presentation.tasks;
    if (point.y >= taskStart && point.y < taskStart + tasks.count * 48) {
        NSUInteger index = (NSUInteger)((point.y - taskStart) / 48);
        if (index < tasks.count && self.taskAction) self.taskAction(index);
        return;
    }
    if (point.y >= self.bounds.size.height - 46) {
        if (point.x < 94 && self.dashboardAction) self.dashboardAction();
        else if (point.x < 205 && self.loginAction) self.loginAction();
        else if (point.x > self.bounds.size.width - 80 && self.quitAction) self.quitAction();
    }
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) {
        if (self.dismissAction) self.dismissAction();
        return;
    }
    [super keyDown:event];
}

@end
