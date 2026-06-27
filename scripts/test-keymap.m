// Exercise the production helper without global registration, event monitoring,
// input capture, windows, or user preference access.
#import "../macos/Runner/DeskKeymap.m"

@interface DeskKeyDefaultsProbe : NSObject
@property(nonatomic, strong) NSMutableDictionary *values;
@property(nonatomic) NSUInteger writes;
- (id)objectForKey:(NSString *)key;
- (void)setObject:(id)value forKey:(NSString *)key;
@end
@implementation DeskKeyDefaultsProbe
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary dictionary]; return self; }
- (id)objectForKey:(NSString *)key { return self.values[key]; }
- (void)setObject:(id)value forKey:(NSString *)key {
  NSCAssert([NSPropertyListSerialization propertyList:value isValidForFormat:NSPropertyListBinaryFormat_v1_0], @"Saved shortcuts must be a property list");
  self.values[key] = value;
  self.writes++;
}
@end

static NSInteger startupFailedKey = -1;
static BOOL startupMonitorFails;
static OSStatus startupHandlerFailure;
static BOOL useRealCarbonHandler;

@interface DeskKeymapProbe : DeskKeymap
@property(nonatomic, strong) NSMutableSet<NSNumber *> *failedKeys;
@property(nonatomic, strong) NSMutableSet<NSValue *> *activeReferences;
@property(nonatomic) NSUInteger registrationCalls;
@property(nonatomic) NSUInteger unregisterCalls;
@property(nonatomic) NSUInteger removedMonitors;
@property(nonatomic) UInt32 lastCarbonModifiers;
@end
@implementation DeskKeymapProbe
- (id)installLocalMonitor { return startupMonitorFails ? nil : [NSObject new]; }
- (void)removeLocalMonitor:(id)monitor { (void)monitor; self.removedMonitors++; }
- (OSStatus)installHotKeyHandler {
  return useRealCarbonHandler ? [super installHotKeyHandler] : startupHandlerFailure;
}
- (OSStatus)registerKeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers
                identifier:(UInt32)identifier reference:(EventHotKeyRef *)reference {
  self.registrationCalls++;
  self.lastCarbonModifiers = modifiers;
  if (startupFailedKey == (NSInteger)keyCode || [self.failedKeys containsObject:@(keyCode)]) return eventHotKeyExistsErr;
  *reference = (EventHotKeyRef)(uintptr_t)(identifier + 1);
  if (!self.activeReferences) self.activeReferences = [NSMutableSet set];
  [self.activeReferences addObject:[NSValue valueWithPointer:*reference]];
  return noErr;
}
- (void)unregisterReference:(EventHotKeyRef)reference {
  self.unregisterCalls++;
  [self.activeReferences removeObject:[NSValue valueWithPointer:reference]];
}
@end

@interface DeskKeyEventProbe : NSObject
@property(nonatomic) NSEventType type;
@property(nonatomic) unsigned short keyCode;
@property(nonatomic) BOOL isARepeat;
@property(nonatomic) NSEventModifierFlags modifierFlags;
@end
@implementation DeskKeyEventProbe
@end

static NSUInteger checks;
static void Check(BOOL condition, NSString *message) {
  if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
  checks++;
}

static id Call(DeskKeymap *keymap, NSString *method, id arguments) {
  __block id response;
  __block BOOL completed = NO;
  BOOL handled = [keymap handleCall:[FlutterMethodCall methodCallWithMethodName:method arguments:arguments]
                            result:^(id value) { response = value; completed = YES; }];
  Check(handled && completed, [@"Synchronous method completes: " stringByAppendingString:method]);
  return response;
}

static NSMutableDictionary *Configuration(BOOL global) {
  NSMutableDictionary *configuration = [DeskShortcutDefaults() mutableCopy];
  configuration[@"global"] = @(global);
  configuration[@"bindings"] = [configuration[@"bindings"] mutableCopy];
  return configuration;
}

static UInt32 Identifier(DeskKeymap *keymap, NSString *action) {
  for (NSNumber *identifier in keymap.hotKeyActions) if ([keymap.hotKeyActions[identifier] isEqual:action]) return identifier.unsignedIntValue;
  return 0;
}

