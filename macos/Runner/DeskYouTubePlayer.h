#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// A visible YouTube IFrame API player. Call its methods on the main thread.
/// Creating, selecting, and showing the player never start playback.
@interface DeskYouTubePlayer : NSObject
- (instancetype)initWithStateChanged:(void (^)(BOOL playing, BOOL starting,
                                               NSString *_Nullable error))stateChanged;
@property(nonatomic, readonly) BOOL playing;
@property(nonatomic, readonly) BOOL starting;
@property(nonatomic, copy, readonly, nullable) NSString *videoId;
/// The embedded view is hosted by the menu-bar panel; it never owns a window.
@property(nonatomic, readonly) NSView *view;
@property(nonatomic, copy, nullable) void (^showPlayer)(void);
- (void)presentationVisibilityChanged:(BOOL)visible;
- (void)setVideoId:(NSString *)videoId title:(NSString *)title volume:(double)volume;
- (void)show;
- (void)play;
- (void)pause;
/// Volume is normalized to 0...1.
- (void)setVolume:(double)volume;
/// Cancels playback and discards the selected web content.
- (void)stop;
@end

NS_ASSUME_NONNULL_END
