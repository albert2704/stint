// Exercise the production snapshot and Flutter codec without opening windows,
// loading audio, contacting YouTube, or reading/writing user preferences.
#import "../macos/Runner/DeskMusic.m"

@interface DeskMusicAudioProbe : NSObject
@property(nonatomic) BOOL playing;
@property(nonatomic) float volume;
@property(nonatomic, weak) id delegate;
- (BOOL)isPlaying;
- (void)stop;
@end
@implementation DeskMusicAudioProbe
- (BOOL)isPlaying { return self.playing; }
- (void)stop { self.playing = NO; }
@end

@interface DeskMusicYouTubeProbe : NSObject
@property(nonatomic, copy) NSString *videoId;
@property(nonatomic) BOOL playing;
@property(nonatomic) BOOL starting;
- (void)stop;
@end
@implementation DeskMusicYouTubeProbe
- (void)stop { self.playing = NO; self.starting = NO; }
@end

static NSUInteger checks;

static void CheckBoolean(NSDictionary *state, NSString *key, BOOL expected, NSString *context) {
  id value = state[key];
  if (![value isKindOfClass:NSNumber.class] ||
      CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() ||
      [value boolValue] != expected) {
    fprintf(stderr, "FAIL: %s %s must be a Boolean %s, got %s (%s)\n",
        context.UTF8String, key.UTF8String, expected ? "true" : "false",
        [[value description] UTF8String], [[value className] UTF8String]);
    exit(1);
  }
  checks++;
}

static void CheckState(DeskMusic *music, BOOL playing, BOOL starting, BOOL follows, NSString *context) {
  NSDictionary *state = [music state];
  // The native snapshot must contain genuine booleans before encoding, and the
  // values reaching Dart must retain that type; Dart compares them to `true`.
  FlutterStandardMessageCodec *codec = FlutterStandardMessageCodec.sharedInstance;
  NSDictionary *decoded = [codec decode:[codec encode:state]];
  for (NSDictionary *snapshot in @[state, decoded]) {
    CheckBoolean(snapshot, @"playing", playing, context);
    CheckBoolean(snapshot, @"starting", starting, context);
    CheckBoolean(snapshot, @"followTimer", follows, context);
  }
}

int main(void) {
  @autoreleasepool {
    // Bypass the app initializer deliberately: it reads preferences and installs
    // a live channel. Only the production state builder is under test here.
    DeskMusic *music = [[DeskMusic alloc] init];
    music.tracks = [NSMutableArray array];
    music.youTubeTracks = [NSMutableArray arrayWithObject:@{
      @"id": @"youtube_M7lc1UVf-VE", @"title": @"Test video",
      @"youtubeVideoId": @"M7lc1UVf-VE"
    }];
    music.selectedId = @"quiet_keys";
    music.volume = 0.35;
    CheckState(music, NO, NO, NO, @"initial state");

    DeskMusicAudioProbe *audio = [[DeskMusicAudioProbe alloc] init];
    DeskMusicYouTubeProbe *youTube = [[DeskMusicYouTubeProbe alloc] init];
    music.player = (AVAudioPlayer *)audio;
    music.youTubePlayer = (DeskYouTubePlayer *)youTube;
    for (NSNumber *follow in @[@NO, @YES]) {
      music.followTimer = follow.boolValue;
      audio.playing = YES;
      CheckState(music, YES, NO, follow.boolValue, @"local playing");
      audio.playing = NO;
      CheckState(music, NO, NO, follow.boolValue, @"local paused");

      music.selectedId = @"youtube_M7lc1UVf-VE";
      CheckState(music, NO, NO, follow.boolValue, @"YouTube not created");
      youTube.videoId = @"M7lc1UVf-VE";
      youTube.starting = YES;
      CheckState(music, NO, YES, follow.boolValue, @"YouTube starting");
      youTube.starting = NO;
      youTube.playing = YES;
      CheckState(music, YES, NO, follow.boolValue, @"YouTube playing");
      youTube.playing = NO;
      CheckState(music, NO, NO, follow.boolValue, @"YouTube paused");

      // A stale player from a previous selection cannot report playback for
      // the newly selected track.
      youTube.videoId = @"dQw4w9WgXcQ";
      youTube.playing = YES;
      youTube.starting = YES;
      CheckState(music, NO, NO, follow.boolValue, @"stale YouTube selection");
      music.selectedId = @"quiet_keys";
      audio.playing = YES;
      CheckState(music, YES, NO, follow.boolValue, @"local ignores stale YouTube");
      audio.playing = NO;
      youTube.videoId = nil;
      youTube.playing = NO;
      youTube.starting = NO;
    }
    printf("Music state: %lu checks passed (production snapshots and Flutter codec).\n", (unsigned long)checks);
  }
  return 0;
}
