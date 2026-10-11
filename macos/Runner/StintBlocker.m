#import "StintBlocker.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "StintWebsiteBlocker.h"
#import "../HostsBlocker/StintBlockerPolicy.h"
#import <math.h>

static FlutterError *StintBlockerError(NSString *message) {
  return [FlutterError errorWithCode:@"blocker_failed" message:message details:nil];
}

static BOOL StintBlockerValidIdentifier(id value) {
  if (![value isKindOfClass:NSString.class] || [value length] == 0 || [value length] > 255) return NO;
  return [value rangeOfString:@"^[A-Za-z0-9][A-Za-z0-9-]*(\\.[A-Za-z0-9][A-Za-z0-9-]*)+$" options:NSRegularExpressionSearch].location != NSNotFound;
}

static BOOL StintBlockerProtectedIdentifier(NSString *identifier) {
  NSString *value = identifier.lowercaseString;
  // Keep the app, system recovery tools and browsers available. Browser sites
  // have an independent hosts helper with explicit administrator setup.
  return [@[@"io.github.albert2704.stint", @"com.apple.finder", @"com.apple.systempreferences",
    @"com.apple.systemsettings", @"com.apple.activitymonitor", @"com.apple.terminal",
    @"com.apple.loginwindow", @"com.apple.systemuiserver", @"com.apple.controlcenter",
    @"com.apple.securityagent", @"com.apple.keychainaccess", @"com.google.chrome",
    @"com.google.chrome.beta", @"com.google.chrome.dev", @"com.google.chrome.canary",
    @"com.microsoft.edgemac", @"com.microsoft.edgemac.beta", @"com.microsoft.edgemac.dev",
    @"com.microsoft.edgemac.canary"] containsObject:value] ||
    [value isEqualToString:NSBundle.mainBundle.bundleIdentifier.lowercaseString];
}

static NSArray<NSDictionary *> *StintBlockerApps(id value) {
  if (![value isKindOfClass:NSArray.class] || [value count] > 100) return nil;
  NSMutableArray *apps = [NSMutableArray array];
  NSMutableSet *seen = [NSMutableSet set];
  for (id item in value) {
    if (![item isKindOfClass:NSDictionary.class]) return nil;
    NSString *identifier = item[@"bundleId"], *name = item[@"name"];
    if (!StintBlockerValidIdentifier(identifier) || ![name isKindOfClass:NSString.class] || name.length == 0 || name.length > 200) return nil;
    NSString *key = identifier.lowercaseString;
    if (StintBlockerProtectedIdentifier(identifier) || [seen containsObject:key]) continue;
    [apps addObject:@{@"bundleId": identifier, @"name": name}];
    [seen addObject:key];
  }
  return apps;
}

@interface StintBlocker () <NSWindowDelegate>
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, strong) FlutterMethodChannel *channel;
@property(nonatomic, strong) id activationObserver;
@property(nonatomic, strong) id wakeObserver;
@property(nonatomic, strong) NSTimer *guardTimer;
@property(nonatomic, copy) NSArray<NSDictionary *> *apps;
@property(nonatomic, copy) NSArray<NSString *> *domains;
@property(nonatomic, strong) StintWebsiteBlocker *websiteBlocker;
@property(nonatomic, copy) NSString *sessionId;
@property(nonatomic, copy) NSString *appearance;
@property(nonatomic, copy) NSString *lastError;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL choosing;
@property(nonatomic) NSUInteger hideRequest;
@property(nonatomic) double deadlineMilliseconds;
@property(nonatomic) double leaseExpiresAt;
@property(nonatomic, strong) NSPanel *panel;
@property(nonatomic, strong) NSTextField *appLabel;
@property(nonatomic, strong) NSTextField *countdownLabel;
@property(nonatomic, strong) NSAlert *confirmation;
@property(nonatomic, strong) NSRunningApplication *lastAllowedApp;
@end

@implementation StintBlocker

