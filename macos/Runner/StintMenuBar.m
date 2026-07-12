#import "StintMenuBar.h"
#import "StintAlertSound.h"
#import "StintCompletionBanner.h"
#import "StintKeymap.h"
#import <UserNotifications/UserNotifications.h>
#import <math.h>
#import <CoreText/CoreText.h>
#import <QuartzCore/QuartzCore.h>

static NSString *const StintTimerNotificationPrefix = @"stint.timer-complete.";
static NSString *const StintAlertSoundPreference = @"StintAlertSound";

static NSArray<NSString *> *StintAlertSounds(void) {
  return @[@"Glass", @"Ping", @"Pop", @"Funk", @"Submarine", @"Basso"];
}

static NSString *StintNotificationIdentifier(NSString *key) {
  return [StintTimerNotificationPrefix stringByAppendingString:key];
}

// The native ticker and Dart's phase transition can arrive in either order.
// Only an interval observed before its deadline is eligible for a live chime.
@interface StintCompletionGate : NSObject
@property(nonatomic, copy) NSString *key;
@property(nonatomic, strong) NSDate *deadline;
@property(nonatomic, copy) NSString *phase;
@property(nonatomic, copy) NSString *routine;
@property(nonatomic) BOOL armed;
- (BOOL)observeKey:(NSString *)key deadline:(NSDate *)deadline phase:(NSString *)phase
           routine:(NSString *)routine idle:(BOOL)idle atTime:(NSDate *)now;
- (BOOL)consumeExpiryAtTime:(NSDate *)now;
@end

@implementation StintCompletionGate
- (BOOL)observeKey:(NSString *)key deadline:(NSDate *)deadline phase:(NSString *)phase
           routine:(NSString *)routine idle:(BOOL)idle atTime:(NSDate *)now {
  BOOL sameKey = self.key == key || [self.key isEqualToString:key];
  if (sameKey) {
    // Saving/deleting a routine can change its label without replacing the timer.
    self.phase = phase;
    self.routine = routine;
    return NO;
  }
  BOOL sameRoutine = self.routine == routine || [self.routine isEqualToString:routine];
  BOOL expectedPhase = [self.phase isEqualToString:@"Focus"]
      ? ([phase isEqualToString:@"Short break"] || [phase isEqualToString:@"Long break"])
      : (([self.phase isEqualToString:@"Short break"] || [self.phase isEqualToString:@"Long break"])
          && [phase isEqualToString:@"Focus"]);
  BOOL completed = self.armed && !key && idle && sameRoutine && expectedPhase
      && [self.deadline compare:now] != NSOrderedDescending;
  self.key = key;
  self.deadline = deadline;
  self.phase = phase;
  self.routine = routine;
  self.armed = key != nil && deadline != nil && [deadline compare:now] == NSOrderedDescending;
  return completed;
}
- (BOOL)consumeExpiryAtTime:(NSDate *)now {
  if (!self.armed || [self.deadline compare:now] == NSOrderedDescending) return NO;
  self.armed = NO;
  return YES;
}
@end

static void StintRegisterFonts(void) {
  NSURL *assets = [NSBundle.mainBundle.privateFrameworksURL URLByAppendingPathComponent:@"App.framework/Resources/flutter_assets/assets/fonts"];
  NSArray *paths = @[@"MartianMono/MartianMono-Light.ttf", @"MartianMono/MartianMono-Regular.ttf", @"MartianMono/MartianMono-Medium.ttf", @"HankenGrotesk/HankenGrotesk-Regular.ttf", @"HankenGrotesk/HankenGrotesk-Medium.ttf", @"HankenGrotesk/HankenGrotesk-SemiBold.ttf", @"HankenGrotesk/HankenGrotesk-Bold.ttf"];
  for (NSString *path in paths) {
    CFErrorRef error = NULL;
    CTFontManagerRegisterFontsForURL((__bridge CFURLRef)[assets URLByAppendingPathComponent:path], kCTFontManagerScopeProcess, &error);
    if (error) CFRelease(error);
  }
}

static NSFont *StintFont(BOOL mono, CGFloat size, NSInteger weight) {
  NSString *name = mono ? (weight <= 300 ? @"MartianMono-SemiExpandedLight" : weight >= 500 ? @"MartianMono-SemiExpandedMedium" : @"MartianMono-SemiExpanded")
      : (weight >= 700 ? @"HankenGrotesk-Bold" : weight >= 600 ? @"HankenGrotesk-SemiBold" : weight >= 500 ? @"HankenGrotesk-Medium" : @"HankenGrotesk-Regular");
  NSFontWeight fallback = weight <= 300 ? NSFontWeightLight : weight >= 600 ? NSFontWeightSemibold : weight >= 500 ? NSFontWeightMedium : NSFontWeightRegular;
  return [NSFont fontWithName:name size:size] ?: (mono ? [NSFont monospacedDigitSystemFontOfSize:size weight:fallback] : [NSFont systemFontOfSize:size weight:fallback]);
}

static NSColor *StintHex(NSUInteger rgb) {
  return [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}

@interface StintPanelView : NSView
@property(nonatomic, copy) void (^appearanceChanged)(void);
@end
@implementation StintPanelView
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; if (self.appearanceChanged) self.appearanceChanged(); }
@end

static NSString *StintDurationLabel(NSInteger seconds) {
  NSInteger minutes = seconds / 60, remainder = seconds % 60;
  NSString *minuteText = [NSString stringWithFormat:@"%ld %@", (long)minutes, minutes == 1 ? @"minute" : @"minutes"];
  if (!remainder) return minuteText;
  NSString *secondText = [NSString stringWithFormat:@"%ld %@", (long)remainder, remainder == 1 ? @"second" : @"seconds"];
  return minutes ? [NSString stringWithFormat:@"%@ %@", minuteText, secondText] : secondText;
}

static void StintUpdateFocusRing(NSControl *control, NSColor *accent, BOOL focused) {
  if (!control.layer) return;
  CALayer *ring = nil;
  for (CALayer *layer in control.layer.sublayers) if ([layer.name isEqualToString:@"stint.focus-ring"]) { ring = layer; break; }
  if (!ring) {
    ring = [CALayer layer]; ring.name = @"stint.focus-ring";
    ring.borderWidth = 2;
    ring.zPosition = 10;
    [control.layer addSublayer:ring];
  }
  [CATransaction begin]; [CATransaction setDisableActions:YES];
  ring.frame = CGRectInset(control.bounds, -4, -4);
  ring.cornerRadius = control.layer.cornerRadius + 4;
  ring.borderColor = (accent ?: NSColor.keyboardFocusIndicatorColor).CGColor;
  ring.hidden = !focused || !control.enabled;
  [CATransaction commit];
}

@interface StintPanelButton : NSButton
@property(nonatomic, strong) NSColor *focusAccent;
@end
@implementation StintPanelButton
- (instancetype)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) { self.wantsLayer = YES; self.layer.masksToBounds = NO; self.focusRingType = NSFocusRingTypeNone; }
  return self;
}
- (BOOL)acceptsFirstResponder { return self.enabled && !self.hidden; }
- (BOOL)becomeFirstResponder {
  BOOL accepted = [super becomeFirstResponder];
  StintUpdateFocusRing(self, self.focusAccent, accepted);
  return accepted;
}
- (BOOL)resignFirstResponder {
  BOOL resigned = [super resignFirstResponder];
  if (resigned) StintUpdateFocusRing(self, self.focusAccent, NO);
  return resigned;
}
- (void)setFocusAccent:(NSColor *)color { _focusAccent = color; StintUpdateFocusRing(self, color, self.window.firstResponder == self); }
- (void)layout { [super layout]; StintUpdateFocusRing(self, self.focusAccent, self.window.firstResponder == self); }
@end

@interface StintCycleButton : StintPanelButton
@property(nonatomic, strong) NSColor *trackColor;
@property(nonatomic, strong) NSColor *fillColor;
@property(nonatomic) double progress;
@property(nonatomic) BOOL current;
@end
@implementation StintCycleButton
- (void)drawRect:(NSRect)dirtyRect {
  CGFloat height = self.current ? 10 : 6;
  NSRect bar = NSMakeRect(0, (self.bounds.size.height - height) / 2, self.bounds.size.width, height);
  [self.trackColor setFill]; [[NSBezierPath bezierPathWithRoundedRect:bar xRadius:4 yRadius:4] fill];
  if (self.progress > 0) {
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRoundedRect:bar xRadius:4 yRadius:4] addClip];
    bar.size.width *= MIN(1, self.progress);
    [self.fillColor setFill]; NSRectFill(bar);
    [NSGraphicsContext restoreGraphicsState];
  }
}
@end

@interface StintMiniSlider : NSSlider
@property(nonatomic) BOOL tracking;
@property(nonatomic, strong) NSColor *focusAccent;
@end
@implementation StintMiniSlider
- (BOOL)acceptsFirstResponder { return self.enabled && !self.hidden; }
- (BOOL)becomeFirstResponder {
  BOOL accepted = [super becomeFirstResponder];
  StintUpdateFocusRing(self, self.focusAccent, accepted);
  return accepted;
}
- (BOOL)resignFirstResponder {
  BOOL resigned = [super resignFirstResponder];
  if (resigned) StintUpdateFocusRing(self, self.focusAccent, NO);
  return resigned;
}
- (void)setFocusAccent:(NSColor *)color { _focusAccent = color; StintUpdateFocusRing(self, color, self.window.firstResponder == self); }
- (void)layout { [super layout]; StintUpdateFocusRing(self, self.focusAccent, self.window.firstResponder == self); }
- (void)mouseDown:(NSEvent *)event {
  self.tracking = YES;
  [super mouseDown:event];
  self.tracking = NO;
}
@end

