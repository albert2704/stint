#import "StintMusic.h"
#import "StintYouTubePlayer.h"
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>

static NSString *const StintMusicTracksKey = @"StintMusicTracks";
static NSString *const StintMusicYouTubeTracksKey = @"StintMusicYouTubeTracks";
static NSString *const StintMusicSelectionKey = @"StintMusicSelectedId";
static NSString *const StintMusicVolumeKey = @"StintMusicVolume";
static NSString *const StintMusicFollowTimerKey = @"StintMusicFollowTimer";
static NSUInteger const StintMusicMaximumBytes = 200 * 1024 * 1024;
static NSTimeInterval const StintMusicFadeDuration = 0.7;

static BOOL StintBuiltinTrack(NSString *identifier) {
  return [@[@"quiet_keys", @"warm_drift", @"night_study"] containsObject:identifier];
}

static BOOL StintYouTubeVideoId(id value) {
  if (![value isKindOfClass:NSString.class] || [value length] != 11) return NO;
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"];
  return [value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static FlutterError *StintMusicError(NSString *code, NSString *message) {
  return [FlutterError errorWithCode:code message:message details:nil];
}

@interface StintMusic () <AVAudioPlayerDelegate>
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, strong) FlutterMethodChannel *channel;
@property(nonatomic, strong) AVAudioPlayer *player;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *tracks;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *youTubeTracks;
@property(nonatomic, strong) StintYouTubePlayer *youTubePlayer;
@property(nonatomic) BOOL suppressYouTubeEvents;
@property(nonatomic, copy) NSString *selectedId;
@property(nonatomic) double volume;
@property(nonatomic) BOOL followTimer;
@property(nonatomic) BOOL importing;
@property(nonatomic, strong) NSTimer *fadeTimer;
@property(nonatomic, copy) FlutterResult fadePauseResult;
@end

@implementation StintMusic

- (instancetype)initWithWindow:(NSWindow *)window messenger:(id<FlutterBinaryMessenger>)messenger {
  self = [super init];
  if (!self) return nil;
  _window = window;
  _tracks = [NSMutableArray array];
  _youTubeTracks = [NSMutableArray array];
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  id savedTracks = [defaults objectForKey:StintMusicTracksKey];
  if ([savedTracks isKindOfClass:NSArray.class]) {
    NSMutableSet *identifiers = [NSMutableSet set];
    for (id entry in savedTracks) {
      if (![entry isKindOfClass:NSDictionary.class]) continue;
      NSString *identifier = entry[@"id"];
      NSString *title = entry[@"title"];
      NSString *filename = entry[@"filename"];
      if (![identifier isKindOfClass:NSString.class] || ![identifier hasPrefix:@"custom_"] ||
          ![[NSUUID alloc] initWithUUIDString:[identifier substringFromIndex:7]] ||
          ![title isKindOfClass:NSString.class] || title.length == 0 ||
          ![filename isKindOfClass:NSString.class] || ![filename.lastPathComponent isEqualToString:filename] ||
          ![filename.stringByDeletingPathExtension isEqualToString:identifier] || [identifiers containsObject:identifier]) continue;
      [_tracks addObject:@{@"id": identifier, @"title": title, @"filename": filename}];
      [identifiers addObject:identifier];
    }
  }
  id savedYouTube = [defaults objectForKey:StintMusicYouTubeTracksKey];
  if ([savedYouTube isKindOfClass:NSArray.class]) {
    NSMutableSet *identifiers = [NSMutableSet set];
    for (id entry in savedYouTube) {
      if (![entry isKindOfClass:NSDictionary.class]) continue;
      NSString *videoId = entry[@"youtubeVideoId"];
      NSString *identifier = entry[@"id"];
      NSString *title = entry[@"title"];
      if (!StintYouTubeVideoId(videoId) ||
          ![identifier isKindOfClass:NSString.class] ||
          ![identifier isEqualToString:[@"youtube_" stringByAppendingString:videoId]] ||
          ![title isKindOfClass:NSString.class] || title.length > 120 ||
          [identifiers containsObject:identifier]) continue;
      title = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if (!title.length) continue;
      [_youTubeTracks addObject:@{@"id": identifier, @"title": title, @"youtubeVideoId": videoId}];
      [identifiers addObject:identifier];
    }
  }
  id savedSelection = [defaults objectForKey:StintMusicSelectionKey];
  _selectedId = [savedSelection isKindOfClass:NSString.class] && [self knownTrack:savedSelection] ? savedSelection : @"quiet_keys";
  id savedVolume = [defaults objectForKey:StintMusicVolumeKey];
  _volume = [savedVolume isKindOfClass:NSNumber.class] && isfinite([savedVolume doubleValue]) ? MIN(1, MAX(0, [savedVolume doubleValue])) : 0.35;
  _followTimer = [defaults boolForKey:StintMusicFollowTimerKey];
  _channel = [FlutterMethodChannel methodChannelWithName:@"stint/music" binaryMessenger:messenger];
  __weak StintMusic *weakSelf = self;
  [_channel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    StintMusic *self = weakSelf;
    if (!self) { result(StintMusicError(@"closed", @"Stint is closing.")); return; }
    [self handleCall:call result:result];
  }];
  // Restoring a library or selection never starts playback.
  return self;
}

