#import "StintYouTubePlayer.h"
#import <WebKit/WebKit.h>
#import <math.h>

static NSString *const StintYouTubeMessageName = @"stintYouTube";

static BOOL StintValidYouTubeId(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length != 11) return NO;
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
      @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"];
  return [value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

// Also safe inside an HTML script element, including titles containing </script>.
static NSString *StintYouTubeJSON(id object) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
  NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
  json = [json stringByReplacingOccurrencesOfString:@"<" withString:@"\\u003c"];
  json = [json stringByReplacingOccurrencesOfString:@"\u2028" withString:@"\\u2028"];
  return [json stringByReplacingOccurrencesOfString:@"\u2029" withString:@"\\u2029"];
}

@interface StintYouTubeMessageProxy : NSObject <WKScriptMessageHandler>
@property(nonatomic, weak) id<WKScriptMessageHandler> target;
@end
@implementation StintYouTubeMessageProxy
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
  [self.target userContentController:controller didReceiveScriptMessage:message];
}
@end

// WKWebView's suspension API is paired. Repeated YES calls accumulate even
// though its Objective-C name looks like a plain Boolean setter.
@interface StintYouTubeSuspension : NSObject
@property(nonatomic) BOOL requestedSuspended;
@property(nonatomic, strong) NSMutableArray<void (^)(void)> *pendingCompletions;
@end
@implementation StintYouTubeSuspension
@end

@interface StintYouTubePlayer () <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler>
@property(nonatomic, readwrite) BOOL playing;
@property(nonatomic, readwrite) BOOL starting;
@property(nonatomic, copy, readwrite, nullable) NSString *videoId;
@property(nonatomic, copy) void (^stateChanged)(BOOL, BOOL, NSString *_Nullable);
@property(nonatomic, strong) NSView *contentView;
@property(nonatomic) BOOL presentationVisible;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) WKNavigation *pageNavigation;
@property(nonatomic, copy) NSString *pageToken;
@property(nonatomic, copy) NSString *origin;
@property(nonatomic, strong) NSTimer *loadTimer;
@property(nonatomic, strong) NSTimer *playTimer;
@property(nonatomic, strong) id inputMonitor;
@property(nonatomic) NSUInteger intentVersion;
@property(nonatomic) BOOL wantsPlayback;
@property(nonatomic) BOOL allowsControlPlayback;
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL failed;
@property(nonatomic) double volume;
@property(nonatomic) BOOL waitingForVisibility;
@property(nonatomic) NSTimeInterval visibilityDeadline;
@property(nonatomic, strong) NSMapTable<WKWebView *, StintYouTubeSuspension *> *mediaSuspensions;
@end

@implementation StintYouTubePlayer

- (instancetype)initWithStateChanged:(void (^)(BOOL, BOOL, NSString *_Nullable))stateChanged {
  self = [super init];
  if (!self) return nil;
  _stateChanged = [stateChanged copy];
  _volume = 0.35;
  NSString *bundleId = NSBundle.mainBundle.bundleIdentifier.lowercaseString;
  NSCharacterSet *hostCharacters = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789.-"];
  if (!bundleId.length || [bundleId rangeOfCharacterFromSet:hostCharacters.invertedSet].location != NSNotFound) {
    bundleId = @"io.github.albert2704.stint";
  }
  _origin = [@"https://" stringByAppendingString:bundleId];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationWillHide:)
      name:NSApplicationWillHideNotification object:NSApp];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowDidChangeOcclusionState:)
      name:NSWindowDidChangeOcclusionStateNotification object:nil];
  return self;
}

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
  if (_inputMonitor) [NSEvent removeMonitor:_inputMonitor];
  [_loadTimer invalidate];
  [_playTimer invalidate];
  [_webView.configuration.userContentController removeScriptMessageHandlerForName:StintYouTubeMessageName];
  [_webView pauseAllMediaPlaybackWithCompletionHandler:nil];
  [_webView stopLoading];
}

- (NSView *)view {
  [self createViewIfNeeded];
  return self.contentView;
}