@interface StintMenuBar () <NSMenuDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate, NSSoundDelegate>
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, strong) FlutterMethodChannel *channel;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSTimer *ticker;
@property(nonatomic, strong) NSMenuItem *phaseItem;
@property(nonatomic, strong) NSMenuItem *toggleItem;
@property(nonatomic, strong) NSMenuItem *adjustItem;
@property(nonatomic, strong) NSMenuItem *notificationItem;
@property(nonatomic, strong) NSMenu *contextMenu;
@property(nonatomic, strong) NSMenuItem *miniMenuItem;
@property(nonatomic, strong) NSMenuItem *testSoundMenuItem;
@property(nonatomic, strong) NSMenuItem *previewNotificationMenuItem;
@property(nonatomic, strong) StintCompletionBanner *completionBanner;
@property(nonatomic, strong) StintKeymap *keymap;
@property(nonatomic, strong) UNNotificationRequest *liveCompletionRequest;
@property(nonatomic, copy) NSDictionary *completionCardContext;
@property(nonatomic, strong) StintCompletionGate *completionGate;
@property(nonatomic, strong) NSSound *completionSound;
@property(nonatomic, strong) NSUserDefaults *alertDefaults;
@property(nonatomic) NSUInteger soundPlaybackGeneration;
@property(nonatomic) NSUInteger remainingAlertPlays;
@property(nonatomic, strong) NSPopover *popover;
@property(nonatomic, strong) NSTextField *miniPhase;
@property(nonatomic, strong) NSTextField *miniTime;
@property(nonatomic, strong) NSTextField *miniStatus;
@property(nonatomic, strong) NSButton *miniToggle;
@property(nonatomic, strong) NSButton *miniReset;
@property(nonatomic, strong) NSButton *miniSkip;
@property(nonatomic, strong) NSButton *rhythmButton;
@property(nonatomic, strong) NSTextField *rhythmDigits;
@property(nonatomic, strong) NSTextField *soundTitle;
@property(nonatomic, strong) NSTextField *soundStatus;
@property(nonatomic, strong) NSTextField *volumeValue;
@property(nonatomic, strong) NSView *soundTile;
@property(nonatomic, strong) NSArray<NSView *> *equalizerBars;
@property(nonatomic, strong) NSArray<StintCycleButton *> *cycleButtons;
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *cycleWidthConstraints;
@property(nonatomic, strong) NSStackView *timerActions;
@property(nonatomic, strong) NSStackView *confirmBar;
@property(nonatomic, strong) NSTextField *confirmTitle;
@property(nonatomic, strong) NSTextField *confirmDetail;
@property(nonatomic, strong) NSButton *keepGoingButton;
@property(nonatomic, strong) NSButton *confirmButton;
@property(nonatomic, strong) NSArray<NSView *> *dividers;
@property(nonatomic, strong) NSButton *openButton;
@property(nonatomic, strong) NSButton *settingsButton;
@property(nonatomic, strong) NSButton *progressButton;
@property(nonatomic, strong) NSMenuItem *showPanelMenuItem;
@property(nonatomic, strong) NSMenuItem *settingsMenuItem;
@property(nonatomic, copy) NSDictionary *pendingAction;
@property(nonatomic, copy) NSString *announcedConfirmationTitle;
@property(nonatomic, copy) NSDictionary *pendingNotificationAction;
@property(nonatomic, copy) NSString *appearancePreference;
@property(nonatomic, copy) NSString *sessionId;
@property(nonatomic) NSInteger cycleStep;
@property(nonatomic) NSInteger focusMinutes;
@property(nonatomic) NSInteger shortBreakMinutes;
@property(nonatomic) NSInteger longBreakMinutes;
@property(nonatomic) NSInteger todayCount;
@property(nonatomic) NSInteger dailyGoal;
@property(nonatomic, strong) NSNumber *completionCount;
@property(nonatomic, strong) NSButton *musicButton;
@property(nonatomic, strong) StintMiniSlider *volumeSlider;
@property(nonatomic, strong) NSTextField *musicError;
@property(nonatomic, strong) NSView *youTubeContainer;
@property(nonatomic, strong) NSView *embeddedYouTubeView;
@property(nonatomic, strong) NSMutableSet<NSMenu *> *trackingMenus;
@property(nonatomic, copy) NSArray<NSDictionary *> *routines;
@property(nonatomic, copy) NSString *activeRoutineId;
@property(nonatomic, copy) NSDictionary *music;
@property(nonatomic) BOOL volumePending;
@property(nonatomic, strong) UNUserNotificationCenter *notifications;
@property(nonatomic, copy) NSString *phase;
@property(nonatomic, strong) NSDate *deadline;
@property(nonatomic, copy) NSString *notificationKey;
@property(nonatomic, copy) NSString *scheduledKey;
@property(nonatomic) NSInteger remaining;
@property(nonatomic) NSInteger totalSeconds;
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL running;
@property(nonatomic) BOOL hasProgress;
@property(nonatomic) BOOL requestedExpiryRefresh;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL authorizationKnown;
@property(nonatomic) UNAuthorizationStatus authorizationStatus;
@property(nonatomic) BOOL requestingAuthorization;
@property(nonatomic) BOOL reportedDenied;
@property(nonatomic) BOOL terminating;
@end

@implementation StintMenuBar

- (instancetype)initWithWindow:(NSWindow *)window messenger:(id<FlutterBinaryMessenger>)messenger {
  self = [super init];
  if (!self) return nil;
  _window = window;
  _phase = @"Focus";
  _focusMinutes = 25; _shortBreakMinutes = 5; _longBreakMinutes = 15;
  _dailyGoal = 8;
  StintRegisterFonts();
  _routines = @[];
  _completionGate = [[StintCompletionGate alloc] init];
  _alertDefaults = NSUserDefaults.standardUserDefaults;
  [self repeatedAlertSoundName];
  _trackingMenus = [NSMutableSet set];
  _notifications = UNUserNotificationCenter.currentNotificationCenter;
  // The host constructs this object before applicationDidFinishLaunching returns.
  _notifications.delegate = self;
  _channel = [FlutterMethodChannel methodChannelWithName:@"stint/timer" binaryMessenger:messenger];
  __weak StintMenuBar *weakSelf = self;
  [_channel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    StintMenuBar *self = weakSelf;
    if (!self) { result(nil); return; }
    [self handleCall:call result:result];
  }];

  _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
  _statusItem.button.font = StintFont(YES, 12, 500);
  NSImage *glyph = [NSImage imageNamed:@"StatusTemplate"];
  if (!glyph) glyph = [[NSImage alloc] initWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"StatusTemplate" withExtension:@"png"]];
  glyph.template = YES;
  glyph.size = NSMakeSize(18, 18);
  _statusItem.button.image = glyph ?: [NSImage imageWithSystemSymbolName:@"timer" accessibilityDescription:@"Stint"];
  _statusItem.button.imagePosition = NSImageLeft;
  _statusItem.button.title = @" --:--";
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Stint"];
  menu.autoenablesItems = NO;
  menu.delegate = self;
  _phaseItem = [self addItem:@"Opening Stint…" action:nil toMenu:menu];
  [menu addItem:NSMenuItem.separatorItem];
  _toggleItem = [self addItem:@"Start timer" action:@selector(toggleTimer:) toMenu:menu];
  _adjustItem = [self addItem:@"Settings…" action:@selector(openSettings:) toMenu:menu];
  [menu addItem:NSMenuItem.separatorItem];
  [self addItem:@"Open Stint" action:@selector(openWindow:) toMenu:menu];
  _notificationItem = [self addItem:@"Checking notifications…" action:@selector(notificationSettings:) toMenu:menu];
  [self addItem:@"Test alert sound" action:@selector(testAlertSound:) toMenu:menu];
  [self addItem:@"Preview notification" action:@selector(previewNotification:) toMenu:menu];
  [menu addItem:NSMenuItem.separatorItem];
  [self addItem:@"Quit Stint" action:@selector(quit:) toMenu:menu];
  _contextMenu = menu;
  _statusItem.button.target = self;
  _statusItem.button.action = @selector(statusItemClicked:);
  [_statusItem.button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
  [self createPopover];
  [self render];

  _ticker = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(__unused NSTimer *timer) { [weakSelf render]; }];
  [NSRunLoop.mainRunLoop addTimer:_ticker forMode:NSRunLoopCommonModes];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshFromSystem:) name:NSApplicationDidBecomeActiveNotification object:nil];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(installMiniTimerMenuItem:) name:NSApplicationDidFinishLaunchingNotification object:nil];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(prepareNotificationForTermination:) name:NSApplicationWillTerminateNotification object:nil];
  [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(refreshFromSystem:) name:NSWorkspaceDidWakeNotification object:nil];
  [self installMiniTimerMenuItem:nil];
  [self registerNotificationActions];
  _keymap = [[StintKeymap alloc] initWithDefaults:NSUserDefaults.standardUserDefaults action:^(NSString *action) {
    [weakSelf performShortcutAction:action];
  }];
  [self checkAuthorizationForGeneration:_generation];
  return self;
}

- (NSDictionary *)alertSoundSettings {
  id saved = [self.alertDefaults objectForKey:StintAlertSoundPreference];
  NSString *selected = [saved isKindOfClass:NSString.class] && [StintAlertSounds() containsObject:saved] ? saved : @"Glass";
  return @{@"selectedSound": selected, @"sounds": StintAlertSounds()};
}

- (NSString *)repeatedAlertSoundName {
  return StintRepeatedAlertSoundName([self alertSoundSettings][@"selectedSound"]);
}