- (NSDictionary *)state {
  NSMutableArray *tracks = [NSMutableArray arrayWithCapacity:self.tracks.count + self.youTubeTracks.count];
  for (NSDictionary *track in self.tracks) [tracks addObject:@{@"id": track[@"id"], @"title": track[@"title"]}];
  [tracks addObjectsFromArray:self.youTubeTracks];
  NSDictionary *selectedYouTube = [self youTubeTrack:self.selectedId];
  BOOL usesYouTube = selectedYouTube && [self.youTubePlayer.videoId isEqualToString:selectedYouTube[@"youtubeVideoId"]];
  // C promotes conditional/logical expressions to int. Box BOOL locals so
  // Flutter's standard codec sends true/false instead of numeric 1/0.
  BOOL playing = usesYouTube ? self.youTubePlayer.playing : self.player.isPlaying;
  BOOL starting = usesYouTube && self.youTubePlayer.starting;
  return @{@"tracks": tracks, @"selectedId": self.selectedId ?: NSNull.null,
           @"volume": @(self.volume), @"playing": @(playing),
           @"starting": @(starting),
           @"followTimer": @(self.followTimer)};
}

- (NSDictionary *)customTrack:(NSString *)identifier {
  for (NSDictionary *track in self.tracks) if ([track[@"id"] isEqualToString:identifier]) return track;
  return nil;
}

- (BOOL)knownTrack:(NSString *)identifier {
  return StintBuiltinTrack(identifier) || [self customTrack:identifier] != nil || [self youTubeTrack:identifier] != nil;
}

- (NSDictionary *)youTubeTrack:(NSString *)identifier {
  for (NSDictionary *track in self.youTubeTracks) if ([track[@"id"] isEqualToString:identifier]) return track;
  return nil;
}

- (void)prepareYouTubeTrack:(NSDictionary *)track {
  if (!self.youTubePlayer) {
    __weak StintMusic *weakSelf = self;
    self.youTubePlayer = [[StintYouTubePlayer alloc] initWithStateChanged:^(BOOL playing, BOOL starting, NSString *error) {
      (void)playing;
      (void)starting;
      StintMusic *self = weakSelf;
      if (!self || self.suppressYouTubeEvents) return;
      NSDictionary *selected = [self youTubeTrack:self.selectedId];
      if (!selected || ![self.youTubePlayer.videoId isEqualToString:selected[@"youtubeVideoId"]]) return;
      if (error.length) [self.channel invokeMethod:@"error" arguments:error];
      [self.channel invokeMethod:@"state" arguments:[self state]];
    }];
  }
  self.youTubePlayer.showPlayer = self.showYouTubePlayer;
  if (self.youTubeViewChanged) self.youTubeViewChanged(self.youTubePlayer.view);
  if (![self.youTubePlayer.videoId isEqualToString:track[@"youtubeVideoId"]]) {
    [self.youTubePlayer setVideoId:track[@"youtubeVideoId"] title:track[@"title"] volume:self.volume];
  } else {
    [self.youTubePlayer setVolume:self.volume];
  }
}