- (instancetype)initWithWindow:(NSWindow *)window messenger:(id<FlutterBinaryMessenger>)messenger {
  self = [super init];
  if (!self) return nil;
  _window = window;
  _apps = @[];
  _domains = @[];
  _channel = [FlutterMethodChannel methodChannelWithName:@"stint/blocker" binaryMessenger:messenger];
  __weak StintBlocker *weakSelf = self;
  [_channel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    StintBlocker *self = weakSelf;
    if (!self) { result(StintBlockerError(@"Stint is closing.")); return; }
    [self handleCall:call result:result];
  }];
  NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
  _activationObserver = [center addObserverForName:NSWorkspaceDidActivateApplicationNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
    [weakSelf handleApplication:note.userInfo[NSWorkspaceApplicationKey]];
  }];
  _wakeObserver = [center addObserverForName:NSWorkspaceDidWakeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
    [weakSelf guardState];
    [weakSelf handleApplication:[weakSelf frontmostApplication]];
  }];
  _websiteBlocker = [[StintWebsiteBlocker alloc] init];
  _websiteBlocker.statusChanged = ^(NSDictionary *status) {
    [weakSelf.channel invokeMethod:@"filter" arguments:status];
  };
  return self;
}

- (void)dealloc {
  [_guardTimer invalidate];
  if (_activationObserver) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:_activationObserver];
  if (_wakeObserver) [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:_wakeObserver];
  [_websiteBlocker update:@{@"active": @NO}];
  [_channel setMethodCallHandler:nil];
  [_panel orderOut:nil];
}

- (double)nowMilliseconds { return NSDate.date.timeIntervalSince1970 * 1000; }
- (NSRunningApplication *)frontmostApplication { return NSWorkspace.sharedWorkspace.frontmostApplication; }

- (void)reportError:(NSString *)error {
  if ((!error && !self.lastError) || [error isEqualToString:self.lastError]) return;
  self.lastError = error;
  [self.channel invokeMethod:@"status" arguments:@{@"error": error ?: NSNull.null}];
}

- (void)releaseBlocking {
  self.active = NO;
  self.hideRequest++;
  [self.websiteBlocker update:@{@"active": @NO}];
  [self.guardTimer invalidate];
  self.guardTimer = nil;
  if (self.confirmation) {
    [self.panel endSheet:self.confirmation.window returnCode:NSModalResponseCancel];
    self.confirmation = nil;
  }
  [self.panel orderOut:nil];
}

- (BOOL)isEffective {
  double now = [self nowMilliseconds];
  return self.active && self.sessionId.length > 0 && self.deadlineMilliseconds > now && self.leaseExpiresAt > now;
}

- (void)guardState {
  if (![self isEffective]) { [self releaseBlocking]; return; }
  NSInteger seconds = (NSInteger)ceil(MAX(0, (self.deadlineMilliseconds - [self nowMilliseconds]) / 1000));
  self.countdownLabel.stringValue = [NSString stringWithFormat:@"%02ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
}

- (void)scheduleGuard {
  if (self.guardTimer) return;
  __weak StintBlocker *weakSelf = self;
  self.guardTimer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf guardState]; }];
  [NSRunLoop.mainRunLoop addTimer:self.guardTimer forMode:NSRunLoopCommonModes];
}

