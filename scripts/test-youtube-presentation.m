// Exercise production presentation/intent logic with in-memory host and WebKit
// substitutes. No AppKit windows, web content, network, audio, or preferences.
#import <Cocoa/Cocoa.h>
static NSApplication *DeskTestApplication;
#define NSApp DeskTestApplication
#pragma clang diagnostic push
// Included .m files are implementation units, not nullability-complete headers.
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "../macos/Runner/DeskYouTubePlayer.m"
#pragma clang diagnostic pop
#undef NSApp

static NSUInteger checks;
static void Check(BOOL condition, NSString *message) {
  checks++;
  if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}

@interface DeskHostWindowProbe : NSObject
@property(nonatomic, getter=isVisible) BOOL visible;
@property(nonatomic, getter=isMiniaturized) BOOL miniaturized;
@property(nonatomic) NSWindowOcclusionState occlusionState;
@end
@implementation DeskHostWindowProbe
@end

@interface DeskHostViewProbe : NSObject
@property(nonatomic, strong) DeskHostWindowProbe *window;
@property(nonatomic, getter=isHiddenOrHasHiddenAncestor) BOOL hiddenOrHasHiddenAncestor;
@property(nonatomic) NSRect visibleRect;
@property(nonatomic, copy) NSString *accessibilityLabel;
@end
@implementation DeskHostViewProbe
@end

@interface DeskStatusProbe : NSObject
@property(nonatomic, copy) NSString *stringValue;
@property(nonatomic, copy) NSString *toolTip;
@end
@implementation DeskStatusProbe
@end

@interface DeskFrameProbe : NSObject
- (BOOL)isMainFrame;
@end
@implementation DeskFrameProbe
- (BOOL)isMainFrame { return YES; }
@end

@interface DeskScriptMessageProbe : NSObject
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) DeskFrameProbe *frameInfo;
@property(nonatomic, copy) NSDictionary *body;
@end
@implementation DeskScriptMessageProbe
@end

@interface DeskWebViewProbe : NSObject
@property(nonatomic, weak) id navigationDelegate;
@property(nonatomic, weak) id UIDelegate;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *commands;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *suspensions;
@property(nonatomic, copy) void (^pendingResume)(void);
@property(nonatomic) BOOL deferResume;
@property(nonatomic) NSUInteger pauses;
@property(nonatomic) NSUInteger removals;
@property(nonatomic) NSUInteger blankLoads;
@property(nonatomic) NSInteger suspensionDepth;
@property(nonatomic) BOOL deferSuspend;
@property(nonatomic, copy) void (^pendingSuspend)(void);
- (id)configuration;
- (void)setAllMediaPlaybackSuspended:(BOOL)suspended completionHandler:(void (^)(void))completion;
- (void)pauseAllMediaPlaybackWithCompletionHandler:(void (^)(void))completion;
- (void)evaluateJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))completion;
- (void)stopLoading;
- (id)loadHTMLString:(NSString *)html baseURL:(NSURL *)baseURL;
- (void)removeFromSuperview;
@end
@implementation DeskWebViewProbe
- (instancetype)init {
  self = [super init];
  if (self) { _commands = [NSMutableArray array]; _suspensions = [NSMutableArray array]; }
  return self;
}
- (id)configuration { return nil; }
- (void)setAllMediaPlaybackSuspended:(BOOL)suspended completionHandler:(void (^)(void))completion {
  [self.suspensions addObject:@(suspended)];
  self.suspensionDepth += suspended ? 1 : -1;
  Check(self.suspensionDepth >= 0, @"A resume always matches an earlier suspension");
  if (suspended && self.deferSuspend) self.pendingSuspend = completion;
  else if (!suspended && self.deferResume) self.pendingResume = completion;
  else if (completion) completion();
}
- (void)pauseAllMediaPlaybackWithCompletionHandler:(void (^)(void))completion {
  self.pauses++;
  if (completion) completion();
}
- (void)evaluateJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))completion {
  NSRange first = [script rangeOfString:@"{"];
  NSRange last = [script rangeOfString:@"}" options:NSBackwardsSearch];
  Check(first.location != NSNotFound && last.location != NSNotFound, @"Commands contain JSON");
  NSString *json = [script substringWithRange:NSMakeRange(first.location, NSMaxRange(last) - first.location)];
  NSDictionary *command = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]
      options:0 error:nil];
  Check([command isKindOfClass:NSDictionary.class], @"Commands have valid JSON");
  [self.commands addObject:command];
  if (completion) completion(nil, nil);
}
- (void)stopLoading {}
- (id)loadHTMLString:(NSString *)html baseURL:(NSURL *)baseURL {
  (void)baseURL;
  Check([html isEqualToString:@"<!doctype html><html></html>"], @"Discard loads only an empty document");
  self.blankLoads++;
  return nil;
}
- (void)removeFromSuperview { self.removals++; }
@end