- (void)handleCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([self.keymap handleCall:call result:result]) return;
  if ([call.method isEqualToString:@"getAlertSoundSettings"]) {
    result([self alertSoundSettings]);
  } else if ([call.method isEqualToString:@"setAlertSound"] || [call.method isEqualToString:@"previewAlertSound"]) {
    if (![call.arguments isKindOfClass:NSString.class] || ![StintAlertSounds() containsObject:call.arguments]) {
      result([FlutterError errorWithCode:@"invalid_alert_sound" message:@"Choose one of the available alert sounds." details:nil]);
      return;
    }
    if ([call.method isEqualToString:@"setAlertSound"]) {
      BOOL changed = ![[self alertSoundSettings][@"selectedSound"] isEqualToString:call.arguments];
      [self.alertDefaults setObject:call.arguments forKey:StintAlertSoundPreference];
      [self repeatedAlertSoundName];
      if (changed) [self refreshScheduledNotification];
      result([self alertSoundSettings]);
    } else {
      [self playAlertSound:call.arguments];
      result(@{@"durationMilliseconds": @((NSInteger)ceil((self.completionSound.duration * 2 + 0.25) * 1000))});
    }
  } else if ([call.method isEqualToString:@"update"]) {
    if (![call.arguments isKindOfClass:NSDictionary.class]) {
      result([FlutterError errorWithCode:@"invalid_timer" message:@"Missing timer state." details:nil]);
      return;
    }
    [self update:call.arguments];
    result(nil);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (NSMenuItem *)addItem:(NSString *)title action:(SEL)action toMenu:(NSMenu *)menu {
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
  item.target = self;
  item.enabled = action != nil;
  [menu addItem:item];
  return item;
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight {
  NSTextField *label = [NSTextField labelWithString:text];
  label.font = StintFont(NO, size, weight >= NSFontWeightSemibold ? 600 : weight >= NSFontWeightMedium ? 500 : 400);
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  return label;
}

- (NSButton *)button:(NSString *)title action:(SEL)action {
  NSButton *button = [StintPanelButton buttonWithTitle:title target:self action:action];
  button.bordered = NO;
  button.wantsLayer = YES;
  button.layer.cornerRadius = 18;
  button.font = StintFont(NO, 12, 600);
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.accessibilityLabel = title;
  button.toolTip = title;
  return button;
}

- (NSStackView *)row:(NSArray<NSView *> *)views {
  NSStackView *row = [NSStackView stackViewWithViews:views];
  row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  row.alignment = NSLayoutAttributeCenterY;
  row.distribution = NSStackViewDistributionFill;
  row.spacing = 10;
  row.translatesAutoresizingMaskIntoConstraints = NO;
  return row;
}

- (NSView *)separator {
  NSView *line = [[NSView alloc] init];
  line.wantsLayer = YES;
  line.translatesAutoresizingMaskIntoConstraints = NO;
  [line.heightAnchor constraintEqualToConstant:1].active = YES;
  return line;
}

- (void)createPopover {
  NSViewController *controller = [[NSViewController alloc] init];
  StintPanelView *panel = [[StintPanelView alloc] initWithFrame:NSMakeRect(0, 0, 340, 428)];
  panel.wantsLayer = YES;
  panel.layer.cornerRadius = 14;
  panel.layer.borderWidth = 1;
  panel.accessibilityLabel = @"Stint menu bar timer";
  controller.view = panel;
  self.popover = [[NSPopover alloc] init];
  self.popover.behavior = NSPopoverBehaviorTransient;
  self.popover.animates = NO;
  self.popover.delegate = self;
  self.popover.contentViewController = controller;
  self.popover.contentSize = NSMakeSize(340, 428);
  __weak StintMenuBar *weakSelf = self;
  panel.appearanceChanged = ^{ [weakSelf render]; };

  self.miniPhase = [self label:@"●  Focus · 1 of 4" size:11 weight:NSFontWeightSemibold];
  [self.miniPhase setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  self.rhythmButton = [self button:@"Classic ⌄" action:@selector(showRhythms:)];
  self.rhythmButton.alignment = NSTextAlignmentRight;
  self.rhythmDigits = [self label:@"25·5·15" size:10 weight:NSFontWeightRegular];
  self.rhythmDigits.font = StintFont(YES, 10, 400);
  self.rhythmDigits.alignment = NSTextAlignmentRight;
  NSStackView *rhythm = [NSStackView stackViewWithViews:@[self.rhythmButton, self.rhythmDigits]];
  rhythm.orientation = NSUserInterfaceLayoutOrientationVertical;
  rhythm.alignment = NSLayoutAttributeTrailing;
  rhythm.spacing = 0;
  [self.rhythmButton.heightAnchor constraintEqualToConstant:22].active = YES;
  NSStackView *heading = [self row:@[self.miniPhase, rhythm]];
  [heading.heightAnchor constraintEqualToConstant:36].active = YES;
  [rhythm.widthAnchor constraintLessThanOrEqualToConstant:155].active = YES;

  self.miniTime = [self label:@"--:--" size:52 weight:NSFontWeightLight];
  self.miniTime.font = StintFont(YES, 52, 300);
  self.miniTime.accessibilityLabel = @"Time remaining";
  [self.miniTime setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
  self.miniStatus = [NSTextField wrappingLabelWithString:@"Ready"];
  self.miniStatus.font = StintFont(NO, 12, 400);
  self.miniStatus.alignment = NSTextAlignmentRight;
  self.miniStatus.maximumNumberOfLines = 3;
  NSStackView *clock = [self row:@[self.miniTime, self.miniStatus]];
  [clock.heightAnchor constraintEqualToConstant:64].active = YES;

  NSMutableArray *segments = [NSMutableArray array];
  for (NSInteger i = 0; i < 8; i++) {
    StintCycleButton *segment = [[StintCycleButton alloc] init];
    segment.bordered = NO;
    segment.title = @"";
    segment.target = self;
    segment.action = @selector(jumpStep:);
    segment.tag = i;
    segment.translatesAutoresizingMaskIntoConstraints = NO;
    [segment.heightAnchor constraintEqualToConstant:24].active = YES;
    [segments addObject:segment];
  }
  self.cycleButtons = segments;
  NSStackView *cycle = [self row:segments];
  cycle.spacing = 5;
  [cycle.heightAnchor constraintEqualToConstant:24].active = YES;

  self.miniToggle = [self button:@"Start focus" action:@selector(toggleTimer:)];
  self.miniToggle.font = StintFont(NO, 14, 600);
  self.miniReset = [self button:@"" action:@selector(resetTimer:)];
  self.miniReset.image = [NSImage imageWithSystemSymbolName:@"arrow.counterclockwise" accessibilityDescription:@"Reset"];
  self.miniReset.accessibilityLabel = self.miniReset.toolTip = @"Reset";
  self.miniSkip = [self button:@"" action:@selector(skipTimer:)];
  self.miniSkip.image = [NSImage imageWithSystemSymbolName:@"forward.end.fill" accessibilityDescription:@"Skip to next"];
  self.miniSkip.accessibilityLabel = self.miniSkip.toolTip = @"Skip to next";
  self.timerActions = [self row:@[self.miniToggle, self.miniReset, self.miniSkip]];
  [self.timerActions.heightAnchor constraintEqualToConstant:44].active = YES;
  for (NSButton *button in @[self.miniToggle, self.miniReset, self.miniSkip]) {
    [button.heightAnchor constraintEqualToConstant:44].active = YES;
    button.layer.cornerRadius = 22;
  }
  [self.miniReset.widthAnchor constraintEqualToConstant:44].active = YES;
  [self.miniSkip.widthAnchor constraintEqualToConstant:44].active = YES;

  self.confirmTitle = [self label:@"" size:14 weight:NSFontWeightSemibold];
  self.confirmDetail = [self label:@"" size:12 weight:NSFontWeightRegular];
  self.keepGoingButton = [self button:@"Keep going" action:@selector(cancelPending:)];
  self.confirmButton = [self button:@"Switch" action:@selector(confirmPending:)];
  NSStackView *confirmActions = [self row:@[self.keepGoingButton, self.confirmButton]];
  confirmActions.distribution = NSStackViewDistributionFillEqually;
  for (NSButton *button in @[self.keepGoingButton, self.confirmButton]) [button.heightAnchor constraintEqualToConstant:36].active = YES;
  self.confirmBar = [NSStackView stackViewWithViews:@[self.confirmTitle, self.confirmDetail, confirmActions]];
  self.confirmBar.orientation = NSUserInterfaceLayoutOrientationVertical;
  self.confirmBar.alignment = NSLayoutAttributeLeading;
  self.confirmBar.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);
  self.confirmBar.spacing = 8;
  self.confirmBar.wantsLayer = YES;
  self.confirmBar.layer.cornerRadius = 14;
  self.confirmBar.layer.borderWidth = 1;
  self.confirmBar.hidden = YES;
  [confirmActions.widthAnchor constraintEqualToAnchor:self.confirmBar.widthAnchor constant:-24].active = YES;

  self.soundTile = [[NSView alloc] init];
  self.soundTile.wantsLayer = YES;
  self.soundTile.layer.cornerRadius = 10;
  self.soundTile.accessibilityElement = NO;
  [self.soundTile.widthAnchor constraintEqualToConstant:36].active = YES;
  [self.soundTile.heightAnchor constraintEqualToConstant:36].active = YES;
  NSMutableArray *bars = [NSMutableArray array];
  for (NSInteger i = 0; i < 3; i++) {
    NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(9 + i * 7, 10, 4, 16)];
    bar.wantsLayer = YES;
    bar.layer.cornerRadius = 2;
    bar.accessibilityElement = NO;
    [self.soundTile addSubview:bar];
    [bars addObject:bar];
  }
  self.equalizerBars = bars;
  self.soundTitle = [self label:@"Choose a sound" size:13 weight:NSFontWeightSemibold];
  self.soundStatus = [self label:@"Paused" size:12 weight:NSFontWeightRegular];
  NSStackView *soundText = [NSStackView stackViewWithViews:@[self.soundTitle, self.soundStatus]];
  soundText.orientation = NSUserInterfaceLayoutOrientationVertical;
  soundText.alignment = NSLayoutAttributeLeading;
  soundText.spacing = 3;
  [soundText setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  self.musicButton = [self button:@"" action:@selector(toggleMusic:)];
  [self.musicButton.widthAnchor constraintEqualToConstant:40].active = YES;
  [self.musicButton.heightAnchor constraintEqualToConstant:40].active = YES;
  self.musicButton.layer.cornerRadius = 20;
  NSStackView *sound = [self row:@[self.soundTile, soundText, self.musicButton]];
  [sound.heightAnchor constraintEqualToConstant:40].active = YES;
  [self.soundTitle.widthAnchor constraintLessThanOrEqualToConstant:212].active = YES;
  self.volumeSlider = [[StintMiniSlider alloc] init];
  self.volumeSlider.wantsLayer = YES;
  self.volumeSlider.layer.masksToBounds = NO;
  self.volumeSlider.layer.cornerRadius = 4;
  self.volumeSlider.focusRingType = NSFocusRingTypeNone;
  self.volumeSlider.minValue = 0; self.volumeSlider.maxValue = 1;
  self.volumeSlider.doubleValue = 0.35;
  self.volumeSlider.continuous = NO;
  self.volumeSlider.target = self;
  self.volumeSlider.action = @selector(changeVolume:);
  self.volumeSlider.accessibilityLabel = self.volumeSlider.toolTip = @"Volume";
  self.volumeValue = [self label:@"35%" size:11 weight:NSFontWeightRegular];
  self.volumeValue.font = StintFont(YES, 11, 400);
  self.volumeValue.alignment = NSTextAlignmentRight;
  [self.volumeValue.widthAnchor constraintEqualToConstant:42].active = YES;
  NSTextField *volumeLabel = [self label:@"Volume" size:11 weight:NSFontWeightRegular];
  NSStackView *volume = [self row:@[volumeLabel, self.volumeSlider, self.volumeValue]];
  [volume.heightAnchor constraintEqualToConstant:36].active = YES;
  self.youTubeContainer = [[NSView alloc] init];
  self.youTubeContainer.translatesAutoresizingMaskIntoConstraints = NO;
  self.youTubeContainer.hidden = YES;
  // The player's 38-point status row leaves a 200-point video viewport.
  [self.youTubeContainer.heightAnchor constraintEqualToConstant:238].active = YES;
  self.musicError = [NSTextField wrappingLabelWithString:@""];
  self.musicError.font = StintFont(NO, 11, 400);
  self.musicError.maximumNumberOfLines = 2;
  self.musicError.hidden = YES;
  self.openButton = [self button:@"Open Stint  ⌘⇧M" action:@selector(openWindow:)];
  self.openButton.alignment = NSTextAlignmentLeft;
  self.settingsButton = [self button:@"Settings…" action:@selector(openSettings:)];
  self.settingsButton.alignment = NSTextAlignmentRight;
  self.progressButton = [self button:@"Progress" action:@selector(openProgress:)];
  NSStackView *footer = [self row:@[self.openButton, self.progressButton, self.settingsButton]];
  footer.distribution = NSStackViewDistributionEqualSpacing;
  for (NSButton *button in @[self.openButton, self.progressButton, self.settingsButton]) [button.heightAnchor constraintEqualToConstant:36].active = YES;
  NSView *divider1 = [self separator], *divider2 = [self separator];
  self.dividers = @[divider1, divider2];
  NSArray<NSView *> *views = @[heading, clock, cycle, self.timerActions, self.confirmBar, divider1, sound, volume, self.youTubeContainer, self.musicError, divider2, footer];
  NSStackView *stack = [NSStackView stackViewWithViews:views];
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = 14;
  stack.detachesHiddenViews = YES;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  [panel addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
    [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16],
    [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:16],
    [stack.bottomAnchor constraintLessThanOrEqualToAnchor:panel.bottomAnchor constant:-16]
  ]];
  for (NSView *view in views) [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
}

- (void)statusItemClicked:(id)sender {
  NSEvent *event = NSApp.currentEvent;
  if (event.type == NSEventTypeRightMouseUp || (event.modifierFlags & NSEventModifierFlagControl)) {
    [self.popover close];
    [self.contextMenu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSMaxY(self.statusItem.button.bounds)) inView:self.statusItem.button];
    return;
  }
  if (self.popover.shown) { [self.popover close]; return; }
  [self showMiniTimer:sender];
}

- (void)showMiniTimer:(id)sender {
  [self.completionBanner setTemporarilyHidden:YES];
  [self.channel invokeMethod:@"refresh" arguments:nil];
  [self render];
  // Activating the app also raises its main window. Only the panel needs focus.
  if (!self.popover.shown) [self.popover showRelativeToRect:self.statusItem.button.bounds ofView:self.statusItem.button preferredEdge:NSRectEdgeMinY];
  [self.popover.contentViewController.view.window makeKeyWindow];
}

- (void)setYouTubeView:(NSView *)view {
  if (self.embeddedYouTubeView == view) return;
  [self.embeddedYouTubeView removeFromSuperview];
  self.embeddedYouTubeView = view;
  self.youTubeContainer.hidden = view == nil;
  if (view) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.youTubeContainer addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
      [view.leadingAnchor constraintEqualToAnchor:self.youTubeContainer.leadingAnchor],
      [view.trailingAnchor constraintEqualToAnchor:self.youTubeContainer.trailingAnchor],
      [view.topAnchor constraintEqualToAnchor:self.youTubeContainer.topAnchor],
      [view.bottomAnchor constraintEqualToAnchor:self.youTubeContainer.bottomAnchor]
    ]];
  }
  [self render];
  if (self.youTubeVisibilityChanged) self.youTubeVisibilityChanged(view != nil && self.popover.shown);
}