- (FlutterError *)update:(id)value {
  NSDictionary *args = [value isKindOfClass:NSDictionary.class] ? value : nil;
  id active = args[@"active"];
  if (![active isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)active) != CFBooleanGetTypeID()) {
    [self releaseBlocking];
    return StintBlockerError(@"Invalid blocker state. Blocking was released.");
  }
  if (![active boolValue]) {
    [self releaseBlocking];
    [self reportError:nil];
    return nil;
  }
  NSString *session = args[@"sessionId"];
  NSArray *apps = StintBlockerApps(args[@"apps"]);
  NSArray *domains = StintValidatedDomains(args[@"domains"] ?: @[]);
  id deadline = args[@"deadlineMilliseconds"], lease = args[@"leaseExpiresAt"];
  if (![session isKindOfClass:NSString.class] || !session.length || session.length > 200 || !apps || !domains ||
      ![deadline isKindOfClass:NSNumber.class] || ![lease isKindOfClass:NSNumber.class] ||
      !isfinite([deadline doubleValue]) || !isfinite([lease doubleValue])) {
    [self releaseBlocking];
    return StintBlockerError(@"Invalid blocker state. Blocking was released.");
  }
  BOOL refresh = ![self isEffective] || ![self.sessionId isEqualToString:session] || ![self.apps isEqualToArray:apps] || ![self.domains isEqualToArray:domains];
  if (refresh) self.hideRequest++;
  if (![self.sessionId isEqualToString:session]) [self releaseBlocking];
  else if (![self.apps isEqualToArray:apps] || ![self.domains isEqualToArray:domains]) {
    [self.panel orderOut:nil];
  }
  self.apps = apps;
  self.domains = domains;
  self.sessionId = session;
  self.deadlineMilliseconds = [deadline doubleValue];
  self.leaseExpiresAt = MIN(MIN([lease doubleValue], self.deadlineMilliseconds), [self nowMilliseconds] + 30000);
  self.appearance = [args[@"appearance"] isKindOfClass:NSString.class] ? args[@"appearance"] : @"system";
  self.active = YES;
  if (refresh) [self reportError:nil];
  [self applyAppearance];
  [self guardState];
  if ([self isEffective]) {
    [self scheduleGuard];
    if (refresh) [self handleApplication:[self frontmostApplication]];
  }
  return nil;
}

- (void)handleApplication:(NSRunningApplication *)application {
  if (!application || application.processIdentifier == NSProcessInfo.processInfo.processIdentifier) return;
  NSString *identifier = application.bundleIdentifier;
  NSDictionary *matched = nil;
  if (StintBlockerValidIdentifier(identifier) && !StintBlockerProtectedIdentifier(identifier)) {
    for (NSDictionary *app in self.apps) {
      if ([app[@"bundleId"] caseInsensitiveCompare:identifier] == NSOrderedSame) { matched = app; break; }
    }
  }
  if (![self isEffective]) { [self releaseBlocking]; return; }
  self.hideRequest++;
  if (!matched) { self.lastAllowedApp = application; return; }
  BOOL hidden = [application hide];
  [self showFocusForApp:matched[@"name"] hidden:hidden || application.hidden];
  [self scheduleHideCheck:application name:matched[@"name"] request:self.hideRequest session:self.sessionId];
}

- (void)completeHideCheck:(NSRunningApplication *)application name:(NSString *)name request:(NSUInteger)request session:(NSString *)session {
  if (![self isEffective] || request != self.hideRequest || ![session isEqualToString:self.sessionId]) return;
  BOOL hidden = application.hidden || application.terminated;
  [self reportError:hidden ? nil : [NSString stringWithFormat:@"Stint could not hide %@. You can close or switch away from it yourself.", name]];
  self.appLabel.stringValue = [NSString stringWithFormat:hidden ? @"%@ is taking a break." : @"Switch away from %@ to stay focused.", name];
}

- (void)scheduleHideCheck:(NSRunningApplication *)application name:(NSString *)name request:(NSUInteger)request session:(NSString *)session {
  // In a sandbox hide() can return NO even when the app becomes hidden on the
  // next event loop. Observe the outcome before reporting an error to the user.
  __weak StintBlocker *weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [weakSelf completeHideCheck:application name:name request:request session:session];
  });
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight {
  NSTextField *label = [NSTextField wrappingLabelWithString:text];
  label.font = [NSFont systemFontOfSize:size weight:weight];
  label.alignment = NSTextAlignmentCenter;
  label.translatesAutoresizingMaskIntoConstraints = NO;
  return label;
}

