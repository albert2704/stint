// Exercise the production snapshot and Flutter codec without opening windows,
// loading audio, contacting YouTube, or reading/writing user preferences.
#import "../macos/Runner/StintMusic.m"

@interface StintMusicAudioProbe : NSObject
@property(nonatomic) BOOL playing;
@property(nonatomic) float volume;
@property(nonatomic, weak) id delegate;
- (BOOL)isPlaying;
- (void)stop;
- (void)pause;
- (BOOL)play;
@end
@implementation StintMusicAudioProbe
- (BOOL)isPlaying { return self.playing; }
- (void)stop { self.playing = NO; }
- (void)pause { self.playing = NO; }
- (BOOL)play { self.playing = YES; return YES; }
@end

@interface StintMusicYouTubeProbe : NSObject
@property(nonatomic, copy) NSString *videoId;
@property(nonatomic) BOOL playing;
@property(nonatomic) BOOL starting;
- (void)stop;
@end
@implementation StintMusicYouTubeProbe
- (void)stop { self.playing = NO; self.starting = NO; }
@end

static NSUInteger checks;

static void Check(BOOL condition, NSString *message) {
  if (!condition) {
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    exit(1);
  }
  checks++;
}

static id Command(StintMusic *music, NSString *method, id arguments) {
  __block id response = nil;
  [music handleCall:[FlutterMethodCall methodCallWithMethodName:method arguments:arguments]
            result:^(id value) { response = value; }];
  return response;
}

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

static void CheckState(StintMusic *music, BOOL playing, BOOL starting, BOOL follows, NSString *context) {
  NSDictionary *state = [music state];
  // The native snapshot must contain genuine booleans before encoding, and the
  // values reaching Dart must retain that type; Dart compares them to `true`.
  FlutterStandardMessageCodec *codec = FlutterStandardMessageCodec.sharedInstance;
  NSDictionary *decoded = [codec decode:[codec encode:state]];
  for (NSDictionary *snapshot in @[state, decoded]) {
    CheckBoolean(snapshot, @"playing", playing, context);
    CheckBoolean(snapshot, @"starting", starting, context);
    CheckBoolean(snapshot, @"followTimer", follows, context);
    CheckBoolean(snapshot, @"ambientPlaying", [music isAmbientPlaying], context);
  }
}