- (void)stopAllPlayers {
  self.suppressYouTubeEvents = YES;
  [self.youTubePlayer stop];
  if (self.youTubeViewChanged) self.youTubeViewChanged(nil);
  self.suppressYouTubeEvents = NO;
  [self stopPlayer];
}

- (void)youTubeVisibilityChanged:(BOOL)visible {
  [self.youTubePlayer presentationVisibilityChanged:visible];
}

- (void)addYouTube:(id)arguments result:(FlutterResult)result {
  NSDictionary *args = [arguments isKindOfClass:NSDictionary.class] ? arguments : nil;
  id videoId = args[@"videoId"];
  id suppliedTitle = args[@"title"];
  if (!StintYouTubeVideoId(videoId) ||
      (suppliedTitle && suppliedTitle != NSNull.null && ![suppliedTitle isKindOfClass:NSString.class])) {
    result(StintMusicError(@"invalid_arguments", @"Enter a valid YouTube video link and an optional title."));
    return;
  }
  NSString *title = [suppliedTitle isKindOfClass:NSString.class]
      ? [suppliedTitle stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
  if (title.length > 120) {
    result(StintMusicError(@"invalid_arguments", @"Keep the YouTube title to 120 characters or fewer."));
    return;
  }
  NSString *identifier = [@"youtube_" stringByAppendingString:videoId];
  NSDictionary *existing = [self youTubeTrack:identifier];
  if (!title.length) title = existing[@"title"] ?: [NSString stringWithFormat:@"YouTube · %@", videoId];
  NSDictionary *track = @{@"id": identifier, @"title": title, @"youtubeVideoId": videoId};
  if (existing) [self.youTubeTracks replaceObjectAtIndex:[self.youTubeTracks indexOfObject:existing] withObject:track];
  else [self.youTubeTracks addObject:track];
  result = [self resultByCancellingFade:result];
  [self stopAllPlayers];
  self.selectedId = identifier;
  [NSUserDefaults.standardUserDefaults setObject:self.youTubeTracks forKey:StintMusicYouTubeTracksKey];
  [NSUserDefaults.standardUserDefaults setObject:identifier forKey:StintMusicSelectionKey];
  // Store a link only. The web player is created after Show player or Play.
  result([self state]);
}

- (NSURL *)musicDirectory:(NSError **)error {
  NSURL *support = [NSFileManager.defaultManager URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:error];
  if (!support) return nil;
  NSURL *directory = [[support URLByAppendingPathComponent:@"Stint" isDirectory:YES] URLByAppendingPathComponent:@"Music" isDirectory:YES];
  if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
  return directory;
}

- (void)handleCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSString *method = call.method;
  if ([method isEqualToString:@"addYouTube"]) { [self addYouTube:call.arguments result:result]; return; }
  if ([method isEqualToString:@"removeCustom"]) {
    NSString *identifier = [call.arguments isKindOfClass:NSString.class] ? call.arguments : nil;
    NSDictionary *track = identifier ? [self customTrack:identifier] : nil;
    NSString *filename = track[@"filename"];
    if (!track || ![identifier hasPrefix:@"custom_"] ||
        ![[NSUUID alloc] initWithUUIDString:[identifier substringFromIndex:7]] ||
        ![filename isKindOfClass:NSString.class] ||
        ![filename.lastPathComponent isEqualToString:filename] ||
        ![filename.stringByDeletingPathExtension isEqualToString:identifier]) {
      result(StintMusicError(@"unknown_track", @"Choose an imported audio file to remove."));
      return;
    }
    NSError *error = nil;
    NSURL *directory = [self musicDirectory:&error];
    if (!directory) {
      result(StintMusicError(@"remove_failed", @"This sound could not be removed. Try again."));
      return;
    }
    // Only remove Stint's cached copy, never the user's original imported file.
    // Reject redirected cache folders and unexpected directories at the file.
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSURL *folder in @[directory, directory.URLByDeletingLastPathComponent]) {
      NSDictionary *attributes = [files attributesOfItemAtPath:folder.path error:&error];
      if (![attributes[NSFileType] isEqualToString:NSFileTypeDirectory]) {
        result(StintMusicError(@"remove_failed", @"The saved audio folder is unavailable."));
        return;
      }
    }
    NSURL *cachedFile = [directory URLByAppendingPathComponent:filename isDirectory:NO];
    NSDictionary *attributes = [files attributesOfItemAtPath:cachedFile.path error:&error];
    if (attributes && ![attributes[NSFileType] isEqualToString:NSFileTypeRegular] &&
        ![attributes[NSFileType] isEqualToString:NSFileTypeSymbolicLink]) {
      result(StintMusicError(@"remove_failed", @"This saved audio file could not be removed."));
      return;
    }
    if ((!attributes && error.code != NSFileReadNoSuchFileError && error.code != NSFileNoSuchFileError) ||
        (attributes && ![files removeItemAtURL:cachedFile error:&error])) {
      result(StintMusicError(@"remove_failed", @"This sound could not be removed. Try again."));
      return;
    }
    if ([self.selectedId isEqualToString:identifier]) {
      result = [self resultByCancellingFade:result];
      [self stopAllPlayers];
      self.selectedId = @"quiet_keys";
      [NSUserDefaults.standardUserDefaults setObject:self.selectedId forKey:StintMusicSelectionKey];
    }
    [self.tracks removeObject:track];
    [NSUserDefaults.standardUserDefaults setObject:self.tracks forKey:StintMusicTracksKey];
    result([self state]);
    return;
  }
  if ([method isEqualToString:@"removeYouTube"]) {
    NSString *identifier = [call.arguments isKindOfClass:NSString.class] ? call.arguments : nil;
    NSDictionary *track = identifier ? [self youTubeTrack:identifier] : nil;
    if (!track) {
      result(StintMusicError(@"unknown_track", @"Choose a saved YouTube link to remove."));
      return;
    }
    if ([self.selectedId isEqualToString:identifier]) {
      result = [self resultByCancellingFade:result];
      [self stopAllPlayers];
      self.selectedId = @"quiet_keys";
      [NSUserDefaults.standardUserDefaults setObject:self.selectedId forKey:StintMusicSelectionKey];
    }
    [self.youTubeTracks removeObject:track];
    [NSUserDefaults.standardUserDefaults setObject:self.youTubeTracks forKey:StintMusicYouTubeTracksKey];
    result([self state]);
    return;
  }
  if ([@[@"load", @"import", @"pause", @"resume", @"fadePause", @"showYouTube"] containsObject:method]) {
    if (call.arguments && call.arguments != NSNull.null) {
      result(StintMusicError(@"invalid_arguments", @"This music command does not accept arguments."));
      return;
    }
    if ([method isEqualToString:@"import"]) { [self importTracks:result]; return; }
    NSDictionary *youTube = [self youTubeTrack:self.selectedId];
    if ([method isEqualToString:@"showYouTube"]) {
      if (!youTube) { result(StintMusicError(@"not_youtube", @"Choose a YouTube track to show its player.")); return; }
      result = [self resultByCancellingFade:result];
      [self stopPlayer];
      [self prepareYouTubeTrack:youTube];
      [self.youTubePlayer show];
      result([self state]);
      return;
    }
    if (youTube && [@[@"pause", @"resume", @"fadePause"] containsObject:method]) {
      result = [self resultByCancellingFade:result];
      if ([method isEqualToString:@"resume"]) {
        [self stopPlayer];
        [self prepareYouTubeTrack:youTube];
        [self.youTubePlayer play];
      } else {
        // Pause immediately so a pending iframe load cannot complete a stale play.
        [self.youTubePlayer pause];
      }
      result([self state]);
      return;
    }
    if ([method isEqualToString:@"fadePause"]) {
      float initialVolume = self.player.volume;
      FlutterResult superseded = [self cancelFade];
      if (self.player.isPlaying) {
        self.player.volume = initialVolume;
        self.fadePauseResult = result;
        [self fadePlayerToVolume:0 pauseOnCompletion:YES];
      } else {
        result([self state]);
      }
      if (superseded) superseded([self state]);
      return;
    }
    if ([method isEqualToString:@"pause"] || [method isEqualToString:@"resume"]) {
      result = [self resultByCancellingFade:result];
    }
    if ([method isEqualToString:@"pause"]) [self.player pause];
    if ([method isEqualToString:@"resume"] && self.player && !self.player.isPlaying && ![self.player play]) {
      result(StintMusicError(@"playback_failed", @"The audio could not resume. Try playing the track again."));
      return;
    }
    result([self state]);
    return;
  }
  if ([method isEqualToString:@"followTimer"]) {
    id value = call.arguments;
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()) {
      result(StintMusicError(@"invalid_arguments", @"Play with timer must be on or off."));
      return;
    }
    self.followTimer = [value boolValue];
    [NSUserDefaults.standardUserDefaults setBool:self.followTimer forKey:StintMusicFollowTimerKey];
    result([self state]);
    return;
  }
  if ([method isEqualToString:@"volume"]) {
    id value = call.arguments;
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() || !isfinite([value doubleValue])) {
      result(StintMusicError(@"invalid_arguments", @"Volume must be a finite number."));
      return;
    }
    result = [self resultByCancellingFade:result];
    self.volume = MIN(1, MAX(0, [value doubleValue]));
    self.player.volume = self.volume;
    [self.youTubePlayer setVolume:self.volume];
    [NSUserDefaults.standardUserDefaults setDouble:self.volume forKey:StintMusicVolumeKey];
    result([self state]);
    return;
  }
  if ([method isEqualToString:@"play"] || [method isEqualToString:@"select"]) {
    BOOL selecting = [method isEqualToString:@"select"];
    NSDictionary *args = [call.arguments isKindOfClass:NSDictionary.class] ? call.arguments : nil;
    NSString *identifier = selecting
        ? ([call.arguments isKindOfClass:NSString.class] ? call.arguments : nil)
        : ([args[@"id"] isKindOfClass:NSString.class] ? args[@"id"] : nil);
    if (!identifier) { result(StintMusicError(@"invalid_arguments", @"Choose a music track.")); return; }
    if (![self knownTrack:identifier]) { result(StintMusicError(@"unknown_track", @"This music track is no longer in your library.")); return; }
    if (selecting) {
      result = [self resultByCancellingFade:result];
      [self stopAllPlayers];
      self.selectedId = identifier;
      [NSUserDefaults.standardUserDefaults setObject:identifier forKey:StintMusicSelectionKey];
      result([self state]);
    } else {
      id fade = args[@"fade"];
      if (fade && (![fade isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)fade) != CFBooleanGetTypeID())) {
        result(StintMusicError(@"invalid_arguments", @"Fade must be a Boolean."));
        return;
      }
      [self playTrack:identifier data:args[@"data"] fade:[fade boolValue] result:result];
    }
    return;
  }
  result(FlutterMethodNotImplemented);
}

