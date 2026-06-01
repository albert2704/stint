#import <Cocoa/Cocoa.h>
#import <FlutterMacOS/FlutterMacOS.h>

NS_ASSUME_NONNULL_BEGIN

/// Native countdown, mini controls, and alert sounds shared by both macOS hosts.
@interface DeskMenuBar : NSObject
- (instancetype)initWithWindow:(NSWindow *)window
                     messenger:(id<FlutterBinaryMessenger>)messenger;
- (void)showWindow;
- (void)windowWillClose;
- (void)setYouTubeView:(nullable NSView *)view;
- (void)showYouTubePlayer;
@property(nonatomic, copy, nullable) void (^youTubeVisibilityChanged)(BOOL visible);
@end

NS_ASSUME_NONNULL_END