- (void)showYouTubePlayer { [self showMiniTimer:nil]; }

- (void)popoverDidShow:(NSNotification *)notification {
  [self.completionBanner setTemporarilyHidden:YES];
  if (self.youTubeVisibilityChanged) self.youTubeVisibilityChanged(self.embeddedYouTubeView != nil);
}

- (void)popoverDidClose:(NSNotification *)notification {
  [self.completionBanner setTemporarilyHidden:NO];
  if (self.youTubeVisibilityChanged) self.youTubeVisibilityChanged(NO);
}

- (void)installMiniTimerMenuItem:(NSNotification *)notification {
  NSMenu *appMenu = NSApp.mainMenu.itemArray.firstObject.submenu;
  if (!appMenu) return;
  for (NSMenuItem *item in appMenu.itemArray) {
    if ([item.keyEquivalent isEqualToString:@","]) { self.settingsMenuItem = item; item.title = @"Settings…"; item.target = self; item.action = @selector(openSettings:); }
    if ([item.identifier isEqualToString:@"stint.show-mini-timer"]) {
      self.miniMenuItem = item;
      item.target = self;
      item.title = @"Open Stint";
      item.action = @selector(openWindow:);
    } else if ([item.identifier isEqualToString:@"stint.test-alert-sound"]) {
      self.testSoundMenuItem = item;
      item.target = self;
      item.action = @selector(testAlertSound:);
    }
  }
  if (self.miniMenuItem.menu != appMenu) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Open Stint" action:@selector(openWindow:) keyEquivalent:@"m"];
    item.identifier = @"stint.show-mini-timer";
    item.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    item.target = self;
    [appMenu insertItem:item atIndex:MIN(2, appMenu.numberOfItems)];
    self.miniMenuItem = item;
  }
  if (self.testSoundMenuItem.menu != appMenu) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Test alert sound" action:@selector(testAlertSound:) keyEquivalent:@""];
    item.identifier = @"stint.test-alert-sound";
    item.target = self;
    [appMenu insertItem:item atIndex:[appMenu indexOfItem:self.miniMenuItem] + 1];
    self.testSoundMenuItem = item;
  }
  if (self.previewNotificationMenuItem.menu != appMenu) {
    self.previewNotificationMenuItem = [self addItem:@"Preview notification" action:@selector(previewNotification:) toMenu:appMenu];
  }
  if (!self.settingsMenuItem) {
    self.settingsMenuItem = [self addItem:@"Settings…" action:@selector(openSettings:) toMenu:appMenu];
    self.settingsMenuItem.keyEquivalent = @",";
  }
  if (self.showPanelMenuItem.menu != appMenu) {
    self.showPanelMenuItem = [self addItem:@"Show menu bar panel" action:@selector(showMiniTimer:) toMenu:appMenu];
  }
}

- (NSArray<NSDictionary *> *)entries:(id)value titleKey:(NSString *)titleKey {
  NSMutableArray *entries = [NSMutableArray array];
  NSMutableSet *ids = [NSMutableSet set];
  if (![value isKindOfClass:NSArray.class]) return entries;
  for (id entry in value) {
    if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"id"] isKindOfClass:NSString.class] || ![entry[titleKey] isKindOfClass:NSString.class] || [ids containsObject:entry[@"id"]]) continue;
    [entries addObject:entry]; [ids addObject:entry[@"id"]];
  }
  return entries;
}

- (NSColor *)color:(NSString *)token {
  BOOL dark = [[self.popover.contentViewController.view.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]] isEqualToString:NSAppearanceNameDarkAqua];
  NSDictionary *colors = dark
      ? @{@"surface": @0x1A1B1F, @"raised": @0x222429, @"line": @0x2C2F35, @"line2": @0x3A3D44, @"track": @0x2C2F35, @"ink": @0xEDEBE6, @"ink2": @0xC9C8C3, @"muted": @0x9C9FA6, @"focus": @0xF2893B, @"focusText": @0xF2893B, @"break": @0x6CB4EE, @"breakText": @0x6CB4EE, @"onAccent": @0x16110C, @"error": @0xFF8A80}
      : @{@"surface": @0xFFFFFF, @"raised": @0xECEBE7, @"line": @0xDEDCD6, @"line2": @0xC9C7C0, @"track": @0xE2E0DA, @"ink": @0x17181B, @"ink2": @0x3A3C41, @"muted": @0x5E6168, @"focus": @0xEE7F2D, @"focusText": @0xA84E0B, @"break": @0x4A9FE0, @"breakText": @0x1F5F94, @"onAccent": @0x1A0F05, @"error": @0xB3261E};
  return StintHex([colors[token] unsignedIntegerValue]);
}

- (void)styleButton:(NSButton *)button fill:(NSColor *)fill text:(NSColor *)text {
  button.layer.backgroundColor = fill.CGColor;
  if ([button isKindOfClass:StintPanelButton.class]) ((StintPanelButton *)button).focusAccent = [self color:[self.phase isEqualToString:@"Focus"] ? @"focus" : @"break"];
  button.contentTintColor = text;
  NSDictionary *attributes = @{NSFontAttributeName: button.font ?: StintFont(NO, 12, 600), NSForegroundColorAttributeName: text};
  NSAttributedString *title = [[NSAttributedString alloc] initWithString:button.title attributes:attributes];
  if (button == self.miniToggle && button.image) {
    // One attributed title keeps the symbol and label centered as a unit.
    NSImage *symbol = button.image;
    NSImage *tinted = [NSImage imageWithSize:NSMakeSize(14, 14) flipped:NO drawingHandler:^BOOL(NSRect rect) {
      [symbol drawInRect:rect];
      [text setFill];
      NSRectFillUsingOperation(rect, NSCompositingOperationSourceIn);
      return YES;
    }];
    NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
    attachment.image = tinted;
    attachment.bounds = NSMakeRect(0, -2, 14, 14);
    NSMutableAttributedString *group = [[NSAttributedString attributedStringWithAttachment:attachment] mutableCopy];
    [group appendAttributedString:[[NSAttributedString alloc] initWithString:@"  " attributes:attributes]];
    [group appendAttributedString:title];
    button.image = nil;
    button.imagePosition = NSNoImage;
    button.alignment = NSTextAlignmentCenter;
    title = group;
  }
  button.attributedTitle = title;
}