- (void)playTrack:(NSString *)identifier data:(id)data fade:(BOOL)fade result:(FlutterResult)result {
  NSDictionary *youTube = [self youTubeTrack:identifier];
  if (youTube) {
    if (data && data != NSNull.null) {
      result(StintMusicError(@"invalid_arguments", @"YouTube tracks play in the visible YouTube player."));
      return;
    }
    result = [self resultByCancellingFade:result];
    [self stopPlayer];
    self.selectedId = identifier;
    [NSUserDefaults.standardUserDefaults setObject:identifier forKey:StintMusicSelectionKey];
    [self prepareYouTubeTrack:youTube];
    [self.youTubePlayer play];
    result([self state]);
    return;
  }
  NSError *error = nil;
  AVAudioPlayer *candidate = nil;
  BOOL builtin = StintBuiltinTrack(identifier);
  NSData *bytes = nil;
  if (builtin) {
    if (![data isKindOfClass:FlutterStandardTypedData.class] || ((FlutterStandardTypedData *)data).type != FlutterStandardDataTypeUInt8) {
      result(StintMusicError(@"invalid_arguments", @"The built-in track's audio data is missing."));
      return;
    }
    bytes = ((FlutterStandardTypedData *)data).data;
    if (bytes.length == 0 || bytes.length > StintMusicMaximumBytes) {
      result(StintMusicError(@"invalid_audio", @"Choose nonempty audio no larger than 200 MB."));
      return;
    }
  } else if (data && data != NSNull.null) {
    result(StintMusicError(@"invalid_arguments", @"Imported tracks play from your saved music library."));
    return;
  }
  result = [self resultByCancellingFade:result];
  // The Flutter play button also resumes: keep the existing playback position.
  if (self.player && [self.selectedId isEqualToString:identifier]) {
    BOOL resuming = !self.player.isPlaying;
    if (resuming && fade) self.player.volume = 0;
    if (!self.player.isPlaying && ![self.player play]) {
      self.player.volume = self.volume;
      result(StintMusicError(@"playback_failed", @"The audio could not resume. Try choosing the track again."));
    } else {
      if (resuming && fade) [self fadePlayerToVolume:self.volume pauseOnCompletion:NO];
      result([self state]);
    }
    return;
  }
  if (builtin) {
    candidate = [[AVAudioPlayer alloc] initWithData:bytes error:&error];
  } else {
    NSURL *directory = [self musicDirectory:&error];
    NSURL *url = [directory URLByAppendingPathComponent:[self customTrack:identifier][@"filename"]];
    NSDictionary *values = [url resourceValuesForKeys:@[NSURLFileSizeKey, NSURLIsRegularFileKey] error:&error];
    if (!values || ![values[NSURLIsRegularFileKey] boolValue] || [values[NSURLFileSizeKey] unsignedLongLongValue] > StintMusicMaximumBytes) {
      result(StintMusicError(@"audio_unavailable", @"This imported audio file is unavailable or exceeds 200 MB. Import it again."));
      return;
    }
    candidate = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
  }
  if (!candidate || candidate.duration <= 0 || !isfinite(candidate.duration) || ![candidate prepareToPlay]) {
    result(StintMusicError(@"unsupported_audio", error.localizedDescription ?: @"This audio file cannot be played. Try MP3, M4A, WAV, or AIFF."));
    return;
  }
  candidate.numberOfLoops = -1;
  candidate.volume = fade ? 0 : self.volume;
  candidate.delegate = self;
  [self stopAllPlayers];
  self.player = candidate;
  self.selectedId = identifier;
  [NSUserDefaults.standardUserDefaults setObject:identifier forKey:StintMusicSelectionKey];
  if (![candidate play]) {
    [self stopPlayer];
    [self.channel invokeMethod:@"state" arguments:[self state]];
    result(StintMusicError(@"playback_failed", @"The audio output could not start. Try playing the track again."));
    return;
  }
  if (fade) [self fadePlayerToVolume:self.volume pauseOnCompletion:NO];
  result([self state]);
}