static NSEvent *Event(NSInteger key, NSUInteger modifiers, BOOL down, BOOL repeat) {
  DeskKeyEventProbe *event = [DeskKeyEventProbe new];
  event.keyCode = (unsigned short)key;
  event.modifierFlags = ((modifiers & 1) ? NSEventModifierFlagControl : 0) |
      ((modifiers & 2) ? NSEventModifierFlagOption : 0) |
      ((modifiers & 4) ? NSEventModifierFlagShift : 0) |
      ((modifiers & 8) ? NSEventModifierFlagCommand : 0);
  event.type = down ? NSEventTypeKeyDown : NSEventTypeKeyUp;
  event.isARepeat = repeat;
  return (NSEvent *)event;
}

// This creates an in-process Carbon notification, not an OS keyboard event.
// RegisterEventHotKey remains faked; the action only appends to a test array.
static OSStatus DeliverCarbonNotification(UInt32 identifier, OSType signature, BOOL pressed, BOOL includeIdentifier) {
  EventRef event = NULL;
  OSStatus status = CreateEvent(NULL, kEventClassKeyboard,
      pressed ? kEventHotKeyPressed : kEventHotKeyReleased, GetCurrentEventTime(),
      kEventAttributeUserEvent, &event);
  Check(status == noErr && event != NULL, @"Creates an in-process Carbon notification");
  if (includeIdentifier) {
    EventHotKeyID hotKeyID = {signature, identifier};
    status = SetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, sizeof(hotKeyID), &hotKeyID);
    Check(status == noErr, @"Sets Carbon hotkey identifier payload");
  }
  status = SendEventToEventTarget(event, GetApplicationEventTarget());
  ReleaseEvent(event);
  return status;
}

