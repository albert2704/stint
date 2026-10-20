// The production state machine is exercised without observers, windows, app
// activation, or user data. Only controlled temporary files are modified.
#import "../macos/Runner/StintBlocker.m"

static NSUInteger checks;
static void Check(BOOL value, NSString *message) {
  if (!value) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
  checks++;
}

@interface BlockerApplicationProbe : NSObject
@property(nonatomic, copy) NSString *bundleIdentifier;
@property(nonatomic) pid_t processIdentifier;
@property(nonatomic) BOOL hideResult;
@property(nonatomic, getter=isHidden) BOOL hidden;
@property(nonatomic, getter=isTerminated) BOOL terminated;
@property(nonatomic) BOOL hidesDespiteFalseResult;
@property(nonatomic) NSUInteger hideCalls;
@property(nonatomic) NSUInteger activationCalls;
@property(nonatomic) NSApplicationActivationOptions activationOptions;
@property(nonatomic, copy) void (^activationHook)(void);
- (BOOL)hide;
- (BOOL)activateWithOptions:(NSApplicationActivationOptions)options;
@end
@implementation BlockerApplicationProbe
- (BOOL)hide { self.hideCalls++; self.hidden = self.hideResult || self.hidesDespiteFalseResult; return self.hideResult; }
- (BOOL)activateWithOptions:(NSApplicationActivationOptions)options {
  self.activationCalls++; self.activationOptions = options; self.hidden = NO;
  if (self.activationHook) self.activationHook();
  return YES;
}
@end

@interface BlockerChannelProbe : NSObject
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *calls;
@property(nonatomic, copy) FlutterResult pendingReply;
- (void)invokeMethod:(NSString *)method arguments:(id)arguments;
- (void)invokeMethod:(NSString *)method arguments:(id)arguments result:(FlutterResult)reply;
- (void)setMethodCallHandler:(id)handler;
@end
@implementation BlockerChannelProbe
- (void)invokeMethod:(NSString *)method arguments:(id)arguments { [self.calls addObject:@{@"method": method, @"arguments": arguments}]; }
- (void)invokeMethod:(NSString *)method arguments:(id)arguments result:(FlutterResult)reply {
  [self invokeMethod:method arguments:arguments]; self.pendingReply = reply;
}
- (void)setMethodCallHandler:(id)handler { (void)handler; }
@end

@interface BlockerLabelProbe : NSObject
@property(nonatomic, copy) NSString *stringValue;
@end
@implementation BlockerLabelProbe
@end

@interface BlockerWindowProbe : NSObject
@property(nonatomic) NSUInteger presentations;
- (void)makeKeyAndOrderFront:(id)sender;
@end
@implementation BlockerWindowProbe
- (void)makeKeyAndOrderFront:(id)sender { (void)sender; self.presentations++; }
@end

@interface BlockerProbe : StintBlocker
@property(nonatomic) double clock;
@property(nonatomic) NSUInteger presentations;
@property(nonatomic) BOOL lastHideResult;
@property(nonatomic, strong) NSRunningApplication *frontmost;
@end
@implementation BlockerProbe
- (double)nowMilliseconds { return self.clock; }
- (NSRunningApplication *)frontmostApplication { return self.frontmost; }
- (void)scheduleGuard {} // All time advances are explicit in the test.
- (void)showFocusForApp:(NSString *)name hidden:(BOOL)hidden { (void)name; self.presentations++; self.lastHideResult = hidden; }
- (void)scheduleHideCheck:(NSRunningApplication *)application name:(NSString *)name request:(NSUInteger)request session:(NSString *)session {
  [self completeHideCheck:application name:name request:request session:session];
}
@end

static NSDictionary *Snapshot(BOOL active, NSString *session, double deadline, double lease, NSArray *apps) {
  return @{@"active": @(active), @"sessionId": session, @"deadlineMilliseconds": @(deadline), @"leaseExpiresAt": @(lease), @"apps": apps, @"appearance": @"dark"};
}