- (void)createViewIfNeeded {
  if (self.contentView) return;
  self.contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 308, 238)];
  self.contentView.wantsLayer = YES;
  self.contentView.layer.cornerRadius = 10;
  self.contentView.layer.masksToBounds = YES;
  self.contentView.accessibilityLabel = @"YouTube player";

  self.statusLabel = [NSTextField labelWithString:@"Choose a video, then press Play."];
  self.statusLabel.font = [NSFont systemFontOfSize:11];
  self.statusLabel.textColor = NSColor.secondaryLabelColor;
  self.statusLabel.maximumNumberOfLines = 2;
  self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
  [self.contentView addSubview:self.statusLabel];
  [NSLayoutConstraint activateConstraints:@[
    [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
    [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
    [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
    [self.statusLabel.heightAnchor constraintEqualToConstant:30],
  ]];

  // This observes ordinary input without overlaying or replacing YouTube controls.
  // A new interaction lets the user resume using the embedded controls after a pause.
  __weak StintYouTubePlayer *weakSelf = self;
  self.inputMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskKeyDown
      handler:^NSEvent *(NSEvent *event) {
    StintYouTubePlayer *self = weakSelf;
    if (!self || event.window != self.contentView.window || ![self isPlaybackVisible] || !self.webView) return event;
    BOOL playerInput = NO;
    if (event.type == NSEventTypeLeftMouseDown) {
      NSPoint point = [self.webView convertPoint:event.locationInWindow fromView:nil];
      playerInput = NSPointInRect(point, self.webView.bounds);
    } else {
      NSResponder *responder = self.contentView.window.firstResponder;
      playerInput = [responder isKindOfClass:NSView.class] &&
          [(NSView *)responder isDescendantOf:self.webView] &&
          (event.keyCode == 49 || event.keyCode == 36 || [event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"k"]);
    }
    if (playerInput) {
      self.intentVersion++;
      self.wantsPlayback = NO;
      self.allowsControlPlayback = YES;
      self.waitingForVisibility = NO;
      [self resumeVisibleMediaForVersion:self.intentVersion token:self.pageToken action:@"controls"];
      if (self.starting) [self startPlaybackTimeout];
    }
    return event;
  }];
}

- (BOOL)isPlaybackVisible {
  NSWindow *window = self.contentView.window;
  return self.presentationVisible && window.isVisible && !window.isMiniaturized &&
      !self.contentView.hiddenOrHasHiddenAncestor && !NSIsEmptyRect(self.contentView.visibleRect) &&
      (window.occlusionState & NSWindowOcclusionStateVisible) != 0;
}

- (void)publishPlaying:(BOOL)playing starting:(BOOL)starting error:(NSString *)error {
  self.playing = playing;
  self.starting = starting;
  if (error) self.statusLabel.stringValue = error;
  else if (starting) self.statusLabel.stringValue = @"Starting YouTube…";
  else if (playing) self.statusLabel.stringValue = @"Playing · Keep this panel open to continue.";
  else self.statusLabel.stringValue = @"Paused · Press Play here or in Stint to resume.";
  self.statusLabel.toolTip = self.statusLabel.stringValue;
  if (self.stateChanged) self.stateChanged(playing, starting, error);
}

- (void)setVideoId:(NSString *)videoId title:(NSString *)title volume:(double)volume {
  if (!StintValidYouTubeId(videoId)) {
    [self pause];
    [self publishPlaying:NO starting:NO error:@"The YouTube video ID is invalid."];
    return;
  }
  [self createViewIfNeeded];
  self.contentView.accessibilityLabel = title.length ? [title stringByAppendingString:@" · YouTube"] : @"YouTube player";
  [self setVolume:volume];
  if ([self.videoId isEqualToString:videoId]) return;
  [self discardPage];
  self.videoId = videoId;
  [self loadSelectedVideo];
  [self publishPlaying:NO starting:NO error:nil];
}

- (void)discardPage {
  self.intentVersion++;
  self.pageToken = nil;
  self.ready = NO;
  self.wantsPlayback = NO;
  self.allowsControlPlayback = NO;
  self.failed = NO;
  self.waitingForVisibility = NO;
  [self.loadTimer invalidate];
  self.loadTimer = nil;
  [self.playTimer invalidate];
  self.playTimer = nil;
  [self setMediaSuspended:YES webView:self.webView completion:nil];
  [self.webView.configuration.userContentController removeScriptMessageHandlerForName:StintYouTubeMessageName];
  self.webView.navigationDelegate = nil;
  self.webView.UIDelegate = nil;
  [self.webView stopLoading];
  [self.webView loadHTMLString:@"<!doctype html><html></html>" baseURL:nil];
  [self.webView removeFromSuperview];
  self.webView = nil;
  self.pageNavigation = nil;
}

- (void)loadSelectedVideo {
  if (!self.videoId) return;
  [self createViewIfNeeded];
  self.pageToken = NSUUID.UUID.UUIDString;
  self.ready = NO;
  self.failed = NO;
  self.allowsControlPlayback = NO;
  WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
  configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
  if (@available(macOS 12.3, *)) configuration.preferences.elementFullscreenEnabled = YES;
  StintYouTubeMessageProxy *proxy = [[StintYouTubeMessageProxy alloc] init];
  proxy.target = self;
  [configuration.userContentController addScriptMessageHandler:proxy name:StintYouTubeMessageName];
  self.webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
  self.webView.navigationDelegate = self;
  self.webView.UIDelegate = self;
  self.webView.translatesAutoresizingMaskIntoConstraints = NO;
  [self.contentView addSubview:self.webView];
  [NSLayoutConstraint activateConstraints:@[
    [self.webView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
    [self.webView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
    [self.webView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
    [self.webView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-38],
  ]];
  if (![self isPlaybackVisible]) [self setMediaSuspended:YES webView:self.webView completion:nil];

  NSDictionary *settings = @{@"token": self.pageToken, @"videoId": self.videoId,
      @"origin": self.origin, @"version": @(self.intentVersion), @"volume": @(self.volume * 100)};
  NSString *html = [NSString stringWithFormat:
      @"<!doctype html><html><head><meta charset='utf-8'>"
       "<meta name='referrer' content='strict-origin-when-cross-origin'>"
       "<meta name='viewport' content='width=device-width, initial-scale=1'>"
       "<style>html,body,#player{margin:0;width:100%%;height:100%%;overflow:hidden;background:#111}"
       "iframe{display:block;border:0}</style></head><body><div id='player'></div><script>"
       "'use strict';const config=%@;let player,ready=false,version=config.version;"
       "let wants=false,controls=false,visible=false,awaitingPlay=false,volume=config.volume;"
       "function emit(type,data){window.webkit.messageHandlers.stintYouTube.postMessage("
       "{token:config.token,version:version,type:type,data:data});}"
       "window.stintYouTubeCommand=function(c){"
       "if(c.token!==config.token||c.version<version)return;version=c.version;volume=c.volume;visible=c.visible;"
       "if(c.action==='play'){wants=visible;controls=visible;awaitingPlay=visible;}"
       "else if(c.action==='pause'){wants=false;controls=false;awaitingPlay=false;}"
       "else if(c.action==='controls'){wants=false;controls=visible;awaitingPlay=false;}"
       "if(!ready)return;player.setVolume(volume);"
       "if(!visible||c.action==='pause')player.pauseVideo();"
       "else if(c.action==='play'&&wants)player.playVideo();};"
       "window.onYouTubeIframeAPIReady=function(){player=new YT.Player('player',{width:'100%%',height:'100%%',videoId:config.videoId,"
       "playerVars:{autoplay:0,controls:1,playsinline:1,origin:config.origin},events:{"
       "onReady:function(){ready=true;player.setVolume(volume);emit('ready',null);},"
       "onStateChange:function(e){if((e.data===1||e.data===3)&&(!visible||(!wants&&!controls))){player.pauseVideo();return;}"
       "if((e.data===0||e.data===2)&&wants&&awaitingPlay)return;"
       "if(e.data===1)awaitingPlay=false;emit('state',e.data);},onError:function(e){emit('error',e.data);},"
       "onAutoplayBlocked:function(){emit('blocked',null);}}});};"
       "const script=document.createElement('script');script.src='https://www.youtube.com/iframe_api';"
       "script.onerror=function(){emit('loadError',null);};document.head.appendChild(script);"
       "</script></body></html>", StintYouTubeJSON(settings)];
  self.pageNavigation = [self.webView loadHTMLString:html baseURL:[NSURL URLWithString:self.origin]];
  NSString *token = self.pageToken;
  __weak StintYouTubePlayer *weakSelf = self;
  self.loadTimer = [NSTimer scheduledTimerWithTimeInterval:25 repeats:NO block:^(NSTimer *timer) {
    (void)timer;
    StintYouTubePlayer *self = weakSelf;
    if (self && [self.pageToken isEqualToString:token] && !self.ready) {
      [self fail:@"YouTube did not load. Check your connection and press Play to retry."];
    }
  }];
}

- (void)show {
  if (!self.videoId) return;
  [self createViewIfNeeded];
  if (![self isPlaybackVisible]) {
    self.waitingForVisibility = YES;
    self.visibilityDeadline = NSProcessInfo.processInfo.systemUptime + 1.5;
  }
  if (!self.showPlayer) {
    [self publishPlaying:NO starting:NO error:@"The YouTube panel is unavailable. Reopen Stint and try again."];
    return;
  }
  self.showPlayer();
  // Restore usable standard/AX controls after making sure the media is paused.
  // Opening the panel never issues playVideo.
  if (!self.wantsPlayback && !self.playing && !self.starting) {
    [self waitForVisibilityForVersion:self.intentVersion token:self.pageToken play:NO];
  }
}

- (void)play {
  if (!self.videoId) {
    [self publishPlaying:NO starting:NO error:@"Choose a YouTube video first."];
    return;
  }
  if (!self.showPlayer) {
    [self pause];
    [self publishPlaying:NO starting:NO error:@"The YouTube panel is unavailable. Reopen Stint and try again."];
    return;
  }
  if (self.failed || !self.webView) {
    [self discardPage];
    [self loadSelectedVideo];
  }
  [self show];
  self.intentVersion++;
  self.wantsPlayback = YES;
  self.allowsControlPlayback = YES;
  self.waitingForVisibility = YES;
  self.visibilityDeadline = NSProcessInfo.processInfo.systemUptime + 1.5;
  [self publishPlaying:NO starting:YES error:nil];
  [self startPlaybackTimeout];
  [self waitForVisibilityForVersion:self.intentVersion token:self.pageToken play:YES];
}

- (BOOL)matchesVersion:(NSUInteger)version token:(NSString *)token webView:(WKWebView *)webView {
  return webView && self.webView == webView && self.intentVersion == version &&
      [self.pageToken isEqualToString:token];
}

- (void)setMediaSuspended:(BOOL)suspended webView:(WKWebView *)webView completion:(void (^)(void))completion {
  if (!webView) { if (completion) completion(); return; }
  if (!self.mediaSuspensions) self.mediaSuspensions = [NSMapTable weakToStrongObjectsMapTable];
  StintYouTubeSuspension *state = [self.mediaSuspensions objectForKey:webView];
  if (!state) {
    state = [[StintYouTubeSuspension alloc] init];
    [self.mediaSuspensions setObject:state forKey:webView];
  }
  if (state.requestedSuspended == suspended) {
    // A second caller must await the current transition, without sending a
    // second suspend/resume or running a play command before WebKit is ready.
    if (state.pendingCompletions) {
      if (completion) [state.pendingCompletions addObject:[completion copy]];
    } else if (completion) completion();
    return;
  }
  state.requestedSuspended = suspended;
  NSMutableArray<void (^)(void)> *callbacks = [NSMutableArray array];
  if (completion) [callbacks addObject:[completion copy]];
  state.pendingCompletions = callbacks;
  [webView setAllMediaPlaybackSuspended:suspended completionHandler:^{
    // An opposite transition may already be pending. Its completion queue is
    // independent; stale intent checks remain the caller's responsibility.
    if (state.pendingCompletions == callbacks) state.pendingCompletions = nil;
    NSArray<void (^)(void)> *finished = [callbacks copy];
    [callbacks removeAllObjects];
    for (void (^callback)(void) in finished) callback();
  }];
}

- (void)waitForVisibilityForVersion:(NSUInteger)version token:(NSString *)token play:(BOOL)play {
  if (self.intentVersion != version || ![self.pageToken isEqualToString:token] ||
      (play && !self.wantsPlayback)) return;
  if ([self isPlaybackVisible]) {
    self.waitingForVisibility = NO;
    if (play) [self resumeVisibleMediaForVersion:version token:token action:@"play"];
    else [self settlePausedMediaForVersion:version token:token];
    return;
  }
  if (NSProcessInfo.processInfo.systemUptime >= self.visibilityDeadline) {
    self.waitingForVisibility = NO;
    if (play) [self pause];
    return;
  }
  __weak StintYouTubePlayer *weakSelf = self;
  // Cocoa may report an ordered-front panel as occluded for several run-loop
  // turns. Keep the explicit intent pending, without starting hidden media.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [weakSelf waitForVisibilityForVersion:version token:token play:play];
  });
}

- (void)resumeVisibleMediaForVersion:(NSUInteger)version token:(NSString *)token action:(NSString *)action {
  WKWebView *webView = self.webView;
  if (![self matchesVersion:version token:token webView:webView] || ![self isPlaybackVisible]) return;
  __weak StintYouTubePlayer *weakSelf = self;
  __weak WKWebView *weakWebView = webView;
  [self setMediaSuspended:NO webView:webView completion:^{
    StintYouTubePlayer *self = weakSelf;
    if (!self || ![self matchesVersion:version token:token webView:weakWebView]) return;
    if (![self isPlaybackVisible]) { [self pause]; return; }
    if ([action isEqualToString:@"play"] && !self.wantsPlayback) return;
    self.allowsControlPlayback = YES;
    if (self.ready) [self sendCommand:action];
  }];
}

- (void)settlePausedMediaForVersion:(NSUInteger)version token:(NSString *)token {
  WKWebView *webView = self.webView;
  if (![self matchesVersion:version token:token webView:webView]) return;
  __weak StintYouTubePlayer *weakSelf = self;
  __weak WKWebView *weakWebView = webView;
  // First quiesce queued playback, then remove the suspension only for a
  // visible, still-paused player. This supports accessibility Play actions,
  // which do not pass through an NSEvent monitor.
  [self setMediaSuspended:YES webView:webView completion:^{
    StintYouTubePlayer *self = weakSelf;
    WKWebView *pausedView = weakWebView;
    if (!self || ![self matchesVersion:version token:token webView:pausedView] || self.wantsPlayback) return;
    [pausedView pauseAllMediaPlaybackWithCompletionHandler:^{
      StintYouTubePlayer *self = weakSelf;
      if (!self || ![self matchesVersion:version token:token webView:weakWebView] || self.wantsPlayback) return;
      if ([self isPlaybackVisible]) [self resumeVisibleMediaForVersion:version token:token action:@"controls"];
    }];
  }];
}

- (void)pause {
  self.intentVersion++;
  self.wantsPlayback = NO;
  self.allowsControlPlayback = NO;
  self.waitingForVisibility = NO;
  [self.playTimer invalidate];
  self.playTimer = nil;
  [self sendCommand:@"pause"];
  [self settlePausedMediaForVersion:self.intentVersion token:self.pageToken];
  [self publishPlaying:NO starting:NO error:nil];
}

- (void)stop {
  [self discardPage];
  self.videoId = nil;
  [self publishPlaying:NO starting:NO error:nil];
}

- (void)setVolume:(double)volume {
  if (!isfinite(volume)) return;
  _volume = MIN(1, MAX(0, volume));
  [self sendCommand:@"volume"];
}

- (void)sendCommand:(NSString *)action {
  if (!self.webView || !self.pageToken) return;
  NSDictionary *command = @{@"token": self.pageToken, @"version": @(self.intentVersion),
      @"action": action, @"volume": @(self.volume * 100), @"visible": @([self isPlaybackVisible])};
  NSString *script = [NSString stringWithFormat:@"window.stintYouTubeCommand && window.stintYouTubeCommand(%@);", StintYouTubeJSON(command)];
  NSString *token = self.pageToken;
  NSUInteger version = self.intentVersion;
  __weak StintYouTubePlayer *weakSelf = self;
  [self.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
    (void)result;
    StintYouTubePlayer *self = weakSelf;
    if (error && self && self.ready && self.intentVersion == version && [self.pageToken isEqualToString:token] && self.wantsPlayback) {
      [self fail:@"The YouTube player stopped responding. Press Play to reload it."];
    }
  }];
}

- (void)startPlaybackTimeout {
  [self.playTimer invalidate];
  NSString *token = self.pageToken;
  NSUInteger version = self.intentVersion;
  __weak StintYouTubePlayer *weakSelf = self;
  self.playTimer = [NSTimer scheduledTimerWithTimeInterval:25 repeats:NO block:^(NSTimer *timer) {
    (void)timer;
    StintYouTubePlayer *self = weakSelf;
    if (self && self.starting && self.intentVersion == version && [self.pageToken isEqualToString:token]) {
      [self fail:@"YouTube could not start. Check your connection, or press Play in the player."];
    }
  }];
}

- (void)fail:(NSString *)message {
  self.failed = YES;
  [self.loadTimer invalidate];
  self.loadTimer = nil;
  [self pause];
  [self publishPlaying:NO starting:NO error:message];
}

- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
  if (message.webView != self.webView || !message.frameInfo.isMainFrame ||
      ![message.body isKindOfClass:NSDictionary.class]) return;
  NSDictionary *body = message.body;
  if (![body[@"token"] isKindOfClass:NSString.class] || ![self.pageToken isEqualToString:body[@"token"]] ||
      ![body[@"type"] isKindOfClass:NSString.class]) return;
  NSString *type = body[@"type"];
  // Ready belongs to the page, while playback/error events also belong to an intent.
  if ([type isEqualToString:@"ready"]) {
    self.ready = YES;
    [self.loadTimer invalidate];
    self.loadTimer = nil;
    if (self.wantsPlayback && [self isPlaybackVisible]) {
      [self resumeVisibleMediaForVersion:self.intentVersion token:self.pageToken action:@"play"];
    } else if (self.wantsPlayback) {
      if (self.waitingForVisibility) {
        [self waitForVisibilityForVersion:self.intentVersion token:self.pageToken play:YES];
      } else [self pause];
    } else if (self.allowsControlPlayback && [self isPlaybackVisible]) {
      [self resumeVisibleMediaForVersion:self.intentVersion token:self.pageToken action:@"controls"];
    } else {
      [self sendCommand:@"pause"];
      [self settlePausedMediaForVersion:self.intentVersion token:self.pageToken];
    }
    return;
  }
  BOOL pageLoadError = !self.ready && ([type isEqualToString:@"error"] || [type isEqualToString:@"loadError"]);
  if (!pageLoadError && (![body[@"version"] isKindOfClass:NSNumber.class] ||
      [body[@"version"] unsignedIntegerValue] != self.intentVersion)) return;
  if ([type isEqualToString:@"error"]) {
    NSInteger code = [body[@"data"] isKindOfClass:NSNumber.class] ? [body[@"data"] integerValue] : 0;
    NSString *error = @"YouTube could not play this video. Try another video.";
    if (code == 100) error = @"This video is unavailable or private. Choose another video.";
    else if (code == 101 || code == 150) error = @"The owner disabled embedded playback. Open this video on YouTube.";
    else if (code == 153) error = @"YouTube could not verify this app’s player identity (153). Open the video on YouTube.";
    else if (code == 2) error = @"YouTube rejected this video ID.";
    else if (code == 5) error = @"This video cannot play in the embedded player. Open it on YouTube.";
    [self fail:error];
  } else if ([type isEqualToString:@"blocked"]) {
    if (self.wantsPlayback || self.starting || self.allowsControlPlayback) {
      [self fail:@"Playback was blocked. Click Play directly in the YouTube player."];
    }
  } else if ([type isEqualToString:@"loadError"]) {
    [self fail:@"Could not connect to YouTube. Check your connection and press Play to retry."];
  } else if ([type isEqualToString:@"state"] && [body[@"data"] isKindOfClass:NSNumber.class]) {
    NSInteger state = [body[@"data"] integerValue];
    if (state == 1 || state == 3) {
      if (![self isPlaybackVisible] || (!self.wantsPlayback && !self.allowsControlPlayback)) {
        [self pause];
        return;
      }
      self.failed = NO;
      if (state == 1) {
        [self.playTimer invalidate];
        self.playTimer = nil;
        [self publishPlaying:YES starting:NO error:nil];
      } else {
        BOOL wasStarting = self.starting;
        [self publishPlaying:NO starting:YES error:nil];
        if (!wasStarting) [self startPlaybackTimeout];
      }
    } else if (state == 0 || state == 2) {
      if (self.playing || self.starting || self.wantsPlayback) [self pause];
    }
  }
}

