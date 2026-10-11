// Opt-in real OS smoke test. Only the self-expiring fixture bundled with this
// probe is selected. All other apps, including the user's frontmost app, are safe.
#import <Cocoa/Cocoa.h>

#ifdef STINT_BLOCKER_FIXTURE
int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 120)
      styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.title = @"Stint temporary blocker test";
    NSTextField *label = [NSTextField labelWithString:@"Controlled fixture. Closes itself in 12 seconds."];
    label.frame = NSMakeRect(20, 45, 290, 40);
    [window.contentView addSubview:label];
    [window center];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [NSTimer scheduledTimerWithTimeInterval:12 repeats:NO block:^(__unused NSTimer *timer) { [NSApp terminate:nil]; }];
    [NSApp run];
  }
  return 0;
}
#else
#import "../macos/Runner/StintBlocker.m"

@interface SmokeMessenger : NSObject <FlutterBinaryMessenger>
@end
@implementation SmokeMessenger
- (void)sendOnChannel:(NSString *)channel message:(NSData *)message { (void)channel; (void)message; }
- (void)sendOnChannel:(NSString *)channel message:(NSData *)message binaryReply:(FlutterBinaryReply)callback {
  (void)channel; (void)message;
  if (callback) callback(nil);
}
- (FlutterBinaryMessengerConnection)setMessageHandlerOnChannel:(NSString *)channel binaryMessageHandler:(FlutterBinaryMessageHandler)handler {
  (void)channel; (void)handler; return 1;
}
- (void)cleanUpConnection:(FlutterBinaryMessengerConnection)connection { (void)connection; }
@end

@interface SmokeBlocker : StintBlocker
@property(nonatomic) NSUInteger hideAttempts;
@property(nonatomic) BOOL hideAccepted;
@property(nonatomic) NSUInteger hideChecks;
@end
@implementation SmokeBlocker
- (void)showFocusForApp:(NSString *)name hidden:(BOOL)hidden { (void)name; self.hideAttempts++; self.hideAccepted = hidden; }
- (void)completeHideCheck:(NSRunningApplication *)application name:(NSString *)name request:(NSUInteger)request session:(NSString *)session {
  [super completeHideCheck:application name:name request:request session:session];
  self.hideChecks++;
}
@end

static void SpinUntil(BOOL (^condition)(void), NSTimeInterval seconds) {
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while (!condition() && limit.timeIntervalSinceNow > 0) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  }
}

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSRunningApplication *previous = NSWorkspace.sharedWorkspace.frontmostApplication;
    SmokeMessenger *messenger = [[SmokeMessenger alloc] init];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 10, 10) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    SmokeBlocker *blocker = [[SmokeBlocker alloc] initWithWindow:window messenger:messenger];
    NSArray *apps = @[@{@"bundleId": @"io.github.albert2704.stint.blocker-fixture", @"name": @"Stint blocker fixture"}];
    double now = NSDate.date.timeIntervalSince1970 * 1000;
    [blocker update:@{@"active": @YES, @"sessionId": @"smoke", @"deadlineMilliseconds": @(now + 20000), @"leaseExpiresAt": @(now + 20000), @"apps": apps}];
    NSURL *fixtureURL = [NSBundle.mainBundle URLForResource:@"BlockerFixture" withExtension:@"app"];
    __block NSRunningApplication *fixture;
    __block NSError *launchError;
    __block BOOL launched = NO;
    NSWorkspaceOpenConfiguration *configuration = NSWorkspaceOpenConfiguration.configuration;
    configuration.activates = YES;
    configuration.createsNewApplicationInstance = YES;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:fixtureURL configuration:configuration completionHandler:^(NSRunningApplication *application, NSError *error) {
      fixture = application; launchError = error; launched = YES;
    }];
    SpinUntil(^BOOL { return launched && blocker.hideChecks > 0 && fixture.hidden; }, 5);
    BOOL first = fixture && fixture.hidden && !blocker.lastError;
    if (!first) fprintf(stderr, "Sandboxed activation/hide failed: %s (attempts=%lu, hidden=%d, launch=%s)\n", blocker.lastError.UTF8String ?: "no native error", (unsigned long)blocker.hideAttempts, fixture.hidden, launchError.localizedDescription.UTF8String ?: "ok");
    [blocker update:@{@"active": @NO}];
    NSUInteger before = blocker.hideAttempts;
    [fixture activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    SpinUntil(^BOOL { return fixture.active && !fixture.hidden; }, 2);
    BOOL pause = fixture.active && !fixture.hidden && blocker.hideAttempts == before;
    now = NSDate.date.timeIntervalSince1970 * 1000;
    NSUInteger previousChecks = blocker.hideChecks;
    [blocker update:@{@"active": @YES, @"sessionId": @"smoke-stable", @"deadlineMilliseconds": @(now + 20000), @"leaseExpiresAt": @(now + 20000), @"apps": apps}];
    SpinUntil(^BOOL { return fixture.hidden && blocker.hideChecks > previousChecks; }, 2);
    BOOL stable = fixture.hidden && blocker.hideAttempts > before && !blocker.lastError;
    fprintf(stdout, "Stable fixture: hide() accepted=%d, observed hidden=%d.\n", blocker.hideAccepted, fixture.hidden);
    [blocker update:@{@"active": @YES, @"sessionId": @"smoke-lease", @"deadlineMilliseconds": @(now + 20000), @"leaseExpiresAt": @(now + 400), @"apps": apps}];
    SpinUntil(^BOOL { return !blocker.active; }, 2);
    BOOL expiry = !blocker.active;
    before = blocker.hideAttempts;
    [fixture activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    SpinUntil(^BOOL { return fixture.active && !fixture.hidden; }, 2);
    expiry = expiry && fixture.active && !fixture.hidden && blocker.hideAttempts == before;
    [blocker update:@{@"active": @NO}];
    [fixture hide];
    if (previous && !previous.terminated) [previous activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    fprintf(stdout, "Sandboxed blocker smoke: activation/hide=%s stable-hide=%s pause=%s lease-expiry=%s. Fixture exits itself.\n", first ? "PASS" : "FAIL", stable ? "PASS" : "FAIL", pause ? "PASS" : "FAIL", expiry ? "PASS" : "FAIL");
    return first && stable && pause && expiry ? 0 : 1;
  }
}
#endif
