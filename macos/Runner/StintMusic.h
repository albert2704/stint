#import <Cocoa/Cocoa.h>
#import <FlutterMacOS/FlutterMacOS.h>

NS_ASSUME_NONNULL_BEGIN

/// Local looping music, independent ambience, and visible YouTube playback.
/// Saved sound settings restore silently; timer controls share the full mix.
@interface StintMusic : NSObject
- (instancetype)initWithWindow:(NSWindow *)window
                     messenger:(id<FlutterBinaryMessenger>)messenger;
@property(nonatomic, copy, nullable) void (^youTubeViewChanged)(NSView *_Nullable view);
@property(nonatomic, copy, nullable) void (^showYouTubePlayer)(void);
- (void)youTubeVisibilityChanged:(BOOL)visible;
@end

NS_ASSUME_NONNULL_END