- (void)renderPopoverWithTime:(NSString *)time status:(NSString *)status {
  if (!self.popover) return;
  NSAppearance *appearance = [self.appearancePreference isEqualToString:@"dark"] ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]
      : [self.appearancePreference isEqualToString:@"light"] ? [NSAppearance appearanceNamed:NSAppearanceNameAqua] : nil;
  if (![self.popover.appearance.name isEqualToString:appearance.name] && (self.popover.appearance || appearance)) self.popover.appearance = appearance;
  if (![self.window.appearance.name isEqualToString:appearance.name] && (self.window.appearance || appearance)) self.window.appearance = appearance;
  NSView *panel = self.popover.contentViewController.view;
  NSColor *surface = [self color:@"surface"], *raised = [self color:@"raised"], *ink = [self color:@"ink"], *muted = [self color:@"muted"];
  BOOL focus = [self.phase isEqualToString:@"Focus"];
  NSColor *accent = [self color:focus ? @"focus" : @"break"];
  panel.layer.backgroundColor = surface.CGColor;
  panel.layer.borderColor = [self color:@"line2"].CGColor;
  self.miniPhase.stringValue = focus ? [NSString stringWithFormat:@"●  Focus · %ld of 4", (long)(self.cycleStep / 2 + 1)] : [@"●  " stringByAppendingString:self.phase];
  self.miniPhase.textColor = [self color:focus ? @"focusText" : @"breakText"];
  NSString *rhythmName = @"Custom";
  for (NSDictionary *routine in [self entries:self.routines titleKey:@"name"]) if ([routine[@"id"] isEqual:self.activeRoutineId]) { rhythmName = routine[@"name"]; break; }
  self.rhythmButton.title = [rhythmName stringByAppendingString:@" ⌄"];
  self.rhythmButton.accessibilityLabel = [@"Rhythms, " stringByAppendingString:rhythmName];
  self.rhythmButton.enabled = self.ready;
  self.rhythmDigits.stringValue = [NSString stringWithFormat:@"%ld·%ld·%ld", (long)self.focusMinutes, (long)self.shortBreakMinutes, (long)self.longBreakMinutes];
  self.rhythmDigits.textColor = muted;
  [self styleButton:self.rhythmButton fill:NSColor.clearColor text:ink];
  self.miniTime.stringValue = time;
  self.miniTime.accessibilityValue = time;
  self.miniTime.textColor = ink;
  NSString *detail = self.running ? @"Running" : self.hasProgress ? @"Paused" : @"Ready";
  if (self.deadline) {
    NSString *finish = [NSDateFormatter localizedStringFromDate:self.deadline dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle];
    detail = [NSString stringWithFormat:focus ? @"Ends at %@" : @"Back at %@", finish];
  }
  if (![self.miniStatus.stringValue isEqualToString:detail]) {
    self.miniStatus.stringValue = detail;
    NSAccessibilityPostNotification(self.miniStatus, NSAccessibilityValueChangedNotification);
  }
  self.miniStatus.textColor = muted;
  self.miniToggle.title = self.running ? @"Pause" : self.hasProgress ? @"Resume" : focus ? @"Start focus" : @"Start break";
  self.miniToggle.image = [NSImage imageWithSystemSymbolName:self.running ? @"pause.fill" : @"play.fill" accessibilityDescription:nil];
  self.miniToggle.imagePosition = NSImageLeft;
  self.miniToggle.accessibilityLabel = self.miniToggle.toolTip = self.miniToggle.title;
  for (NSButton *button in @[self.miniToggle, self.miniReset, self.miniSkip]) button.enabled = self.ready;
  [self styleButton:self.miniToggle fill:accent text:[self color:@"onAccent"]];
  for (NSButton *button in @[self.miniReset, self.miniSkip]) [self styleButton:button fill:raised text:[self color:@"ink2"]];
  BOOL confirming = self.pendingAction != nil;
  self.timerActions.hidden = confirming;
  self.confirmBar.hidden = !confirming;
  if (confirming) {
    NSString *title = [self.pendingAction[@"title"] isKindOfClass:NSString.class] ? self.pendingAction[@"title"] : @"Switch interval?";
    BOOL newlyShown = self.announcedConfirmationTitle == nil;
    self.confirmTitle.stringValue = title;
    if (![self.announcedConfirmationTitle isEqualToString:title]) {
      self.announcedConfirmationTitle = title;
      if (self.popover.shown) {
        NSAccessibilityPostNotificationWithUserInfo(self.confirmTitle, NSAccessibilityAnnouncementRequestedNotification,
            @{NSAccessibilityAnnouncementKey: title, NSAccessibilityPriorityKey: @(NSAccessibilityPriorityMedium)});
        if (newlyShown) [self.popover.contentViewController.view.window makeFirstResponder:self.keepGoingButton];
      }
    }
    self.confirmDetail.stringValue = [NSString stringWithFormat:@"%@ left will be discarded.", time];
    self.confirmButton.title = [self.pendingAction[@"confirmLabel"] isKindOfClass:NSString.class] ? self.pendingAction[@"confirmLabel"] : @"Switch";
    self.confirmButton.accessibilityLabel = self.confirmButton.toolTip = self.confirmButton.title;
  } else {
    self.announcedConfirmationTitle = nil;
  }
  self.confirmBar.layer.backgroundColor = surface.CGColor;
  self.confirmBar.layer.borderColor = [self color:@"line2"].CGColor;
  self.confirmTitle.textColor = ink;
  self.confirmDetail.textColor = muted;
  [self styleButton:self.keepGoingButton fill:raised text:ink];
  [self styleButton:self.confirmButton fill:accent text:[self color:@"onAccent"]];

  NSInteger durations[8] = {self.focusMinutes * 60, self.shortBreakMinutes * 60, self.focusMinutes * 60, self.shortBreakMinutes * 60, self.focusMinutes * 60, self.shortBreakMinutes * 60, self.focusMinutes * 60, self.longBreakMinutes * 60};
  if (self.totalSeconds > 0) durations[self.cycleStep] = self.totalSeconds;
  double total = 0; for (NSInteger i = 0; i < 8; i++) total += durations[i];
  double widths[8] = {0}; BOOL fixed[8] = {NO}; double available = 273;
  for (NSInteger pass = 0; pass < 8; pass++) {
    BOOL changed = NO;
    for (NSInteger i = 0; i < 8; i++) if (!fixed[i] && total > 0 && available * durations[i] / total < 10) {
      widths[i] = 10; fixed[i] = YES; available -= 10; total -= durations[i]; changed = YES;
    }
    if (!changed) break;
  }
  [NSLayoutConstraint deactivateConstraints:self.cycleWidthConstraints ?: @[]];
  NSMutableArray *widthConstraints = [NSMutableArray array];
  for (NSInteger i = 0; i < (NSInteger)self.cycleButtons.count; i++) {
    StintCycleButton *button = self.cycleButtons[i];
    if (!fixed[i]) widths[i] = total > 0 ? available * durations[i] / total : available / 8;
    [widthConstraints addObject:[button.widthAnchor constraintEqualToConstant:widths[i]]];
    BOOL isFocus = i % 2 == 0;
    NSString *phase = isFocus ? @"Focus" : i == 7 ? @"Long break" : @"Short break";
    button.current = i == self.cycleStep;
    button.enabled = self.ready && !button.current;
    button.trackColor = [self color:@"track"];
    NSColor *color = [self color:isFocus ? @"focus" : @"break"];
    button.fillColor = i < self.cycleStep ? [color colorWithAlphaComponent:0.45] : color;
    NSInteger remaining = self.deadline ? MIN(self.totalSeconds, MAX(0, (NSInteger)ceil(self.deadline.timeIntervalSinceNow))) : self.remaining;
    button.progress = i < self.cycleStep ? 1 : i == self.cycleStep && self.totalSeconds > 0 ? 1 - remaining / (double)self.totalSeconds : 0;
    button.accessibilityLabel = button.toolTip = [NSString stringWithFormat:@"%@, %@%@", phase, StintDurationLabel(durations[i]), button.current ? @", current" : @""];
    button.focusAccent = accent;
    button.accessibilityValue = button.current ? @"Current" : @"";
    button.accessibilitySelected = button.current;
    [button setNeedsDisplay:YES];
  }
  self.cycleWidthConstraints = widthConstraints;
  [NSLayoutConstraint activateConstraints:widthConstraints];

  BOOL busy = [self.music[@"busy"] boolValue];
  BOOL starting = [self.music[@"starting"] boolValue];
  BOOL playing = [self.music[@"playing"] boolValue] || starting;
  NSString *name = @"Choose a sound";
  for (NSDictionary *track in [self entries:self.music[@"tracks"] titleKey:@"title"]) if ([track[@"id"] isEqual:self.music[@"selectedId"]]) { name = track[@"title"]; break; }
  self.soundTitle.stringValue = name;
  self.soundTitle.textColor = ink;
  self.soundStatus.stringValue = starting ? @"Starting…" : playing ? ([self.music[@"followTimer"] boolValue] ? @"Playing with timer" : @"Playing") : @"Paused";
  self.soundStatus.textColor = muted;
  self.soundTile.layer.backgroundColor = raised.CGColor;
  BOOL animate = [self.music[@"playing"] boolValue] && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
  for (NSInteger i = 0; i < (NSInteger)self.equalizerBars.count; i++) {
    NSView *bar = self.equalizerBars[i];
    double height = animate ? 10 + 12 * (0.5 + 0.5 * sin(NSDate.timeIntervalSinceReferenceDate * 5 + i * 2)) : (i == 1 ? 20 : 12);
    bar.frame = NSMakeRect(9 + i * 7, (36 - height) / 2, 4, height);
    bar.layer.backgroundColor = [self color:@"focus"].CGColor;
  }
  self.musicButton.image = [NSImage imageWithSystemSymbolName:playing ? @"pause.fill" : @"play.fill" accessibilityDescription:nil];
  self.musicButton.accessibilityLabel = self.musicButton.toolTip = playing ? @"Pause sound" : @"Play sound";
  self.musicButton.enabled = self.music != nil && !busy;
  [self styleButton:self.musicButton fill:raised text:ink];
  self.volumeSlider.enabled = self.music != nil && (!busy || self.volumeSlider.tracking);
  if (!self.volumeSlider.tracking && !self.volumePending && [self.music[@"volume"] isKindOfClass:NSNumber.class]) self.volumeSlider.doubleValue = MIN(1, MAX(0, [self.music[@"volume"] doubleValue]));
  self.volumeValue.stringValue = [NSString stringWithFormat:@"%.0f%%", self.volumeSlider.doubleValue * 100];
  self.volumeValue.textColor = muted;
  self.volumeSlider.accessibilityValueDescription = [NSString stringWithFormat:@"%.0f percent", self.volumeSlider.doubleValue * 100];
  self.volumeSlider.trackFillColor = [self color:@"focus"];
  self.volumeSlider.focusAccent = accent;
  NSString *error = [self.music[@"error"] isKindOfClass:NSString.class] ? self.music[@"error"] : @"";
  self.musicError.stringValue = error;
  self.musicError.textColor = [self color:@"error"];
  self.musicError.hidden = error.length == 0;
  for (NSView *divider in self.dividers) divider.layer.backgroundColor = [self color:@"line"].CGColor;
  for (NSButton *button in @[self.openButton, self.progressButton, self.settingsButton]) [self styleButton:button fill:NSColor.clearColor text:muted];
  NSSize size = NSMakeSize(340, 428 + (confirming ? 72 : 0) + (error.length ? 42 : 0)
      + (self.embeddedYouTubeView ? 252 : 0));
  if (!NSEqualSizes(size, self.popover.contentSize)) self.popover.contentSize = size;
}

