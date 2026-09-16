#import <Cocoa/Cocoa.h>
#import "HUDGeometry.h"
#import "HUDPresentationModel.h"

@interface HUDIslandView : NSView
@property(nonatomic, strong) HUDPresentationModel *presentation;
@property(nonatomic) HUDPresentationState state;
@property(nonatomic) CGFloat notchHeight;
@property(nonatomic, copy) void (^primaryAction)(void);
@property(nonatomic, copy) void (^dismissAction)(void);
@property(nonatomic, copy) void (^taskAction)(NSUInteger index);
@property(nonatomic, copy) void (^dashboardAction)(void);
@property(nonatomic, copy) void (^loginAction)(void);
@property(nonatomic, copy) void (^quitAction)(void);
- (BOOL)containsLocalPoint:(NSPoint)point;
@end