static BlockerApplicationProbe *App(NSString *identifier) {
  BlockerApplicationProbe *app = [[BlockerApplicationProbe alloc] init];
  app.bundleIdentifier = identifier;
  app.processIdentifier = 123456;
  app.hideResult = YES;
  return app;
}

int main(void) {
  @autoreleasepool {
    NSDictionary *blocked = @{@"bundleId": @"org.example.Distraction", @"name": @"Distraction"};
    NSArray *apps = @[blocked];
    for (NSString *identifier in @[@"io.github.albert2704.stint", @"COM.APPLE.FINDER", @"com.apple.Terminal", @"com.apple.systempreferences", @"com.apple.ActivityMonitor", @"com.apple.loginwindow", @"com.google.Chrome", @"com.microsoft.edgemac", @"com.microsoft.edgemac.Beta"]) {
      Check(StintBlockerProtectedIdentifier(identifier), [@"protected: " stringByAppendingString:identifier]);
      Check(StintBlockerApps(@[@{@"bundleId": identifier, @"name": @"Recovery"}]).count == 0, @"protected apps removed from native input");
    }
    Check(!StintBlockerProtectedIdentifier(blocked[@"bundleId"]), @"ordinary app is selectable");
    Check(StintBlockerApps(@[blocked, @{@"bundleId": @"ORG.EXAMPLE.DISTRACTION", @"name": @"Duplicate"}]).count == 1, @"case insensitive deduplication");
    Check(!StintBlockerApps(@[@{@"bundleId": @"bad/id", @"name": @"Bad"}]), @"invalid identifier rejected");
    for (NSString *identifier in @[@"org..app", @".org.app", @"org.app.", @"org._app", @"org.-app", @"app"]) {
      Check(!StintBlockerValidIdentifier(identifier), @"malformed identifier segments rejected");
    }
    Check(!StintBlockerApps(@[@{@"bundleId": @"org.example.app", @"name": @17}]), @"invalid name rejected");
    Check(!StintBlockerApps(@[@"bad"]), @"malformed app rejected");
    NSMutableArray *tooMany = [NSMutableArray array];
    for (int index = 0; index < 101; index++) [tooMany addObject:blocked];
    Check(!StintBlockerApps(tooMany), @"oversized app list rejected");

    BlockerProbe *blocker = [[BlockerProbe alloc] init];
    blocker.clock = 100000;
    BlockerChannelProbe *channel = [[BlockerChannelProbe alloc] init];
    channel.calls = [NSMutableArray array];
    blocker.channel = (FlutterMethodChannel *)channel;
    BlockerApplicationProbe *distraction = App(blocked[@"bundleId"]);
    blocker.frontmost = (NSRunningApplication *)distraction;
    Check(![blocker update:Snapshot(YES, @"first", 200000, 120000, apps)], @"valid start accepted");
    Check(blocker.active && distraction.hideCalls == 1 && blocker.presentations == 1, @"starting protects already frontmost app");
    Check(blocker.lastHideResult && !blocker.lastError, @"successful hiding state");
    [blocker update:Snapshot(YES, @"first", 200000, 125000, apps)];
    Check(distraction.hideCalls == 1, @"heartbeat does not steal focus");
    [blocker handleApplication:(NSRunningApplication *)distraction];
    Check(distraction.hideCalls == 2, @"new blocked activation hides again");
    BlockerApplicationProbe *allowed = App(@"org.example.Editor");
    [blocker handleApplication:(NSRunningApplication *)allowed];
    Check(allowed.hideCalls == 0 && blocker.lastAllowedApp == (NSRunningApplication *)allowed, @"allowed app remains available");
    BlockerApplicationProbe *selfApp = App(@"org.example.Distraction");
    selfApp.processIdentifier = NSProcessInfo.processInfo.processIdentifier;
    [blocker handleApplication:(NSRunningApplication *)selfApp];
    Check(selfApp.hideCalls == 0, @"never hides current process even with unexpected bundle identifier");
    for (NSString *identifier in @[@"com.apple.finder", @"com.apple.Terminal", @"com.google.Chrome", @"com.microsoft.edgemac"]) {
      BlockerApplicationProbe *recovery = App(identifier);
      [blocker handleApplication:(NSRunningApplication *)recovery];
      Check(recovery.hideCalls == 0, @"recovery and supported browsers never hidden");
    }
    distraction.hideResult = NO;
    [blocker handleApplication:(NSRunningApplication *)distraction];
    Check(blocker.lastError.length > 0 && !blocker.lastHideResult, @"hide failure reaches visible status and focus panel");
    Check([channel.calls.lastObject[@"method"] isEqualToString:@"status"], @"hide failure reports native status");
    distraction.hidesDespiteFalseResult = YES;
    [blocker handleApplication:(NSRunningApplication *)distraction];
    Check(!blocker.lastError, @"observed hidden state handles false hide return from sandbox");
    distraction.hidesDespiteFalseResult = NO;
    distraction.hideResult = YES;
    [blocker handleApplication:(NSRunningApplication *)distraction];
    Check(!blocker.lastError && channel.calls.lastObject[@"arguments"][@"error"] == NSNull.null, @"successful retry clears error");
    distraction.hidden = NO;
    [blocker completeHideCheck:(NSRunningApplication *)distraction name:@"Distraction" request:blocker.hideRequest - 1 session:@"first"];
    Check(!blocker.lastError, @"late result from previous activation ignored");
    [blocker completeHideCheck:(NSRunningApplication *)distraction name:@"Distraction" request:blocker.hideRequest session:@"stale"];
    Check(!blocker.lastError, @"late result from previous session ignored");

    NSUInteger before = channel.calls.count;
    [blocker completeUnblockForSession:@"first" confirmed:NO];
    [blocker completeUnblockForSession:@"stale" confirmed:YES];
    Check(channel.calls.count == before, @"cancel and stale confirmations do not escape");
    [blocker completeUnblockForSession:@"first" confirmed:YES];
    Check(channel.calls.count == before + 1 && [channel.calls.lastObject[@"method"] isEqualToString:@"unblock"], @"confirmed current session requests escape");
    Check([channel.calls.lastObject[@"arguments"][@"sessionId"] isEqualToString:@"first"], @"escape bound to session identity");
    [blocker update:@{@"active": @NO}];
    Check(!blocker.active, @"pause releases even without other snapshot fields");
    NSUInteger hides = distraction.hideCalls;
    [blocker handleApplication:(NSRunningApplication *)distraction];
    Check(distraction.hideCalls == hides, @"inactive applications are untouched");
    [blocker completeUnblockForSession:@"first" confirmed:YES];
    Check(channel.calls.count == before + 1, @"released session cannot escape later");

    [blocker update:Snapshot(YES, @"second", 200000, 1000000, apps)];
    Check(blocker.leaseExpiresAt == 130000, @"lease independently capped to thirty seconds");
    blocker.clock = 130000;
    [blocker guardState];
    Check(!blocker.active, @"expired lease releases without Flutter update");
    [blocker update:Snapshot(YES, @"second", 135000, 160000, apps)];
    Check(blocker.leaseExpiresAt == 135000, @"lease never exceeds timer deadline");
    blocker.clock = 135000;
    [blocker handleApplication:(NSRunningApplication *)distraction];
    Check(!blocker.active, @"activation at expiry releases before hiding");
    Check(![blocker update:Snapshot(YES, @"third", 134000, 136000, apps)] && !blocker.active, @"past snapshot cannot reenable");
    Check([blocker update:@{@"active": @1}] != nil && !blocker.active, @"numeric nonboolean active rejected safely");
    Check([blocker update:Snapshot(YES, @"", 200000, 150000, apps)] != nil, @"empty session rejected");
    Check([blocker update:Snapshot(YES, @"fourth", INFINITY, 150000, apps)] != nil, @"nonfinite time rejected");
    Check([blocker update:Snapshot(YES, @"fourth", 200000, NAN, apps)] != nil, @"nonfinite lease rejected");
    Check([blocker update:NSNull.null] != nil && !blocker.active, @"malformed state fails open");
    [blocker update:Snapshot(YES, @"fifth", 200000, 150000, @[])];
    hides = distraction.hideCalls;
    [blocker handleApplication:(NSRunningApplication *)distraction];
    Check(distraction.hideCalls == hides, @"website only protection does not hide apps");

    BlockerProbe *flowProbe = [[BlockerProbe alloc] init];
    flowProbe.clock = 100000;
    BlockerLabelProbe *flowLabel = [[BlockerLabelProbe alloc] init];
    flowProbe.countdownLabel = (NSTextField *)flowLabel;
    NSMutableDictionary *flowState = [Snapshot(YES, @"flow", 130000, 130000, @[]) mutableCopy];
    flowState[@"flowFocus"] = @YES;
    [flowProbe update:flowState];
    Check([flowLabel.stringValue isEqualToString:@"Flow"], @"Flow guard never presents its recovery lease as focus time remaining");
    flowProbe.clock = 131000;
    [flowProbe guardState];
    Check(!flowProbe.active, @"Flow guard still releases when its lease expires");

    BlockerProbe *actions = [[BlockerProbe alloc] init];
    actions.clock = 100000;
    actions.channel = (FlutterMethodChannel *)channel;
    BlockerLabelProbe *label = [[BlockerLabelProbe alloc] init];
    label.stringValue = @"Focus";
    actions.appLabel = (NSTextField *)label;
    [actions update:Snapshot(YES, @"action", 200000, 120000, apps)];
    [actions completeUnblockForSession:@"action" confirmed:YES];
    FlutterError *saveFailure = [FlutterError errorWithCode:@"save_failed" message:@"Disk full" details:nil];
    channel.pendingReply(saveFailure);
    Check(actions.active && [label.stringValue isEqualToString:@"Could not unblock. Try again or pause the timer."], @"failed override is visible on focus panel and does not release protection");
    label.stringValue = @"New stint";
    [actions update:Snapshot(YES, @"next-action", 200000, 120000, apps)];
    channel.pendingReply(saveFailure);
    Check([label.stringValue isEqualToString:@"New stint"], @"stale failed override cannot overwrite new session panel");
    [actions completeUnblockForSession:@"next-action" confirmed:YES];
    [actions update:@{@"active": @NO}];
    channel.pendingReply(saveFailure);
    Check(!actions.active && [label.stringValue isEqualToString:@"New stint"], @"failed override arriving after release is ignored");

    BlockerWindowProbe *fallbackWindow = [[BlockerWindowProbe alloc] init];
    actions.window = (NSWindow *)fallbackWindow;
    actions.lastAllowedApp = (NSRunningApplication *)allowed;
    [actions update:Snapshot(YES, @"return", 200000, 120000, apps)];
    [actions backToFocus:nil];
    Check(allowed.activationCalls == 1 && fallbackWindow.presentations == 0, @"back to focus returns to a still allowed app");
    [actions update:Snapshot(YES, @"return", 200000, 120000, @[blocked, @{@"bundleId": allowed.bundleIdentifier, @"name": @"Editor"}])];
    [actions backToFocus:nil];
    Check(allowed.activationCalls == 1 && fallbackWindow.presentations == 1, @"back to focus uses Stint when previous app was newly blocked");



    printf("Native blocker: %lu checks passed (fake apps, lifecycle, recovery, confirmation and app guards).\n", (unsigned long)checks);
  }
  return 0;
}