// Replace only construction of platform views/pages. Show, play, pause,
// visibility checks, command generation, and stale-intent guards stay real.
@interface DeskPlayerProbe : DeskYouTubePlayer
@property(nonatomic) NSUInteger pageLoads;
@end
@implementation DeskPlayerProbe
- (void)createViewIfNeeded {
  if (self.contentView) return;
  DeskHostViewProbe *host = [[DeskHostViewProbe alloc] init];
  host.window = [[DeskHostWindowProbe alloc] init];
  host.window.occlusionState = NSWindowOcclusionStateVisible;
  host.visibleRect = NSMakeRect(0, 0, 308, 238);
  self.contentView = (NSView *)host;
  self.statusLabel = (NSTextField *)[[DeskStatusProbe alloc] init];
}
- (void)loadSelectedVideo {
  Check(self.videoId.length == 11, @"A selected video exists before page construction");
  [self createViewIfNeeded];
  self.pageLoads++;
  self.pageToken = NSUUID.UUID.UUIDString;
  self.ready = YES;
  self.failed = NO;
  self.webView = (WKWebView *)[[DeskWebViewProbe alloc] init];
  if (![self isPlaybackVisible]) [self setMediaSuspended:YES webView:self.webView completion:nil];
}
@end

// Inject the view/page probe at DeskMusic's single player-construction boundary.
#define DeskYouTubePlayer DeskPlayerProbe
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "../macos/Runner/DeskMusic.m"
#pragma clang diagnostic pop
#undef DeskYouTubePlayer

static DeskWebViewProbe *Web(DeskPlayerProbe *player) { return (DeskWebViewProbe *)player.webView; }
static void SetVisible(DeskPlayerProbe *player, BOOL visible) {
  ((DeskHostViewProbe *)player.contentView).window.visible = visible;
  [player presentationVisibilityChanged:visible];
}
static NSUInteger Plays(DeskWebViewProbe *web) {
  NSUInteger count = 0;
  for (NSDictionary *command in web.commands) if ([command[@"action"] isEqualToString:@"play"]) count++;
  return count;
}