- (void)showRhythms:(NSButton *)sender {
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Rhythms"];
  menu.autoenablesItems = NO;
  for (NSDictionary *rhythm in [self entries:self.routines titleKey:@"name"]) {
    NSString *title = [NSString stringWithFormat:@"%@    %@·%@·%@", rhythm[@"name"], rhythm[@"focusMinutes"], rhythm[@"shortBreakMinutes"], rhythm[@"longBreakMinutes"]];
    NSMenuItem *item = [self addItem:title action:@selector(selectRhythm:) toMenu:menu];
    item.representedObject = rhythm[@"id"];
    item.state = [rhythm[@"id"] isEqual:self.activeRoutineId] ? NSControlStateValueOn : NSControlStateValueOff;
  }
  [menu addItem:NSMenuItem.separatorItem];
  [self addItem:@"Edit rhythms…" action:@selector(openSettings:) toMenu:menu];
  [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, sender.bounds.size.height) inView:sender];
}
- (void)selectRhythm:(NSMenuItem *)sender { [self.channel invokeMethod:@"applyRoutine" arguments:sender.representedObject]; }
- (void)resetTimer:(id)sender { [self.channel invokeMethod:@"reset" arguments:nil]; }
- (void)skipTimer:(id)sender { [self.channel invokeMethod:@"skip" arguments:nil]; }
- (void)jumpStep:(NSButton *)sender { [self.channel invokeMethod:@"jumpStep" arguments:@(sender.tag)]; }
- (void)confirmPending:(id)sender { [self.channel invokeMethod:@"confirm" arguments:nil]; }
- (void)cancelPending:(id)sender { [self.channel invokeMethod:@"cancel" arguments:nil]; }
- (void)openSettings:(id)sender { [self showWindow]; [self.channel invokeMethod:@"settings" arguments:nil]; }
- (void)openProgress:(id)sender { [self showWindow]; [self.channel invokeMethod:@"progress" arguments:nil]; }
- (void)toggleMusic:(id)sender { [self.channel invokeMethod:@"musicToggle" arguments:nil]; }
- (void)changeVolume:(NSSlider *)sender {
  self.volumePending = YES;
  __weak StintMenuBar *weakSelf = self;
  [self.channel invokeMethod:@"musicVolume" arguments:@(sender.doubleValue) result:^(__unused id result) {
    weakSelf.volumePending = NO;
    [weakSelf render];
  }];
}

- (void)update:(NSDictionary *)state {
  UNNotificationRequest *previousCompletionRequest = self.liveCompletionRequest;
  NSDate *previousDeadline = self.deadline;
  NSString *previousKey = self.notificationKey;
  NSString *previousSession = self.sessionId;
  NSInteger previousTodayCount = self.todayCount, previousDailyGoal = self.dailyGoal;
  NSArray *previousDurations = @[@(self.focusMinutes), @(self.shortBreakMinutes), @(self.longBreakMinutes)];
  NSNumber *previousCompletionCount = self.completionCount;
  BOOL firstUpdate = !self.ready;
  self.ready = YES;
  self.running = [state[@"running"] boolValue];
  self.hasProgress = [state[@"hasProgress"] boolValue];
  self.totalSeconds = MAX(0, [state[@"totalSeconds"] integerValue]);
  self.remaining = MIN(self.totalSeconds, MAX(0, [state[@"remaining"] integerValue]));
  if ([state[@"phase"] isKindOfClass:NSString.class]) self.phase = state[@"phase"];
  if ([state[@"routines"] isKindOfClass:NSArray.class]) self.routines = state[@"routines"];
  self.activeRoutineId = [state[@"activeRoutineId"] isKindOfClass:NSString.class] ? state[@"activeRoutineId"] : nil;
  self.cycleStep = MIN(7, MAX(0, [state[@"cycleStep"] integerValue]));
  self.focusMinutes = MAX(1, [state[@"focusMinutes"] integerValue]);
  self.shortBreakMinutes = MAX(1, [state[@"shortBreakMinutes"] integerValue]);
  self.longBreakMinutes = MAX(1, [state[@"longBreakMinutes"] integerValue]);
  self.todayCount = MAX(0, [state[@"todayCount"] integerValue]);
  self.dailyGoal = [state[@"dailyGoal"] isKindOfClass:NSNumber.class] ? MIN(16, MAX(1, [state[@"dailyGoal"] integerValue])) : 8;
  self.completionCount = [state[@"completionCount"] isKindOfClass:NSNumber.class] ? @(MAX(0, [state[@"completionCount"] integerValue])) : nil;
  self.appearancePreference = [state[@"appearance"] isKindOfClass:NSString.class] ? state[@"appearance"] : @"system";
  self.pendingAction = [state[@"pendingAction"] isKindOfClass:NSDictionary.class] ? state[@"pendingAction"] : nil;
  if ([state[@"music"] isKindOfClass:NSDictionary.class]) self.music = state[@"music"];
  NSNumber *milliseconds = [state[@"deadlineMilliseconds"] isKindOfClass:NSNumber.class] ? state[@"deadlineMilliseconds"] : nil;
  self.deadline = self.running && milliseconds && isfinite(milliseconds.doubleValue)
      ? [NSDate dateWithTimeIntervalSince1970:milliseconds.doubleValue / 1000.0] : nil;
  NSString *session = [state[@"sessionId"] isKindOfClass:NSString.class] ? state[@"sessionId"] : @"";
  self.sessionId = session;
  self.notificationKey = self.deadline ? [NSString stringWithFormat:@"%@:%@", session, milliseconds] : nil;
  if (!self.deadline && state[@"completedSessionId"] && ![state[@"completedSessionId"] isEqual:previousSession]) self.completionGate.armed = NO;
  BOOL idle = !self.running && !self.hasProgress && session.length == 0 && self.remaining == self.totalSeconds;
  if ([self.completionGate observeKey:self.notificationKey deadline:self.deadline phase:self.phase
                             routine:self.activeRoutineId idle:idle atTime:NSDate.date]) {
    [self completeInterval:previousCompletionRequest];
  }
  if (self.notificationKey && self.deadline.timeIntervalSinceNow > 0) {
    self.liveCompletionRequest = [self notificationForKey:self.notificationKey deadline:self.deadline audible:NO];
  } else if (!self.running) {
    self.liveCompletionRequest = nil;
  }
  if (self.completionCardContext) {
    BOOL finishing = self.running && [self.completionCardContext[@"timerKey"] isEqualToString:self.notificationKey];
    BOOL offered = idle && [self.completionCardContext[@"sessionId"] isEqual:state[@"completedSessionId"]]
        && [self.completionCardContext[@"cycleStep"] integerValue] == self.cycleStep;
    BOOL sameRhythm = !self.completionCardContext[@"rhythmId"]
        || [self.completionCardContext[@"rhythmId"] isEqual:self.activeRoutineId ?: @""];
    BOOL sameDurations = !self.completionCardContext[@"routineMinutes"]
        || [self.completionCardContext[@"routineMinutes"] isEqual:@[@(self.focusMinutes), @(self.shortBreakMinutes), @(self.longBreakMinutes)]];
    if ((!finishing && !offered) || !sameRhythm || !sameDurations) [self dismissCompletionCard];
  }
  BOOL changed = !((previousKey == nil && self.notificationKey == nil) || [previousKey isEqualToString:self.notificationKey]);
  if (changed || firstUpdate) {
    self.generation++;
    self.requestedExpiryRefresh = NO;
    self.scheduledKey = nil;
    // Completion changes Dart's state to the next phase. Keep its just-due alert.
    if (previousKey && previousDeadline.timeIntervalSinceNow > 0) {
      [self.notifications removePendingNotificationRequestsWithIdentifiers:@[StintNotificationIdentifier(previousKey)]];
    }
    if (self.notificationKey || firstUpdate) [self checkAuthorizationForGeneration:self.generation];
    if (!self.notificationKey && firstUpdate) [self removeFutureOrphanForGeneration:self.generation];
  } else if (previousDailyGoal != self.dailyGoal || !((previousCompletionCount == nil && self.completionCount == nil)
      || [previousCompletionCount isEqualToNumber:self.completionCount])
      || (!self.completionCount && previousTodayCount != self.todayCount)
      || ![previousDurations isEqual:@[@(self.focusMinutes), @(self.shortBreakMinutes), @(self.longBreakMinutes)]]) {
    [self refreshScheduledNotification];
  }
  [self render];
  if (self.pendingNotificationAction) {
    NSDictionary *action = self.pendingNotificationAction;
    self.pendingNotificationAction = nil;
    [self.channel invokeMethod:@"startNext" arguments:action];
  }
}