- (void)applyAppearance {
  self.panel.appearance = [self.appearance isEqualToString:@"dark"] ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] :
    ([self.appearance isEqualToString:@"light"] ? [NSAppearance appearanceNamed:NSAppearanceNameAqua] : nil);
}

- (void)makePanel {
  if (self.panel) return;
  self.panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 440, 350)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
  self.panel.title = @"Stint";
  self.panel.delegate = self;
  self.panel.releasedWhenClosed = NO;
  self.panel.hidesOnDeactivate = NO;
  self.panel.level = NSFloatingWindowLevel;
  self.panel.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary;
  NSView *view = self.panel.contentView;
  NSTextField *heading = [self label:@"A little space to focus" size:24 weight:NSFontWeightSemibold];
  self.appLabel = [self label:@"" size:14 weight:NSFontWeightRegular];
  self.appLabel.maximumNumberOfLines = 2;
  self.appLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  self.countdownLabel = [self label:@"00:00" size:44 weight:NSFontWeightMedium];
  self.countdownLabel.font = [NSFont monospacedDigitSystemFontOfSize:44 weight:NSFontWeightMedium];
  NSTextField *caption = [self label:@"Your app and its unsaved work are still there.\nBlocking ends when your focus timer stops." size:12 weight:NSFontWeightRegular];
  caption.textColor = NSColor.secondaryLabelColor;
  NSButton *back = [NSButton buttonWithTitle:@"Back to focus" target:self action:@selector(backToFocus:)];
  back.bezelStyle = NSBezelStyleRounded;
  back.keyEquivalent = @"\r";
  NSButton *unblock = [NSButton buttonWithTitle:@"Unblock this stint…" target:self action:@selector(requestUnblock:)];
  unblock.bezelStyle = NSBezelStyleRounded;
  NSStackView *buttons = [NSStackView stackViewWithViews:@[back, unblock]];
  buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  buttons.spacing = 12;
  buttons.translatesAutoresizingMaskIntoConstraints = NO;
  for (NSView *child in @[heading, self.appLabel, self.countdownLabel, caption, buttons]) [view addSubview:child];
  [NSLayoutConstraint activateConstraints:@[
    [heading.topAnchor constraintEqualToAnchor:view.topAnchor constant:28],
    [heading.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
    [self.appLabel.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:10],
    [self.appLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:24],
    [self.appLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-24],
    [self.countdownLabel.topAnchor constraintEqualToAnchor:self.appLabel.bottomAnchor constant:16],
    [self.countdownLabel.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
    [caption.topAnchor constraintEqualToAnchor:self.countdownLabel.bottomAnchor constant:12],
    [caption.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:24],
    [caption.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-24],
    [buttons.topAnchor constraintEqualToAnchor:caption.bottomAnchor constant:20],
    [buttons.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
  ]];
}

- (void)showFocusForApp:(NSString *)name hidden:(BOOL)hidden {
  [self makePanel];
  [self applyAppearance];
  self.appLabel.stringValue = [NSString stringWithFormat:hidden ? @"%@ is taking a break." : @"Switch away from %@ to stay focused.", name];
  [self guardState];
  if (![self isEffective]) return;
  if (!self.panel.visible) [self.panel center];
  [self.panel makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)backToFocus:(id)sender {
  (void)sender;
  [self.panel orderOut:nil];
  NSRunningApplication *previous = self.lastAllowedApp;
  if ([self isEffective]) {
    for (NSDictionary *app in self.apps) {
      if ([app[@"bundleId"] caseInsensitiveCompare:previous.bundleIdentifier ?: @""] == NSOrderedSame) { previous = nil; break; }
    }
  }
  if (previous && !previous.terminated && [previous activateWithOptions:NSApplicationActivateIgnoringOtherApps]) return;
  [self.window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)completeUnblockForSession:(NSString *)session confirmed:(BOOL)confirmed {
  if (!confirmed || ![self isEffective] || ![session isEqualToString:self.sessionId]) return;
  __weak StintBlocker *weakSelf = self;
  [self.channel invokeMethod:@"unblock" arguments:@{@"sessionId": session} result:^(id reply) {
    StintBlocker *self = weakSelf;
    if (![reply isKindOfClass:FlutterError.class] || ![self isEffective] || ![session isEqualToString:self.sessionId]) return;
    self.appLabel.stringValue = @"Could not unblock. Try again or pause the timer.";
  }];
}

- (void)requestUnblock:(id)sender {
  (void)sender;
  if (![self isEffective] || self.confirmation) return;
  NSString *session = self.sessionId;
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Unblock this stint?";
  alert.informativeText = @"Your selected apps and websites will be available for the rest of this focus interval, including after pausing and resuming.";
  [alert addButtonWithTitle:@"Keep focusing"];
  [alert addButtonWithTitle:@"Unblock this stint"];
  self.confirmation = alert;
  __weak StintBlocker *weakSelf = self;
  [alert beginSheetModalForWindow:self.panel completionHandler:^(NSModalResponse response) {
    StintBlocker *self = weakSelf;
    if (!self) return;
    if (self.confirmation == alert) self.confirmation = nil;
    [self completeUnblockForSession:session confirmed:response == NSAlertSecondButtonReturn];
  }];
}

- (void)chooseApps:(FlutterResult)result {
  if (self.choosing) { result(StintBlockerError(@"Finish the open file picker first.")); return; }
  self.choosing = YES;
  NSOpenPanel *picker = NSOpenPanel.openPanel;
  picker.title = @"Choose apps to block during focus";
  picker.message = @"Stint hides selected apps without quitting them. Browsers and recovery tools remain available.";
  picker.prompt = @"Add apps";
  picker.canChooseFiles = YES;
  picker.canChooseDirectories = NO;
  picker.allowsMultipleSelection = YES;
  picker.allowedContentTypes = @[UTTypeApplicationBundle];
  picker.directoryURL = [NSURL fileURLWithPath:@"/Applications" isDirectory:YES];
  __weak StintBlocker *weakSelf = self;
  [picker beginWithCompletionHandler:^(NSModalResponse response) {
    weakSelf.choosing = NO;
    if (response != NSModalResponseOK) { result(@[]); return; }
    NSMutableArray *apps = [NSMutableArray array];
    for (NSURL *url in picker.URLs) {
      NSBundle *bundle = [NSBundle bundleWithURL:url];
      NSString *identifier = bundle.bundleIdentifier;
      NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [bundle objectForInfoDictionaryKey:@"CFBundleName"];
      if (![name isKindOfClass:NSString.class] || !name.length) name = url.lastPathComponent.stringByDeletingPathExtension;
      if (!StintBlockerValidIdentifier(identifier) || StintBlockerProtectedIdentifier(identifier)) continue;
      if (name.length > 200) name = [name substringToIndex:200];
      [apps addObject:@{@"bundleId": identifier, @"name": name}];
      if (apps.count == 100) break;
    }
    result(StintBlockerApps(apps) ?: @[]);
  }];
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)handleCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"update"]) {
    FlutterError *error = [self update:call.arguments];
    [self.websiteBlocker update:error ? @{@"active": @NO} : call.arguments];
    result(error);
  }
  else if ([call.method isEqualToString:@"chooseApps"]) [self chooseApps:result];
  else if ([call.method isEqualToString:@"filterStatus"]) [self.websiteBlocker statusWithReply:^(NSDictionary *status) { result(status); }];
  else if ([call.method isEqualToString:@"enableFilter"]) [self.websiteBlocker enableWithReply:^(NSDictionary *status) { result(status); }];
  else if ([call.method isEqualToString:@"removeFilter"]) [self.websiteBlocker removeWithReply:^(NSDictionary *status) { result(status); }];
  else result(FlutterMethodNotImplemented);
}

@end