- (FlutterResult)cancelFade {
  [self.fadeTimer invalidate];
  self.fadeTimer = nil;
  self.player.volume = self.volume;
  FlutterResult pending = self.fadePauseResult;
  self.fadePauseResult = nil;
  return pending;
}

- (FlutterResult)resultByCancellingFade:(FlutterResult)result {
  FlutterResult superseded = [self cancelFade];
  if (!superseded) return result;
  // Resolve after the superseding command, so its caller sees the current state.
  return ^(id response) {
    superseded([self state]);
    result(response);
  };
}

- (void)fadePlayerToVolume:(float)volume pauseOnCompletion:(BOOL)pause {
  AVAudioPlayer *player = self.player;
  float initialVolume = player.volume;
  NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
  __weak StintMusic *weakSelf = self;
  NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 / 60.0 repeats:YES block:^(NSTimer *timer) {
    StintMusic *self = weakSelf;
    if (!self || self.fadeTimer != timer || self.player != player) {
      [timer invalidate];
      return;
    }
    double progress = MIN(1, MAX(0, (NSProcessInfo.processInfo.systemUptime - started) / StintMusicFadeDuration));
    player.volume = initialVolume + (volume - initialVolume) * progress;
    if (progress < 1) return;
    [timer invalidate];
    self.fadeTimer = nil;
    if (pause) [player pause];
    player.volume = self.volume;
    FlutterResult completion = self.fadePauseResult;
    self.fadePauseResult = nil;
    if (completion) completion([self state]);
  }];
  self.fadeTimer = timer;
  [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
}