- (void)render {
  if ([self.completionGate consumeExpiryAtTime:NSDate.date]) [self completeInterval:self.liveCompletionRequest];
  NSInteger seconds = self.deadline ? MIN(self.totalSeconds, MAX(0, (NSInteger)ceil(self.deadline.timeIntervalSinceNow))) : self.remaining;
  NSString *time = self.ready ? [NSString stringWithFormat:@"%02ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)] : @"--:--";
  self.statusItem.button.title = [@" " stringByAppendingString:time];
  NSString *status = self.running ? @"Running" : (self.hasProgress ? @"Paused" : @"Ready");
  NSString *description = [NSString stringWithFormat:@"Stint timer, %@", time];
  self.statusItem.button.toolTip = description;
  self.statusItem.button.accessibilityLabel = description;
  self.phaseItem.title = self.ready ? [NSString stringWithFormat:@"%@ · %@ · %@", self.phase, time, status] : @"Opening Stint…";
  self.progressButton.title = [NSString stringWithFormat:@"Progress %ld/%ld", (long)self.todayCount, (long)MAX(1, self.dailyGoal)];
  self.progressButton.accessibilityLabel = self.progressButton.toolTip = [NSString stringWithFormat:@"Progress, %ld of %ld stints today", (long)self.todayCount, (long)MAX(1, self.dailyGoal)];
  self.toggleItem.title = self.running ? @"Pause" : (self.hasProgress ? @"Resume" : [self.phase isEqualToString:@"Focus"] ? @"Start focus" : @"Start break");
  self.toggleItem.enabled = self.ready;
  self.adjustItem.enabled = self.ready;
  self.notificationItem.enabled = self.authorizationKnown && !self.requestingAuthorization;
  self.notificationItem.title = self.requestingAuthorization ? @"Waiting for notification permission…"
      : !self.authorizationKnown ? @"Checking notifications…"
      : self.authorizationStatus == UNAuthorizationStatusDenied ? @"Enable notifications in System Settings…"
      : self.authorizationStatus == UNAuthorizationStatusNotDetermined ? @"Enable notifications…"
      : @"Notification settings…";
  [self renderPopoverWithTime:time status:status];
  if (self.deadline && seconds == 0 && !self.requestedExpiryRefresh) {
    self.requestedExpiryRefresh = YES;
    [self.channel invokeMethod:@"refresh" arguments:nil];
  }
}

- (void)showWindow {
  [self.popover close];
  [NSApp activateIgnoringOtherApps:YES];
  if (self.window.miniaturized) [self.window deminiaturize:nil];
  [self.window makeKeyAndOrderFront:nil];
}

- (void)windowWillClose {
  if ([self.alertDefaults boolForKey:@"StintMenuBarHintShown"]) return;
  [self.alertDefaults setBool:YES forKey:@"StintMenuBarHintShown"];
  [self presentMenuBarHint];
}

- (NSDictionary<NSString *, NSColor *> *)completionColors {
  NSMutableDictionary *colors = [NSMutableDictionary dictionary];
  for (NSString *token in @[@"surface", @"line", @"ink", @"ink2", @"muted", @"onAccent", @"track", @"focus", @"break", @"focusText"])
    colors[token] = [self color:token];
  return colors;
}

- (NSRect)completionAnchor {
  NSStatusBarButton *button = self.statusItem.button;
  if (!button.window.screen) return NSZeroRect;
  return [button.window convertRectToScreen:[button convertRect:button.bounds toView:nil]];
}

- (void)ensureCompletionBanner {
  if (self.completionBanner) return;
  self.completionBanner = [[StintCompletionBanner alloc] init];
  __weak StintMenuBar *weakSelf = self;
  self.completionBanner.dismissedHandler = ^{ weakSelf.completionCardContext = nil; };
}

- (void)presentMenuBarHint {
  // A completion takes priority over the once-only onboarding hint.
  if (self.completionBanner.hasContent && !self.completionBanner.isHint) return;
  [self ensureCompletionBanner];
  [self.completionBanner setTemporarilyHidden:self.popover.shown];
  [self.completionBanner showHintWithColors:[self completionColors]
      screen:self.statusItem.button.window.screen ?: self.window.screen anchor:[self completionAnchor]];
}

- (void)openWindow:(id)sender { [self showWindow]; }
- (void)testAlertSound:(id)sender { [self playCompletionSound]; }

- (void)completeInterval:(UNNotificationRequest *)request {
  [self playCompletionSound];
  if (request) [self presentCompletionContent:request.content preview:NO];
}

- (void)dismissCompletionCard {
  [self.completionBanner dismiss];
  self.completionCardContext = nil;
}

- (void)startFromCompletionCard:(NSDictionary *)context {
  // The card may outlive its offered break/focus. Dart settles expiry and
  // validates this exact finished session and next step before starting it.
  if (![self.completionCardContext isEqual:context]) return;
  [self dismissCompletionCard];
  [self.channel invokeMethod:@"startNext" arguments:context];
}

- (void)skipFromCompletionCard:(NSDictionary *)context {
  if (![self.completionCardContext isEqual:context] || [context[@"cycleStep"] integerValue] % 2 != 1) return;
  [self dismissCompletionCard];
  [self.channel invokeMethod:@"skipOffered" arguments:context];
}

- (void)presentCompletionContent:(UNNotificationContent *)content preview:(BOOL)preview {
  if (preview) [self.popover close];
  [self ensureCompletionBanner];
  self.completionCardContext = preview ? nil : content.userInfo;
  NSMutableDictionary *card = [content.userInfo mutableCopy];
  card[@"title"] = content.title;
  card[@"body"] = content.body;
  card[@"detail"] = content.subtitle;
  NSDictionary *context = content.userInfo;
  __weak StintMenuBar *weakSelf = self;
  [self.completionBanner setTemporarilyHidden:self.popover.shown];
  [self.completionBanner showContent:card colors:[self completionColors]
      screen:self.statusItem.button.window.screen ?: self.window.screen anchor:[self completionAnchor]
      action:^{
    if (preview) [weakSelf dismissCompletionCard];
    else [weakSelf startFromCompletionCard:context];
  } secondaryAction:^{
    if (preview || [context[@"cycleStep"] integerValue] % 2 == 0) [weakSelf dismissCompletionCard];
    else [weakSelf skipFromCompletionCard:context];
  }];
  if (preview) [self.completionBanner focusForPreview];
}

- (void)previewNotification:(id)sender {
  // A silent appearance preview never changes the timer or records a stint.
  UNNotificationContent *content = [self notificationForKey:@"preview" deadline:NSDate.date audible:NO].content;
  [self presentCompletionContent:content preview:YES];
}
- (void)playCompletionSound {
  [self playAlertSound:[self alertSoundSettings][@"selectedSound"]];
}
- (NSSound *)newAlertSoundNamed:(NSString *)name {
  NSString *path = [@"/System/Library/Sounds" stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"aiff"]];
  return [[NSSound alloc] initWithContentsOfFile:path byReference:NO];
}
- (void)playAlertSound:(NSString *)name {
  if (![StintAlertSounds() containsObject:name]) return;
  self.soundPlaybackGeneration++;
  self.remainingAlertPlays = 1;
  self.completionSound.delegate = nil;
  [self.completionSound stop];
  // Load our own instance: soundNamed: returns a shared object other code can stop.
  self.completionSound = [self newAlertSoundNamed:name];
  self.completionSound.delegate = self;
  self.completionSound.volume = 1;
  self.completionSound.loops = NO;
  [self startCurrentAlertSound];
}
- (void)startCurrentAlertSound {
  self.completionSound.currentTime = 0;
  if (![self.completionSound play]) {
    self.remainingAlertPlays = 0;
    self.soundPlaybackGeneration++;
    self.completionSound.delegate = nil;
    [self reportNotificationError:@"The timer alert sound could not play. Check your Mac’s sound output, then choose Test alert sound from the Stint menu."];
  }
}
- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)finished {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (sound != self.completionSound) return;
    if (!finished) {
      self.remainingAlertPlays = 0;
      self.soundPlaybackGeneration++;
      self.completionSound.delegate = nil;
      [self reportNotificationError:@"The timer alert sound could not finish playing. Check your Mac’s sound output, then try Test alert sound again."];
      return;
    }
    if (self.remainingAlertPlays == 0) return;
    self.remainingAlertPlays--;
    NSUInteger generation = self.soundPlaybackGeneration;
    __weak StintMenuBar *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      StintMenuBar *self = weakSelf;
      if (!self || generation != self.soundPlaybackGeneration || sound != self.completionSound) return;
      [self startCurrentAlertSound];
    });
  });
}
- (void)quit:(id)sender { [NSApp terminate:nil]; }
- (void)performShortcutAction:(NSString *)action {
  if (!self.ready) return;
  if ([action isEqualToString:@"toggle"]) {
    [self toggleTimer:nil];
  } else if ([action isEqualToString:@"reset"] || [action isEqualToString:@"skip"]) {
    // The shared controller may ask before discarding unfinished time.
    [self showMiniTimer:nil];
    if ([action isEqualToString:@"reset"]) [self resetTimer:nil];
    else [self skipTimer:nil];
  } else if ([action isEqualToString:@"panel"]) {
    [self showMiniTimer:nil];
  }
}

- (void)toggleTimer:(id)sender {
  [self.channel invokeMethod:@"toggle" arguments:@{
    @"running": @(self.running),
    @"sessionId": self.sessionId.length ? self.sessionId : NSNull.null,
    @"cycleStep": @(self.cycleStep)
  }];
}
- (void)menuWillOpen:(NSMenu *)menu {
  [self.trackingMenus addObject:menu];
  [self render];
  [self.channel invokeMethod:@"refresh" arguments:nil];
}
- (void)menuDidClose:(NSMenu *)menu {
  [self.trackingMenus removeObject:menu];
  // Popup actions read the chosen item after menuDidClose; update it next turn.
  dispatch_async(dispatch_get_main_queue(), ^{ [self render]; });
}
- (void)refreshFromSystem:(NSNotification *)notification {
  [self render];
  [self.channel invokeMethod:@"refresh" arguments:nil];
  [self checkAuthorizationForGeneration:self.generation];
}

- (void)checkAuthorizationForGeneration:(NSUInteger)generation {
  __weak StintMenuBar *weakSelf = self;
  [self.notifications getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
    dispatch_async(dispatch_get_main_queue(), ^{
      StintMenuBar *self = weakSelf;
      if (!self || generation != self.generation) return;
      self.authorizationKnown = YES;
      self.authorizationStatus = settings.authorizationStatus;
      [self render];
      if (!self.notificationKey) return;
      if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) {
        [self requestAuthorization];
      } else if (settings.authorizationStatus == UNAuthorizationStatusDenied) {
        [self reportDenied];
      } else {
        self.reportedDenied = NO;
        [self scheduleForGeneration:generation];
      }
    });
  }];
}

- (void)requestAuthorization {
  if (self.requestingAuthorization) return;
  self.requestingAuthorization = YES;
  [self render];
  __weak StintMenuBar *weakSelf = self;
  [self.notifications requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound completionHandler:^(BOOL granted, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      StintMenuBar *self = weakSelf;
      if (!self) return;
      self.requestingAuthorization = NO;
      if (error) {
        self.authorizationKnown = YES;
        self.authorizationStatus = UNAuthorizationStatusNotDetermined;
        [self render];
        [self reportNotificationError:[NSString stringWithFormat:@"Notifications could not be enabled: %@", error.localizedDescription]];
        return;
      }
      if (!granted) [self reportDenied];
      // Permission belongs to the app, but any timer captured before the prompt
      // may have been paused/replaced. Re-read the latest generation and deadline.
      [self checkAuthorizationForGeneration:self.generation];
    });
  }];
}

- (void)refreshScheduledNotification {
  if (!self.notificationKey || !self.running || self.deadline.timeIntervalSinceNow <= 0) return;
  self.liveCompletionRequest = [self notificationForKey:self.notificationKey deadline:self.deadline audible:NO];
  // Replace the same pending request so goal, history and sound edits appear at
  // completion without creating another notification or changing the deadline.
  self.generation++;
  self.scheduledKey = nil;
  [self checkAuthorizationForGeneration:self.generation];
}

- (void)scheduleForGeneration:(NSUInteger)generation {
  if (generation != self.generation || !self.notificationKey || !self.running || [self.scheduledKey isEqualToString:self.notificationKey]) return;
  NSTimeInterval delay = self.deadline.timeIntervalSinceNow;
  if (delay <= 0) return;
  NSString *key = self.notificationKey;
  NSDate *deadline = self.deadline;
  NSString *identifier = StintNotificationIdentifier(key);
  self.scheduledKey = key;
  UNNotificationRequest *request = [self notificationForKey:key deadline:deadline audible:NO];
  __weak StintMenuBar *weakSelf = self;
  [self.notifications addNotificationRequest:request withCompletionHandler:^(NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      StintMenuBar *self = weakSelf;
      if (!self) return;
      if (generation != self.generation || ![key isEqualToString:self.notificationKey]) {
        // A pending add may finish after pause/replacement canceled it. Its
        // unique identifier lets cleanup avoid touching a newer or just-due alert.
        if (![key isEqualToString:self.notificationKey] && deadline.timeIntervalSinceNow > 0) {
          [self.notifications removePendingNotificationRequestsWithIdentifiers:@[identifier]];
        }
        return;
      }
      if (error) {
        self.scheduledKey = nil;
        [self reportNotificationError:[NSString stringWithFormat:@"The timer notification could not be scheduled: %@", error.localizedDescription]];
      }
    });
  }];
}