int main(void) {
  @autoreleasepool {
    __block NSUInteger shown = 0;
    DeskPlayerProbe *player = [[DeskPlayerProbe alloc] initWithStateChanged:^(BOOL playing, BOOL starting, NSString *error) {
      (void)playing; (void)starting; (void)error;
    }];
    Check(!player.contentView && !player.webView, @"Construction creates no presentation or web page");
    [player show];
    Check(shown == 0 && !player.starting, @"Show without selection stays idle");
    NSView *view = player.view;
    Check(view && player.view == view && player.pageLoads == 0, @"Embedded view is stable and lazy");
    __weak DeskPlayerProbe *weakPlayer = player;
    player.showPlayer = ^{ shown++; SetVisible(weakPlayer, YES); };
    [player setVideoId:@"M7lc1UVf-VE" title:@"Focus stream" volume:0.3];
    DeskWebViewProbe *firstWeb = Web(player);
    Check(player.pageLoads == 1 && !player.playing && !player.starting, @"Selecting creates a paused page");
    Check(firstWeb.suspensions.lastObject.boolValue, @"Hidden selection suspends media");
    Check(firstWeb.suspensionDepth == 1, @"Hidden selection owns one suspension");
    DeskScriptMessageProbe *ready = [[DeskScriptMessageProbe alloc] init];
    ready.webView = player.webView;
    ready.frameInfo = [[DeskFrameProbe alloc] init];
    ready.body = @{@"token": player.pageToken, @"type": @"ready"};
    [player userContentController:(WKUserContentController *)[[NSObject alloc] init]
        didReceiveScriptMessage:(WKScriptMessage *)ready];
    Check(firstWeb.suspensionDepth == 1, @"Iframe readiness while hidden does not add another suspension");
    Check(shown == 0 && Plays(firstWeb) == 0, @"Selection never opens the panel or starts playback");
    [player show];
    Check(shown == 1 && Plays(firstWeb) == 0 && !player.starting, @"Show requests the host without autoplay");
    Check([[firstWeb.commands lastObject][@"action"] isEqualToString:@"controls"], @"Visible paused controls are usable");
    Check(firstWeb.suspensionDepth == 0, @"Showing fully releases hidden-page suspension");
    DeskHostViewProbe *host = (DeskHostViewProbe *)view;
    host.hiddenOrHasHiddenAncestor = YES;
    Check(![player isPlaybackVisible], @"A hidden embedded view is ineligible for playback");
    host.hiddenOrHasHiddenAncestor = NO;
    host.window.miniaturized = YES;
    Check(![player isPlaybackVisible], @"A minimized host is ineligible for playback");
    host.window.miniaturized = NO;
    host.window.occlusionState = 0;
    Check(![player isPlaybackVisible], @"An occluded host is ineligible for playback");
    host.window.occlusionState = NSWindowOcclusionStateVisible;
    host.visibleRect = NSZeroRect;
    Check(![player isPlaybackVisible], @"An empty visible region is ineligible for playback");
    host.visibleRect = NSMakeRect(0, 0, 308, 238);
    [player play];
    Check(shown == 2 && player.starting && player.wantsPlayback && Plays(firstWeb) == 1, @"Explicit play opens and starts a visible player");
    [player publishPlaying:YES starting:NO error:nil];
    SetVisible(player, NO);
    Check(!player.playing && !player.starting && !player.wantsPlayback, @"Closing cancels active playback");
    Check(firstWeb.suspensions.lastObject.boolValue, @"Closing suspends media");
    for (NSUInteger i = 0; i < 3; i++) SetVisible(player, NO);
    Check(firstWeb.suspensionDepth == 1, @"Repeated close and pause callbacks do not nest suspension");
    Check([[firstWeb.commands lastObject][@"action"] isEqualToString:@"pause"], @"Closing sends a pause command");
    [player show];
    Check(Plays(firstWeb) == 1 && !player.starting && !player.wantsPlayback, @"Reopening does not resume old playback");
    Check(firstWeb.suspensionDepth == 0, @"Reopening leaves the iframe eligible for native and AX play");

    // Show's pause/settle callback can still be pending when explicit Play
    // changes the intent. The suspension must still be released exactly once.
    firstWeb.deferSuspend = YES;
    [player show];
    [player play];
    Check(firstWeb.suspensionDepth == 0, @"Play releases an in-flight show suspension");
    void (^lateSuspend)(void) = firstWeb.pendingSuspend;
    Check(lateSuspend != nil, @"The old show suspension completion remains pending");
    lateSuspend();
    firstWeb.pendingSuspend = nil;
    firstWeb.deferSuspend = NO;
    Check(firstWeb.suspensionDepth == 0, @"Stale show callbacks cannot strand or over-resume media");
    [player pause];

    // A late WebKit unsuspend callback may arrive after the popover closes.
    firstWeb.deferResume = YES;
    [player play];
    Check(player.starting && firstWeb.pendingResume, @"A pending resume can await WebKit");
    void (^lateResume)(void) = firstWeb.pendingResume;
    SetVisible(player, NO);
    NSUInteger before = Plays(firstWeb);
    lateResume();
    Check(Plays(firstWeb) == before && !player.starting && !player.wantsPlayback, @"A close invalidates late resume callbacks");
    Check(firstWeb.suspensionDepth == 1, @"Close keeps exactly one suspension while a stale resume completes");
    firstWeb.pendingResume = nil;
    firstWeb.deferResume = NO;

    [player setVideoId:@"M7lc1UVf-VE" title:@"Renamed stream" volume:0.4];
    Check(Web(player) == firstWeb && player.pageLoads == 1, @"Reselecting the same video reuses its page");
    [player setVideoId:@"dQw4w9WgXcQ" title:@"Second stream" volume:0.4];
    Check(player.view == view && Web(player) != firstWeb && player.pageLoads == 2, @"Changing videos preserves the embedded host view");
    Check(firstWeb.removals == 1 && firstWeb.blankLoads == 1, @"Changing videos detaches and clears the old page");
    [player stop];
    Check(!player.videoId && !player.webView && player.view == view, @"Stop discards media while retaining the reusable host view");

    __block NSString *missingHostError = nil;
    DeskPlayerProbe *unhosted = [[DeskPlayerProbe alloc] initWithStateChanged:^(BOOL playing, BOOL starting, NSString *error) {
      (void)playing; (void)starting;
      missingHostError = error;
    }];
    [unhosted setVideoId:@"M7lc1UVf-VE" title:@"Unhosted stream" volume:0.3];
    [unhosted play];
    Check([missingHostError containsString:@"panel is unavailable"], @"Missing host preserves an actionable error");
    Check(!unhosted.starting && !unhosted.wantsPlayback && !unhosted.playTimer && Plays(Web(unhosted)) == 0,
        @"Missing host does not leave a pending play intent or timeout");
    [unhosted stop];

    // Bypass DeskMusic's preferences/channel initializer; only production
    // preparation, host callbacks, and teardown are exercised.
    DeskMusic *music = [[DeskMusic alloc] init];
    music.tracks = [NSMutableArray array];
    NSDictionary *track = @{@"id": @"youtube_M7lc1UVf-VE", @"title": @"Focus stream", @"youtubeVideoId": @"M7lc1UVf-VE"};
    music.youTubeTracks = [NSMutableArray arrayWithObject:track];
    music.selectedId = track[@"id"];
    music.volume = 0.3;
    __block NSView *hostedView = nil;
    __block NSUInteger hostShows = 0;
    __weak DeskMusic *weakMusic = music;
    music.youTubeViewChanged = ^(NSView *changed) { hostedView = changed; };
    music.showYouTubePlayer = ^{ hostShows++; SetVisible(weakMusic.youTubePlayer, YES); };
    [music prepareYouTubeTrack:track];
    Check(hostedView == music.youTubePlayer.view && hostShows == 0, @"Music attaches its selected player without showing it");
    [music.youTubePlayer show];
    Check(hostShows == 1 && !music.youTubePlayer.starting, @"Music routes Show through the host callback");
    [music.youTubePlayer play];
    Check(music.youTubePlayer.starting, @"Music's embedded player accepts explicit play");
    [music youTubeVisibilityChanged:NO];
    Check(!music.youTubePlayer.starting && !music.youTubePlayer.wantsPlayback, @"Music forwards panel closure and cancels pending play");
    NSView *originalHost = hostedView;
    [music stopAllPlayers];
    Check(!hostedView && !music.youTubePlayer.videoId, @"Changing away from YouTube detaches its host view and stops media");
    [music prepareYouTubeTrack:track];
    Check(hostedView == originalHost && !music.youTubePlayer.starting, @"Selecting YouTube again reattaches the same paused view");
    __block NSUInteger reboundShows = 0;
    music.showYouTubePlayer = ^{ reboundShows++; SetVisible(weakMusic.youTubePlayer, YES); };
    [music prepareYouTubeTrack:track];
    [music.youTubePlayer show];
    Check(reboundShows == 1, @"Preparing an existing player refreshes the host callback");
    [music stopAllPlayers];
    printf("YouTube presentation: %lu checks passed (production lifecycle and playback guards).\n", (unsigned long)checks);
  }
  return 0;
}