int main(void) {
  @autoreleasepool {
    // Bypass the app initializer deliberately: it reads preferences and installs
    // a live channel. Only the production state builder is under test here.
    StintMusic *music = [[StintMusic alloc] init];
    music.tracks = [NSMutableArray array];
    music.youTubeTracks = [NSMutableArray arrayWithObject:@{
      @"id": @"youtube_M7lc1UVf-VE", @"title": @"Test video",
      @"youtubeVideoId": @"M7lc1UVf-VE"
    }];
    music.selectedId = @"quiet_keys";
    music.volume = 0.35;
    CheckState(music, NO, NO, NO, @"initial state");

    StintMusicAudioProbe *audio = [[StintMusicAudioProbe alloc] init];
    StintMusicYouTubeProbe *youTube = [[StintMusicYouTubeProbe alloc] init];
    music.player = (AVAudioPlayer *)audio;
    music.youTubePlayer = (StintYouTubePlayer *)youTube;
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
    music.youTubePlayer = nil;
    music.player = nil;
    music.selectedId = @"quiet_keys";
    music.ambientLevels = StintAmbientLevels(@{});
    music.ambientPlayers = [NSMutableDictionary dictionary];
    music.ambientGain = 1;
    Check(!StintAmbientLevels(@{@"rain": @YES}), @"Booleans cannot become layer volumes.");
    Check(!StintAmbientLevels(@{@"rain": @(NAN)}), @"Nonfinite levels must be rejected.");
    Check(!StintAmbientLevels(@{@"ocean": @0.5}), @"Unknown layers must be rejected.");
    Check([StintAmbientLevels(@{@"rain": @3})[@"rain"] doubleValue] == 1, @"Levels clamp at one.");
    Check([StintAmbientLevels(@{@"rain": @-2})[@"rain"] doubleValue] == 0, @"Levels clamp at zero.");

    id updated = Command(music, @"ambientLevels", @{@"levels": @{@"rain": @0.6, @"cafe": @0.3}});
    Check([updated isKindOfClass:NSDictionary.class], @"Paused mix settings apply without audio data.");
    CheckBoolean(updated, @"ambientPlaying", NO, @"saved mix stays paused");
    Check([music.ambientLevels[@"brown_noise"] doubleValue] == 0, @"Unspecified layers are off.");
    Check(music.ambientPlayers.count == 0, @"Editing a paused mix never creates audio players.");
    id unavailable = Command(music, @"ambientPlay", @{});
    Check([unavailable isKindOfClass:FlutterError.class], @"Missing bundled data reports an error.");
    Check(![music isAmbientPlaying], @"Missing data cannot partly start the mix.");

    StintMusicAudioProbe *rain = [[StintMusicAudioProbe alloc] init];
    StintMusicAudioProbe *cafe = [[StintMusicAudioProbe alloc] init];
    music.ambientPlayers = [@{@"rain": rain, @"cafe": cafe} mutableCopy];
    id started = Command(music, @"ambientPlay", @{});
    CheckBoolean(started, @"ambientPlaying", YES, @"ambient only");
    CheckBoolean(started, @"playing", NO, @"ambient does not pretend music is playing");
    Check(rain.isPlaying && cafe.isPlaying, @"Independent ambient layers play simultaneously.");
    Check(fabs(rain.volume - .6) < .001 && fabs(cafe.volume - .3) < .001, @"Each layer retains its own gain.");

    // Adding an unavailable layer must leave the old playing mix intact.
    id failure = Command(music, @"ambientLevels", @{@"levels": @{@"rain": @0.8, @"brown_noise": @0.4}});
    Check([failure isKindOfClass:FlutterError.class], @"A newly enabled layer requires its bytes.");
    Check([music.ambientLevels[@"rain"] doubleValue] == .6 && cafe.isPlaying,
          @"Preparing a failed layer does not partly replace a live mix.");

    music.player = (AVAudioPlayer *)audio;
    audio.playing = YES;
    Command(music, @"ambientPause", nil);
    Check(!rain.isPlaying && !cafe.isPlaying && audio.isPlaying,
          @"Pause ambience leaves music playing.");
    Command(music, @"ambientPlay", @{});
    Check(audio.volume <= .65, @"Music gain reserves headroom when layers play.");
    __block BOOL faded = NO;
    [music handleCall:[FlutterMethodCall methodCallWithMethodName:@"fadePause" arguments:nil]
              result:^(id value) {
                CheckBoolean(value, @"ambientPlaying", NO, @"faded mix");
                CheckBoolean(value, @"playing", NO, @"faded music");
                faded = YES;
              }];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    Check(faded && !rain.isPlaying && !cafe.isPlaying && !audio.isPlaying,
          @"One fade completion pauses music and all layers.");

    // Exercise the production play wrapper and resume path with an existing
    // audio probe. Nonempty bytes satisfy validation but are never decoded.
    music.ambientLevels = StintAmbientLevels(@{});
    FlutterStandardTypedData *resumeBytes =
        [FlutterStandardTypedData typedDataWithBytes:[@"probe" dataUsingEncoding:NSUTF8StringEncoding]];
    id fadeStart = Command(music, @"play", @{
      @"id": @"quiet_keys", @"data": resumeBytes, @"fade": @YES
    });
    CheckBoolean(fadeStart, @"playing", YES, @"music only fade begins");
    Check(music.fadeTimer != nil && audio.volume == 0,
          @"A music-only fade stays silent until its first tick, without a full-volume transient.");
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
    Check(audio.volume > 0 && audio.volume < music.volume,
          @"A music-only fade rises gradually after its first tick.");
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.8]];
    Check(music.fadeTimer == nil && fabs(audio.volume - music.volume) < .001,
          @"A music-only fade reaches the saved volume.");
    Command(music, @"pause", nil);
    music.ambientLevels = StintAmbientLevels(@{@"rain": @0.6, @"cafe": @0.3});

    // Preference storage is deliberately nil in this harness: commands only
    // exercise in-memory transitions and never write real user preferences.
    id invalidProfile = Command(music, @"applyProfile", @{
      @"selectedId": @"quiet_keys", @"volume": @0.9,
      @"followTimer": @1, @"ambientLevels": @{@"rain": @0.2}
    });
    Check([invalidProfile isKindOfClass:FlutterError.class], @"Malformed profile fails atomically.");
    Check([music.ambientLevels[@"rain"] doubleValue] == .6, @"Rejected profile leaves settings unchanged.");
    id profile = Command(music, @"applyProfile", @{
      @"selectedId": @"missing_import", @"volume": @0.2,
      @"followTimer": @YES, @"ambientLevels": @{@"brown_noise": @0.4}
    });
    Check([profile[@"selectedId"] isEqualToString:@"quiet_keys"], @"Missing profile track safely falls back.");
    Check([profile[@"profileWarning"] length] > 0, @"Fallback includes a user explanation.");
    CheckBoolean(profile, @"playing", NO, @"profile never starts music");
    CheckBoolean(profile, @"ambientPlaying", NO, @"profile never starts ambience");
    Check([music.ambientLevels[@"brown_noise"] doubleValue] == .4 && music.ambientPlayers.count == 0,
          @"Profile stores levels and releases old players.");
    NSString *missing = [@"custom_" stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString];
    [music.tracks addObject:@{@"id": missing, @"title": @"Deleted cache",
                             @"filename": [missing stringByAppendingPathExtension:@"wav"]}];
    id missingCache = Command(music, @"applyProfile", @{
      @"selectedId": missing, @"volume": @0.4,
      @"followTimer": @NO, @"ambientLevels": @{}
    });
    Check([missingCache[@"selectedId"] isEqualToString:@"quiet_keys"] &&
          [missingCache[@"profileWarning"] length] > 0,
          @"A library entry whose cached file is missing also falls back silently.");
    printf("Music state: %lu checks passed (production snapshots and Flutter codec).\n", (unsigned long)checks);
  }
  return 0;
}