- (void)stopPlayer {
  FlutterResult pending = [self cancelFade];
  self.player.delegate = nil;
  [self.player stop];
  self.player = nil;
  if (pending) pending([self state]);
}

- (void)importTracks:(FlutterResult)result {
  if (self.importing) { result(StintMusicError(@"import_busy", @"Finish the current music import first.")); return; }
  NSWindow *window = self.window;
  if (!window) { result(StintMusicError(@"closed", @"Open Stint to import audio.")); return; }
  self.importing = YES;
  [NSApp activateIgnoringOtherApps:YES];
  if (window.miniaturized) [window deminiaturize:nil];
  [window makeKeyAndOrderFront:nil];
  NSOpenPanel *panel = NSOpenPanel.openPanel;
  panel.title = @"Add your music";
  panel.message = @"Choose audio files up to 200 MB each. A copy stays in Stint.";
  panel.prompt = @"Add music";
  panel.allowedContentTypes = @[UTTypeAudio];
  panel.allowsMultipleSelection = YES;
  panel.canChooseFiles = YES;
  panel.canChooseDirectories = NO;
  __weak StintMusic *weakSelf = self;
  [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
    StintMusic *self = weakSelf;
    if (!self) { result(StintMusicError(@"closed", @"Stint closed before the import finished.")); return; }
    if (response != NSModalResponseOK) {
      self.importing = NO;
      result([self state]);
      return;
    }
    NSError *directoryError = nil;
    NSURL *directory = [self musicDirectory:&directoryError];
    if (!directory) {
      self.importing = NO;
      result(StintMusicError(@"import_failed", directoryError.localizedDescription ?: @"Your music folder could not be created."));
      return;
    }
    NSArray<NSURL *> *sources = panel.URLs;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSMutableArray *imported = [NSMutableArray array];
      NSMutableArray<NSURL *> *created = [NSMutableArray array];
      NSString *failure = nil;
      for (NSURL *source in sources) {
        BOOL scoped = [source startAccessingSecurityScopedResource];
        @try {
          NSError *error = nil;
          NSDictionary *values = [source resourceValuesForKeys:@[NSURLFileSizeKey, NSURLIsRegularFileKey] error:&error];
          if (!values || ![values[NSURLIsRegularFileKey] boolValue]) {
            failure = [NSString stringWithFormat:@"“%@” is not a readable audio file.", source.lastPathComponent];
            break;
          }
          unsigned long long size = [values[NSURLFileSizeKey] unsignedLongLongValue];
          if (size == 0 || size > StintMusicMaximumBytes) {
            failure = [NSString stringWithFormat:@"“%@” must contain audio and be no larger than 200 MB.", source.lastPathComponent];
            break;
          }
          NSString *identifier = [@"custom_" stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString];
          NSString *extension = source.pathExtension.lowercaseString;
          if (extension.length > 16 || [extension rangeOfCharacterFromSet:NSCharacterSet.alphanumericCharacterSet.invertedSet].location != NSNotFound) extension = @"audio";
          NSString *filename = extension.length ? [identifier stringByAppendingPathExtension:extension] : identifier;
          NSURL *destination = [directory URLByAppendingPathComponent:filename];
          [created addObject:destination];
          if (![NSFileManager.defaultManager copyItemAtURL:source toURL:destination error:&error]) {
            failure = [NSString stringWithFormat:@"“%@” could not be copied: %@", source.lastPathComponent, error.localizedDescription];
            break;
          }
          NSDictionary *copiedValues = [destination resourceValuesForKeys:@[NSURLFileSizeKey] error:&error];
          if (!copiedValues || [copiedValues[NSURLFileSizeKey] unsignedLongLongValue] > StintMusicMaximumBytes) {
            failure = [NSString stringWithFormat:@"“%@” could not be imported within the 200 MB limit.", source.lastPathComponent];
            break;
          }
          AVAudioPlayer *validation = [[AVAudioPlayer alloc] initWithContentsOfURL:destination error:&error];
          if (!validation || !isfinite(validation.duration) || validation.duration <= 0 || validation.numberOfChannels < 1) {
            failure = [NSString stringWithFormat:@"“%@” is not playable audio. Try MP3, M4A, WAV, or AIFF.", source.lastPathComponent];
            break;
          }
          NSString *title = source.lastPathComponent.stringByDeletingPathExtension;
          [imported addObject:@{@"id": identifier, @"title": title.length ? title : @"Imported audio", @"filename": filename}];
        } @finally {
          if (scoped) [source stopAccessingSecurityScopedResource];
        }
      }
      // Import a selection atomically; a bad file never leaves a partial library.
      if (failure) for (NSURL *url in created) [NSFileManager.defaultManager removeItemAtURL:url error:NULL];
      dispatch_async(dispatch_get_main_queue(), ^{
        self.importing = NO;
        if (failure) { result(StintMusicError(@"import_failed", failure)); return; }
        [self.tracks addObjectsFromArray:imported];
        [NSUserDefaults.standardUserDefaults setObject:self.tracks forKey:StintMusicTracksKey];
        result([self state]);
      });
    });
  }];
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (player != self.player) return;
    [self stopPlayer];
    [self.channel invokeMethod:@"error" arguments:error.localizedDescription ?: @"Playback stopped because this audio could not be decoded."];
    [self.channel invokeMethod:@"state" arguments:[self state]];
  });
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (player != self.player) return;
    [self stopPlayer];
    if (!flag) [self.channel invokeMethod:@"error" arguments:@"Playback stopped unexpectedly. Try playing the track again."];
    [self.channel invokeMethod:@"state" arguments:[self state]];
  });
}

- (void)dealloc {
  [_fadeTimer invalidate];
  if (_fadePauseResult) _fadePauseResult(StintMusicError(@"closed", @"Stint closed before the music fade finished."));
  _player.delegate = nil;
  [_player stop];
  _suppressYouTubeEvents = YES;
  [_youTubePlayer stop];
  [_channel setMethodCallHandler:nil];
}

@end
