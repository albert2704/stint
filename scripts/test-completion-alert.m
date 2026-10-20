// Compile the real native implementation; this harness never starts AppKit or audio.
#import <Cocoa/Cocoa.h>
static NSApplication *StintTestApplication;
#define NSApp StintTestApplication
#import "../macos/Runner/StintMenuBar.m"
#undef NSApp

static NSUInteger checks = 0;
static void Check(BOOL condition, NSString *message) {
  checks++;
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
static NSDate *At(NSTimeInterval seconds) { return [NSDate dateWithTimeIntervalSince1970:seconds]; }
static StintCompletionGate *Started(NSString *phase) {
  StintCompletionGate *gate = [[StintCompletionGate alloc] init];
  Check(![gate observeKey:@"session:200" deadline:At(200) phase:phase routine:@"classic" idle:NO atTime:At(100)], @"Starting is silent");
  return gate;
}
static BOOL Transition(StintCompletionGate *gate, NSString *phase, NSString *routine, NSTimeInterval now) {
  return [gate observeKey:nil deadline:nil phase:phase routine:routine idle:YES atTime:At(now)];
}

@interface StintAlertProbe : StintMenuBar
@property(nonatomic) NSUInteger chimes;
@property(nonatomic) NSUInteger openedWindows;
@property(nonatomic) NSUInteger completionCards;
@property(nonatomic) NSUInteger previewCards;
@property(nonatomic) NSUInteger hints;
@property(nonatomic, strong) UNNotificationContent *presentedContent;
@end
@implementation StintAlertProbe
- (void)playCompletionSound { self.chimes++; }
- (void)presentMenuBarHint { self.hints++; }
- (void)presentCompletionContent:(UNNotificationContent *)content preview:(BOOL)preview {
  self.presentedContent = content;
  if (preview) self.previewCards++;
  else self.completionCards++;
  self.completionCardContext = preview ? nil : content.userInfo;
}
- (void)checkAuthorizationForGeneration:(NSUInteger)generation {}
- (void)removeFutureOrphanForGeneration:(NSUInteger)generation {}
- (void)renderPopoverWithTime:(NSString *)time status:(NSString *)status {}
- (NSString *)repeatedAlertSoundName { return nil; }
- (void)showWindow { self.openedWindows++; }
@end

// In-memory substitutes keep preferences, Library/Sounds, and audio untouched.
@interface StintDefaultsProbe : NSObject
@property(nonatomic, strong) NSMutableDictionary *values;
@property(nonatomic) NSUInteger writes;
@end
@implementation StintDefaultsProbe
- (id)objectForKey:(NSString *)key { return self.values[key]; }
- (BOOL)boolForKey:(NSString *)key { return [self.values[key] boolValue]; }
- (void)setBool:(BOOL)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setObject:(id)value forKey:(NSString *)key {
  if (!self.values) self.values = [NSMutableDictionary dictionary];
  self.values[key] = value;
  self.writes++;
}
@end

@interface StintFakeSound : NSObject
@property(nonatomic, weak) id<NSSoundDelegate> delegate;
@property(nonatomic) NSTimeInterval currentTime;
@property(nonatomic) NSTimeInterval duration;
@property(nonatomic) float volume;
@property(nonatomic) BOOL loops;
@property(nonatomic) BOOL failPlay;
@property(nonatomic) NSUInteger plays;
@property(nonatomic) NSUInteger stops;
@end
@implementation StintFakeSound
- (BOOL)play { self.plays++; return !self.failPlay; }
- (BOOL)stop { self.stops++; return YES; }
@end

@interface StintSoundProbe : StintMenuBar
@property(nonatomic, copy) NSString *lastSoundName;
@property(nonatomic, copy) NSString *cachedSoundName;
@property(nonatomic, strong) StintFakeSound *lastAudio;
@property(nonatomic) BOOL failNextPlay;
@property(nonatomic) NSUInteger errors;
@end
@implementation StintSoundProbe
- (NSSound *)newAlertSoundNamed:(NSString *)name {
  self.lastSoundName = name;
  self.lastAudio = [[StintFakeSound alloc] init];
  self.lastAudio.duration = 1;
  self.lastAudio.failPlay = self.failNextPlay;
  self.failNextPlay = NO;
  return (NSSound *)self.lastAudio;
}
- (NSString *)repeatedAlertSoundName { return self.cachedSoundName; }
- (void)reportNotificationError:(NSString *)message { self.errors++; }
@end

static id Call(StintMenuBar *probe, NSString *method, id arguments) {
  __block id answer = nil;
  __block NSUInteger replies = 0;
  [probe handleCall:[FlutterMethodCall methodCallWithMethodName:method arguments:arguments] result:^(id result) {
    answer = result;
    replies++;
  }];
  Check(replies == 1, @"Channel method answers exactly once");
  return answer;
}
static void Pump(NSTimeInterval seconds) {
  [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

@interface StintNotificationProbe : NSObject
@property(nonatomic, strong) UNNotificationRequest *lastRequest;
@property(nonatomic) NSUInteger requests;
@property(nonatomic, copy) NSSet<UNNotificationCategory *> *categories;
@end
@implementation StintNotificationProbe
- (void)addNotificationRequest:(UNNotificationRequest *)request withCompletionHandler:(void (^)(NSError *))completion {
  self.lastRequest = request;
  self.requests++;
  if (completion) completion(nil);
}
- (void)setNotificationCategories:(NSSet *)categories { self.categories = categories; }
- (void)removePendingNotificationRequestsWithIdentifiers:(NSArray *)identifiers {}
- (id)delegate { return nil; }
@end

@interface StintDeliveredNotificationProbe : NSObject
@property(nonatomic, strong) UNNotificationRequest *request;
@end
@implementation StintDeliveredNotificationProbe
@end

static UNNotificationPresentationOptions PresentationOptions(StintMenuBar *probe, UNNotificationRequest *request) {
  StintDeliveredNotificationProbe *notification = [[StintDeliveredNotificationProbe alloc] init];
  notification.request = request;
  StintNotificationProbe *center = [[StintNotificationProbe alloc] init];
  __block NSUInteger replies = 0;
  __block UNNotificationPresentationOptions options = UNNotificationPresentationOptionNone;
  [probe userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification
      withCompletionHandler:^(UNNotificationPresentationOptions result) { options = result; replies++; }];
  Pump(0.02);
  Check(replies == 1, @"Foreground notification presentation answers exactly once");
  return options;
}

@interface StintSchedulingProbe : StintAlertProbe
@end
@implementation StintSchedulingProbe
- (void)checkAuthorizationForGeneration:(NSUInteger)generation { [self scheduleForGeneration:generation]; }
@end

@interface StintChannelProbe : NSObject
@property(nonatomic, copy) NSString *method;
@property(nonatomic, strong) id arguments;
@property(nonatomic) NSUInteger calls;
@property(nonatomic, copy) void (^callObserver)(NSString *method);
@end
@implementation StintChannelProbe
- (void)invokeMethod:(NSString *)method arguments:(id)arguments {
  self.method = method; self.arguments = arguments; self.calls++;
  if (self.callObserver) self.callObserver(method);
}
- (void)setMethodCallHandler:(id)handler {}
@end

@interface StintApplicationProbe : NSObject
@property(nonatomic) NSUInteger activations;
@property(nonatomic, strong) NSEvent *currentEvent;
@end
@implementation StintApplicationProbe
- (void)activateIgnoringOtherApps:(BOOL)ignore { self.activations++; }
@end

@interface StintWindowProbe : NSObject
@property(nonatomic, getter=isMiniaturized) BOOL miniaturized;
@property(nonatomic) NSUInteger keyRequests;
@property(nonatomic) NSUInteger frontRequests;
@end
@implementation StintWindowProbe
- (void)makeKeyWindow { self.keyRequests++; }
- (void)deminiaturize:(id)sender { self.miniaturized = NO; }
- (void)makeKeyAndOrderFront:(id)sender { self.frontRequests++; }
@end

@interface StintViewProbe : NSObject
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic) NSRect bounds;
@property(nonatomic) NSUInteger removals;
@end
@implementation StintViewProbe
- (void)removeFromSuperview { self.removals++; }
@end

@interface StintControllerProbe : NSObject
@property(nonatomic, strong) NSView *view;
@end
@implementation StintControllerProbe
@end

@interface StintPopoverProbe : NSObject
@property(nonatomic, getter=isShown) BOOL shown;
@property(nonatomic) NSUInteger shows;
@property(nonatomic) NSUInteger closes;
@property(nonatomic, strong) NSViewController *contentViewController;
@end
@implementation StintPopoverProbe
- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge {
  self.shown = YES; self.shows++;
}
- (void)close { self.shown = NO; self.closes++; }
@end

@interface StintPanelProbe : StintMenuBar
@end
@implementation StintPanelProbe
- (void)render {}
@end

@interface StintBannerProbe : NSObject
@property(nonatomic) BOOL hasContent;
@property(nonatomic, getter=isHint) BOOL hint;
@property(nonatomic, getter=isVisible) BOOL visible;
@property(nonatomic) BOOL temporarilyHidden;
@property(nonatomic) NSUInteger dismissals;
@property(nonatomic, copy) void (^dismissedHandler)(void);
@end
@implementation StintBannerProbe
- (void)setTemporarilyHidden:(BOOL)hidden {
  _temporarilyHidden = hidden;
  self.visible = self.hasContent && !hidden;
}
- (void)dismiss {
  self.hasContent = NO; self.visible = NO; self.dismissals++;
  if (self.dismissedHandler) self.dismissedHandler();
}
@end

@interface StintButtonProbe : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *accessibilityLabel;
@property(nonatomic, copy) NSString *toolTip;
@end
@implementation StintButtonProbe
@end

static void CheckPanelPresentation(void) {
  StintApplicationProbe *application = [[StintApplicationProbe alloc] init];
  StintTestApplication = (NSApplication *)application;
  StintPanelProbe *panel = [[StintPanelProbe alloc] init];
  StintChannelProbe *channel = [[StintChannelProbe alloc] init];
  StintWindowProbe *mainWindow = [[StintWindowProbe alloc] init];
  StintWindowProbe *popoverWindow = [[StintWindowProbe alloc] init];
  StintViewProbe *view = [[StintViewProbe alloc] init];
  view.window = (NSWindow *)popoverWindow;
  StintControllerProbe *controller = [[StintControllerProbe alloc] init];
  controller.view = (NSView *)view;
  StintPopoverProbe *popover = [[StintPopoverProbe alloc] init];
  popover.contentViewController = (NSViewController *)controller;
  panel.channel = (FlutterMethodChannel *)channel;
  panel.window = (NSWindow *)mainWindow;
  panel.popover = (NSPopover *)popover;
  StintBannerProbe *banner = [[StintBannerProbe alloc] init];
  banner.hasContent = YES; banner.visible = YES;
  panel.completionBanner = (StintCompletionBanner *)banner;
  [panel statusItemClicked:nil];
  Check(popover.shown && popover.shows == 1, @"Status click opens the timer popover");
  Check([channel.method isEqualToString:@"refresh"] && popoverWindow.keyRequests == 1, @"Opening refreshes the timer and requests popover keyboard focus");
  Check(application.activations == 0 && mainWindow.frontRequests == 0, @"Opening the menu panel never activates the app or brings its main window forward");
  Check(banner.temporarilyHidden && !banner.visible && banner.hasContent && banner.dismissals == 0,
      @"Opening the panel hides the completion card without consuming it");
  [panel statusItemClicked:nil];
  Check(!popover.shown && popover.shows == 1, @"Second status click closes the panel without reopening it");
  [panel popoverDidClose:[NSNotification notificationWithName:NSPopoverDidCloseNotification object:popover]];
  Check(!banner.temporarilyHidden && banner.visible && banner.dismissals == 0,
      @"Closing the panel without an action restores the existing card");
  [panel showMiniTimer:nil];
  mainWindow.miniaturized = YES;
  [panel showWindow];
  Check(!popover.shown && application.activations == 1 && mainWindow.frontRequests == 1 && !mainWindow.miniaturized,
      @"Explicit Open Stint closes the popover, activates the app, and restores the main window");
  NSMutableArray<NSNumber *> *visibility = [NSMutableArray array];
  panel.youTubeVisibilityChanged = ^(BOOL visible) { [visibility addObject:@(visible)]; };
  panel.embeddedYouTubeView = (NSView *)view;
  [panel showYouTubePlayer];
  Check(popover.shown && application.activations == 1 && mainWindow.frontRequests == 1,
      @"Showing the embedded YouTube player opens only the timer panel");
  [panel popoverDidShow:[NSNotification notificationWithName:NSPopoverDidShowNotification object:popover]];
  Check(banner.temporarilyHidden && !banner.visible, @"Popover delegate show also hides a retained completion card");
  popover.shown = NO;
  [panel popoverDidClose:[NSNotification notificationWithName:NSPopoverDidCloseNotification object:popover]];
  Check(!banner.temporarilyHidden && banner.visible, @"Popover delegate close restores the retained completion card");
  Check([visibility isEqualToArray:@[@YES, @NO]], @"Popover show and close report embedded player visibility");
  [panel showMiniTimer:nil];
  [panel dismissCompletionCard];
  popover.shown = NO;
  [panel popoverDidClose:[NSNotification notificationWithName:NSPopoverDidCloseNotification object:popover]];
  Check(!banner.hasContent && !banner.visible, @"A card dismissed while the panel is open is not resurrected on close");
  [panel setYouTubeView:nil];
  Check(!panel.embeddedYouTubeView && view.removals == 1 && !visibility.lastObject.boolValue,
      @"Removing the embedded player detaches its view and reports it hidden");
  StintTestApplication = nil;
}

static void CheckShortcutRouting(void) {
  StintApplicationProbe *application = [[StintApplicationProbe alloc] init];
  StintTestApplication = (NSApplication *)application;
  StintPanelProbe *panel = [[StintPanelProbe alloc] init];
  StintChannelProbe *channel = [[StintChannelProbe alloc] init];
  StintWindowProbe *mainWindow = [[StintWindowProbe alloc] init];
  StintWindowProbe *popoverWindow = [[StintWindowProbe alloc] init];
  StintViewProbe *view = [[StintViewProbe alloc] init];
  view.window = (NSWindow *)popoverWindow;
  StintControllerProbe *controller = [[StintControllerProbe alloc] init];
  controller.view = (NSView *)view;
  StintPopoverProbe *popover = [[StintPopoverProbe alloc] init];
  popover.contentViewController = (NSViewController *)controller;
  panel.channel = (FlutterMethodChannel *)channel;
  panel.window = (NSWindow *)mainWindow;
  panel.popover = (NSPopover *)popover;

  for (NSString *action in @[@"toggle", @"reset", @"skip", @"panel", @"unknown"])
    [panel performShortcutAction:action];
  Check(channel.calls == 0 && popover.shows == 0 && mainWindow.frontRequests == 0,
      @"Shortcuts dispatch nothing before the first ready timer snapshot");

  panel.ready = YES; panel.running = YES; panel.sessionId = @"shortcut-session"; panel.cycleStep = 2;
  [panel performShortcutAction:@"toggle"];
  Check(channel.calls == 1 && [channel.method isEqualToString:@"toggle"]
      && [channel.arguments isEqual:@{@"running": @YES, @"sessionId": @"shortcut-session", @"cycleStep": @2}],
      @"Shortcut Pause uses the existing toggle command with the displayed running session and step");
  panel.running = NO; panel.sessionId = nil; panel.cycleStep = 3;
  [panel performShortcutAction:@"toggle"];
  Check(channel.calls == 2 && [channel.arguments isEqual:@{@"running": @NO, @"sessionId": NSNull.null, @"cycleStep": @3}],
      @"Shortcut Start carries the current idle context for shared validation");
  Check(popover.shows == 0 && application.activations == 0 && mainWindow.frontRequests == 0,
      @"Timer-toggle shortcuts do not reveal a panel or activate the main window");

  NSMutableArray<NSString *> *commands = [NSMutableArray array];
  channel.callObserver = ^(NSString *method) {
    [commands addObject:method];
    if ([method isEqualToString:@"reset"] || [method isEqualToString:@"skip"])
      Check(popover.shown, @"The timer panel is already visible when Reset or Skip requests shared confirmation");
  };
  for (NSString *action in @[@"reset", @"skip"]) {
    [popover close]; [commands removeAllObjects];
    [panel performShortcutAction:action];
    Check(popover.shown && [commands isEqual:@[@"refresh", action]] && channel.arguments == nil,
        [NSString stringWithFormat:@"Shortcut %@ refreshes the panel and requests the existing action without confirming it", action]);
  }
  [popover close]; [commands removeAllObjects];
  [panel performShortcutAction:@"panel"];
  Check(popover.shown && [commands isEqual:@[@"refresh"]],
      @"Show timer panel shortcut opens and refreshes the panel without changing the timer");
  NSUInteger shows = popover.shows;
  [panel performShortcutAction:@"panel"];
  Check(popover.shown && popover.shows == shows,
      @"Show timer panel shortcut keeps an already visible panel open");
  NSUInteger calls = channel.calls;
  [panel performShortcutAction:@"unknown"];
  Check(channel.calls == calls && popover.shows == shows,
      @"Unknown shortcut action identifiers have no effect");
  Check(application.activations == 0 && mainWindow.frontRequests == 0,
      @"Reset, Skip and Show panel shortcuts never activate or raise the main window");
  channel.callObserver = nil;
  StintTestApplication = nil;
}

static NSDictionary *Snapshot(NSString *phase, NSNumber *deadline) {
  BOOL running = deadline != nil;
  return @{@"phase": phase, @"running": @(running), @"hasProgress": @(running),
    @"remaining": @60, @"totalSeconds": @60, @"activeRoutineId": @"classic",
    @"focusMinutes": @25, @"shortBreakMinutes": @5, @"longBreakMinutes": @15,
    @"sessionId": running ? @"probe" : NSNull.null,
    @"deadlineMilliseconds": deadline ?: NSNull.null};
}

static void CheckNotificationVariants(void) {
  StintAlertProbe *probe = [[StintAlertProbe alloc] init];
  probe.alertDefaults = (NSUserDefaults *)[[StintDefaultsProbe alloc] init];
  probe.focusMinutes = 25; probe.shortBreakMinutes = 5;
  probe.dailyGoal = 8; probe.sessionId = @"completed";
  NSArray<NSDictionary *> *variants = @[
    @{@"phase": @"Focus", @"step": @2, @"count": @3, @"longMinutes": @15,
      @"title": @"Focus complete", @"body": @"Your short break is ready.",
      @"action": @"Start break", @"secondary": @"Skip break", @"category": @"stint.start-break", @"goalMet": @NO},
    @{@"phase": @"Focus", @"step": @6, @"count": @4, @"longMinutes": @15,
      @"title": @"Four stints done", @"body": @"Your long break is ready. Take the full 15 minutes.",
      @"action": @"Start long break", @"secondary": @"Skip break", @"category": @"stint.start-long-break", @"goalMet": @NO},
    @{@"phase": @"Focus", @"step": @6, @"count": @4, @"longMinutes": @30,
      @"title": @"Four stints done", @"body": @"Your long break is ready. Take the full 30 minutes.",
      @"action": @"Start long break", @"secondary": @"Skip break", @"category": @"stint.start-long-break", @"goalMet": @NO},
    @{@"phase": @"Focus", @"step": @2, @"count": @8, @"longMinutes": @15,
      @"title": @"Daily goal met", @"body": @"8 stints today. Your short break is ready.",
      @"action": @"Start break", @"secondary": @"Skip break", @"category": @"stint.start-break", @"goalMet": @YES},
    @{@"phase": @"Focus", @"step": @6, @"count": @8, @"longMinutes": @30,
      @"title": @"Daily goal met", @"body": @"8 stints today. Your long break is ready.",
      @"action": @"Start long break", @"secondary": @"Skip break", @"category": @"stint.start-long-break", @"goalMet": @YES},
    @{@"phase": @"Focus", @"step": @0, @"count": @9, @"longMinutes": @15,
      @"title": @"Focus complete", @"body": @"Your short break is ready.",
      @"action": @"Start break", @"secondary": @"Skip break", @"category": @"stint.start-break", @"goalMet": @NO},
    @{@"phase": @"Focus", @"step": @6, @"count": @12, @"longMinutes": @15,
      @"title": @"Four stints done", @"body": @"Your long break is ready. Take the full 15 minutes.",
      @"action": @"Start long break", @"secondary": @"Skip break", @"category": @"stint.start-long-break", @"goalMet": @NO},
    @{@"phase": @"Short break", @"step": @3, @"count": @8, @"longMinutes": @15,
      @"title": @"Break over", @"body": @"Focus 3 of 4 is ready when you are.",
      @"action": @"Start focus", @"secondary": @"Not now", @"category": @"stint.start-focus", @"goalMet": @NO},
    @{@"phase": @"Long break", @"step": @7, @"count": @8, @"longMinutes": @15,
      @"title": @"Break over", @"body": @"Focus 1 of 4 is ready when you are.",
      @"action": @"Start focus", @"secondary": @"Not now", @"category": @"stint.start-focus", @"goalMet": @NO}
  ];
  for (NSDictionary *variant in variants) {
    probe.phase = variant[@"phase"]; probe.cycleStep = [variant[@"step"] integerValue];
    probe.completionCount = variant[@"count"]; probe.longBreakMinutes = [variant[@"longMinutes"] integerValue];
    UNNotificationContent *content = [probe notificationForKey:@"variant" deadline:NSDate.date audible:NO].content;
    NSString *description = [NSString stringWithFormat:@"%@ at step %@ and count %@", variant[@"title"], variant[@"step"], variant[@"count"]];
    Check([content.title isEqual:variant[@"title"]] && [content.body isEqual:variant[@"body"]],
        [description stringByAppendingString:@" has the specified title and body"]);
    Check([content.categoryIdentifier isEqual:variant[@"category"]]
        && [content.userInfo[@"actionTitle"] isEqual:variant[@"action"]]
        && [content.userInfo[@"secondaryTitle"] isEqual:variant[@"secondary"]],
        [description stringByAppendingString:@" offers the correct actions and system category"]);
    NSString *count = [NSString stringWithFormat:@"%@ of 8 today", variant[@"count"]];
    NSString *subtitle = [variant[@"goalMet"] boolValue] ? count : [count stringByAppendingString:@" · Glass played twice"];
    Check([content.subtitle isEqualToString:subtitle]
        && [content.userInfo[@"goalMet"] isEqual:variant[@"goalMet"]],
        [description stringByAppendingString:@" uses count-first detail and hides the sound note only for exact goal attainment"]);
    Check([content.userInfo[@"count"] isEqual:variant[@"count"]] && [content.userInfo[@"goal"] isEqual:@8]
        && [content.userInfo[@"finishedStep"] isEqual:variant[@"step"]]
        && [content.userInfo[@"nextStep"] integerValue] == (probe.cycleStep + 1) % 8
        && [content.userInfo[@"cycleStep"] isEqual:content.userInfo[@"nextStep"]],
        [description stringByAppendingString:@" carries the finished step, offered step, and projected progress"]);
    Check([content.userInfo[@"stepMinutes"] isEqual:@[@25, @5, @25, @5, @25, @5, @25, variant[@"longMinutes"]]],
        [description stringByAppendingString:@" supplies all eight configured durations for the proportional track"]);
  }

  // Build dates in the same local Gregorian calendar as production. Changing
  // defaultTimeZone mid-process does not reliably update a cached localTimeZone.
  // CI also runs this fixture in a non-UTC process to distinguish local midnight.
  NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
  calendar.timeZone = NSTimeZone.localTimeZone;
  NSDateComponents *components = [[NSDateComponents alloc] init];
  components.year = 2026; components.month = 10; components.day = 9;
  components.hour = 23; components.minute = 59; components.second = 59;
  NSDate *beforeMidnight = [calendar dateFromComponents:components];
  NSDate *afterMidnight = [beforeMidnight dateByAddingTimeInterval:2];
  probe.phase = @"Focus"; probe.cycleStep = 0; probe.completionCount = @8;
  UNNotificationContent *before = [probe notificationForKey:@"local-before" deadline:beforeMidnight audible:NO].content;
  probe.completionCount = @1;
  UNNotificationContent *after = [probe notificationForKey:@"local-after" deadline:afterMidnight audible:NO].content;
  Check([before.threadIdentifier isEqualToString:@"stint-2026-10-09"]
      && [after.threadIdentifier isEqualToString:@"stint-2026-10-10"],
      @"Notification grouping changes at the deadline's local midnight rather than UTC midnight");
  Check([before.title isEqualToString:@"Daily goal met"] && [before.subtitle isEqualToString:@"8 of 8 today"]
      && [after.title isEqualToString:@"Focus complete"] && [after.subtitle isEqualToString:@"1 of 8 today · Glass played twice"],
      @"Scheduled goal attainment and subtitle use the projected count on each completion day");
}

int main(void) {
  @autoreleasepool {
    CheckPanelPresentation();
    CheckShortcutRouting();
    CheckNotificationVariants();
    Check([StintDurationLabel(89) isEqualToString:@"1 minute 29 seconds"], @"Adjusted interval duration preserves non-minute seconds in accessibility copy");
    Check([StintDurationLabel(1500) isEqualToString:@"25 minutes"], @"Whole configured durations remain concise");
    StintCompletionGate *gate = Started(@"Focus");
    Check(![gate consumeExpiryAtTime:At(199)], @"No early chime");
    Check([gate consumeExpiryAtTime:At(200)], @"Native expiry chimes");
    Check(![gate consumeExpiryAtTime:At(201)], @"Repeated native expiry is silent");
    Check(!Transition(gate, @"Short break", @"classic", 201), @"Dart transition after native expiry is silent");

    gate = Started(@"Focus");
    Check(Transition(gate, @"Long break", @"classic", 200), @"Dart-first completion chimes");
    Check(![gate consumeExpiryAtTime:At(201)], @"Native expiry after Dart completion is silent");
    Check(!Transition(gate, @"Long break", @"classic", 201), @"Repeated Dart snapshot is silent");
    for (NSString *phase in @[@"Short break", @"Long break"]) {
      gate = Started(phase);
      Check(Transition(gate, @"Focus", @"classic", 200), @"Break completion chimes");
    }

    gate = Started(@"Focus");
    Check(!Transition(gate, @"Short break", @"classic", 199), @"Early phase switch is silent");
    Check(![gate consumeExpiryAtTime:At(201)], @"Abandoned phase never chimes");
    gate = Started(@"Focus");
    Check(!Transition(gate, @"Focus", @"classic", 201), @"Reset after deadline is silent");
    gate = Started(@"Short break");
    Check(!Transition(gate, @"Focus", @"deep-work", 201), @"Routine replacement is silent");
    gate = Started(@"Focus");
    Check(![gate observeKey:@"session:200" deadline:At(200) phase:@"Focus" routine:@"saved-copy" idle:NO atTime:At(199)], @"Saving the active routine is silent");
    Check(Transition(gate, @"Short break", @"saved-copy", 200), @"Saving a routine does not suppress completion of the unchanged timer");
    gate = Started(@"Focus");
    Check(![gate observeKey:nil deadline:nil phase:@"Focus" routine:@"classic" idle:NO atTime:At(199)], @"Pause is silent");
    Check(![gate consumeExpiryAtTime:At(201)], @"Paused interval never chimes");
    Check(![gate observeKey:@"session:300" deadline:At(300) phase:@"Focus" routine:@"classic" idle:NO atTime:At(210)], @"Resume is silent");
    Check([gate consumeExpiryAtTime:At(300)], @"Resumed interval chimes at its new deadline");

    gate = [[StintCompletionGate alloc] init];
    Check(![gate observeKey:@"old:200" deadline:At(200) phase:@"Focus" routine:@"classic" idle:NO atTime:At(201)], @"Overdue restored state is silent");
    Check(![gate consumeExpiryAtTime:At(201)], @"Overdue restored state does not arm the ticker");
    Check(!Transition(gate, @"Short break", @"classic", 201), @"Restored completion transition is silent");
    gate = Started(@"Focus");
    Check(![gate observeKey:@"new:400" deadline:At(400) phase:@"Focus" routine:@"classic" idle:NO atTime:At(201)], @"New session replaces an expired session without chime");
    Check([gate consumeExpiryAtTime:At(400)], @"New session completes normally");
    gate = Started(@"Focus");
    Check([gate consumeExpiryAtTime:At(500)], @"A live interval that expires during sleep chimes on wake");

    // Verify the actual update/render entry points share the same gate.
    StintAlertProbe *probe = [[StintAlertProbe alloc] init];
    probe.completionGate = [[StintCompletionGate alloc] init];
    NSNumber *future = @((NSDate.date.timeIntervalSince1970 + 600) * 1000);
    [probe update:Snapshot(@"Focus", future)];
    probe.completionGate.deadline = NSDate.distantPast;
    [probe update:Snapshot(@"Short break", nil)];
    [probe render];
    Check(probe.chimes == 1 && probe.completionCards == 1, @"Dart update then render plays once and presents one completion card");
    Check([probe.presentedContent.title isEqualToString:@"Focus complete"]
        && [probe.presentedContent.body isEqualToString:@"Your short break is ready."],
        @"Dart-first completion retains the finished focus copy after the snapshot has advanced to break");
    [probe update:Snapshot(@"Focus", future)];
    probe.completionGate.deadline = NSDate.distantPast;
    [probe render];
    [probe update:Snapshot(@"Short break", nil)];
    [probe render];
    Check(probe.chimes == 2 && probe.completionCards == 2, @"Render then Dart update plays once and presents one completion card");
    [probe update:Snapshot(@"Focus", @1)];
    [probe update:Snapshot(@"Short break", nil)];
    Check(probe.chimes == 2 && probe.completionCards == 2, @"Overdue startup remains silent and card-free through actual entry points");

    for (NSString *action in @[@"pause", @"reset", @"skip", @"jump"]) {
      StintAlertProbe *canceled = [[StintAlertProbe alloc] init];
      canceled.completionGate = [[StintCompletionGate alloc] init];
      [canceled update:Snapshot(@"Focus", future)];
      NSMutableDictionary *state = [Snapshot([action isEqualToString:@"skip"] || [action isEqualToString:@"jump"]
          ? @"Short break" : @"Focus", nil) mutableCopy];
      if ([action isEqualToString:@"pause"]) state[@"hasProgress"] = @YES;
      if ([action isEqualToString:@"reset"] || [action isEqualToString:@"jump"]) canceled.completionGate.deadline = NSDate.distantPast;
      state[@"completedSessionId"] = NSNull.null;
      [canceled update:state];
      [canceled render];
      Check(canceled.chimes == 0 && canceled.completionCards == 0,
          [NSString stringWithFormat:@"%@ never presents a completion card or plays a completion chime", action]);
    }

    StintAlertProbe *card = [[StintAlertProbe alloc] init];
    card.completionGate = [[StintCompletionGate alloc] init];
    StintChannelProbe *cardChannel = [[StintChannelProbe alloc] init];
    card.channel = (FlutterMethodChannel *)cardChannel;
    NSMutableDictionary *fourthFocus = [Snapshot(@"Focus", future) mutableCopy];
    fourthFocus[@"cycleStep"] = @6;
    fourthFocus[@"todayCount"] = @3;
    fourthFocus[@"dailyGoal"] = @8;
    fourthFocus[@"completionCount"] = @4;
    [card update:fourthFocus];
    card.completionGate.deadline = NSDate.distantPast;
    NSMutableDictionary *offeredBreak = [Snapshot(@"Long break", nil) mutableCopy];
    offeredBreak[@"cycleStep"] = @7;
    offeredBreak[@"todayCount"] = @4;
    offeredBreak[@"dailyGoal"] = @8;
    offeredBreak[@"completionCount"] = @4;
    offeredBreak[@"completedSessionId"] = @"probe";
    [card update:offeredBreak];
    Check([card.presentedContent.title isEqualToString:@"Four stints done"]
        && [card.presentedContent.body isEqualToString:@"Your long break is ready. Take the full 15 minutes."]
        && [card.presentedContent.subtitle isEqualToString:@"4 of 8 today · Glass played twice"],
        @"Completion card uses the finished fourth-focus copy and includes the new stint exactly once");
    NSDictionary *offeredContext = card.completionCardContext;
    Check([offeredContext[@"sessionId"] isEqualToString:@"probe"] && [offeredContext[@"cycleStep"] integerValue] == 7,
        @"Completion card retains the precise finished session and offered break");
    [card update:offeredBreak];
    Check([card.completionCardContext isEqual:offeredContext] && card.completionCards == 1,
        @"Repeated idle offered snapshots preserve the card without presenting it again");
    NSUInteger cardCalls = cardChannel.calls;
    [card startFromCompletionCard:@{@"sessionId": @"stale", @"cycleStep": @7}];
    Check(cardChannel.calls == cardCalls && [card.completionCardContext isEqual:offeredContext],
        @"A stale card action cannot start an interval or dismiss the current completion");
    [card startFromCompletionCard:offeredContext];
    Check([cardChannel.method isEqualToString:@"startNext"] && [cardChannel.arguments isEqual:offeredContext]
        && cardChannel.calls == cardCalls + 1 && card.openedWindows == 0 && !card.completionCardContext,
        @"Card Start forwards the exact context once, dismisses the card, and keeps the main window closed");
    [card startFromCompletionCard:offeredContext];
    Check(cardChannel.calls == cardCalls + 1, @"Repeated clicks on a consumed completion card are ignored");

    card.completionCardContext = offeredContext;
    [card skipFromCompletionCard:@{@"sessionId": @"stale", @"cycleStep": @7}];
    Check(cardChannel.calls == cardCalls + 1 && [card.completionCardContext isEqual:offeredContext],
        @"A stale Skip break action cannot consume a newer completion card");
    [card skipFromCompletionCard:offeredContext];
    Check([cardChannel.method isEqualToString:@"skipOffered"] && [cardChannel.arguments isEqual:offeredContext]
        && cardChannel.calls == cardCalls + 2 && !card.completionCardContext && card.openedWindows == 0,
        @"Skip break forwards the same completion context once without opening the main window");
    [card skipFromCompletionCard:offeredContext];
    Check(cardChannel.calls == cardCalls + 2, @"Repeated Skip break clicks are ignored after consumption");
    NSDictionary *offeredFocusContext = @{@"sessionId": @"finished-break", @"cycleStep": @0};
    card.completionCardContext = offeredFocusContext;
    [card skipFromCompletionCard:offeredFocusContext];
    Check(cardChannel.calls == cardCalls + 2 && [card.completionCardContext isEqual:offeredFocusContext],
        @"Native Skip break cannot skip an offered focus interval");

    card.completionCardContext = offeredContext;
    NSMutableDictionary *nextRunning = [Snapshot(@"Long break", future) mutableCopy];
    nextRunning[@"cycleStep"] = @7; nextRunning[@"sessionId"] = @"next-session";
    [card update:nextRunning];
    Check(!card.completionCardContext, @"Starting another interval invalidates the old completion card");
    card.completionCardContext = offeredContext;
    NSMutableDictionary *jumpedPhase = [offeredBreak mutableCopy];
    jumpedPhase[@"cycleStep"] = @1;
    [card update:jumpedPhase];
    Check(!card.completionCardContext, @"Changing the offered cycle position invalidates the completion card");
    card.completionCardContext = offeredContext;
    NSMutableDictionary *clearedCompletion = [offeredBreak mutableCopy];
    clearedCompletion[@"completedSessionId"] = NSNull.null;
    [card update:clearedCompletion];
    Check(!card.completionCardContext, @"Resetting completion proof invalidates the card even at the same idle step");
    card.completionCardContext = offeredContext;
    NSMutableDictionary *changedRhythm = [offeredBreak mutableCopy];
    changedRhythm[@"activeRoutineId"] = @"deep-work";
    [card update:changedRhythm];
    Check(!card.completionCardContext, @"Changing rhythm dismisses the card even if its completed session and offered step still match");
    card.completionCardContext = offeredContext;
    NSMutableDictionary *changedDuration = [offeredBreak mutableCopy];
    changedDuration[@"longBreakMinutes"] = @30;
    [card update:changedDuration];
    Check(!card.completionCardContext, @"Changing a rhythm duration invalidates the card's old offer");
    card.completionCardContext = offeredContext;
    NSMutableDictionary *pausedOffer = [offeredBreak mutableCopy];
    pausedOffer[@"hasProgress"] = @YES;
    [card update:pausedOffer];
    Check(!card.completionCardContext, @"An offered interval with progress is no longer idle and invalidates the card");

    NSMutableDictionary *longRest = [Snapshot(@"Long break", future) mutableCopy];
    longRest[@"cycleStep"] = @7; longRest[@"completionCount"] = @4; longRest[@"dailyGoal"] = @8;
    [card update:longRest];
    card.completionGate.deadline = NSDate.distantPast;
    [card render];
    Check([card.presentedContent.title isEqualToString:@"Break over"]
        && [card.presentedContent.body isEqualToString:@"Focus 1 of 4 is ready when you are."]
        && [card.presentedContent.subtitle isEqualToString:@"4 of 8 today · Glass played twice"],
        @"Native-first break completion offers focus without incrementing the completed-focus count");
    Check(![card.completionCardContext isEqual:offeredContext]
        && [card.completionCardContext[@"cycleStep"] isEqual:@0] && card.completionCards == 2,
        @"A new completion replaces the previous card's context with its own next interval");

    StintAlertProbe *preview = [[StintAlertProbe alloc] init];
    preview.completionGate = [[StintCompletionGate alloc] init];
    [preview update:Snapshot(@"Focus", future)];
    NSString *previewTimerKey = preview.notificationKey;
    [preview previewNotification:nil];
    Check(preview.previewCards == 1 && preview.completionCards == 0 && preview.chimes == 0,
        @"Appearance preview presents a silent sample without manufacturing a completion");
    Check(preview.completionGate.armed && [preview.notificationKey isEqualToString:previewTimerKey]
        && !preview.completionCardContext && preview.openedWindows == 0,
        @"Appearance preview preserves the running timer and carries no actionable completion context");

    probe.phase = @"Focus";
    UNNotificationRequest *live = [probe notificationForKey:@"same-key" deadline:At(NSDate.date.timeIntervalSince1970 + 600) audible:NO];
    UNNotificationRequest *quit = [probe notificationForKey:@"same-key" deadline:At(NSDate.date.timeIntervalSince1970 + 600) audible:YES];
    Check(live.content.sound == nil, @"Running-app notification does not duplicate its direct chime");
    Check(quit.content.sound != nil, @"Normal-quit notification retains system sound");
    Check([live.identifier isEqualToString:quit.identifier], @"Normal-quit replacement keeps one notification identifier");
    Check(live.content.interruptionLevel == UNNotificationInterruptionLevelPassive,
        @"Live timer uses passive system delivery so the branded card is the only banner");
    Check(quit.content.interruptionLevel == UNNotificationInterruptionLevelActive,
        @"Normal Quit restores active system notification delivery");
    Check(PresentationOptions(probe, live) == UNNotificationPresentationOptionList,
        @"Foreground live timer retains its Notification Center entry without a duplicate system banner or sound");
    probe.terminating = YES;
    Check(PresentationOptions(probe, quit) == (UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList | UNNotificationPresentationOptionSound),
        @"Foreground notification during Quit permits the system banner and sound");
    probe.terminating = NO;
    UNNotificationRequest *otherNotification = [UNNotificationRequest requestWithIdentifier:@"stint.menu-bar-hint" content:live.content trigger:nil];
    Check(PresentationOptions(probe, otherNotification) == (UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList | UNNotificationPresentationOptionSound),
        @"Non-timer notifications retain their normal foreground presentation");

    StintNotificationProbe *center = [[StintNotificationProbe alloc] init];
    probe.notifications = (UNUserNotificationCenter *)center;
    probe.authorizationKnown = YES;
    probe.authorizationStatus = UNAuthorizationStatusAuthorized;
    probe.notificationKey = @"exit:600";
    probe.deadline = [NSDate dateWithTimeIntervalSinceNow:600];
    probe.completionGate.armed = YES;
    [probe prepareNotificationForTermination:nil];
    Check(center.lastRequest.content.sound != nil, @"Quit schedules sound for a future interval");
    center.lastRequest = nil;
    probe.deadline = NSDate.distantPast;
    [probe prepareNotificationForTermination:nil];
    Check(center.lastRequest.content.sound != nil, @"Quit immediately after expiry retains sound before the next ticker");
    Check(!probe.completionGate.armed, @"Quit consumes the just-completed live gate");
    center.lastRequest = nil;
    [probe prepareNotificationForTermination:nil];
    Check(center.lastRequest == nil, @"Quit does not repeat an already consumed completion");
    probe.notificationKey = nil;
    probe.deadline = nil;
    [probe prepareNotificationForTermination:nil];
    Check(center.lastRequest == nil, @"Quit while idle does not create an alert");

    StintChannelProbe *channel = [[StintChannelProbe alloc] init];
    StintAlertProbe *stint = [[StintAlertProbe alloc] init];
    stint.channel = (FlutterMethodChannel *)channel;
    stint.notifications = (UNUserNotificationCenter *)center;
    stint.completionGate = [[StintCompletionGate alloc] init];
    stint.alertDefaults = (NSUserDefaults *)[[StintDefaultsProbe alloc] init];
    StintButtonProbe *progressButton = [[StintButtonProbe alloc] init];
    stint.progressButton = (NSButton *)progressButton;
    NSMutableDictionary *progressState = [Snapshot(@"Focus", nil) mutableCopy];
    progressState[@"todayCount"] = @3; progressState[@"dailyGoal"] = @8; progressState[@"completionCount"] = @3;
    [stint update:progressState];
    Check([progressButton.title isEqualToString:@"Progress 3/8"], @"Panel footer shows today's count and daily goal");
    Check([progressButton.accessibilityLabel isEqualToString:@"Progress, 3 of 8 stints today"]
        && [progressButton.toolTip isEqualToString:progressButton.accessibilityLabel], @"Progress button has a complete accessible name and tooltip");
    progressState[@"dailyGoal"] = @99; [stint update:progressState];
    Check(stint.dailyGoal == 16, @"Native goal respects its upper limit");
    progressState[@"dailyGoal"] = @0; [stint update:progressState];
    Check(stint.dailyGoal == 1, @"Native goal respects its lower limit");
    [progressState removeObjectForKey:@"dailyGoal"]; [stint update:progressState];
    Check(stint.dailyGoal == 8, @"Older bridge snapshots use the default daily goal");
    stint.running = YES; stint.sessionId = @"displayed-session"; stint.cycleStep = 2;
    [stint toggleTimer:nil];
    Check([channel.method isEqualToString:@"toggle"] && [channel.arguments isEqual:@{@"running": @YES, @"sessionId": @"displayed-session", @"cycleStep": @2}], @"Native Pause carries the displayed session and cycle context");
    stint.running = NO; stint.sessionId = nil; stint.cycleStep = 3;
    [stint toggleTimer:nil];
    Check([channel.arguments isEqual:@{@"running": @NO, @"sessionId": NSNull.null, @"cycleStep": @3}], @"Native Start carries idle context with a null session");
    [stint resetTimer:nil]; Check([channel.method isEqualToString:@"reset"], @"Panel Reset requests the shared confirmation");
    [stint skipTimer:nil]; Check([channel.method isEqualToString:@"skip"], @"Panel Skip requests the shared confirmation");
    [stint confirmPending:nil]; Check([channel.method isEqualToString:@"confirm"], @"Panel confirms the shared pending action");
    [stint cancelPending:nil]; Check([channel.method isEqualToString:@"cancel"], @"Panel cancels the shared pending action");
    [stint openSettings:nil]; Check([channel.method isEqualToString:@"settings"] && stint.openedWindows == 1, @"Panel Settings opens the window and routes to Settings");
    [stint openProgress:nil]; Check([channel.method isEqualToString:@"progress"] && stint.openedWindows == 2, @"Panel Progress opens the window and routes to Progress");
    [stint openProfiles:nil]; Check([channel.method isEqualToString:@"profiles"], @"Profiles routes to the shared editor");
    [stint openContinuation:nil]; Check([channel.method isEqualToString:@"continuation"], @"Continuation routes to the shared editor");
    [stint openAmbient:nil]; Check([channel.method isEqualToString:@"ambient"], @"Mixer routes to the shared editor");
    NSMutableDictionary *flowState = [Snapshot(@"Focus", nil) mutableCopy];
    flowState[@"flowFocus"] = @YES; flowState[@"flowElapsedSeconds"] = @750;
    flowState[@"continuationNote"] = @"Next: fix the login redirect";
    flowState[@"running"] = @YES; flowState[@"sessionId"] = @"flow-session";
    flowState[@"cycleStep"] = @2;
    [stint update:flowState];
    Check(stint.flowFocus && stint.flowElapsedSeconds == 750 && stint.deadline == nil, @"Flow snapshot has elapsed time and no notification deadline");
    Check([stint.continuationNote isEqualToString:@"Next: fix the login redirect"], @"Continuation text reaches the native panel");
    [stint skipTimer:nil];
    Check([channel.method isEqualToString:@"finishFlow"] && [channel.arguments isEqual:@{@"sessionId": @"flow-session", @"cycleStep": @2}], @"Flow Take break carries session identity");
    [stint systemWillSleep:nil];
    Check([channel.method isEqualToString:@"systemWillSleep"], @"Sleep requests Flow pause");
    [stint update:Snapshot(@"Focus", nil)];
    NSUInteger sleepCalls = channel.calls;
    [stint systemWillSleep:nil];
    Check(channel.calls == sleepCalls, @"Sleep leaves Pomodoro deadline behavior intact");
    NSDictionary *context = @{@"sessionId": @"finished-session", @"cycleStep": @3};
    stint.ready = NO;
    [stint handleNotificationAction:@"stint.start-next" userInfo:context];
    Check([stint.pendingNotificationAction isEqual:context], @"Cold notification action waits for Dart readiness");
    [stint update:Snapshot(@"Short break", nil)];
    Check([channel.method isEqualToString:@"startNext"] && [channel.arguments isEqual:context] && !stint.pendingNotificationAction, @"First snapshot forwards the exact completion context once");
    NSUInteger calls = channel.calls;
    [stint handleNotificationAction:@"stint.start-next" userInfo:@{@"sessionId": @"", @"cycleStep": @3}];
    [stint handleNotificationAction:@"stint.start-next" userInfo:@{@"sessionId": @"old", @"cycleStep": @8}];
    Check(channel.calls == calls, @"Malformed notification context is not forwarded");
    [stint registerNotificationActions];
    NSMutableSet *actionTitles = [NSMutableSet set];
    NSMutableSet *categoryIdentifiers = [NSMutableSet set];
    for (UNNotificationCategory *category in center.categories) {
      [categoryIdentifiers addObject:category.identifier];
      Check(category.actions.count == 1, @"Each completion category has one primary system action");
      for (UNNotificationAction *action in category.actions) {
        [actionTitles addObject:action.title];
        Check([action.identifier isEqualToString:@"stint.start-next"], @"All system completion actions retain the validated start-next identifier");
      }
    }
    Check([actionTitles isEqualToSet:[NSSet setWithArray:@[@"Start focus", @"Start break", @"Start long break"]]], @"Notification categories offer the correct next-interval actions");
    Check([categoryIdentifiers isEqualToSet:[NSSet setWithArray:@[@"stint.start-focus", @"stint.start-break", @"stint.start-long-break"]]],
        @"Long breaks have a distinct system notification category");
    stint.phase = @"Focus"; stint.cycleStep = 6; stint.sessionId = @"focus-four";
    UNNotificationRequest *longBreak = [stint notificationForKey:@"copy" deadline:[NSDate dateWithTimeIntervalSinceNow:60] audible:NO];
    Check([longBreak.content.title isEqualToString:@"Four stints done"] && [longBreak.content.body isEqualToString:@"Your long break is ready. Take the full 15 minutes."], @"Fourth focus offers the long break in notification copy");
    Check([longBreak.content.userInfo[@"sessionId"] isEqualToString:@"focus-four"] && [longBreak.content.userInfo[@"cycleStep"] integerValue] == 7, @"Notification carries the finished session and offered step");
    stint.phase = @"Long break"; stint.cycleStep = 7;
    UNNotificationRequest *newCycle = [stint notificationForKey:@"copy" deadline:[NSDate dateWithTimeIntervalSinceNow:60] audible:NO];
    Check([newCycle.content.title isEqualToString:@"Break over"] && [newCycle.content.body isEqualToString:@"Focus 1 of 4 is ready when you are."], @"Long-break completion offers a new cycle");
    [(StintDefaultsProbe *)stint.alertDefaults setObject:@"Ping" forKey:StintAlertSoundPreference];
    stint.todayCount = 2; stint.dailyGoal = 8; stint.completionCount = @3;
    stint.phase = @"Focus";
    NSDate *today = [NSCalendar.currentCalendar startOfDayForDate:NSDate.date];
    NSDate *tomorrow = [NSCalendar.currentCalendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:today options:0];
    UNNotificationRequest *progressAlert = [stint notificationForKey:@"progress-copy" deadline:today audible:NO];
    Check([progressAlert.content.subtitle isEqualToString:@"3 of 8 today · Ping played twice"], @"Completion subtitle uses the selected sound and projected count without adding the focus twice");
    stint.phase = @"Short break";
    progressAlert = [stint notificationForKey:@"progress-copy" deadline:today audible:NO];
    Check([progressAlert.content.subtitle isEqualToString:@"3 of 8 today · Ping played twice"], @"Break completion does not increase the projected focus count");
    stint.completionCount = @5; stint.phase = @"Focus";
    progressAlert = [stint notificationForKey:@"progress-copy" deadline:tomorrow audible:NO];
    Check([progressAlert.content.subtitle isEqualToString:@"5 of 8 today · Ping played twice"], @"Cross-midnight notifications use history projected for the deadline's date");
    stint.completionCount = @0; stint.phase = @"Long break";
    progressAlert = [stint notificationForKey:@"progress-copy" deadline:tomorrow audible:NO];
    Check([progressAlert.content.subtitle isEqualToString:@"0 of 8 today · Ping played twice"], @"An explicit zero completion count is preserved after midnight");
    stint.completionCount = nil; stint.phase = @"Focus";
    progressAlert = [stint notificationForKey:@"legacy" deadline:today audible:NO];
    Check([progressAlert.content.subtitle isEqualToString:@"3 of 8 today · Ping played twice"], @"Older snapshots project one focus onto today's count");
    progressAlert = [stint notificationForKey:@"legacy" deadline:tomorrow audible:NO];
    Check([progressAlert.content.subtitle isEqualToString:@"1 of 8 today · Ping played twice"], @"Older snapshots reset the projected focus count across midnight");
    stint.phase = @"Short break";
    progressAlert = [stint notificationForKey:@"legacy" deadline:tomorrow audible:NO];
    Check([progressAlert.content.subtitle isEqualToString:@"0 of 8 today · Ping played twice"], @"Older snapshots do not count a break crossing midnight");
    NSUInteger requests = center.requests;
    [stint windowWillClose]; [stint windowWillClose];
    Check(stint.hints == 1 && [(StintDefaultsProbe *)stint.alertDefaults boolForKey:@"StintMenuBarHintShown"], @"First-close hint presents once and persists its Stint flag");
    Check(center.requests == requests && stint.chimes == 0, @"First-close hint never posts a system notification or plays sound");
    StintAlertProbe *restoredHint = [[StintAlertProbe alloc] init];
    restoredHint.alertDefaults = stint.alertDefaults;
    [restoredHint windowWillClose];
    Check(restoredHint.hints == 0, @"Once-only hint stays suppressed after creating a new native owner");

    stint.notifications = nil;
    [stint update:Snapshot(@"Focus", future)];
    stint.completionGate.deadline = NSDate.distantPast;
    NSMutableDictionary *jump = [Snapshot(@"Short break", nil) mutableCopy];
    jump[@"completedSessionId"] = NSNull.null;
    [stint update:jump];
    Check(stint.chimes == 0, @"A cycle jump at expiry cannot masquerade as completion");
    [stint update:Snapshot(@"Focus", future)];
    stint.completionGate.deadline = NSDate.distantPast;
    jump[@"completedSessionId"] = @"probe";
    jump[@"cycleStep"] = @1;
    jump[@"pendingAction"] = @{@"kind": @"reset", @"title": @"Reset this break?", @"confirmLabel": @"Reset"};
    [stint update:jump];
    Check(stint.chimes == 1 && stint.cycleStep == 1 && [stint.pendingAction[@"kind"] isEqualToString:@"reset"], @"Completion proof, cycle position, and shared confirmation arrive in one snapshot");

    StintNotificationProbe *progressCenter = [[StintNotificationProbe alloc] init];
    StintSchedulingProbe *scheduled = [[StintSchedulingProbe alloc] init];
    scheduled.notifications = (UNUserNotificationCenter *)progressCenter;
    scheduled.alertDefaults = (NSUserDefaults *)[[StintDefaultsProbe alloc] init];
    scheduled.completionGate = [[StintCompletionGate alloc] init];
    NSMutableDictionary *scheduledState = [Snapshot(@"Focus", future) mutableCopy];
    scheduledState[@"todayCount"] = @2; scheduledState[@"dailyGoal"] = @8; scheduledState[@"completionCount"] = @3;
    [scheduled update:scheduledState];
    NSString *scheduledIdentifier = progressCenter.lastRequest.identifier;
    Check(progressCenter.requests == 1 && [progressCenter.lastRequest.content.subtitle isEqualToString:@"3 of 8 today · Glass played twice"], @"Scheduling includes progress in the completion subtitle");
    [scheduled update:scheduledState];
    Check(progressCenter.requests == 1, @"Unchanged timer and progress do not reschedule notifications");
    scheduledState[@"dailyGoal"] = @10; [scheduled update:scheduledState];
    Check(progressCenter.requests == 2 && [progressCenter.lastRequest.identifier isEqualToString:scheduledIdentifier]
        && [progressCenter.lastRequest.content.subtitle isEqualToString:@"3 of 10 today · Glass played twice"], @"Changing the goal replaces the same pending notification");
    Check([scheduled.liveCompletionRequest.content.subtitle isEqualToString:@"3 of 10 today · Glass played twice"],
        @"Changing the goal also refreshes the cached live completion card");
    scheduledState[@"completionCount"] = @4; [scheduled update:scheduledState];
    Check(progressCenter.requests == 3 && [progressCenter.lastRequest.content.subtitle isEqualToString:@"4 of 10 today · Glass played twice"], @"Changed completion-day history refreshes the pending count");
    Call(scheduled, @"setAlertSound", @"Pop");
    Check(progressCenter.requests == 4 && [progressCenter.lastRequest.identifier isEqualToString:scheduledIdentifier]
        && [progressCenter.lastRequest.content.subtitle isEqualToString:@"4 of 10 today · Pop played twice"], @"Changing the alert sound refreshes the same pending subtitle");
    Check([scheduled.liveCompletionRequest.content.subtitle isEqualToString:@"4 of 10 today · Pop played twice"],
        @"Changing the selected alert sound updates the completion card's cached detail");

    StintNotificationProbe *rhythmCenter = [[StintNotificationProbe alloc] init];
    StintSchedulingProbe *rhythmSchedule = [[StintSchedulingProbe alloc] init];
    rhythmSchedule.notifications = (UNUserNotificationCenter *)rhythmCenter;
    rhythmSchedule.alertDefaults = (NSUserDefaults *)[[StintDefaultsProbe alloc] init];
    rhythmSchedule.completionGate = [[StintCompletionGate alloc] init];
    NSMutableDictionary *rhythmState = [fourthFocus mutableCopy];
    [rhythmSchedule update:rhythmState];
    NSString *rhythmIdentifier = rhythmCenter.lastRequest.identifier;
    Check([rhythmCenter.lastRequest.content.body isEqualToString:@"Your long break is ready. Take the full 15 minutes."],
        @"A fourth-focus deadline schedules the current long-break duration");
    rhythmState[@"longBreakMinutes"] = @30;
    [rhythmSchedule update:rhythmState];
    Check(rhythmCenter.requests == 2 && [rhythmCenter.lastRequest.identifier isEqualToString:rhythmIdentifier]
        && [rhythmCenter.lastRequest.content.body isEqualToString:@"Your long break is ready. Take the full 30 minutes."]
        && [rhythmSchedule.liveCompletionRequest.content.body isEqual:rhythmCenter.lastRequest.content.body],
        @"Editing the long break refreshes pending and live completion copy without changing the timer key or count");
    [rhythmSchedule update:rhythmState];
    Check(rhythmCenter.requests == 2, @"Unchanged rhythm durations do not repeatedly reschedule the deadline");
    rhythmState[@"dailyGoal"] = @4;
    [rhythmSchedule update:rhythmState];
    Check(rhythmCenter.requests == 3 && [rhythmCenter.lastRequest.content.title isEqualToString:@"Daily goal met"]
        && [rhythmCenter.lastRequest.content.subtitle isEqualToString:@"4 of 4 today"]
        && [rhythmSchedule.liveCompletionRequest.content.title isEqualToString:@"Daily goal met"],
        @"Changing the goal refreshes the scheduled and live goal-met variant at exactly the projected count");

    StintDefaultsProbe *defaults = [[StintDefaultsProbe alloc] init];
    StintSoundProbe *sounds = [[StintSoundProbe alloc] init];
    sounds.alertDefaults = (NSUserDefaults *)defaults;
    NSDictionary *settings = Call(sounds, @"getAlertSoundSettings", nil);
    Check([settings[@"selectedSound"] isEqualToString:@"Glass"], @"Glass is the default alert sound");
    Check([settings[@"sounds"] isEqualToArray:@[@"Glass", @"Ping", @"Pop", @"Funk", @"Submarine", @"Basso"]], @"Settings expose only the six supported sounds");
    settings = Call(sounds, @"setAlertSound", @"Ping");
    Check([settings[@"selectedSound"] isEqualToString:@"Ping"] && [defaults.values[StintAlertSoundPreference] isEqualToString:@"Ping"], @"Selection is persisted under the native preference key");
    Check(sounds.lastAudio == nil, @"Saving the choice does not preview it");
    Check([Call(sounds, @"previewAlertSound", @"Pop")[@"durationMilliseconds"] integerValue] == 2250, @"Preview reports the two-play duration including the gap");
    Check([sounds.lastSoundName isEqualToString:@"Pop"] && defaults.writes == 1, @"Preview plays the requested sound without saving it");
    [sounds testAlertSound:nil];
    Check([sounds.lastSoundName isEqualToString:@"Ping"], @"Menu test uses the saved sound");
    [sounds playCompletionSound];
    Check([sounds.lastSoundName isEqualToString:@"Ping"], @"Completion uses the saved sound");

    for (id invalid in @[@"glass", @"Unknown", @"../Glass", @"/System/Library/Sounds/Glass.aiff", @17, @{}, @[], NSNull.null]) {
      for (NSString *method in @[@"setAlertSound", @"previewAlertSound"]) {
        id error = Call(sounds, method, invalid);
        Check([error isKindOfClass:FlutterError.class] && [((FlutterError *)error).code isEqualToString:@"invalid_alert_sound"], @"Invalid names and argument types are rejected");
      }
    }
    Check(defaults.writes == 1 && [sounds.lastSoundName isEqualToString:@"Ping"], @"Invalid calls neither persist nor play");
    StintSoundProbe *restored = [[StintSoundProbe alloc] init];
    restored.alertDefaults = (NSUserDefaults *)defaults;
    Check([[restored alertSoundSettings][@"selectedSound"] isEqualToString:@"Ping"], @"New native instance restores the saved choice");
    [defaults setObject:@"obsolete" forKey:StintAlertSoundPreference];
    Check([[restored alertSoundSettings][@"selectedSound"] isEqualToString:@"Glass"], @"Unknown stored choice falls back to Glass");
    [defaults setObject:@[] forKey:StintAlertSoundPreference];
    Check([[restored alertSoundSettings][@"selectedSound"] isEqualToString:@"Glass"], @"Corrupt preference type falls back safely");

    Call(sounds, @"previewAlertSound", @"Basso");
    StintFakeSound *first = sounds.lastAudio;
    Check(first.plays == 1, @"Alert starts its first play immediately");
    [sounds sound:(NSSound *)first didFinishPlaying:YES];
    Pump(0.1);
    Check(first.plays == 1, @"Second play waits for the short gap");
    Pump(0.25);
    Check(first.plays == 2, @"First successful finish triggers the second play");
    [sounds sound:(NSSound *)first didFinishPlaying:YES];
    Pump(0.3);
    Check(first.plays == 2, @"Second finish does not loop");

    Call(sounds, @"previewAlertSound", @"Funk");
    StintFakeSound *replaced = sounds.lastAudio;
    [sounds sound:(NSSound *)replaced didFinishPlaying:YES];
    Pump(0.05);
    Call(sounds, @"previewAlertSound", @"Submarine");
    StintFakeSound *replacement = sounds.lastAudio;
    Pump(0.3);
    Check(replaced.plays == 1 && replacement.plays == 1, @"New preview cancels the old scheduled repeat");
    [sounds sound:(NSSound *)replaced didFinishPlaying:YES];
    Pump(0.3);
    Check(replacement.plays == 1, @"Stale sound callbacks cannot advance the replacement");
    [sounds sound:(NSSound *)replacement didFinishPlaying:NO];
    Pump(0.3);
    Check(replacement.plays == 1 && sounds.errors == 1, @"Playback failure reports an error without repeating");
    sounds.failNextPlay = YES;
    Call(sounds, @"previewAlertSound", @"Glass");
    Pump(0.3);
    Check(sounds.lastAudio.plays == 1 && sounds.errors == 2, @"Initial play failure does not retry");

    StintFakeSound *disposedAudio;
    __weak StintSoundProbe *weakDisposed;
    @autoreleasepool {
      StintSoundProbe *disposed = [[StintSoundProbe alloc] init];
      weakDisposed = disposed;
      [disposed playAlertSound:@"Pop"];
      disposedAudio = disposed.lastAudio;
      [disposed sound:(NSSound *)disposedAudio didFinishPlaying:YES];
      Pump(0.05);
    }
    Pump(0.3);
    Check(weakDisposed == nil && disposedAudio.plays == 1, @"Disposing the native owner cancels the scheduled repeat");
    sounds.cachedSoundName = @"stint-alert-Ping-v1.wav";
    UNNotificationRequest *pairedQuit = [sounds notificationForKey:@"sound-choice" deadline:[NSDate dateWithTimeIntervalSinceNow:60] audible:YES];
    Check(pairedQuit.content.sound != nil, @"Quit notification accepts the cached repeated sound");
    printf("Passed %lu completion alert checks.\n", (unsigned long)checks);
  }
  return 0;
}