- (UNNotificationRequest *)notificationForKey:(NSString *)key deadline:(NSDate *)deadline audible:(BOOL)audible {
  UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
  BOOL focus = [self.phase isEqualToString:@"Focus"];
  NSInteger nextStep = (self.cycleStep + 1) % 8;
  BOOL longBreak = focus && nextStep == 7;
  NSInteger goal = MAX(1, self.dailyGoal);
  // Dart projects history on the deadline's local date and includes this focus
  // once. Older snapshots need the same-day fallback; breaks never add a stint.
  NSInteger finishedToday = self.completionCount ? self.completionCount.integerValue
      : ([NSCalendar.currentCalendar isDate:deadline inSameDayAsDate:NSDate.date] ? self.todayCount : 0) + (focus ? 1 : 0);
  BOOL goalMet = focus && finishedToday == goal;
  NSString *count = [NSString stringWithFormat:@"%ld of %ld today", (long)finishedToday, (long)goal];
  content.subtitle = goalMet ? count : [NSString stringWithFormat:@"%@ · %@ played twice", count, [self alertSoundSettings][@"selectedSound"]];
  content.title = goalMet ? @"Daily goal met" : longBreak ? @"Four stints done" : focus ? @"Focus complete" : @"Break over";
  if (goalMet) {
    content.body = [NSString stringWithFormat:@"%ld %@ today. Your %@ break is ready.", (long)finishedToday,
        finishedToday == 1 ? @"stint" : @"stints", longBreak ? @"long" : @"short"];
  } else if (longBreak) {
    content.body = [NSString stringWithFormat:@"Your long break is ready. Take the full %ld %@.",
        (long)MAX(1, self.longBreakMinutes), self.longBreakMinutes == 1 ? @"minute" : @"minutes"];
  } else {
    content.body = focus ? @"Your short break is ready."
        : [NSString stringWithFormat:@"Focus %ld of 4 is ready when you are.", (long)(nextStep / 2 + 1)];
  }
  content.categoryIdentifier = longBreak ? @"stint.start-long-break" : focus ? @"stint.start-break" : @"stint.start-focus";
  // Use the deadline's local Gregorian date, including sessions across midnight.
  NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
  calendar.timeZone = NSTimeZone.localTimeZone;
  NSDateComponents *day = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:deadline];
  content.threadIdentifier = [NSString stringWithFormat:@"stint-%04ld-%02ld-%02ld", (long)day.year, (long)day.month, (long)day.day];
  // A live interval rings directly, regardless of notification presentation settings.
  NSString *repeatedSound = audible ? [self repeatedAlertSoundName] : nil;
  content.sound = audible ? (repeatedSound ? [UNNotificationSound soundNamed:repeatedSound] : UNNotificationSound.defaultSound) : nil;
  // Preserve list-only live delivery and an active system fallback after Quit.
  content.interruptionLevel = audible ? UNNotificationInterruptionLevelActive : UNNotificationInterruptionLevelPassive;
  NSMutableArray *minutes = [NSMutableArray array];
  for (NSInteger step = 0; step < 8; step++) {
    double duration = step % 2 == 0 ? self.focusMinutes : step == 7 ? self.longBreakMinutes : self.shortBreakMinutes;
    if (step == self.cycleStep && self.totalSeconds > 0) duration = self.totalSeconds / 60.0;
    [minutes addObject:@(MAX(1, duration))];
  }
  content.userInfo = @{
    @"timerKey": key, @"sessionId": self.sessionId ?: @"", @"cycleStep": @(nextStep),
    @"nextStep": @(nextStep), @"finishedStep": @(self.cycleStep), @"stepMinutes": minutes,
    @"count": @(finishedToday), @"goal": @(goal), @"goalMet": @(goalMet),
    @"actionTitle": longBreak ? @"Start long break" : focus ? @"Start break" : @"Start focus",
    @"secondaryTitle": focus ? @"Skip break" : @"Not now",
    @"rhythmId": self.activeRoutineId ?: @"",
    @"routineMinutes": @[@(self.focusMinutes), @(self.shortBreakMinutes), @(self.longBreakMinutes)]
  };
  UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:MAX(0.1, deadline.timeIntervalSinceNow) repeats:NO];
  return [UNNotificationRequest requestWithIdentifier:StintNotificationIdentifier(key) content:content trigger:trigger];
}

- (void)registerNotificationActions {
  NSMutableSet *categories = [NSMutableSet set];
  NSDictionary *titles = @{@"break": @"Start break", @"long-break": @"Start long break", @"focus": @"Start focus"};
  for (NSString *phase in @[@"break", @"long-break", @"focus"]) {
    UNNotificationAction *action = [UNNotificationAction actionWithIdentifier:@"stint.start-next" title:titles[phase] options:UNNotificationActionOptionForeground];
    [categories addObject:[UNNotificationCategory categoryWithIdentifier:[@"stint.start-" stringByAppendingString:phase] actions:@[action] intentIdentifiers:@[] options:UNNotificationCategoryOptionNone]];
  }
  [self.notifications setNotificationCategories:categories];
}

- (void)handleNotificationAction:(NSString *)identifier userInfo:(NSDictionary *)userInfo {
  if ([identifier isEqualToString:@"stint.start-next"] && [userInfo[@"sessionId"] isKindOfClass:NSString.class]
      && [userInfo[@"sessionId"] length] > 0 && [userInfo[@"cycleStep"] isKindOfClass:NSNumber.class]
      && [userInfo[@"cycleStep"] integerValue] >= 0 && [userInfo[@"cycleStep"] integerValue] <= 7) {
    NSDictionary *action = @{@"sessionId": userInfo[@"sessionId"], @"cycleStep": userInfo[@"cycleStep"]};
    [self showWindow];
    // Dart verifies the completed session and still-idle offered interval. Keep
    // the context until its first snapshot when a notification launches the app.
    if (self.ready) [self.channel invokeMethod:@"startNext" arguments:action];
    else self.pendingNotificationAction = action;
  } else if ([identifier isEqualToString:UNNotificationDefaultActionIdentifier]) {
    [self showWindow];
  }
}

- (void)prepareNotificationForTermination:(NSNotification *)notification {
  self.terminating = YES;
  BOOL justCompleted = self.completionGate.armed && self.deadline.timeIntervalSinceNow <= 0;
  if (!self.notificationKey || (self.deadline.timeIntervalSinceNow <= 0 && !justCompleted) || !self.authorizationKnown
      || self.authorizationStatus == UNAuthorizationStatusDenied
      || self.authorizationStatus == UNAuthorizationStatusNotDetermined) return;
  // On normal Quit the system becomes responsible for sound. Replacing the same
  // identifier retains one alert; briefly await XPC scheduling before process exit.
  UNNotificationRequest *request = [self notificationForKey:self.notificationKey deadline:self.deadline audible:YES];
  if (justCompleted) self.completionGate.armed = NO;
  dispatch_semaphore_t scheduled = dispatch_semaphore_create(0);
  __block NSError *failure = nil;
  [self.notifications addNotificationRequest:request withCompletionHandler:^(NSError *error) {
    failure = error;
    dispatch_semaphore_signal(scheduled);
  }];
  long timedOut = dispatch_semaphore_wait(scheduled, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
  if (timedOut) NSLog(@"Stint could not confirm its exit notification: scheduling timed out");
  else if (failure) NSLog(@"Stint could not confirm its exit notification: %@", failure.localizedDescription);
}

- (void)removeFutureOrphanForGeneration:(NSUInteger)generation {
  __weak StintMenuBar *weakSelf = self;
  [self.notifications getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> *requests) {
    dispatch_async(dispatch_get_main_queue(), ^{
      StintMenuBar *self = weakSelf;
      if (!self || generation != self.generation || self.notificationKey) return;
      for (UNNotificationRequest *request in requests) {
        UNTimeIntervalNotificationTrigger *trigger = [request.trigger isKindOfClass:UNTimeIntervalNotificationTrigger.class] ? (UNTimeIntervalNotificationTrigger *)request.trigger : nil;
        if ([request.identifier hasPrefix:StintTimerNotificationPrefix] && trigger.nextTriggerDate.timeIntervalSinceNow > 0) {
          [self.notifications removePendingNotificationRequestsWithIdentifiers:@[request.identifier]];
        }
      }
    });
  }];
}

- (void)reportDenied {
  if (self.reportedDenied) return;
  self.reportedDenied = YES;
  [self reportNotificationError:@"Timer notifications are disabled. The alert sound still plays while Stint is running. Enable Stint in System Settings → Notifications for notification banners."];
}
- (void)reportNotificationError:(NSString *)message {
  [self.channel invokeMethod:@"notificationError" arguments:message];
}
- (void)notificationSettings:(id)sender {
  if (self.authorizationStatus == UNAuthorizationStatusNotDetermined) [self requestAuthorization];
  else [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.notifications"]];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
  dispatch_async(dispatch_get_main_queue(), ^{
    BOOL liveTimer = !self.terminating && [notification.request.identifier hasPrefix:StintTimerNotificationPrefix];
    UNNotificationPresentationOptions options = UNNotificationPresentationOptionList;
    if (!liveTimer) options |= UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound;
    completionHandler(options);
  });
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self handleNotificationAction:response.actionIdentifier userInfo:response.notification.request.content.userInfo];
    [self.channel invokeMethod:@"refresh" arguments:nil];
    completionHandler();
  });
}

- (void)dealloc {
  [_keymap invalidate];
  [_ticker invalidate];
  [_channel setMethodCallHandler:nil];
  [NSNotificationCenter.defaultCenter removeObserver:self];
  [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
  [_miniMenuItem.menu removeItem:_miniMenuItem];
  [_testSoundMenuItem.menu removeItem:_testSoundMenuItem];
  [_previewNotificationMenuItem.menu removeItem:_previewNotificationMenuItem];
  [_completionBanner dismiss];
  [_showPanelMenuItem.menu removeItem:_showPanelMenuItem];
  [_settingsMenuItem.menu removeItem:_settingsMenuItem];
  _completionSound.delegate = nil;
  _soundPlaybackGeneration++;
  [_completionSound stop];
  if (_notifications.delegate == self) _notifications.delegate = nil;
  if (_statusItem) [NSStatusBar.systemStatusBar removeStatusItem:_statusItem];
}

@end