- (void)presentationVisibilityChanged:(BOOL)visible {
  self.presentationVisible = visible;
  if (!visible) {
    // Cancels a pending iframe start as well as active playback.
    [self pause];
  } else {
    [self restorePausedControlsIfVisible];
  }
}

- (void)applicationWillHide:(NSNotification *)notification { [self pause]; }
- (void)restorePausedControlsIfVisible {
  if ([self isPlaybackVisible] && !self.waitingForVisibility &&
      !self.playing && !self.starting && !self.wantsPlayback) {
    [self settlePausedMediaForVersion:self.intentVersion token:self.pageToken];
  }
}
- (void)windowDidChangeOcclusionState:(NSNotification *)notification {
  if (notification.object != self.contentView.window) return;
  if (!self.waitingForVisibility && ![self isPlaybackVisible] &&
      (self.playing || self.starting || self.allowsControlPlayback)) [self pause];
  else [self restorePausedControlsIfVisible];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  NSURL *url = action.request.URL;
  BOOL userLink = action.navigationType == WKNavigationTypeLinkActivated;
  BOOL externalTarget = !action.targetFrame || action.targetFrame.isMainFrame;
  if (userLink && externalTarget && [url.scheme.lowercaseString isEqualToString:@"https"] && url.host.length) {
    [NSWorkspace.sharedWorkspace openURL:url];
    decisionHandler(WKNavigationActionPolicyCancel);
    return;
  }
  if (action.targetFrame && !action.targetFrame.isMainFrame) {
    // The official player owns its own cross-origin frames and playback resources.
    decisionHandler([url.scheme.lowercaseString isEqualToString:@"https"] || [url.absoluteString isEqualToString:@"about:blank"]
        ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
    return;
  }
  // Only allow the loadHTMLString document to occupy the main frame.
  BOOL localDocument = !self.ready && !userLink &&
      ([url.absoluteString isEqualToString:self.origin] ||
       [url.absoluteString isEqualToString:[self.origin stringByAppendingString:@"/"]] ||
       [url.absoluteString isEqualToString:@"about:blank"]);
  decisionHandler(localDocument ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
  // Link-activated HTTPS targets are handled by the navigation delegate; no popups.
  return nil;
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
  if (webView == self.webView && navigation == self.pageNavigation && error.code != NSURLErrorCancelled) {
    [self fail:@"YouTube could not load. Check your connection and press Play to retry."];
  }
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
  [self webView:webView didFailProvisionalNavigation:navigation withError:error];
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
  if (webView == self.webView) [self fail:@"The YouTube player closed unexpectedly. Press Play to reload it."];
}

@end