int main(void) {
  @autoreleasepool {
    DeskKeyDefaultsProbe *defaults = [DeskKeyDefaultsProbe new];
    NSMutableArray *actions = [NSMutableArray array];
    DeskKeymapProbe *keymap = [[DeskKeymapProbe alloc] initWithDefaults:(NSUserDefaults *)defaults
        action:^(NSString *action) { [actions addObject:action]; }];
    Check(keymap.hotKeys.count == 4 && keymap.activeReferences.count == 4, @"Default global shortcuts register");
    Check(defaults.writes == 0, @"Launch does not mutate saved preferences");
    NSDictionary *state = Call(keymap, @"getShortcutSettings", nil);
    Check([state[@"global"] isEqual:@YES] && !state[@"error"], @"Default state is globally enabled without an error");
    Check([state[@"bindings"] isEqual:state[@"defaults"][@"bindings"]], @"State exposes defaults in configuration shape");
    Check([state[@"bindings"][@"toggle"][@"label"] isEqual:@"⌃⌥⌘P"], @"Default Start/Pause label");
    Check(keymap.lastCarbonModifiers == (controlKey | optionKey | cmdKey), @"Spec modifier bits become Carbon flags");
    FlutterStandardMessageCodec *codec = FlutterStandardMessageCodec.sharedInstance;
    NSDictionary *decoded = [codec decode:[codec encode:state]];
    Check(CFGetTypeID((__bridge CFTypeRef)decoded[@"global"]) == CFBooleanGetTypeID(), @"Scope survives codec as Boolean");

    for (NSNumber *key in DeskShortcutKeys()) {
      NSString *error;
      NSDictionary *binding = DeskShortcutBinding(@{@"keyCode": key, @"modifiers": @3, @"label": @"untrusted"}, &error);
      Check(binding != nil && error == nil, [NSString stringWithFormat:@"Catalogue key %@ is supported", key]);
      Check(![binding[@"label"] isEqual:@"untrusted"], @"Native key catalogue owns labels");
    }
    Check(DeskShortcutModifiers(NSEventModifierFlagControl | NSEventModifierFlagCommand |
        NSEventModifierFlagCapsLock | NSEventModifierFlagFunction) == 9, @"Caps lock/function do not contaminate modifiers");
    NSArray *invalidBindings = @[
      NSNull.null, @[], @{}, @{@"keyCode": @YES, @"modifiers": @3},
      @{@"keyCode": @0.5, @"modifiers": @3}, @{@"keyCode": @35, @"modifiers": @2.5},
      @{@"keyCode": @35, @"modifiers": @YES}, @{@"keyCode": @35, @"modifiers": @0},
      @{@"keyCode": @35, @"modifiers": @2}, @{@"keyCode": @35, @"modifiers": @4},
      @{@"keyCode": @35, @"modifiers": @16}, @{@"keyCode": @35, @"modifiers": @(-1)},
      @{@"keyCode": @999, @"modifiers": @3}, @{@"keyCode": @(-1), @"modifiers": @3},
      @{@"keyCode": @53, @"modifiers": @3}, @{@"keyCode": @36, @"modifiers": @3},
      @{@"keyCode": @12, @"modifiers": @8}, @{@"keyCode": @12, @"modifiers": @9},
      @{@"keyCode": @4, @"modifiers": @8}, @{@"keyCode": @46, @"modifiers": @8},
      @{@"keyCode": @43, @"modifiers": @8}, @{@"keyCode": @8, @"modifiers": @8},
      @{@"keyCode": @6, @"modifiers": @12}, @{@"keyCode": @9, @"modifiers": @10},
      @{@"keyCode": @49, @"modifiers": @8}, @{@"keyCode": @49, @"modifiers": @1},
      @{@"keyCode": @3, @"modifiers": @9}, @{@"keyCode": @20, @"modifiers": @12},
      @{@"keyCode": @123, @"modifiers": @1}, @{@"keyCode": @120, @"modifiers": @1}
    ];
    for (id binding in invalidBindings) {
      NSString *error;
      Check(!DeskShortcutBinding(binding, &error) && error.length > 0, [NSString stringWithFormat:@"Malformed/reserved binding rejected: %@", binding]);
    }
    for (id malformed in @[NSNull.null, @[], @{}, @{@"global": @1, @"bindings": @{}},
                          @{@"global": @YES, @"bindings": @[]}, @{@"global": @YES, @"bindings": @{}}]) {
      id result = Call(keymap, @"setShortcutSettings", malformed);
      Check([result isKindOfClass:FlutterError.class], @"Malformed settings report a Flutter error");
    }
    Check(defaults.writes == 0 && keymap.hotKeys.count == 4, @"Malformed settings leave preference and registration intact");
    NSMutableDictionary *duplicate = Configuration(YES);
    duplicate[@"bindings"][@"reset"] = duplicate[@"bindings"][@"toggle"];
    FlutterError *duplicateError = Call(keymap, @"setShortcutSettings", duplicate);
    Check([duplicateError.message containsString:@"Start/Pause and Reset"], @"Duplicate error names both actions");
    Check(defaults.writes == 0, @"Duplicate draft is not persisted");

    for (NSString *action in DeskShortcutActions()) {
      UInt32 identifier = Identifier(keymap, action);
      NSUInteger before = actions.count;
      [keymap handleHotKeyIdentifier:identifier pressed:YES];
      [keymap handleHotKeyIdentifier:identifier pressed:YES];
      Check(actions.count == before + 1 && [actions.lastObject isEqual:action], @"Global shortcut dispatches once per press");
      [keymap handleHotKeyIdentifier:identifier pressed:NO];
      [keymap handleHotKeyIdentifier:identifier pressed:YES];
      Check(actions.count == before + 2, @"Key release permits next global action");
      [keymap handleHotKeyIdentifier:identifier pressed:NO];
    }
    NSUInteger beforeUnknown = actions.count;
    [keymap handleHotKeyIdentifier:99999 pressed:YES];
    Check(actions.count == beforeUnknown, @"Unknown/removed Carbon identifier is ignored");

    NSMutableDictionary *canonical = Configuration(YES);
    canonical[@"bindings"][@"toggle"] = @{@"keyCode": @0, @"modifiers": @11, @"label": @"Forged"};
    state = Call(keymap, @"setShortcutSettings", canonical);
    Check([state[@"bindings"][@"toggle"][@"label"] isEqual:@"⌃⌥⌘A"], @"Save derives labels from keys");
    Check(defaults.writes == 1 && keymap.activeReferences.count == 4, @"Successful save commits after registration");
    NSDictionary *previousSaved = defaults.values[DeskKeymapPreference];
    NSDictionary *previousConfig = keymap.configuration;
    UInt32 staleIdentifier = Identifier(keymap, @"toggle");
    NSMutableDictionary *conflict = Configuration(YES);
    conflict[@"bindings"][@"toggle"] = @{@"keyCode": @11, @"modifiers": @11};
    keymap.failedKeys = [NSMutableSet setWithObject:@11];
    FlutterError *conflictError = Call(keymap, @"setShortcutSettings", conflict);
    Check([conflictError isKindOfClass:FlutterError.class] && [conflictError.message containsString:@"Start/Pause"], @"OS conflict reports action and readable error");
    Check(defaults.writes == 1 && [defaults.values[DeskKeymapPreference] isEqual:previousSaved], @"Failed registration never commits preferences");
    Check([keymap.configuration isEqual:previousConfig] && keymap.activeReferences.count == 4, @"Failed save restores previous registration");
    NSUInteger beforeStale = actions.count;
    [keymap handleHotKeyIdentifier:staleIdentifier pressed:YES];
    Check(actions.count == beforeStale, @"Queued event from old registration cannot dispatch");
    [keymap.failedKeys addObject:@0];
    conflictError = Call(keymap, @"setShortcutSettings", conflict);
    Check([conflictError.message containsString:@"also could not be restored"] && keymap.activeReferences.count == 0, @"Rollback failure is truthful and unregisters partial results");
    state = Call(keymap, @"getShortcutSettings", nil);
    Check([state[@"error"] containsString:@"also could not be restored"] && [state[@"bindings"] isEqual:previousConfig[@"bindings"]], @"Editor sees saved configuration and restoration failure");
    [keymap.failedKeys removeAllObjects];
    state = Call(keymap, @"setShortcutSettings", Configuration(YES));
    Check(!state[@"error"] && keymap.activeReferences.count == 4, @"Saving again recovers from conflict");

    __block id recorded;
    __block NSUInteger recordReplies = 0;
    FlutterResult recording = ^(id value) { recorded = value; recordReplies++; };
    NSUInteger writesBeforeRecording = defaults.writes;
    [keymap handleCall:[FlutterMethodCall methodCallWithMethodName:@"recordShortcut" arguments:nil] result:recording];
    Check(keymap.activeReferences.count == 0 && recordReplies == 0, @"Recording unregisters global shortcuts and waits for deliberate input");
    Check([Call(keymap, @"recordShortcut", nil) isKindOfClass:FlutterError.class], @"Overlapping recording requests are rejected");
    Check([Call(keymap, @"setShortcutSettings", Configuration(YES)) isKindOfClass:FlutterError.class], @"Save is rejected while recording");
    NSUInteger actionsBeforeRecord = actions.count;
    [keymap handleHotKeyIdentifier:staleIdentifier pressed:YES];
    [keymap handleLocalEvent:Event(35, 11, YES, YES)];
    Check(recordReplies == 0 && actions.count == actionsBeforeRecord, @"Recording ignores repeat events and suspends dispatch");
    Check([keymap handleLocalEvent:Event(35, 11, YES, NO)] == nil, @"Recorded input is consumed");
    Check(recordReplies == 1 && [recorded[@"label"] isEqual:@"⌃⌥⌘P"], @"Recording returns canonical shortcut");
    Check(keymap.activeReferences.count == 4 && defaults.writes == writesBeforeRecording, @"Recording restores saved shortcuts without saving its draft");
    UInt32 heldIdentifier = Identifier(keymap, @"toggle");
    [keymap handleHotKeyIdentifier:heldIdentifier pressed:YES];
    [keymap handleLocalEvent:Event(35, 11, YES, YES)];
    Check(actions.count == actionsBeforeRecord, @"Held captured chord cannot dispatch after globals are restored");
    [keymap applicationResigned];
    [keymap handleHotKeyIdentifier:heldIdentifier pressed:YES];
    Check(actions.count == actionsBeforeRecord && [keymap.suppressedKeyCodes containsObject:@35],
          @"Changing apps while capture keys remain held preserves global repeat suppression");
    [keymap handleHotKeyIdentifier:heldIdentifier pressed:NO];
    [keymap handleHotKeyIdentifier:heldIdentifier pressed:YES];
    Check(actions.count == actionsBeforeRecord + 1, @"Captured global shortcut works after release and fresh press");
    [keymap handleHotKeyIdentifier:heldIdentifier pressed:NO];

    [keymap handleCall:[FlutterMethodCall methodCallWithMethodName:@"recordShortcut" arguments:nil] result:recording];
    [keymap handleLocalEvent:Event(53, 0, YES, NO)];
    Check(recordReplies == 2 && recorded == nil && keymap.activeReferences.count == 4, @"Escape cancels recording and restores registration");
    [keymap handleCall:[FlutterMethodCall methodCallWithMethodName:@"recordShortcut" arguments:nil] result:recording];
    [keymap applicationResigned];
    Check(recordReplies == 3 && recorded == nil && keymap.activeReferences.count == 4, @"App deactivation cancels recording and restores registration");
    [keymap handleCall:[FlutterMethodCall methodCallWithMethodName:@"recordShortcut" arguments:nil] result:recording];
    Check(Call(keymap, @"cancelShortcutRecording", nil) == nil, @"Explicit cancellation returns null");
    Check(recordReplies == 4 && recorded == nil && keymap.activeReferences.count == 4, @"Sheet cancellation restores saved registration");
    [keymap handleCall:[FlutterMethodCall methodCallWithMethodName:@"recordShortcut" arguments:nil] result:recording];
    [keymap handleLocalEvent:Event(35, 0, YES, NO)];
    Check(recordReplies == 5 && [recorded isKindOfClass:FlutterError.class] && keymap.activeReferences.count == 4, @"Invalid recording reports error and restores saved registration");
    [keymap handleLocalEvent:Event(35, 0, NO, NO)];
    [keymap handleCall:[FlutterMethodCall methodCallWithMethodName:@"recordShortcut" arguments:nil] result:recording];
    [keymap.failedKeys addObject:@35];
    FlutterError *cancelError = Call(keymap, @"cancelShortcutRecording", nil);
    Check([cancelError.message containsString:@"restored after recording"] && [recorded isKindOfClass:FlutterError.class], @"Restoration failure reaches pending recording and cancellation callers");
    Check(keymap.activeReferences.count == 0 && defaults.writes == writesBeforeRecording, @"Failed recording restoration does not change saved settings");
    [keymap.failedKeys removeAllObjects];

    state = Call(keymap, @"setShortcutSettings", Configuration(NO));
    Check([state[@"global"] isEqual:@NO] && keymap.activeReferences.count == 0 && !state[@"error"], @"App scope removes globals and clears failure");
    NSUInteger localActions = actions.count;
    Check([keymap handleLocalEvent:Event(35, 11, YES, NO)] == nil, @"App scoped shortcut consumes matching input");
    [keymap handleLocalEvent:Event(35, 11, YES, YES)];
    [keymap handleLocalEvent:Event(35, 11, YES, NO)];
    Check(actions.count == localActions + 1 && [actions.lastObject isEqual:@"toggle"], @"Local shortcut dispatches once per press");
    Check([keymap handleLocalEvent:Event(35, 0, NO, NO)] == nil, @"Local release works when modifiers release first");
    [keymap handleLocalEvent:Event(35, 11, YES, NO)];
    Check(actions.count == localActions + 2, @"Local action repeats after key release");
    [keymap handleLocalEvent:Event(35, 11, NO, NO)];
    NSEvent *unbound = Event(10, 0, YES, NO);
    Check([keymap handleLocalEvent:unbound] == unbound, @"Unbound input remains untouched");
    NSEvent *wrongModifiers = Event(35, 3, YES, NO);
    Check([keymap handleLocalEvent:wrongModifiers] == wrongModifiers, @"Chord requires exact modifiers");
    [keymap handleCall:[FlutterMethodCall methodCallWithMethodName:@"recordShortcut" arguments:nil] result:recording];
    [keymap handleLocalEvent:Event(35, 11, YES, NO)];
    [keymap handleLocalEvent:Event(35, 11, YES, YES)];
    Check(actions.count == localActions + 2, @"Capturing an app scoped chord suppresses held input too");
    [keymap handleLocalEvent:Event(35, 11, YES, NO)];
    Check(actions.count == localActions + 3, @"A fresh nonrepeat press recovers if captured key-up went to another app");
    [keymap applicationResigned];
    [keymap handleLocalEvent:Event(35, 11, YES, NO)];
    Check(actions.count == localActions + 4, @"App deactivation clears abandoned held key state");
    [keymap handleCall:[FlutterMethodCall methodCallWithMethodName:@"recordShortcut" arguments:nil] result:recording];
    [keymap handleLocalEvent:Event(7, 0, YES, NO)];
    Check([keymap.suppressedKeyCodes containsObject:@7], @"Invalid capture suppresses held input until release");
    [keymap applicationResigned];
    Check(![keymap.suppressedKeyCodes containsObject:@7], @"App deactivation clears capture suppression for an unregistered key");
    NSEvent *freshUnbound = Event(7, 0, YES, NO);
    Check([keymap handleLocalEvent:freshUnbound] == freshUnbound, @"Unbound key is not swallowed after switching apps");

    NSMutableDictionary *cleared = Configuration(YES);
    for (NSString *action in DeskShortcutActions()) cleared[@"bindings"][action] = NSNull.null;
    state = Call(keymap, @"setShortcutSettings", cleared);
    Check(keymap.activeReferences.count == 0 && [state[@"bindings"] isEqual:cleared[@"bindings"]], @"All shortcuts may be disabled");
    Check([defaults.values[DeskKeymapPreference][@"bindings"] count] == 0, @"Disabled bindings persist as valid empty property list");
    DeskKeymapProbe *relaunched = [[DeskKeymapProbe alloc] initWithDefaults:(NSUserDefaults *)defaults action:^(NSString *action) { (void)action; }];
    Check([[relaunched state][@"bindings"] isEqual:cleared[@"bindings"]] && relaunched.activeReferences.count == 0, @"Disabled bindings survive relaunch as channel nulls");
    [relaunched invalidate];

    __block BOOL unknownCalled = NO;
    BOOL unknownHandled = [keymap handleCall:[FlutterMethodCall methodCallWithMethodName:@"otherTimerMethod" arguments:nil]
                                     result:^(id value) { (void)value; unknownCalled = YES; }];
    Check(!unknownHandled && !unknownCalled, @"Unknown channel methods remain available to owner");
    [keymap handleCall:[FlutterMethodCall methodCallWithMethodName:@"recordShortcut" arguments:nil] result:recording];
    NSUInteger repliesBeforeDispose = recordReplies;
    [keymap invalidate];
    [keymap invalidate];
    Check(recordReplies == repliesBeforeDispose + 1 && recorded == nil, @"Disposal completes pending recording once");
    Check(keymap.activeReferences.count == 0 && keymap.removedMonitors == 1, @"Disposal unregisters and removes monitor once");
    Check([Call(keymap, @"getShortcutSettings", nil) isKindOfClass:FlutterError.class], @"Disposed helper fails visibly");

    DeskKeyDefaultsProbe *fresh = [DeskKeyDefaultsProbe new];
    startupFailedKey = 15;
    DeskKeymapProbe *startupConflict = [[DeskKeymapProbe alloc] initWithDefaults:(NSUserDefaults *)fresh action:^(NSString *action) { (void)action; }];
    Check([[startupConflict state][@"error"] containsString:@"Reset"] && startupConflict.activeReferences.count == 0, @"Startup conflict is visible and rolls back partial registration");
    Check(fresh.writes == 0, @"Startup conflict does not replace preference");
    startupFailedKey = -1;
    [startupConflict invalidate];
    startupHandlerFailure = eventInternalErr;
    DeskKeymapProbe *handlerFailure = [[DeskKeymapProbe alloc] initWithDefaults:(NSUserDefaults *)fresh action:^(NSString *action) { (void)action; }];
    Check([[handlerFailure state][@"error"] containsString:@"global shortcuts"], @"Missing global platform support is visible");
    state = Call(handlerFailure, @"setShortcutSettings", Configuration(NO));
    Check([state[@"global"] isEqual:@NO] && !state[@"error"], @"App scope remains available when global handler fails");
    [handlerFailure invalidate];
    startupHandlerFailure = noErr;
    startupMonitorFails = YES;
    DeskKeymapProbe *monitorFailure = [[DeskKeymapProbe alloc] initWithDefaults:(NSUserDefaults *)fresh action:^(NSString *action) { (void)action; }];
    Check([[monitorFailure state][@"error"] containsString:@"listen for shortcuts"], @"Missing local platform support is visible");
    Check([Call(monitorFailure, @"recordShortcut", nil) isKindOfClass:FlutterError.class], @"Unavailable recording returns a useful failure");
    [monitorFailure invalidate];
    startupMonitorFails = NO;
    fresh.values[DeskKeymapPreference] = @{@"global": @"corrupt", @"bindings": @{}};
    NSUInteger writesBeforeCorrupt = fresh.writes;
    DeskKeymapProbe *corrupt = [[DeskKeymapProbe alloc] initWithDefaults:(NSUserDefaults *)fresh action:^(NSString *action) { (void)action; }];
    Check([[corrupt state][@"error"] containsString:@"could not be read"] && fresh.writes == writesBeforeCorrupt, @"Malformed saved settings are reported without overwriting them");
    [corrupt invalidate];

    // Exercise the real production InstallEventHandler, Carbon parameter
    // decoding, and application target dispatch. No real hotkeys are registered
    // and no keyboard input is sent to the system or any running application.
    useRealCarbonHandler = YES;
    DeskKeyDefaultsProbe *carbonDefaults = [DeskKeyDefaultsProbe new];
    NSMutableArray *carbonActions = [NSMutableArray array];
    DeskKeymapProbe *carbon = [[DeskKeymapProbe alloc] initWithDefaults:(NSUserDefaults *)carbonDefaults
        action:^(NSString *action) { [carbonActions addObject:action]; }];
    Check(carbon.eventHandler != NULL && ![carbon state][@"error"], @"Production Carbon handler installs on application target");
    for (NSString *action in DeskShortcutActions()) {
      UInt32 identifier = Identifier(carbon, action);
      NSUInteger before = carbonActions.count;
      Check(DeliverCarbonNotification(identifier, DeskKeymapSignature, YES, YES) == noErr,
            @"Application target delivers Carbon press to production callback");
      Check(carbonActions.count == before + 1 && [carbonActions.lastObject isEqual:action],
            @"Production Carbon callback decodes identifier and routes the correct action");
      DeliverCarbonNotification(identifier, DeskKeymapSignature, YES, YES);
      Check(carbonActions.count == before + 1, @"Repeated Carbon press is suppressed through actual event handler");
      Check(DeliverCarbonNotification(identifier, DeskKeymapSignature, NO, YES) == noErr,
            @"Application target delivers Carbon release to production callback");
      DeliverCarbonNotification(identifier, DeskKeymapSignature, YES, YES);
      Check(carbonActions.count == before + 2, @"Carbon release permits a new press through actual handler");
      DeliverCarbonNotification(identifier, DeskKeymapSignature, NO, YES);
    }
    NSUInteger beforeIgnored = carbonActions.count;
    Check(DeliverCarbonNotification(Identifier(carbon, @"toggle"), 'OTHR', YES, YES) == eventNotHandledErr,
          @"Production handler declines other hotkey signatures");
    Check(DeliverCarbonNotification(Identifier(carbon, @"toggle"), DeskKeymapSignature, YES, NO) == eventNotHandledErr,
          @"Production handler declines missing identifier payload");
    DeliverCarbonNotification(99999, DeskKeymapSignature, YES, YES);
    Check(carbonActions.count == beforeIgnored, @"Foreign, malformed, and stale Carbon notifications never route an action");
    [carbon invalidate];
    Check(carbon.eventHandler == NULL, @"Disposal removes the actual Carbon event handler");
    useRealCarbonHandler = NO;
    printf("Keyboard shortcuts: %lu checks passed (production validation, registration transactions, recording, and dispatch).\n", (unsigned long)checks);
    printf("Carbon routing verified with the real application event target and production handler; OS keyboard input and real hotkey registration were not synthesized.\n");
  }
  return 0;
}
