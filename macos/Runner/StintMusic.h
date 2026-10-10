#import <Cocoa/Cocoa.h>
#import <FlutterMacOS/FlutterMacOS.h>

NS_ASSUME_NONNULL_BEGIN

/// Local looping music and visible YouTube playback with optional timer-follow controls.
@interface StintMusic : NSObject
- (instancetype)initWithWindow:(NSWindow *)window
                     messenger:(id<FlutterBinaryMessenger>)messenger;
@property(nonatomic, copy, nullable) void (^youTubeViewChanged)(NSView *_Nullable view);
@property(nonatomic, copy, nullable) void (^showYouTubePlayer)(void);
- (void)youTubeVisibilityChanged:(BOOL)visible;
@end

NS_ASSUME_NONNULL_END
